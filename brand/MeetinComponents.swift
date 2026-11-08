import SwiftUI

// Meetin-OS · composants SwiftUI (dépend de MeetinTheme.swift)
// Miroir de brand/components/components.css. Compilé avec l'app Mac par mac/build.sh.
//
// Règles : citron vert = fond, un seul bouton .mtPrimary par écran, pas d'ombres.
// Granola : ce que l'utilisateur écrit est en encre, ce que l'IA ajoute est en encre secondaire,
// et l'accord est marqué au surligneur (MTHighlight).

// MARK: - Surligneur (coup de feutre légèrement irrégulier)

struct MTHighlightShape: Shape {
    func path(in r: CGRect) -> Path {
        // Rayons inégaux : haut-gauche 3, haut-droit 9, bas-droit 4, bas-gauche 10 (comme le CSS .mt-hl)
        let tl: CGFloat = 3, tr: CGFloat = 9, br: CGFloat = 4, bl: CGFloat = 10
        var p = Path()
        p.move(to: CGPoint(x: r.minX + tl, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - tr, y: r.minY))
        p.addArc(center: CGPoint(x: r.maxX - tr, y: r.minY + tr), radius: tr, startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - br))
        p.addArc(center: CGPoint(x: r.maxX - br, y: r.maxY - br), radius: br, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        p.addLine(to: CGPoint(x: r.minX + bl, y: r.maxY))
        p.addArc(center: CGPoint(x: r.minX + bl, y: r.maxY - bl), radius: bl, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        p.addLine(to: CGPoint(x: r.minX, y: r.minY + tl))
        p.addArc(center: CGPoint(x: r.minX + tl, y: r.minY + tl), radius: tl, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        p.closeSubpath()
        return p
    }
}

struct MTHighlight: View {
    let text: String
    var size: CGFloat = 15
    var body: some View {
        Text(text)
            .font(.mtSans(size))
            .foregroundStyle(Color.mtOnAccent)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(MTHighlightShape().fill(Color.mtAccent))
    }
}

// MARK: - Pastille d'état

enum MTPillKind { case wait, run, ok, err }

struct MTPill: View {
    let text: String
    var kind: MTPillKind = .wait
    var onCard = false

    private var bg: Color {
        switch kind {
        case .wait: return onCard ? .mtCanvas : .mtSurface
        case .run, .ok: return .mtAccentTint
        case .err: return .mtRecTint
        }
    }
    private var fg: Color {
        switch kind {
        case .wait: return .mtInk2
        case .run, .ok: return .mtAccentText
        case .err: return .mtRec
        }
    }
    var body: some View {
        Text(text)
            .font(.mtSans(12, weight: .medium))
            .foregroundStyle(fg)
            .padding(.horizontal, 10)
            .frame(height: 24)
            .background(bg, in: Capsule())
    }
}

// MARK: - Carte « engagement proposé »

enum MTReviewState { case proposed, validated, ignored }

struct MTCommitment: Identifiable {
    let id = UUID()
    var title: String
    var owner: String
    var due: Date
    var quoteBefore: String
    var quoteHighlight: String
    var timestamp: String
    var speakers: String
}

struct MTReviewCard: View {
    @Binding var item: MTCommitment
    @Binding var state: MTReviewState
    var onValidate: () -> Void = {}
    var onIgnore: () -> Void = {}
    var onPlay: () -> Void = {}
    @State private var editing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Engagement proposé").font(.mtSans(12)).foregroundStyle(Color.mtInk2)
                Spacer()
                switch state {
                case .proposed: MTPill(text: "À valider", kind: .wait, onCard: true)
                case .validated: MTPill(text: "Validé", kind: .ok)
                case .ignored: MTPill(text: "Ignoré", kind: .wait, onCard: true)
                }
            }

            if editing {
                TextField("Titre", text: $item.title)
                    .textFieldStyle(.plain)
                    .font(.mtSerif(24))
                    .padding(4)
                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color.mtLineStrong, style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
            } else {
                Text(item.title)
                    .font(.mtSerif(24))
                    .strikethrough(state == .ignored)
                    .foregroundStyle(Color.mtInk)
            }

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Responsable").font(.mtSans(12)).foregroundStyle(Color.mtInk2)
                    TextField("Responsable", text: $item.owner)
                        .textFieldStyle(.plain)
                        .font(.mtSans(14))
                        .padding(.horizontal, 10).frame(height: 36)
                        .background(Color.mtCanvas, in: RoundedRectangle(cornerRadius: MTRadius.input))
                        .overlay(RoundedRectangle(cornerRadius: MTRadius.input).stroke(Color.mtLineStrong, lineWidth: 1))
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Échéance").font(.mtSans(12)).foregroundStyle(Color.mtInk2)
                    DatePicker("", selection: $item.due, displayedComponents: .date)
                        .labelsHidden()
                        .frame(height: 36)
                }
            }
            .disabled(state != .proposed)

            // Extrait source : l'accord est surligné, le timestamp est en mono
            HStack(alignment: .top, spacing: 12) {
                Button(action: onPlay) {
                    Image(systemName: "play.fill").font(.system(size: 11))
                        .foregroundStyle(Color.mtInk)
                        .frame(width: 32, height: 32)
                        .overlay(Circle().stroke(Color.mtLineStrong, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Écouter l’extrait à \(item.timestamp)")

                VStack(alignment: .leading, spacing: 4) {
                    (Text("« \(item.quoteBefore) ").font(.mtSans(15)) )
                        .foregroundStyle(Color.mtInk)
                    MTHighlight(text: item.quoteHighlight)
                    Text("\(item.timestamp) · \(item.speakers)")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Color.mtInk2)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.mtCanvas, in: RoundedRectangle(cornerRadius: MTRadius.input))

            if state == .proposed {
                HStack(spacing: 8) {
                    Button("Valider") { state = .validated; onValidate() }.buttonStyle(.mtPrimary)
                    Button(editing ? "Terminer" : "Corriger") { editing.toggle() }.buttonStyle(.mtGhost)
                    Button("Ignorer") { state = .ignored; onIgnore() }
                        .buttonStyle(.plain)
                        .font(.mtSans(14, weight: .medium))
                        .foregroundStyle(Color.mtInk2)
                        .padding(.horizontal, 12)
                }
            } else {
                Text(state == .validated
                     ? "Validé et envoyé à l’agent."
                     : "Ignoré. Rien n’est envoyé à l’agent.")
                    .font(.mtSans(14)).foregroundStyle(Color.mtInk2)
            }
        }
        .padding(EdgeInsets(top: 16, leading: 24, bottom: 16, trailing: 24))
        .background(Color.mtSurface, in: RoundedRectangle(cornerRadius: MTRadius.card))
        .opacity(state == .ignored ? 0.6 : 1)
    }
}

// MARK: - Suivi de l'agent (avant → après)

enum MTStepStatus { case pending, running, done, error }

struct MTAgentStep: Identifiable {
    let id = UUID()
    var title: String
    var meta: String? = nil
    var status: MTStepStatus = .pending
}

struct MTProofRow: Identifiable {
    let id = UUID()
    var label: String
    var before: String
    var after: String
}

struct MTAgentTimeline: View {
    var steps: [MTAgentStep]
    var statusText: String
    var statusKind: MTPillKind
    var proof: [MTProofRow] = []
    var alreadyUpToDate = false          // 2e validation : aucun doublon créé
    var onOpenRecord: () -> Void = {}

    private var isDone: Bool { !steps.isEmpty && steps.allSatisfy { $0.status == .done } }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("L’agent").font(.mtSerif(22)).foregroundStyle(Color.mtInk)
                Spacer()
                MTPill(text: statusText, kind: statusKind, onCard: true)
            }

            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                    HStack(alignment: .top, spacing: 12) {
                        VStack(spacing: 0) {
                            MTStepDot(status: step.status)
                            if index < steps.count - 1 {
                                Rectangle().fill(Color.mtLine).frame(width: 2).frame(maxHeight: .infinity)
                                    .padding(.top, 2)
                            }
                        }
                        .frame(width: 20)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(step.title).font(.mtSans(15))
                                .foregroundStyle(step.status == .pending ? Color.mtInk2 : Color.mtInk)
                            if let meta = step.meta {
                                Text(meta).font(.mtSans(12))
                                    .foregroundStyle(step.status == .error ? Color.mtRec : Color.mtInk2)
                            }
                        }
                        .padding(.bottom, index < steps.count - 1 ? 16 : 0)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
            }

            if isDone && !proof.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Valeurs relues sur la fiche").font(.mtSans(13, weight: .medium)).foregroundStyle(Color.mtInk2)
                    ForEach(proof) { row in
                        HStack(spacing: 12) {
                            Text(row.label).font(.mtSans(14)).foregroundStyle(Color.mtInk2)
                                .frame(width: 96, alignment: .leading)
                            Text(row.before).font(.mtSans(14)).strikethrough().foregroundStyle(Color.mtInk2)
                            MTHighlight(text: row.after, size: 14)
                        }
                    }
                    if alreadyUpToDate {
                        Text("Fiche déjà à jour : aucune nouvelle fiche créée.")
                            .font(.mtSans(13)).foregroundStyle(Color.mtAccentText)
                    }
                    Button("Ouvrir la fiche", action: onOpenRecord)
                        .buttonStyle(.plain)
                        .font(.mtSans(14, weight: .medium))
                        .foregroundStyle(Color.mtAccentText)
                        .underline()
                }
                .padding(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.mtCanvas, in: RoundedRectangle(cornerRadius: MTRadius.input))
            }
        }
        .padding(EdgeInsets(top: 16, leading: 24, bottom: 16, trailing: 24))
        .background(Color.mtSurface, in: RoundedRectangle(cornerRadius: MTRadius.card))
    }
}

struct MTStepDot: View {
    let status: MTStepStatus
    @State private var pulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            switch status {
            case .pending:
                Circle().strokeBorder(Color.mtLineStrong, lineWidth: 2)
            case .running:
                Circle().strokeBorder(Color.mtInk, lineWidth: 2)
                Circle().fill(Color.mtInk).padding(5)
                Circle().stroke(Color.mtLineStrong, lineWidth: 2)
                    .scaleEffect(pulse ? 1.4 : 1).opacity(pulse ? 0 : 1)
            case .done:
                Circle().fill(Color.mtAccent)
                Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(Color.mtOnAccent)
            case .error:
                Circle().fill(Color.mtRecTint)
                Circle().strokeBorder(Color.mtRec, lineWidth: 2)
                Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).foregroundStyle(Color.mtRec)
            }
        }
        .frame(width: 20, height: 20)
        .onAppear {
            guard status == .running, !reduceMotion else { return }
            withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) { pulse = true }
        }
        .accessibilityLabel(label)
    }

    private var label: String {
        switch status {
        case .pending: return "À faire"
        case .running: return "En cours"
        case .done: return "Terminé"
        case .error: return "Erreur"
        }
    }
}

// MARK: - Barre d'enregistrement (toujours sombre, en clair comme en sombre)

struct MTRecordGlyph: View {
    var animated = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var t = false

    private let bar = Color(red: 0xFA / 255, green: 0xF8 / 255, blue: 0xF1 / 255)
    private let dot = Color(red: 1, green: 0x6A / 255, blue: 0x4D / 255)

    var body: some View {
        let move = (animated && !reduceMotion)
        HStack(spacing: 3) {
            Text("››").offset(x: move && !t ? -4 : 0)
            Circle().fill(dot).frame(width: 8, height: 8).scaleEffect(move && t ? 1.25 : 1)
            Text("‹‹").offset(x: move && !t ? 4 : 0)
        }
        .font(.system(size: 16, weight: .bold, design: .rounded))
        .foregroundStyle(bar)
        .onAppear {
            guard move else { return }
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { t = true }
        }
        .accessibilityHidden(true)
    }
}

struct MTRecordingBar: View {
    var elapsed: TimeInterval
    var level: Double = 0.5                  // 0...1
    var paused = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var onPause: () -> Void = {}
    var onStop: () -> Void = {}

    private let barBG = Color(red: 0x14 / 255, green: 0x20 / 255, blue: 0x1C / 255)
    private let barFG = Color(red: 0xFA / 255, green: 0xF8 / 255, blue: 0xF1 / 255)

    private var timeText: String {
        let s = Int(elapsed)
        return String(format: "%02d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
    }

    var body: some View {
        HStack(spacing: 12) {
            MTRecordGlyph()
            Text(timeText)
                .font(.system(size: 14, weight: .medium, design: .monospaced))
                .foregroundStyle(barFG)
                .monospacedDigit()
            HStack(spacing: 3) {
                ForEach(0..<7, id: \.self) { i in
                    let shape = [0.45, 0.7, 1.0, 0.6, 0.9, 0.55, 0.35][i]
                    Capsule().fill(barFG.opacity(0.8))
                        .frame(width: 3, height: max(4, 24 * level * shape))
                }
            }
            .frame(height: 24)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: level)

            Button(paused ? "Reprendre" : "Pause", action: onPause)
                .buttonStyle(.plain)
                .font(.mtSans(14, weight: .medium)).foregroundStyle(barFG)
                .padding(.horizontal, 16).frame(height: 36)
                .overlay(Capsule().stroke(barFG.opacity(0.32), lineWidth: 1))
            // Un seul citron vert par écran : « Arrêter » est crème plein dans la barre
            Button("Terminer", action: onStop)
                .buttonStyle(.plain)
                .font(.mtSans(14, weight: .medium)).foregroundStyle(barBG)
                .padding(.horizontal, 16).frame(height: 36)
                .background(barFG, in: Capsule())
        }
        .padding(EdgeInsets(top: 0, leading: 14, bottom: 0, trailing: 8))
        .frame(height: 52)
        .background(barBG, in: Capsule())
        .overlay(Capsule().stroke(barFG.opacity(0.14), lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(paused ? "Enregistrement en pause" : "Enregistrement en cours")
    }
}

// MARK: - Notification « tu es en appel »

struct MTMeetingToast: View {
    var title = "Tu es en appel Zoom"
    var meta: String
    var onRecord: () -> Void = {}
    var onIgnore: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.mtSerif(19)).foregroundStyle(Color.mtInk)
                Text(meta).font(.mtSans(13)).foregroundStyle(Color.mtInk2)
            }
            HStack(spacing: 8) {
                Button("Enregistrer", action: onRecord).buttonStyle(.mtPrimary)
                Button("Ignorer", action: onIgnore)
                    .buttonStyle(.plain)
                    .font(.mtSans(14, weight: .medium)).foregroundStyle(Color.mtInk2)
                    .padding(.horizontal, 12)
            }
        }
        .padding(16)
        .frame(maxWidth: 320, alignment: .leading)
        .background(Color.mtCanvas, in: RoundedRectangle(cornerRadius: MTRadius.card))
        .overlay(RoundedRectangle(cornerRadius: MTRadius.card).stroke(Color.mtLineStrong, lineWidth: 1))
    }
}

// MARK: - Aperçu Xcode

#Preview("Composants Meetin-OS") {
    struct Demo: View {
        @State var item = MTCommitment(
            title: "Envoyer le devis à Atlas", owner: "Karim", due: Date(),
            quoteBefore: "Léa s’en charge…", quoteHighlight: "finalement, Karim le fait mardi.",
            timestamp: "12:41", speakers: "Léa, Karim")
        @State var state = MTReviewState.proposed
        var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    MTReviewCard(item: $item, state: $state)
                    MTAgentTimeline(
                        steps: [
                            MTAgentStep(title: "Retrouve la fiche « Devis Atlas »", meta: "1 fiche correspond", status: .done),
                            MTAgentStep(title: "Passe le responsable à Karim", status: .done),
                            MTAgentStep(title: "Relit la fiche pour vérifier", status: .done)
                        ],
                        statusText: "Terminé", statusKind: .ok,
                        proof: [MTProofRow(label: "Responsable", before: "Léa", after: "Karim")],
                        alreadyUpToDate: true)
                    MTMeetingToast(meta: "Point projet Atlas · 3 participants")
                    MTRecordingBar(elapsed: 761, level: 0.7)
                }
                .padding(24)
            }
            .frame(width: 520, height: 900)
            .background(Color.mtCanvas)
        }
    }
    return Demo()
}
