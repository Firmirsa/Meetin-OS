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
    var capture: AudioCapture?
    var recording: URL?
    var recordedTracks: AudioCapture.Tracks?
    var busy = false
    var key = ProcessInfo.processInfo.environment["GLADIA_API_KEY"] ?? GladiaKeyStore.load() ?? ""
    var live: LiveTranscription?
    var statusBelongsToMeeting = false
    var transcriptIncomplete = false { didSet { syncMeeting() } }
    var proposals: [TaskProposal] = [] { didSet { syncMeeting() } }
    var detector: TaskDetector?
    var launchingProposals: Set<String> = []
    var showAgentTab = false
    var openWindowAction: OpenWindowAction?
    var proposalIssues: [String: String] = [:]
    var agentAccessCode = ""
    var agentAccess: AgentAccess?
    var integrationsRequest: IntegrationsRequest?
    let agent = AgentWorkspaceState()
    var status = "Prêt à enregistrer"
    var permissionHelp: AudioPermissionHelp? { didSet { noteSystemAudioPermission() } }
    var transcript = "" { didSet { syncMeeting() } }
    var notes = "" { didSet { syncMeeting() } }
    let store = MeetingStore()
    var route: MainRoute = .home
    var meetingID: UUID?
    var startedAt: Date?
    var startedInZoom = false
    var zoomDetector = ZoomMeetingDetector()
    @ObservationIgnored var zoomMonitor: Task<Void, Never>?
    var notebookIsOpen = false
    var meetingIsActive: Bool { capture != nil || zoomDetector.inMeeting }

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
    private enum MeetingTab: Hashable { case transcription, agent }

    @Environment(\.openWindow) private var openWindow
    @Bindable var session: MeetingSession
    var isMeetingWindow = false
    @State private var integrationsRequest: IntegrationsRequest?
    @AppStorage("webWorkspaceURL") private var webWorkspaceURL = "http://localhost:3000"
    @State private var tab: MeetingTab = .transcription

    private var hasKey: Bool {
        !session.key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
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
                    Button {
                        session.showMain(.settings, openWindow: openWindow)
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
                Picker("Vue de la réunion", selection: $tab) {
                    Text("Transcription").tag(MeetingTab.transcription)
                    Text(session.pendingProposalCount > 0 ? "Agent (\(session.pendingProposalCount))" : "Agent").tag(MeetingTab.agent)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .tint(Color.mtControlTint)
                .onChange(of: session.showAgentTab, initial: true) {
                    guard session.showAgentTab else { return }
                    tab = .agent
                    session.showAgentTab = false
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
            }

            if (isMeetingWindow || session.recording != nil) && tab == .agent {
                agentPanel
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if let live = session.live {
                            Text("Transcription").font(.headline).accessibilityAddTraits(.isHeader)
                            LiveTranscriptPanel(live: live) {
                                session.showMain(.settings, openWindow: openWindow)
                            }
                        } else if isMeetingWindow {
                            Text("PENDANT ET APRÈS L’APPEL")
                                .font(.mtSans(11, weight: .semibold))
                                .tracking(2)
                                .foregroundStyle(Color.mtAccentText)
                            Text("Le fil de la réunion.")
                                .font(.mtSerif(42))
                                .accessibilityAddTraits(.isHeader)
                            Text("Prenez des notes pendant l’appel, puis retrouvez la transcription ici.")
                                .foregroundStyle(Color.mtInk2)
                        }
                        Text("Notes").font(.headline).accessibilityAddTraits(.isHeader)
                        ZStack(alignment: .topLeading) {
                            TextEditor(text: $session.notes)
                                .font(.body)
                                .scrollContentBackground(.hidden)
                                .accessibilityLabel("Notes de réunion")
                            if session.notes.isEmpty {
                                Text("Points clés, décisions, questions…")
                                    .foregroundStyle(Color.mtInk2)
                                    .padding(.leading, 5)
                                    .padding(.top, 1)
                                    .allowsHitTesting(false)
                                    .accessibilityHidden(true)
                            }
                        }
                        .frame(minHeight: 116)
                        .padding(10)
                        .background(Color.mtSurface, in: RoundedRectangle(cornerRadius: MTRadius.card))

                        if isMeetingWindow && session.live == nil && session.transcript.isEmpty {
                            Text(session.liveWaitingMessage)
                                .foregroundStyle(Color.mtInk2)
                        }
                        if !session.transcript.isEmpty {
                            Rectangle().fill(Color.mtLine).frame(height: 1)
                            HStack {
                                Text("Transcription").font(.headline).accessibilityAddTraits(.isHeader)
                                Spacer()
                                Button("Copier") {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(session.transcript, forType: .string)
                                }
                                .accessibilityLabel("Copier la transcription")
                            }
                            Text(session.transcript)
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
            }

            Rectangle().fill(Color.mtLine).frame(height: 1)

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 7) {
                    if session.busy {
                        ProgressView().controlSize(.small)
                    } else {
                        Circle()
                            .fill(session.capture == nil ? Color.mtInk2 : Color.mtRec)
                            .frame(width: 7, height: 7)
                            .accessibilityHidden(true)
                    }
                    Text(session.status)
                        .font(.callout)
                        .foregroundStyle(Color.mtInk2)
                        .accessibilityAddTraits(.updatesFrequently)
                }
                if let help = session.permissionHelp, !session.busy {
                    Button(help.settingsLabel, systemImage: "arrow.up.right.square") {
                        NSWorkspace.shared.open(help.settingsURL)
                    }
                    .buttonStyle(.link)
                }
                HStack {
                    if let recording = session.recording, session.capture == nil {
                        Button("Écouter", systemImage: "play.circle") { NSWorkspace.shared.open(recording) }
                        Button("Voir les pistes") { NSWorkspace.shared.activateFileViewerSelecting([recording]) }
                    }
                    Spacer()
                    if session.recording != nil {
                        if tab == .agent {
                            Button("Transcrire", systemImage: "text.alignleft", action: transcribe)
                                .buttonStyle(.mtGhost)
                        } else {
                            Button("Transcrire", systemImage: "text.alignleft", action: transcribe)
                                .buttonStyle(.mtPrimary)
                        }
                    } else {
                        if session.capture == nil {
                            Button("Enregistrer", systemImage: "mic", action: toggleRecording)
                                .buttonStyle(.mtPrimary)
                                .disabled(session.agent.busy)
                        } else {
                            Button("Arrêter", systemImage: "stop.fill", action: toggleRecording)
                                .buttonStyle(.mtGhost)
                        }
                    }
                }
                .disabled(session.busy)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 14)
        }
        .foregroundStyle(Color.mtInk)
        .frame(minWidth: isMeetingWindow ? 360 : 560, minHeight: 420)
        .sheet(item: $integrationsRequest) { request in
            IntegrationsView(session: session, workspaceURL: $webWorkspaceURL, request: request, transcribe: transcribe)
        }
        .toolbar {
            if isMeetingWindow, session.recording != nil, session.capture == nil {
                Button("Nouvel enregistrement", systemImage: "plus", action: toggleRecording)
                    .disabled(session.busy || session.agent.busy)
            }
        }
    }

    private var agentClient: AgentClient? {
        guard session.agentAccess != nil, let base = AgentClient.serverURL(webWorkspaceURL) else { return nil }
        return AgentClient(baseURL: base, accessCode: session.agentAccessCode)
    }

    private var agentPanel: some View {
        AgentWorkspace(state: session.agent, transcript: session.transcript, client: agentClient,
                       access: session.agentAccess, showIntegrations: showIntegrations) {
            ProposalCards(session: session, client: agentClient, showIntegrations: showIntegrations)
        }
    }

    private func showIntegrations(_ page: IntegrationsPage) {
        integrationsRequest = IntegrationsRequest(page: page)
    }

    private func toggleRecording() {
        Self.toggleRecording(session: session, openWindow: openWindow)
    }

    static func toggleRecording(session: MeetingSession, openWindow: OpenWindowAction) {
        guard !session.busy, session.capture != nil || (!session.agent.busy && session.launchingProposals.isEmpty) else { return }
        session.busy = true
        Task {
            defer { session.busy = false }
            do {
                if let current = session.capture {
                    defer { session.capture = nil }
                    session.status = "Préparation du fichier audio…"
                    let result: (mix: URL, tracks: AudioCapture.Tracks?, help: AudioPermissionHelp?)
                    do {
                        result = try await current.stop()
                    } catch {
                        await session.finishLive()
                        throw error
                    }
                    await session.finishLive()
                    session.recording = result.mix
                    session.recordedTracks = result.tracks
                    session.permissionHelp = result.help
                    session.status = result.help.map { "Une piste a été conservée. \($0.localizedDescription)" }
                        ?? "Enregistrement prêt · micro et audio système"
                    await session.meetingDidStop()
                } else {
                    let next = AudioCapture()
                    let live = session.makeLive()
                    if let live {
                        next.onAudio = { track, buffer, hostTime in live.feed(track, buffer, hostTime: hostTime) }
                    }
                    session.statusBelongsToMeeting = false
                    session.permissionHelp = nil
                    session.status = "Vérification des autorisations…"
                    try await next.start()
                    session.meetingDidStart()
                    session.recordedTracks = nil
                    session.recording = nil
                    session.transcript = ""
                    session.agent.newRecording()
                    session.capture = next
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
        guard hasKey else {
            showIntegrations(.transcribe)
            return
        }
        session.busy = true
        session.transcript = ""
        session.status = "Envoi et transcription en cours…"
        Task {
            defer { session.busy = false }
            do {
                let gladia = Gladia(key: session.key.trimmingCharacters(in: .whitespacesAndNewlines))
                if let tracks = session.recordedTracks {
                    session.transcript = try await gladia.transcribe(tracks: tracks)
                } else {
                    session.transcript = try await gladia.transcribe(recording)
                }
                session.transcriptIncomplete = false
                session.status = "Transcription prête"
            } catch Gladia.RequestError.unauthorized {
                session.status = Gladia.RequestError.unauthorized.localizedDescription
                showIntegrations(.transcribe)
            } catch { session.status = error.localizedDescription }
        }
    }
}
