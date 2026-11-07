import AppKit
import SwiftUI

@main
struct MeetinOS: App {
    var body: some Scene {
        WindowGroup { CaptureView() }
    }
}

struct CaptureView: View {
    @State private var capture: AudioCapture?
    @State private var recording: URL?
    @State private var busy = false
    @State private var key = ProcessInfo.processInfo.environment["GLADIA_API_KEY"] ?? ""
    @State private var status = "Prêt à enregistrer"
    @State private var transcript = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Meetin-OS").font(.largeTitle.bold())
            Text("Capture de réunion · Micro et audio du Mac")
            Text(status).accessibilityAddTraits(.updatesFrequently)
            HStack {
                Button(capture == nil ? "Enregistrer" : "Arrêter", action: toggleRecording)
                    .keyboardShortcut(.defaultAction)
                if let recording, capture == nil {
                    Button("Écouter") { NSWorkspace.shared.open(recording) }
                    Button("Voir les pistes") { NSWorkspace.shared.activateFileViewerSelecting([recording]) }
                }
            }.disabled(busy)
            Divider()
            SecureField("Clé API Gladia", text: $key)
                .textFieldStyle(.roundedBorder)
                .disabled(busy)
            Button("Transcrire avec Gladia", action: transcribe)
                .disabled(recording == nil || capture != nil || busy || key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            if !transcript.isEmpty {
                ScrollView {
                    Text(transcript).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                }
                Button("Copier la transcription") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(transcript, forType: .string)
                }
            }
        }
        .padding(24)
        .frame(minWidth: 510, minHeight: 260)
    }

    private func toggleRecording() {
        busy = true
        Task {
            defer { busy = false }
            do {
                if let current = capture {
                    capture = nil
                    status = "Préparation du fichier audio…"
                    recording = try await current.stop()
                    status = "Enregistrement prêt · micro et audio système"
                } else {
                    recording = nil
                    transcript = ""
                    let next = AudioCapture()
                    status = "Vérification des autorisations…"
                    try await next.start()
                    capture = next
                    status = "Enregistrement en cours"
                }
            } catch { status = error.localizedDescription }
        }
    }

    private func transcribe() {
        guard let recording else { return }
        busy = true
        transcript = ""
        status = "Envoi et transcription en cours…"
        Task {
            defer { busy = false }
            do {
                transcript = try await Gladia(key: key.trimmingCharacters(in: .whitespacesAndNewlines)).transcribe(recording)
                status = "Transcription prête"
            } catch { status = error.localizedDescription }
        }
    }
}
