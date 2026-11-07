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
    var status = "Prêt à enregistrer"
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
    @State private var showingSettings = false
    @AppStorage("webWorkspaceURL") private var webWorkspaceURL = "http://localhost:3000"
    @State private var copiedForAgent = false
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
                Button {
                    showingSettings = true
                } label: {
                    Image(systemName: "gearshape").frame(width: 24, height: 24)
                }
                .buttonStyle(.borderless)
                .help("Réglages de transcription")
                .accessibilityLabel("Réglages de transcription")
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
        .onChange(of: session.transcript) { copiedForAgent = false }
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
                Text("Réglages de transcription").font(.title2.bold())
                Text("Meetin-OS utilise Gladia pour transcrire l’audio. La clé sert uniquement pendant cette session.")
                    .foregroundStyle(Color.mtInk2)
                SecureField("Clé API Gladia", text: $session.key)
                    .textFieldStyle(.roundedBorder)
                Rectangle().fill(Color.mtLine).frame(height: 1)
                TextField("Adresse du site Meetin-OS", text: $webWorkspaceURL)
                    .textFieldStyle(.roundedBorder)
                Toggle("Ouvrir la fenêtre quand je rejoins une réunion Zoom", isOn: $detectZoomMeetings)
                Text("Activez Meetin-OS dans Réglages Système → Confidentialité et sécurité → Accessibilité. Vous lancez l’enregistrement depuis la fenêtre de réunion.")
                    .foregroundStyle(Color.mtInk2)
                if detectZoomMeetings {
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
        .toolbar {
            if !isMeetingWindow && session.meetingIsActive {
                Button("Afficher la réunion", systemImage: "rectangle.on.rectangle") {
                    openWindow(id: "meeting")
                }
            }
            if !isMeetingWindow && session.capture == nil {
                Button("Ouvrir un enregistrement", systemImage: "folder", action: openRecording)
                    .disabled(session.busy)
            }
            if session.recording != nil, session.capture == nil {
                Button("Nouvel enregistrement", systemImage: "plus", action: toggleRecording)
                    .disabled(session.busy)
            }
        }
    }

    private var agentURL: URL? {
        guard let base = URL(string: webWorkspaceURL.trimmingCharacters(in: .whitespacesAndNewlines)),
              let host = base.host, base.user == nil, base.password == nil,
              base.query == nil, base.fragment == nil,
              base.scheme == "https" || (base.scheme == "http" && ["localhost", "127.0.0.1"].contains(host))
        else { return nil }
        return base.appendingPathComponent("agent")
    }

    private var agentPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("ESPACE AGENT")
                    .font(.mtSans(11, weight: .semibold))
                    .tracking(2)
                    .foregroundStyle(Color.mtAccentText)
                Text("De la décision à la tâche.")
                    .font(.mtSerif(42))
                    .accessibilityAddTraits(.isHeader)
                Text("Choisissez un extrait de la réunion, ajoutez le contexte utile et relisez la tâche avant de la confier à Devin.")
                    .foregroundStyle(Color.mtInk2)
                VStack(alignment: .leading, spacing: 12) {
                    Text("Contexte de réunion").font(.mtSans(16, weight: .semibold))
                    Text(session.transcript.isEmpty
                         ? "Lancez la transcription pour pouvoir copier le texte de la réunion."
                         : "La transcription est prête. Vous pouvez la copier ou sélectionner un passage dans l’onglet Transcription.")
                        .foregroundStyle(Color.mtInk2)
                    if !session.transcript.isEmpty {
                        Button(copiedForAgent ? "Transcription copiée" : "Copier la transcription") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(session.transcript, forType: .string)
                            copiedForAgent = true
                        }
                        .buttonStyle(.mtGhost)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .mtCard()
                if let agentURL {
                    Button("Ouvrir l’espace agent", systemImage: "arrow.up.right") {
                        NSWorkspace.shared.open(agentURL)
                    }
                    .buttonStyle(.mtPrimary)
                } else {
                    Button("Configurer l’adresse du site") { showingSettings = true }
                        .buttonStyle(.mtGhost)
                }
            }
            .frame(maxWidth: 620, alignment: .leading)
            .padding(28)
            .frame(maxWidth: .infinity)
        }
    }

    private func openRecording() {
        guard !session.busy, session.capture == nil else { return }
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
            session.status = "Fichier audio prêt"
            tab = .transcription
        }
    }

    private func toggleRecording() {
        guard !session.busy else { return }
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
                    session.status = "Enregistrement prêt · micro et audio système"
                } else {
                    session.recordedTracks = nil
                    session.recording = nil
                    session.transcript = ""
                    let next = AudioCapture()
                    session.status = "Vérification des autorisations…"
                    try await next.start()
                    session.capture = next
                    session.status = "Enregistrement en cours"
                    openWindow(id: "meeting")
                }
            } catch { session.status = error.localizedDescription }
        }
    }

    private func transcribe() {
        guard !session.busy, let recording = session.recording else { return }
        guard hasKey else {
            showingSettings = true
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
                showingSettings = true
            } catch { session.status = error.localizedDescription }
        }
    }
}
