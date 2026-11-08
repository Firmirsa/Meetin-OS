import SwiftUI

enum MeetingWorkspaceTab: String, CaseIterable {
    case transcription, agent, summary

    var title: String {
        switch self {
        case .transcription: "Transcription"
        case .agent: "Agent"
        case .summary: "Résumé"
        }
    }
}

struct WorkspaceButtonStyle: ButtonStyle {
    var prominent = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        WorkspaceButtonBody(label: configuration.label, prominent: prominent,
                            pressed: configuration.isPressed, enabled: isEnabled)
    }
}

private struct WorkspaceButtonBody<Content: View>: View {
    let label: Content
    let prominent: Bool
    let pressed: Bool
    let enabled: Bool
    @State private var hovering = false

    var body: some View {
        label
            .font(.mtSans(13, weight: .medium))
            .foregroundStyle(prominent ? Color.mtOnAccent : Color.mtInk)
            .padding(.horizontal, 14)
            .frame(height: 40)
            .background(background, in: RoundedRectangle(cornerRadius: MTRadius.button))
            .overlay(RoundedRectangle(cornerRadius: MTRadius.button)
                .strokeBorder(prominent ? Color.clear : Color.mtLineStrong, lineWidth: 1))
            .opacity(enabled ? 1 : 0.5)
            .contentShape(RoundedRectangle(cornerRadius: MTRadius.button))
            .onHover { hovering = $0 }
    }

    private var background: Color {
        if prominent { return pressed || (hovering && enabled) ? .mtAccentHover : .mtAccent }
        return pressed ? .mtSurface : hovering && enabled ? .mtInk.opacity(0.08) : .mtGlass
    }
}

struct MeetingCaptureControls: View {
    let session: MeetingSession
    let recordOrFinish: () -> Void

    private var idle: Bool { session.captureState == .idle }
    private var paused: Bool { session.captureState == .paused }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Group {
                    if session.busy { ProgressView().controlSize(.small) }
                    else {
                        Circle().fill(idle ? Color.mtInk2 : paused ? Color.mtWarn : Color.mtRec)
                            .frame(width: 8, height: 8)
                    }
                }
                .frame(width: 16, height: 16)
                .accessibilityHidden(true)
                Text(session.busy ? session.status : idle ? session.status : paused ? "En pause" : "Enregistrement en cours")
                    .font(.mtSans(13))
                    .foregroundStyle(Color.mtInk2)
                    .accessibilityAddTraits(.updatesFrequently)
                Spacer(minLength: 4)
                if !idle {
                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                        Text(clock(session.captureActiveDuration))
                            .font(.system(size: 13, design: .monospaced))
                            .monospacedDigit()
                            .accessibilityLabel("Durée audio active : \(clock(session.captureActiveDuration))")
                    }
                }
            }
            if paused {
                Text("Audio et direct suspendus. Tes notes restent modifiables.")
                    .font(.mtSans(12)).foregroundStyle(Color.mtInk2)
            }
            if !idle, !session.busy,
               session.status != "Enregistrement en cours", session.status != "Enregistrement en pause" {
                Text(session.status)
                    .font(.mtSans(12)).foregroundStyle(Color.mtWarn)
                    .accessibilityAddTraits(.updatesFrequently)
            }
            HStack(spacing: 8) {
                Button(action: recordOrFinish) {
                    Text("Enregistrer").frame(width: 68)
                }
                .buttonStyle(WorkspaceButtonStyle(prominent: idle))
                .keyboardShortcut("r", modifiers: .command)
                .disabled(!idle || session.busy || session.agent.busy || !session.launchingProposals.isEmpty)
                .help("Démarrer une nouvelle capture locale (⌘R)")
                Button {
                    Task {
                        if paused { await session.resumeCapture() }
                        else { await session.pauseCapture() }
                    }
                } label: {
                    Text(paused ? "Reprendre" : "Pause").frame(width: 68)
                }
                .buttonStyle(WorkspaceButtonStyle())
                .disabled(idle || session.busy)
                .help(paused ? "Continuer la même réunion" : "Suspendre l’audio et la transcription")
                Button(action: recordOrFinish) {
                    Text("Terminer").frame(width: 68)
                }
                .buttonStyle(WorkspaceButtonStyle())
                .disabled(idle || session.busy)
                .help("Finaliser le fichier audio et conserver la réunion")
            }
        }
    }

    private func clock(_ duration: TimeInterval) -> String {
        let seconds = max(0, Int(duration))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}

struct MeetingSummaryView: View {
    @Binding var notes: String
    let savedMeeting: Bool
    let saveError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Résumé et notes").font(.mtSerif(36)).accessibilityAddTraits(.isHeader)
                Text("Garde les décisions, les points clés et les prochaines étapes. Ce texte est rédigé par toi, sans génération automatique.")
                    .font(.mtSans(14)).foregroundStyle(Color.mtInk2)
                ZStack(alignment: .topLeading) {
                    TextEditor(text: $notes)
                        .font(.mtSans(15))
                        .scrollContentBackground(.hidden)
                        .accessibilityLabel("Résumé et notes de la réunion")
                        .frame(minHeight: 260)
                    if notes.isEmpty {
                        Text("Décisions prises\n\nPoints à retenir\n\nProchaines étapes")
                            .font(.mtSans(15)).foregroundStyle(Color.mtInk2)
                            .padding(.horizontal, 5).padding(.top, 1)
                            .allowsHitTesting(false).accessibilityHidden(true)
                    }
                }
                .padding(14)
                .mtGlass()
                Label(saveError ?? (savedMeeting ? "Enregistrement local automatique au fil de la saisie." : "Brouillon de cette session. Enregistré avec la réunion quand tu termines la capture."),
                      systemImage: saveError == nil ? "internaldrive" : "exclamationmark.triangle")
                    .font(.mtSans(12))
                    .foregroundStyle(saveError == nil ? Color.mtInk2 : Color.mtWarn)
            }
            .frame(maxWidth: 620, alignment: .leading)
            .padding(24)
            .frame(maxWidth: .infinity)
        }
    }
}

// Les panneaux restent montés : changer d'onglet ne relance aucun service.
struct MeetingPaneVisibility: ViewModifier {
    let visible: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(visible ? 1 : 0)
            .offset(x: visible || reduceMotion ? 0 : 8)
            .allowsHitTesting(visible)
            .disabled(!visible)
            .accessibilityHidden(!visible)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: visible)
    }
}
