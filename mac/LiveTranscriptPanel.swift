import SwiftUI

struct LiveTranscriptPanel: View {
    let live: LiveTranscription
    var paused = false
    var participants: MeetingParticipants? = nil
    let openSettings: () -> Void
    @State private var followsEnd = true

    private var lines: [LiveTranscript.Line] { live.transcript.lines }

    private var statusText: String {
        if paused { return "Direct en pause. Le texte est conservé." }
        return switch live.state {
        case .connecting: "Connexion à Gladia…"
        case .live: "En direct"
        case .reconnecting: "Connexion perdue, nouvelle tentative. L’enregistrement continue."
        case .unauthorized: "La connexion à Meetin-OS a expiré. L’enregistrement continue."
        case .ended: "Le direct s’est arrêté. L’enregistrement continue."
        case .failed(let message): "Direct indisponible : \(message) L’enregistrement continue."
        }
    }

    private var statusColor: Color {
        if paused { return .mtWarn }
        return switch live.state {
        case .live: .mtAccent
        case .connecting, .reconnecting, .ended: .mtWarn
        case .unauthorized, .failed: .mtRec
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Circle().fill(statusColor).frame(width: 7, height: 7).accessibilityHidden(true)
                Text(statusText)
                    .font(.mtSans(13))
                    .foregroundStyle(Color.mtInk2)
                    .accessibilityAddTraits(.updatesFrequently)
                if live.state == .unauthorized {
                    Button("Se reconnecter", action: openSettings).buttonStyle(.link)
                }
            }
            if live.lostAudio, live.state == .live || live.state == .reconnecting {
                Text("Une partie de l’audio n’a pas pu être envoyée pendant la coupure. Le fichier reste complet : « Transcrire » peut reprendre tout l’appel.")
                    .font(.mtSans(12))
                    .foregroundStyle(Color.mtWarn)
            }
            if !lines.isEmpty {
                Button("Copier") {
                    NSPasteboard.general.clearContents()
                    let text = participants?.render(lines.map(\.structured)) ?? live.transcript.finalText
                    NSPasteboard.general.setString(text, forType: .string)
                }
                .buttonStyle(.link)
                .accessibilityLabel("Copier la transcription")
            }
            ScrollViewReader { reader in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        if lines.isEmpty {
                            if !paused && live.state == .connecting {
                                VStack(alignment: .leading, spacing: 10) {
                                    ForEach(0..<3) { index in
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(Color.mtInk2.opacity(0.16))
                                            .frame(maxWidth: index == 2 ? 180 : .infinity)
                                            .frame(height: 12)
                                    }
                                }
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel("Chargement de la transcription en direct")
                            } else {
                                Text(paused ? "Reprends l’enregistrement pour continuer le direct." : "Le texte apparaîtra ici quand quelqu’un parlera.")
                                    .font(.mtSans(14))
                                    .foregroundStyle(Color.mtInk2)
                            }
                        }
                        ForEach(lines) { line in
                            Text(participants?.render([line.structured]) ?? line.formatted)
                                .font(.mtSans(14))
                                .lineSpacing(4)
                                .foregroundStyle(line.isFinal ? Color.mtInk : Color.mtInk2)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        Color.clear.frame(height: 1).id("end")
                    }
                    .padding(14)
                }
                .frame(minHeight: 180, maxHeight: 260)
                .onScrollGeometryChange(for: Bool.self) { geometry in
                    geometry.contentOffset.y + geometry.containerSize.height >= geometry.contentSize.height - 24
                } action: { _, atEnd in
                    followsEnd = atEnd
                }
                .onChange(of: lines) {
                    if followsEnd { reader.scrollTo("end", anchor: .bottom) }
                }
                .mtGlass()
            }
        }
    }
}
