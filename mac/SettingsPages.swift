import AppKit
import SwiftUI

private struct SettingsScaffold<Content: View>: View {
    let title: String
    let session: MeetingSession
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if session.recording != nil, session.capture == nil {
                    Button { session.route = .meetingDetail } label: {
                        Label("Revenir à la réunion", systemImage: "chevron.left").font(.mtSans(13))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.mtInk2)
                }
                Text(title).font(.mtSerif(40)).accessibilityAddTraits(.isHeader)
                content
            }
            .frame(maxWidth: 620, alignment: .leading)
            .padding(.horizontal, 48)
            .padding(.vertical, 40)
            .frame(maxWidth: .infinity)
        }
    }
}

private struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.mtSerif(22)).accessibilityAddTraits(.isHeader)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .mtGlass()
    }
}

struct SettingsPage: View {
    @Bindable var session: MeetingSession
    @AppStorage("detectZoomMeetings") private var detectZoomMeetings = false

    var body: some View {
        SettingsScaffold(title: "Paramètres", session: session) {
            SettingsSection(title: "Transcription") {
                Text("Meetin-OS utilise Gladia pour transcrire l’audio. La clé sert uniquement pendant cette session.")
                    .foregroundStyle(Color.mtInk2)
                SecureField("Clé API Gladia", text: $session.key)
                    .textFieldStyle(.roundedBorder)
            }
            SettingsSection(title: "Autorisations audio") {
                Text("Au premier enregistrement, macOS peut demander l’accès au micro et à l’audio du système.")
                    .foregroundStyle(Color.mtInk2)
                HStack {
                    Button("Microphone") { NSWorkspace.shared.open(AudioPermissionHelp.microphone.settingsURL) }
                        .buttonStyle(.mtGhost)
                    Button("Audio du système") { NSWorkspace.shared.open(AudioPermissionHelp.systemAudio.settingsURL) }
                        .buttonStyle(.mtGhost)
                }
            }
            SettingsSection(title: "Détection Zoom") {
                Toggle("Ouvrir la fenêtre quand je rejoins une réunion Zoom", isOn: $detectZoomMeetings)
                    .tint(Color.mtControlTint)
                if detectZoomMeetings {
                    Text("L’accès à l’accessibilité sert à détecter les fenêtres Zoom. L’enregistrement se lance manuellement.")
                        .foregroundStyle(Color.mtInk2)
                    Button("Ouvrir les réglages d’accessibilité") {
                        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
                        NSWorkspace.shared.open(url)
                    }
                    .buttonStyle(.mtGhost)
                }
            }
        }
    }
}

struct AccountPage: View {
    @Bindable var session: MeetingSession
    @AppStorage("webWorkspaceURL") private var webWorkspaceURL = "http://localhost:3000"

    private var addressIsValid: Bool { MeetinSite.baseURL(webWorkspaceURL) != nil }

    var body: some View {
        SettingsScaffold(title: "Compte", session: session) {
            SettingsSection(title: "Accès de l’équipe") {
                Text("Meetin-OS n’a pas de compte utilisateur. L’onglet Agent et l’abonnement passent par le site de l’équipe.")
                    .foregroundStyle(Color.mtInk2)
                TextField("Adresse du site Meetin-OS", text: $webWorkspaceURL)
                    .textFieldStyle(.roundedBorder)
                    .disabled(session.agent.busy)
                if !addressIsValid {
                    Text("Utilise une adresse https, ou http sur localhost, sans chemin.")
                        .font(.mtSans(13))
                        .foregroundStyle(Color.mtWarn)
                }
                SecureField("Code d’accès de l’équipe", text: $session.agentAccessCode)
                    .textFieldStyle(.roundedBorder)
                    .disabled(session.agent.busy)
                Text("Le code reste en mémoire pendant cette session.")
                    .font(.mtSans(13))
                    .foregroundStyle(Color.mtInk2)
            }
        }
    }
}
