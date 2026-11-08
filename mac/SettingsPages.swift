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
    @AppStorage("detectZoomMeetings") private var detectCalls = true
    @AppStorage(MeetingSession.liveTranscriptionKey) private var liveTranscription = true
    var body: some View {
        SettingsScaffold(title: "Paramètres", session: session) {
            SettingsSection(title: "Transcription") {
                Text("La transcription utilise ton quota Meetin-OS. Ouvre Compte pour te connecter ou consulter ton plan.")
                    .foregroundStyle(Color.mtInk2)
                Button("Ouvrir le compte") { session.route = .account }.buttonStyle(.mtGhost)
                Toggle("Transcription en direct pendant l’enregistrement", isOn: $liveTranscription)
                    .tint(Color.mtControlTint)
                Text("L’audio est envoyé en continu à Gladia pendant l’enregistrement. Si l’agent est connecté, le texte part aussi chez Holo (H Company) toutes les 15 s pour proposer des tâches. Rien n’est lancé sans ta validation.")
                    .font(.mtSans(13))
                    .foregroundStyle(Color.mtInk2)
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
            SettingsSection(title: "Détection des appels") {
                Toggle("Me prévenir quand je rejoins un appel", isOn: $detectCalls)
                    .tint(Color.mtControlTint)
                if detectCalls {
                    Text("Google Meet dans Chrome, Zoom et WhatsApp pour Mac. Autorise l’accessibilité et les notifications, puis clique sur Enregistrer quand l’appel est détecté.")
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
    @AppStorage("webWorkspaceURL") private var webWorkspaceURL = MeetinSite.defaultAddress

    private var accountAddress: Binding<String> {
        Binding(get: { webWorkspaceURL }, set: { address in
            if MeetinSite.baseURL(address) != MeetinSite.baseURL(webWorkspaceURL) {
                session.agentAccess = nil
            }
            webWorkspaceURL = address
        })
    }

    var body: some View {
        SettingsScaffold(title: "Compte", session: session) {
            SettingsSection(title: "Compte Meetin-OS") {
                HostedAccountView(session: session, address: accountAddress)
            }
            SettingsSection(title: "Agent") {
                Text("Votre connexion Google donne accès aux outils de l’onglet Agent.")
                    .foregroundStyle(Color.mtInk2)
                LabeledContent("Adresse du site", value: webWorkspaceURL).font(.mtSans(14))
                if MeetinSite.baseURL(webWorkspaceURL) == nil {
                    Text("Utilise une adresse https, ou http sur localhost, sans chemin.")
                        .font(.mtSans(13))
                        .foregroundStyle(Color.mtWarn)
                }
                Button(session.agentAccess == nil ? "Connecter l’agent" : "Gérer l’accès") {
                    session.integrationsRequest = IntegrationsRequest(page: session.agentAccess == nil ? .agent : .catalog)
                }
                .buttonStyle(.mtPrimary)
                .disabled(session.agent.busy)
            }
        }
    }
}
