import AppKit
import SwiftUI
import UniformTypeIdentifiers

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

    @State private var notes = ""
    @State private var showingSettings = false

    private var hasKey: Bool {
        !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Carnet de réunion")
                        .font(.system(size: 32, weight: .semibold, design: .serif))
                        .accessibilityAddTraits(.isHeader)
                    Text("Prenez des notes pendant l’appel, puis retrouvez la transcription ici.")
                        .foregroundStyle(.secondary)
                    Text("Notes").font(.headline).accessibilityAddTraits(.isHeader)
                    ZStack(alignment: .topLeading) {
                        TextEditor(text: $notes)
                            .font(.body)
                            .scrollContentBackground(.hidden)
                            .accessibilityLabel("Notes de réunion")
                        if notes.isEmpty {
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

                    if !transcript.isEmpty {
                        Divider()
                        HStack {
                            Text("Transcription").font(.headline).accessibilityAddTraits(.isHeader)
                            Spacer()
                            Button("Copier") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(transcript, forType: .string)
                            }
                            .accessibilityLabel("Copier la transcription")
                        }
                        Text(transcript).textSelection(.enabled)
                    }
                }
                .frame(maxWidth: 620, alignment: .leading)
                .padding(.horizontal, 28)
                .padding(.vertical, 24)
                .frame(maxWidth: .infinity)
            }
            .background(Color(nsColor: .textBackgroundColor))

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 7) {
                    if busy {
                        ProgressView().controlSize(.small)
                    } else {
                        Circle()
                            .fill(capture == nil ? Color.secondary : Color.red)
                            .frame(width: 7, height: 7)
                            .accessibilityHidden(true)
                    }
                    Text(status)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .accessibilityAddTraits(.updatesFrequently)
                }
                HStack {
                    if let recording, capture == nil {
                        Button("Écouter", systemImage: "play.circle") { NSWorkspace.shared.open(recording) }
                        Button("Voir les pistes") { NSWorkspace.shared.activateFileViewerSelecting([recording]) }
                    }
                    Spacer()
                    if recording != nil {
                        Button("Transcrire", systemImage: "text.alignleft", action: transcribe)
                            .buttonStyle(.borderedProminent)
                    } else {
                        Button(capture == nil ? "Enregistrer" : "Arrêter",
                               systemImage: capture == nil ? "mic" : "stop.fill",
                               action: toggleRecording)
                            .buttonStyle(.borderedProminent)
                            .tint(capture == nil ? Color.accentColor : .red)
                    }
                }
                .disabled(busy)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 14)
        }
        .frame(minWidth: 560, minHeight: 400)
        .sheet(isPresented: $showingSettings) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Réglages de transcription").font(.title2.bold())
                Text("Meetin-OS utilise Gladia pour transcrire l’audio. La clé sert uniquement pendant cette session.")
                    .foregroundStyle(.secondary)
                SecureField("Clé API Gladia", text: $key)
                    .textFieldStyle(.roundedBorder)
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
            if capture == nil {
                Button("Ouvrir un enregistrement", systemImage: "folder", action: openRecording)
                    .disabled(busy)
            }
            if recording != nil, capture == nil {
                Button("Nouvel enregistrement", systemImage: "plus", action: toggleRecording)
                    .disabled(busy)
            }
        }
    }

    private func openRecording() {
        let picker = NSOpenPanel()
        picker.allowedContentTypes = [.mpeg4Audio]
        picker.message = "Choisissez un fichier M4A à écouter ou à transcrire."
        picker.begin { response in
            guard response == .OK, let file = picker.url else { return }
            recording = file
            transcript = ""
            status = "Fichier audio prêt"
        }
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
        guard hasKey else {
            showingSettings = true
            return
        }
        busy = true
        transcript = ""
        status = "Envoi et transcription en cours…"
        Task {
            defer { busy = false }
            do {
                transcript = try await Gladia(key: key.trimmingCharacters(in: .whitespacesAndNewlines)).transcribe(recording)
                status = "Transcription prête"
            } catch Gladia.RequestError.unauthorized {
                status = Gladia.RequestError.unauthorized.localizedDescription
                showingSettings = true
            } catch { status = error.localizedDescription }
        }
    }
}
