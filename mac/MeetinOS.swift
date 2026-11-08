import AppKit
import ApplicationServices
import SwiftUI

@main
struct MeetinOS: App {
    @State private var meeting = MeetingSession()

    var body: some Scene {
        Window("Meetin-OS", id: "notebook") {
            MainWindow(session: meeting)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1100, height: 760)
        .defaultWindowPlacement { _, context in MainWindow.placement(in: context) }
        .restorationBehavior(.disabled)
        .commands { CommandGroup(replacing: .newItem) {} }
        Window("Réunion Meetin-OS", id: "meeting") {
            MeetingWindow(session: meeting)
                .meetinNight()
                .windowMinimizeBehavior(.disabled)
                .windowFullScreenBehavior(.disabled)
        }
        .defaultWindowPlacement { _, context in
            let visible = context.defaultDisplay.visibleRect
            return WindowPlacement(.trailing, size: CGSize(width: visible.width / 3, height: visible.height))
        }
        .restorationBehavior(.disabled)
        .commandsRemoved()
    }
}

@MainActor
@Observable
final class MeetingSession {
    enum CaptureState { case idle, recording, paused }

    var capture: AudioCapture?
    var capturePaused = false
    var captureSegment = 0
    var captureRevision = 0

    var captureState: CaptureState {
        guard capture != nil else { return .idle }
        return capturePaused ? .paused : .recording
    }

    var captureActiveDuration: TimeInterval { capture?.activeDuration ?? 0 }
    var recording: URL?
    var recordedTracks: AudioCapture.Tracks?
    var busy = false
    let account = HostedAccount()
    var billingLaunchPending = false
    var billingRequestBusy = false
    var live: LiveTranscription?
    var statusBelongsToMeeting = false
    var transcriptIncomplete = false { didSet { syncMeeting() } }
    var proposals: [TaskProposal] = [] { didSet { syncMeeting() } }
    var detector: TaskDetector?
    var launchingProposals: Set<String> = []
    var showAgentTab = false
    var openWindowAction: OpenWindowAction?
    var proposalIssues: [String: String] = [:]
    var agentAccess: AgentAccess?
    var integrationsRequest: IntegrationsRequest? {
        didSet { if integrationsRequest != nil { route = .integrations } }
    }
    let agent = AgentWorkspaceState()
    let recordingLevel = RecordingLevel()
    let audioLevelMeter = AudioLevelMeter()
    var status = "Prêt à enregistrer"
    var permissionHelp: AudioPermissionHelp? { didSet { noteSystemAudioPermission() } }
    var transcript = "" { didSet { syncMeeting() } }
    var participants: MeetingParticipants? { didSet { participantNamesChanged() } }
    var structuredLines: [StructuredTranscriptLine]?

    var participantLines: [StructuredTranscriptLine] {
        live?.transcript.lines.map(\.structured) ?? structuredLines ?? []
    }

    var displayedTranscript: String {
        guard let participants, live != nil || structuredLines != nil else { return transcript }
        return participants.render(participantLines)
    }

    func participantNamesChanged() {
        if let participants, let structuredLines {
            transcript = participants.render(structuredLines)
        }
        syncMeeting()
    }
    var notes = "" { didSet { syncMeeting() } }
    let store = MeetingStore()
    var pageReturnRoute: MainRoute = .home
    var route: MainRoute = .home {
        didSet {
            if oldValue == .integrations && route != .integrations { integrationsRequest = nil }
            if [.settings, .account, .integrations, .billing].contains(route),
               ![.settings, .account, .integrations, .billing].contains(oldValue) {
                pageReturnRoute = oldValue
            }
        }
    }

    func returnFromPage() {
        route = pageReturnRoute
        integrationsRequest = nil
    }
    var meetingID: UUID?
    var startedAt: Date?
    var recordingSource: MeetingSource?
    var callDetector = MeetingDetector()
    @ObservationIgnored var callMonitor: Task<Void, Never>?
    @ObservationIgnored var callAccessibility: MeetingAccessibility?
    var notebookIsOpen = false
    var meetingIsActive: Bool { capture != nil || !callDetector.arrivals.isEmpty }

    init() {
        TaskNotifications.shared.attach(self)
    }
}

private struct MeetingWindow: View {
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.openWindow) private var openWindow
    let session: MeetingSession

    var body: some View {
        Group {
            if session.meetingIsActive {
                CaptureView(session: session, isMeetingWindow: true)
            } else {
                Color.clear
            }
        }
        .onChange(of: session.meetingIsActive, initial: true) { wasActive, isActive in
            guard !isActive else { return }
            if wasActive && !session.notebookIsOpen { openWindow(id: "notebook") }
            dismissWindow()
        }
    }
}

struct CaptureView: View {
    @Environment(\.openWindow) private var openWindow
    @Bindable var session: MeetingSession
    var isMeetingWindow = false
    @State private var integrationsRequest: IntegrationsRequest?
    @State private var internalRoute: MainRoute?
    @AppStorage("webWorkspaceURL") private var webWorkspaceURL = MeetinSite.defaultAddress
    @SceneStorage("meetingWorkspaceTab") private var selectedTab = MeetingWorkspaceTab.transcription.rawValue

    private var tab: MeetingWorkspaceTab { MeetingWorkspaceTab(rawValue: selectedTab) ?? .transcription }

    var body: some View {
        ZStack {
            meetingContent
                .modifier(MeetingPaneVisibility(visible: internalRoute == nil))
            if let internalRoute {
                VStack(spacing: 0) {
                    HStack {
                        Button("Retour à la réunion", systemImage: "chevron.left", action: returnToMeeting)
                            .buttonStyle(.mtGhost)
                        Spacer()
                    }.padding(16)
                    switch internalRoute {
                    case .integrations:
                        if let request = integrationsRequest {
                            IntegrationsNativePage(session: session, workspaceURL: $webWorkspaceURL,
                                                   request: request, back: returnToMeeting, transcribe: transcribe,
                                                   showsBack: false)
                        }
                    case .billing: BillingPage(session: session, showsBack: false)
                    case .account:
                        AccountPage(session: session, showsBack: false) {
                            showIntegrations(session.agentAccess == nil ? .agent : .catalog)
                        }
                    case .settings:
                        SettingsPage(session: session, showsBack: false, navigate: { self.internalRoute = $0 })
                    default: EmptyView()
                    }
                }
                .background(Color.mtCanvas)
            }
        }
    }

    private var meetingContent: some View {
        VStack(spacing: 0) {
            if isMeetingWindow {
                HStack(spacing: 10) {
                    MTLogo()
                    Text("Meetin-OS").font(.mtSans(16, weight: .semibold))
                    Text("Réunion").font(.mtSans(12)).foregroundStyle(Color.mtInk2)
                    Spacer()
                    Button("Intégrations", systemImage: "puzzlepiece.extension") { showIntegrations(.catalog) }
                        .buttonStyle(.borderless)
                        .disabled(session.agent.busy)
                    Button { internalRoute = .billing } label: {
                        Image(systemName: "creditcard")
                    }
                        .buttonStyle(.borderless)
                        .help("Facturation et abonnement")
                        .accessibilityLabel("Facturation et abonnement")
                    Button {
                        internalRoute = .settings
                    } label: {
                        Image(systemName: "gearshape").frame(width: 24, height: 24)
                    }
                    .buttonStyle(.borderless)
                    .help("Réglages")
                    .accessibilityLabel("Réglages")
                    .disabled(session.agent.busy)
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 10)

                Rectangle().fill(Color.mtLine).frame(height: 1)
            }

            if isMeetingWindow || session.recording != nil {
                HStack(spacing: 0) {
                    ForEach(MeetingWorkspaceTab.allCases, id: \.self) { item in
                        Button {
                            selectedTab = item.rawValue
                        } label: {
                            VStack(spacing: 9) {
                                Text(item == .agent && session.pendingProposalCount > 0
                                     ? "Agent (\(session.pendingProposalCount))" : item.title)
                                    .font(.mtSans(13, weight: tab == item ? .semibold : .regular))
                                    .foregroundStyle(tab == item ? Color.mtInk : Color.mtInk2)
                                    .frame(maxWidth: .infinity)
                                Rectangle().fill(tab == item ? Color.mtAccent : Color.mtLine).frame(height: 2)
                            }
                            .padding(.top, 10)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(tab == item ? .isSelected : [])
                        .accessibilityLabel(item.title)
                        .accessibilityValue(item == .agent ? "\(session.pendingProposalCount) tâche(s) à valider" : "")
                    }
                }
                .accessibilityLabel("Vue de la réunion")
                .onChange(of: session.showAgentTab, initial: true) {
                    guard session.showAgentTab else { return }
                    selectedTab = MeetingWorkspaceTab.agent.rawValue
                    session.showAgentTab = false
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
            }

            ZStack {
                agentPanel
                    .modifier(MeetingPaneVisibility(visible: tab == .agent))
                MeetingSummaryView(notes: $session.notes, savedMeeting: session.meetingID != nil,
                                   saveError: session.store.lastError)
                    .modifier(MeetingPaneVisibility(visible: tab == .summary))
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if session.participants != nil {
                            ParticipantsEditor(session: session)
                        }
                        if let live = session.live {
                            Text("Transcription").font(.headline).accessibilityAddTraits(.isHeader)
                            LiveTranscriptPanel(live: live, paused: session.captureState == .paused,
                                                participants: session.participants) {
                                internalRoute = .billing
                            }
                        } else if isMeetingWindow {
                            Text("PENDANT ET APRÈS L’APPEL")
                                .font(.mtSans(11, weight: .semibold))
                                .tracking(2)
                                .foregroundStyle(Color.mtAccentText)
                            Text("Le fil de la réunion.")
                                .font(.mtSerif(42))
                                .accessibilityAddTraits(.isHeader)
                            Text("Retrouve le texte ici et garde tes décisions dans Résumé.")
                                .foregroundStyle(Color.mtInk2)
                        }
                        if isMeetingWindow && session.live == nil && session.transcript.isEmpty {
                            Text(session.liveWaitingMessage)
                                .foregroundStyle(Color.mtInk2)
                        }
                        if !session.displayedTranscript.isEmpty && session.live == nil {
                            Rectangle().fill(Color.mtLine).frame(height: 1)
                            HStack {
                                Text("Transcription").font(.headline).accessibilityAddTraits(.isHeader)
                                Spacer()
                                Button("Copier") {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(session.displayedTranscript, forType: .string)
                                }
                                .accessibilityLabel("Copier la transcription")
                            }
                            Text(session.displayedTranscript)
                                .font(.mtSans(14))
                                .lineSpacing(6)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .mtCard()
                        }
                    }
                    .frame(maxWidth: 620, alignment: .leading)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 24)
                    .frame(maxWidth: .infinity)
                }
                .modifier(MeetingPaneVisibility(visible: tab == .transcription))
            }

            Rectangle().fill(Color.mtLine).frame(height: 1)

            VStack(alignment: .leading, spacing: 10) {
                MeetingCaptureControls(session: session, recordOrFinish: toggleRecording)
                if let help = session.permissionHelp, !session.busy {
                    Button(help.settingsLabel, systemImage: "arrow.up.right.square") {
                        NSWorkspace.shared.open(help.settingsURL)
                    }
                    .buttonStyle(.link)
                }
                if let recording = session.recording, session.capture == nil {
                    ViewThatFits(in: .horizontal) {
                        HStack {
                            Button("Écouter", systemImage: "play.circle") { NSWorkspace.shared.open(recording) }
                            Button("Voir les pistes") { NSWorkspace.shared.activateFileViewerSelecting([recording]) }
                            Spacer(minLength: 8)
                            Button("Transcrire", systemImage: "text.alignleft", action: transcribe)
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Button("Écouter", systemImage: "play.circle") { NSWorkspace.shared.open(recording) }
                                Button("Voir les pistes") { NSWorkspace.shared.activateFileViewerSelecting([recording]) }
                            }
                            Button("Transcrire", systemImage: "text.alignleft", action: transcribe)
                        }
                    }
                    .buttonStyle(WorkspaceButtonStyle())
                    .disabled(session.busy)
                }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 14)
        }
        .foregroundStyle(Color.mtInk)
        .frame(minWidth: isMeetingWindow ? 360 : 560, minHeight: 420)
        .toolbar {
            if isMeetingWindow, session.recording != nil, session.capture == nil {
                Button("Nouvel enregistrement", systemImage: "plus", action: toggleRecording)
                    .disabled(session.busy || session.agent.busy)
            }
        }
    }

    private var agentClient: AgentClient? {
        session.agentClient
    }

    private var agentPanel: some View {
        AgentWorkspace(state: session.agent, transcript: session.transcript, client: agentClient,
                       access: session.agentAccess, showIntegrations: showIntegrations) {
            ProposalCards(session: session, client: agentClient, showIntegrations: showIntegrations)
        }
    }

    private func showIntegrations(_ page: IntegrationsPage) {
        integrationsRequest = IntegrationsRequest(page: page)
        internalRoute = .integrations
    }

    private func returnToMeeting() {
        internalRoute = nil
        integrationsRequest = nil
    }

    private func toggleRecording() {
        Self.toggleRecording(session: session, openWindow: openWindow)
    }

    static func toggleRecording(session: MeetingSession, openWindow: OpenWindowAction, source: MeetingSource? = nil) {
        guard !session.busy, session.capture != nil || (!session.agent.busy && session.launchingProposals.isEmpty) else { return }
        session.busy = true
        Task {
            defer { session.busy = false }
            do {
                if let current = session.capture {
                    session.recordingLevel.stop()
                    session.status = "Préparation du fichier audio…"
                    let result: (mix: URL, tracks: AudioCapture.Tracks?, help: AudioPermissionHelp?)
                    do {
                        try current.pause()
                        await session.finishCaptureSegment()
                        result = try await current.stop()
                    } catch {
                        session.capturePaused = true
                        await session.finishCaptureSegment()
                        if current.activeDuration == 0 {
                            await session.finishLive()
                            session.capture = nil
                        }
                        throw error
                    }
                    await session.finishLive()
                    defer { session.capture = nil }
                    session.recording = result.mix
                    session.recordedTracks = result.tracks
                    session.permissionHelp = result.help
                    session.status = result.help.map { "Une piste a été conservée. \($0.localizedDescription)" }
                        ?? "Enregistrement prêt · micro et audio système"
                    await session.meetingDidStop()
                } else {
                    let next = AudioCapture()
                    let live = session.makeLive()
                    let meter = session.audioLevelMeter
                    next.onAudio = { track, buffer, hostTime in
                        meter.feed(buffer)
                        live?.feed(track, buffer, hostTime: hostTime)
                    }
                    session.statusBelongsToMeeting = false
                    session.permissionHelp = nil
                    session.status = "Vérification des autorisations…"
                    try await next.start()
                    session.meetingDidStart(source: source)
                    session.recordedTracks = nil
                    session.recording = nil
                    session.transcript = ""
                    session.agent.newRecording()
                    session.capture = next
                    session.recordingLevel.start(reading: session.audioLevelMeter, since: Date())
                    session.live = live
                    live?.start()
                    if let live { session.startDetection(reading: live) }
                    session.status = "Enregistrement en cours"
                    openWindow(id: "meeting")
                }
            } catch let help as AudioPermissionHelp {
                session.permissionHelp = help
                session.status = help.localizedDescription
            } catch { session.status = error.localizedDescription }
        }
    }

    private func transcribe() {
        guard !session.busy, let recording = session.recording else { return }
        guard let client = session.accountClient, session.accountConnected else {
            showIntegrations(.transcribe)
            return
        }
        session.busy = true
        session.status = "Envoi et transcription en cours…"
        let tracks = session.recordedTracks
        let account = session.account
        Task {
            defer { session.busy = false }
            do {
                let usage = try await account.refreshUsage(client)
                let files = tracks.map { [$0.microphone, $0.system] } ?? [recording]
                guard try Gladia.audioMs(files) <= Double(usage.remainingMs) else {
                    throw CaptureError("Ton quota audio restant est trop petit pour cet enregistrement. Consulte ton plan dans Compte.")
                }
                let gladia = Gladia(client: client, token: { try await account.token(client) })
                let result: String
                if let tracks {
                    result = try await gladia.transcribe(tracks: tracks)
                } else {
                    result = try await gladia.transcribe(recording)
                }
                session.structuredLines = nil
                session.transcript = result
                session.transcriptIncomplete = false
                session.status = "Transcription prête"
            } catch let error as AccountClient.Failure where error.status == 401 {
                account.forget(client)
                session.status = error.localizedDescription
                showIntegrations(.transcribe)
            } catch { session.status = error.localizedDescription }
        }
    }
}
