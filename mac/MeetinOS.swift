import AppKit
import ApplicationServices
import SwiftUI
import UniformTypeIdentifiers

@main
struct MeetinOS: App {
    @State private var meeting = MeetingSession()

    var body: some Scene {
        WindowGroup { CaptureView(session: meeting) }
        Window("Réunion Meetin-OS", id: "meeting") {
            CaptureView(session: meeting, isMeetingWindow: true)
        }
        .defaultSize(width: 720, height: 520)
    }
}

@MainActor
@Observable
final class MeetingSession {
    var capture: AudioCapture?
    var recording: URL?
    var busy = false
    var key = ProcessInfo.processInfo.environment["GLADIA_API_KEY"] ?? ""
    var status = "Prêt à enregistrer"
    var transcript = ""
    var notes = ""
    var zoomDetector = ZoomMeetingDetector()
}

struct CaptureView: View {
    private enum MeetingTab: Hashable { case transcription, agent }

    @Environment(\.openWindow) private var openWindow
    @Bindable var session: MeetingSession
    var isMeetingWindow = false
    @AppStorage("detectZoomMeetings") private var detectZoomMeetings = false
    @State private var showingSettings = false
    @State private var tab: MeetingTab = .transcription

    private var hasKey: Bool {
        !session.key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 9) {
                Image(systemName: "waveform").foregroundStyle(Color.accentColor)
                Text("Meetin-OS").font(.headline)
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

            Divider()

            if isMeetingWindow {
                Picker("Vue de la réunion", selection: $tab) {
                    Text("Transcription").tag(MeetingTab.transcription)
                    Text("Agent").tag(MeetingTab.agent)
                }
                .pickerStyle(.segmented)
                .padding(14)
            }

            if isMeetingWindow && tab == .agent {
                ContentUnavailableView(
                    "Agent de réunion",
                    systemImage: "sparkles",
                    description: Text("L’agent et la validation des tâches seront disponibles dans cet onglet une fois intégrés.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        Text(isMeetingWindow ? "Transcription de la réunion" : "Carnet de réunion")
                            .font(.system(size: 32, weight: .semibold, design: .serif))
                            .accessibilityAddTraits(.isHeader)
                        Text("Prenez des notes pendant l’appel, puis retrouvez la transcription ici.")
                            .foregroundStyle(.secondary)
                        Text("Notes").font(.headline).accessibilityAddTraits(.isHeader)
                        ZStack(alignment: .topLeading) {
                            TextEditor(text: $session.notes)
                                .font(.body)
                                .scrollContentBackground(.hidden)
                                .accessibilityLabel("Notes de réunion")
                            if session.notes.isEmpty {
                                Text("Points clés, décisions, questions…")
                                    .foregroundStyle(.secondary)
                                    .padding(.leading, 5)
                                    .padding(.top, 1)
                                    .allowsHitTesting(false)
                                    .accessibilityHidden(true)
                            }
                        }
                        .frame(minHeight: 116)
                        .padding(10)
                        .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 10))

                        if isMeetingWindow && session.transcript.isEmpty {
                            Text("La transcription sera disponible après l’arrêt de l’enregistrement et l’envoi à Gladia.")
                                .foregroundStyle(.secondary)
                        }
                        if !session.transcript.isEmpty {
                            Divider()
                            HStack {
                                Text("Transcription").font(.headline).accessibilityAddTraits(.isHeader)
                                Spacer()
                                Button("Copier") {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(session.transcript, forType: .string)
                                }
                                .accessibilityLabel("Copier la transcription")
                            }
                            Text(session.transcript).textSelection(.enabled)
                        }
                    }
                    .frame(maxWidth: 620, alignment: .leading)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 24)
                    .frame(maxWidth: .infinity)
                }
                .background(Color(nsColor: .textBackgroundColor))
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 7) {
                    if session.busy {
                        ProgressView().controlSize(.small)
                    } else {
                        Circle()
                            .fill(session.capture == nil ? Color.secondary : Color.red)
                            .frame(width: 7, height: 7)
                            .accessibilityHidden(true)
                    }
                    Text(session.status)
                        .font(.callout)
                        .foregroundStyle(.secondary)
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
                            .buttonStyle(.borderedProminent)
                    } else {
                        Button(session.capture == nil ? "Enregistrer" : "Arrêter",
                               systemImage: session.capture == nil ? "mic" : "stop.fill",
                               action: toggleRecording)
                            .buttonStyle(.borderedProminent)
                            .tint(session.capture == nil ? Color.accentColor : .red)
                    }
                }
                .disabled(session.busy)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 14)
        }
        .frame(minWidth: 560, minHeight: 400)
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
                    .foregroundStyle(.secondary)
                SecureField("Clé API Gladia", text: $session.key)
                    .textFieldStyle(.roundedBorder)
                Divider()
                Toggle("Ouvrir la fenêtre quand je rejoins une réunion Zoom", isOn: $detectZoomMeetings)
                Text("Activez Meetin-OS dans Réglages Système → Confidentialité et sécurité → Accessibilité. Vous lancez l’enregistrement depuis la fenêtre de réunion.")
                    .foregroundStyle(.secondary)
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
            .frame(width: 400)
        }
        .toolbar {
            if !isMeetingWindow && (session.capture != nil || session.recording != nil) {
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

    private func openRecording() {
        guard !session.busy, session.capture == nil else { return }
        session.busy = true
        let picker = NSOpenPanel()
        picker.allowedContentTypes = [.mpeg4Audio]
        picker.message = "Choisissez un fichier M4A à écouter ou à transcrire."
        picker.begin { response in
            session.busy = false
            guard response == .OK, let file = picker.url else { return }
            session.recording = file
            session.transcript = ""
            session.status = "Fichier audio prêt"
            openWindow(id: "meeting")
        }
    }

    private func toggleRecording() {
        guard !session.busy else { return }
        session.busy = true
        Task {
            defer { session.busy = false }
            do {
                if let current = session.capture {
                    session.capture = nil
                    session.status = "Préparation du fichier audio…"
                    session.recording = try await current.stop()
                    session.status = "Enregistrement prêt · micro et audio système"
                } else {
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
                session.transcript = try await Gladia(key: session.key.trimmingCharacters(in: .whitespacesAndNewlines)).transcribe(recording)
                session.status = "Transcription prête"
            } catch Gladia.RequestError.unauthorized {
                session.status = Gladia.RequestError.unauthorized.localizedDescription
                showingSettings = true
            } catch { session.status = error.localizedDescription }
        }
    }
}
