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
    @AppStorage(MeetingSession.liveTranscriptionKey) private var liveTranscription = true
    @State private var draftKey = ""
    @State private var keyMessage = ""

    private var trimmedDraft: String { draftKey.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        SettingsScaffold(title: "Paramètres", session: session) {
            SettingsSection(title: "Transcription") {
                HStack {
                    Text("Clé API Gladia").font(.mtSans(14, weight: .medium))
                    Spacer()
                    MTPill(
                        text: session.trimmedKey.isEmpty ? "Aucune clé" : "Clé enregistrée",
                        kind: session.trimmedKey.isEmpty ? .wait : .ok
                    )
                }
                Text("Meetin-OS utilise Gladia pour transcrire l’audio. La clé est gardée dans le trousseau de ce Mac.")
                    .foregroundStyle(Color.mtInk2)
                SecureField(session.trimmedKey.isEmpty ? "Colle ta clé ici" : "Colle une nouvelle clé pour la remplacer", text: $draftKey)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Clé API Gladia")
                    .onSubmit(saveKey)
                HStack(spacing: 10) {
                    Button("Enregistrer la clé", action: saveKey)
                        .buttonStyle(.mtPrimary)
                        .disabled(trimmedDraft.isEmpty)
                    if !session.trimmedKey.isEmpty {
                        Button("Retirer", action: removeKey).buttonStyle(.mtGhost)
                    }
                    Link("Obtenir une clé", destination: URL(string: "https://app.gladia.io")!)
                        .font(.mtSans(13))
                }
                if !keyMessage.isEmpty {
                    Text(keyMessage).font(.mtSans(13)).foregroundStyle(Color.mtInk2)
                }
                Rectangle().fill(Color.mtLine).frame(height: 1)
                Toggle("Transcription en direct pendant l’enregistrement", isOn: $liveTranscription)
                    .tint(Color.mtControlTint)
                Text("L’audio est envoyé en continu à Gladia pendant l’enregistrement.")
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

private extension SettingsPage {
    func saveKey() {
        guard !trimmedDraft.isEmpty else { return }
        session.key = trimmedDraft
        keyMessage = GladiaKeyStore.save(trimmedDraft)
            ? "Clé enregistrée. Gladia la vérifiera à la première transcription."
            : "Trousseau indisponible : la clé servira uniquement jusqu’à la fermeture de l’app."
        draftKey = ""
    }

    func removeKey() {
        session.key = ""
        keyMessage = GladiaKeyStore.delete() ? "Clé retirée de ce Mac." : "Impossible de retirer la clé du trousseau."
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
