import SwiftUI

struct LiveTranscriptPanel: View {
    let live: LiveTranscription
    let openSettings: () -> Void
    @State private var followsEnd = true

    private var lines: [LiveTranscript.Line] { live.transcript.lines }

    private var statusText: String {
        switch live.state {
        case .connecting: "Connexion à Gladia…"
        case .live: "En direct"
        case .partial(let track): "Direct partiel : une seule piste (\(track.label)). L’autre piste est indisponible. L’enregistrement continue."
        case .reconnecting: "Connexion perdue, nouvelle tentative. L’enregistrement continue."
        case .unauthorized: "Gladia a refusé la clé. L’enregistrement continue."
        case .ended: "Le direct s’est arrêté. L’enregistrement continue."
        case .failed(let message): "Direct indisponible : \(message) L’enregistrement continue."
        }
    }

    private var statusColor: Color {
        switch live.state {
        case .live: .mtAccent
        case .connecting, .reconnecting, .ended, .partial: .mtWarn
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
                    Button("Modifier la clé", action: openSettings).buttonStyle(.link)
                }
            }
            if live.lostAudio {
                Text("Une partie de l’audio n’a pas pu être envoyée pendant la coupure. Le fichier reste complet : « Transcrire » peut reprendre tout l’appel.")
                    .font(.mtSans(12))
                    .foregroundStyle(Color.mtWarn)
            }
            ScrollViewReader { reader in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        if lines.isEmpty {
                            Text("Le texte apparaîtra ici quand quelqu’un parlera.")
                                .font(.mtSans(14))
                                .foregroundStyle(Color.mtInk2)
                        }
                        ForEach(lines) { line in
                            Text(line.formatted)
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
