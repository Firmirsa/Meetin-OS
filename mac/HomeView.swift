import AppKit
import AVFoundation
import SwiftUI

struct HomeView: View {
    @Environment(\.openWindow) private var openWindow
    @Bindable var session: MeetingSession
    @AppStorage(MeetingSession.systemAudioStateKey) private var systemAudioState = ""
    @State private var microphone = AVCaptureDevice.authorizationStatus(for: .audio)

    private var firstName: String? {
        NSFullUserName().split(separator: " ").first.map(String.init)
    }

    private var dateLine: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateFormat = "EEEE d MMMM"
        return formatter.string(from: Date()).uppercased(with: formatter.locale)
    }

    private var hasKey: Bool {
        !session.key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(dateLine)
                        .font(.mtSans(11, weight: .medium))
                        .tracking(2)
                        .foregroundStyle(Color.mtAccentText)
                        .padding(.bottom, 16)
                    title
                        .padding(.bottom, 12)
                    Text("Lance l’enregistrement quand l’appel commence. Meetin-OS garde tes notes et la transcription, et t’aide à préparer les tâches à valider.")
                        .font(.mtSans(15))
                        .lineSpacing(4)
                        .foregroundStyle(Color.mtInk2)
                        .frame(maxWidth: 560, alignment: .leading)
                        .padding(.bottom, 20)
                    readiness
                        .padding(.bottom, 34)
                    HStack(alignment: .firstTextBaseline) {
                        Text("Réunions récentes")
                            .font(.mtSerif(24))
                            .accessibilityAddTraits(.isHeader)
                        Spacer()
                        Button { session.route = .meetings } label: {
                            Label("Voir tout", systemImage: "arrow.right").labelStyle(TrailingIconLabelStyle())
                        }
                        .buttonStyle(MTCapsuleLinkStyle())
                    }
                    .padding(.bottom, 14)
                    recentMeetings
                }
                .frame(maxWidth: 800, alignment: .leading)
                .padding(.horizontal, 48)
                .padding(.top, 32)
                .padding(.bottom, 20)
                .frame(maxWidth: .infinity)
            }
            Rectangle().fill(Color.mtLine).frame(height: 1)
            actionBar
                .padding(.horizontal, 24)
                .padding(.vertical, 18)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshMicrophone()
        }
        .onChange(of: session.capture == nil) { refreshMicrophone() }
        .onChange(of: session.status) { refreshMicrophone() }
    }

    private var title: some View {
        ViewThatFits(in: .horizontal) {
            heading(size: 58)
            heading(size: 46)
            heading(size: 36)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(firstName.map { "Bonjour \($0). " } ?? "")Prêt pour la prochaine réunion ?")
        .accessibilityAddTraits(.isHeader)
    }

    private func heading(size: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if let firstName { Text("Bonjour \(firstName).").fixedSize() }
            HStack(spacing: size * 0.2) {
                Text("Prêt pour la").fixedSize()
                HeroHighlight(text: "prochaine réunion")
                Text("?").fixedSize()
            }
        }
        .font(.mtSerif(size))
    }

    private var readiness: some View {
        HStack(spacing: 18) {
            statusDot(microphoneText, microphoneColor)
            statusDot(systemAudioText, systemAudioColor)
            if hasKey {
                statusDot("Clé Gladia enregistrée", .mtAccent)
            } else {
                Button { session.route = .settings } label: {
                    HStack(spacing: 7) {
                        Circle().fill(Color.mtWarn).frame(width: 7, height: 7).accessibilityHidden(true)
                        Text("Ajouter la clé Gladia").font(.mtSans(13)).underline().foregroundStyle(Color.mtInk)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint("Ouvre les paramètres")
            }
        }
    }

    private func statusDot(_ text: String, _ color: Color) -> some View {
        HStack(spacing: 7) {
            Circle().fill(color).frame(width: 7, height: 7).accessibilityHidden(true)
            Text(text).font(.mtSans(13)).foregroundStyle(Color.mtInk2)
        }
    }

    private var microphoneText: String {
        switch microphone {
        case .authorized: "Micro autorisé"
        case .notDetermined: "Micro à autoriser"
        default: "Micro refusé"
        }
    }

    private var microphoneColor: Color {
        switch microphone {
        case .authorized: .mtAccent
        case .notDetermined: .mtWarn
        default: .mtRec
        }
    }

    // macOS n'expose pas cette autorisation : l'état vient du dernier enregistrement réel.
    private var systemAudioText: String {
        switch systemAudioState {
        case "ok": "Audio système autorisé"
        case "denied": "Audio système refusé"
        case "silent": "Audio système silencieux"
        default: "Audio système non vérifié"
        }
    }

    private var systemAudioColor: Color {
        switch systemAudioState {
        case "ok": .mtAccent
        case "denied": .mtRec
        default: .mtWarn
        }
    }

    @ViewBuilder private var recentMeetings: some View {
        let recent = session.store.recent()
        if recent.isEmpty {
            Text("Aucune réunion pour l’instant. Ton premier enregistrement apparaîtra ici.")
                .font(.mtSans(14))
                .foregroundStyle(Color.mtInk2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)
                .mtGlass()
        } else {
            MeetingList(records: recent, session: session)
        }
    }

    private var actionBar: some View {
        VStack(spacing: 10) {
            if session.status != "Prêt à enregistrer", !session.statusBelongsToMeeting {
                HStack(spacing: 7) {
                    if session.busy { ProgressView().controlSize(.small) }
                    Text(session.status)
                        .font(.mtSans(13))
                        .foregroundStyle(Color.mtInk2)
                        .multilineTextAlignment(.center)
                        .accessibilityAddTraits(.updatesFrequently)
                }
            }
            if let help = session.permissionHelp, !session.busy {
                Button(help.settingsLabel, systemImage: "arrow.up.right.square") {
                    NSWorkspace.shared.open(help.settingsURL)
                }
                .buttonStyle(.link)
            }
            HStack(spacing: 10) {
                if session.meetingIsActive {
                    Button("Afficher la réunion", systemImage: "rectangle.on.rectangle") {
                        openWindow(id: "meeting")
                    }
                    .buttonStyle(.mtGhost)
                }
                if session.capture == nil {
                    Button(action: toggleRecording) {
                        HStack(spacing: 10) {
                            ZStack {
                                Circle().fill(Color.mtOnAccent).frame(width: 14, height: 14)
                                Circle().fill(Color.mtAccent).frame(width: 5, height: 5)
                            }
                            .accessibilityHidden(true)
                            Text("Commencer à enregistrer")
                            Text("⌘R").font(.mtSans(11)).opacity(0.6).accessibilityHidden(true)
                        }
                    }
                    .buttonStyle(RecordCapsuleStyle())
                    .keyboardShortcut("r", modifiers: .command)
                    .disabled(!session.canSwitchMeeting)
                } else {
                    Button("Arrêter", systemImage: "stop.fill", action: toggleRecording)
                        .buttonStyle(.mtGhost)
                        .disabled(session.busy)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func toggleRecording() {
        CaptureView.toggleRecording(session: session, openWindow: openWindow)
    }

    private func refreshMicrophone() {
        microphone = AVCaptureDevice.authorizationStatus(for: .audio)
    }
}

// Le geste de marque : le citron balaie le texte une fois, comme un coup de feutre.
private struct HeroHighlight: View {
    let text: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var swept = HeroHighlight.hasSwept
    private static var hasSwept = false

    var body: some View {
        Text(text)
            .fixedSize()
            .foregroundStyle(swept ? Color.mtOnAccent : Color.mtInk)
            .padding(.horizontal, 6)
            .background(
                MTHighlightShape()
                    .fill(Color.mtAccent)
                    .scaleEffect(x: swept ? 1 : 0, y: 1, anchor: .leading)
            )
            .onAppear {
                guard !swept else { return }
                Self.hasSwept = true
                if reduceMotion {
                    swept = true
                } else {
                    withAnimation(.timingCurve(0.65, 0, 0.35, 1, duration: 0.68).delay(0.35)) { swept = true }
                }
            }
    }
}

private struct RecordCapsuleStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.mtSans(15, weight: .medium))
            .foregroundStyle(Color.mtOnAccent)
            .padding(.horizontal, 26)
            .frame(height: 48)
            .background(configuration.isPressed ? Color.mtAccentHover : Color.mtAccent, in: Capsule())
            .opacity(isEnabled ? 1 : 0.55)
            .contentShape(Capsule())
    }
}

private struct TrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.title
            configuration.icon.font(.system(size: 11))
        }
    }
}
