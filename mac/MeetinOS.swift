import AppKit
import ApplicationServices
import SwiftUI
import UniformTypeIdentifiers

@main
struct MeetinOS: App {
    @State private var meeting = MeetingSession()

    var body: some Scene {
        WindowGroup("Meetin-OS", id: "notebook") {
            CaptureView(session: meeting)
        }
        .defaultSize(width: 660, height: 540)
        .restorationBehavior(.disabled)
        Window("Réunion Meetin-OS", id: "meeting") {
            MeetingWindow(session: meeting)
        }
        .defaultSize(width: 720, height: 520)
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
    var key = ProcessInfo.processInfo.environment["GLADIA_API_KEY"] ?? ""
    var agentAccessCode = ""
    var agentAccess: AgentAccess?
    let agent = AgentWorkspaceState()
    var status = "Prêt à enregistrer"
    var permissionHelp: AudioPermissionHelp?
    var transcript = ""
    var notes = ""
    var zoomDetector = ZoomMeetingDetector()
    var notebookCount = 0
    var meetingIsActive: Bool { capture != nil || zoomDetector.inMeeting }
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
            if wasActive && session.notebookCount == 0 { openWindow(id: "notebook") }
            dismissWindow()
        }
    }
}

struct CaptureView: View {
    private enum MeetingTab: Hashable { case transcription, agent }

    @Environment(\.openWindow) private var openWindow
    @Bindable var session: MeetingSession
    var isMeetingWindow = false
    @AppStorage("detectZoomMeetings") private var detectZoomMeetings = false
    @AppStorage("seenGuestIntro") private var seenGuestIntro = false
    @State private var showingSettings = false
    @State private var integrationsRequest: IntegrationsRequest?
    @AppStorage("webWorkspaceURL") private var webWorkspaceURL = "http://localhost:3000"
    @State private var tab: MeetingTab = .transcription

    private var hasKey: Bool {
        !session.key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Group {
                    if let url = Bundle.main.url(forResource: "MeetinOS", withExtension: "png"),
                       let logo = NSImage(contentsOf: url) {
                        Image(nsImage: logo).resizable().scaledToFit()
                    } else {
                        Image(systemName: "waveform").foregroundStyle(Color.mtAccentText)
                    }
                }
                .frame(width: 32, height: 32)
                .accessibilityHidden(true)
                Text("Meetin-OS").font(.mtSans(16, weight: .semibold))
                if isMeetingWindow {
                    Text("Réunion").font(.mtSans(12)).foregroundStyle(Color.mtInk2)
                }
                Spacer()
                Button("Intégrations", systemImage: "puzzlepiece.extension") { showIntegrations(.catalog) }
                    .buttonStyle(.borderless)
                    .disabled(session.agent.busy)
                Button {
                    showingSettings = true
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

            if isMeetingWindow || session.recording != nil {
                Picker("Vue de la réunion", selection: $tab) {
                    Text("Transcription").tag(MeetingTab.transcription)
                    Text("Agent").tag(MeetingTab.agent)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
            }

            if (isMeetingWindow || session.recording != nil) && tab == .agent {
                agentPanel
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        Text(isMeetingWindow ? "PENDANT ET APRÈS L’APPEL" : "CARNET DE RÉUNION POUR MAC")
                            .font(.mtSans(11, weight: .semibold))
                            .tracking(2)
                            .foregroundStyle(Color.mtAccentText)
                        Text(isMeetingWindow ? "Le fil de la réunion." : "Chaque décision compte.")
                            .font(.mtSerif(42))
                            .accessibilityAddTraits(.isHeader)
                        Text("Prenez des notes pendant l’appel, puis retrouvez la transcription ici.")
                            .foregroundStyle(Color.mtInk2)
                        if !isMeetingWindow && !seenGuestIntro && session.recording == nil && session.agentAccess == nil {
                            guestIntro
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

                        if isMeetingWindow && session.transcript.isEmpty {
                            Text("La transcription sera disponible après l’arrêt de l’enregistrement et l’envoi à Gladia.")
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
                .background(Color.mtCanvas)
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
                        Button("Transcrire", systemImage: "text.alignleft", action: transcribe)
                            .buttonStyle(.mtPrimary)
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
        .background(Color.mtCanvas)
        .foregroundStyle(Color.mtInk)
        .frame(minWidth: 560, minHeight: 420)
        .onAppear {
            if !isMeetingWindow { session.notebookCount += 1 }
        }
        .onDisappear {
            if !isMeetingWindow { session.notebookCount -= 1 }
        }
        .onOpenURL { url in
            guard !isMeetingWindow, !showingSettings, integrationsRequest == nil,
                  let request = IntegrationsRequest.fromLink(url) else { return }
            integrationsRequest = request
        }
        .task(id: detectZoomMeetings) {
            guard !isMeetingWindow else { return }
            session.zoomDetector = ZoomMeetingDetector()
            guard detectZoomMeetings else { return }
            while !Task.isCancelled {
                if session.zoomDetector.observe(ZoomMeetingDetector.windowTitles()) {
                    openWindow(id: "meeting")
                }
                do { try await Task.sleep(for: .seconds(2)) }
                catch { return }
            }
        }
        .sheet(isPresented: $showingSettings) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Réglages").font(.title2.bold())
                Text("Autorisations audio").font(.headline)
                Text("Au premier enregistrement, macOS peut demander l’accès au micro et à l’audio du système.")
                    .foregroundStyle(Color.mtInk2)
                HStack {
                    Button("Microphone") { NSWorkspace.shared.open(AudioPermissionHelp.microphone.settingsURL) }
                    Button("Audio du système") { NSWorkspace.shared.open(AudioPermissionHelp.systemAudio.settingsURL) }
                }
                Rectangle().fill(Color.mtLine).frame(height: 1)
                Toggle("Ouvrir la fenêtre quand je rejoins une réunion Zoom", isOn: $detectZoomMeetings)
                if detectZoomMeetings {
                    Text("L’accès à l’accessibilité sert à détecter les fenêtres Zoom. L’enregistrement se lance manuellement.")
                        .foregroundStyle(Color.mtInk2)
                    Button("Ouvrir les réglages d’accessibilité") {
                        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
                        NSWorkspace.shared.open(url)
                    }
                }
                HStack {
                    Spacer()
                    Button("Fermer") { showingSettings = false }
                        .keyboardShortcut(.cancelAction)
                }
            }
            .padding(24)
            .frame(width: 420)
            .background(Color.mtCanvas)
        }
        .sheet(item: $integrationsRequest) { request in
            IntegrationsView(session: session, workspaceURL: $webWorkspaceURL, request: request, transcribe: transcribe)
        }
        .toolbar {
            if !isMeetingWindow && session.meetingIsActive {
                Button("Afficher la réunion", systemImage: "rectangle.on.rectangle") {
                    openWindow(id: "meeting")
                }
            }
            if !isMeetingWindow && session.capture == nil {
                Button("Ouvrir un enregistrement", systemImage: "folder", action: openRecording)
                    .disabled(session.busy || session.agent.busy)
            }
            if session.recording != nil, session.capture == nil {
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
                       access: session.agentAccess, showIntegrations: showIntegrations)
    }

    private var guestIntro: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("Votre premier carnet").font(.headline)
            Text("Enregistrez et prenez des notes dès maintenant. Vous pourrez activer la transcription et les outils de l’équipe dans Intégrations.")
                .font(.callout).foregroundStyle(Color.mtInk2)
            HStack {
                Button("Continuer sans compte") { seenGuestIntro = true }.buttonStyle(.mtPrimary)
                Button("Voir les intégrations") {
                    seenGuestIntro = true
                    showIntegrations(.catalog)
                }.buttonStyle(.mtGhost)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .mtCard()
    }

    private func showIntegrations(_ page: IntegrationsPage) {
        integrationsRequest = IntegrationsRequest(page: page)
    }

    private func openRecording() {
        guard !session.busy, !session.agent.busy, session.capture == nil else { return }
        session.busy = true
        let picker = NSOpenPanel()
        picker.allowedContentTypes = [.mpeg4Audio]
        picker.message = "Choisissez un fichier M4A à écouter ou à transcrire."
        picker.begin { response in
            session.busy = false
            guard response == .OK, let file = picker.url else { return }
            session.recordedTracks = nil
            session.recording = file
            session.transcript = ""
            session.agent.newRecording()
            session.permissionHelp = nil
            session.status = "Fichier audio prêt"
            tab = .transcription
        }
    }

    private func toggleRecording() {
        guard !session.busy, session.capture != nil || !session.agent.busy else { return }
        session.busy = true
        Task {
            defer { session.busy = false }
            do {
                if let current = session.capture {
                    defer { session.capture = nil }
                    session.status = "Préparation du fichier audio…"
                    let result = try await current.stop()
                    session.recording = result.mix
                    session.recordedTracks = result.tracks
                    session.permissionHelp = result.help
                    session.status = result.help.map { "Une piste a été conservée. \($0.localizedDescription)" }
                        ?? "Enregistrement prêt · micro et audio système"
                } else {
                    let next = AudioCapture()
                    session.permissionHelp = nil
                    session.status = "Vérification des autorisations…"
                    try await next.start()
                    session.recordedTracks = nil
                    session.recording = nil
                    session.transcript = ""
                    session.agent.newRecording()
                    session.capture = next
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
                session.status = "Transcription prête"
            } catch Gladia.RequestError.unauthorized {
                session.status = Gladia.RequestError.unauthorized.localizedDescription
                showIntegrations(.transcribe)
            } catch { session.status = error.localizedDescription }
        }
    }
}
