import SwiftUI

enum IntegrationsPage {
    case catalog, agent, prepare, gladia, transcribe
}

struct IntegrationsRequest: Identifiable {
    let id = UUID()
    let page: IntegrationsPage
    var suggestedServer: URL? = nil

    static func fromLink(_ url: URL) -> Self? {
        guard let link = URLComponents(url: url, resolvingAgainstBaseURL: false),
              link.scheme == "meetinos", ["connect", "account"].contains(link.host ?? ""), link.user == nil, link.password == nil,
              link.port == nil, link.fragment == nil, link.path.isEmpty || link.path == "/",
              let items = link.queryItems, items.count == 1, items[0].name == "server",
              let address = items[0].value, let server = AgentClient.serverURL(address)
        else { return nil }
        return Self(page: link.host == "account" ? .gladia : .agent, suggestedServer: server)
    }
}

struct IntegrationsView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var session: MeetingSession
    @Binding var workspaceURL: String
    let transcribe: () -> Void
    @State private var page: IntegrationsPage
    @State private var server: String
    @State private var accountAddress: String
    @State private var code = ""
    @State private var checking = false
    @State private var issue = ""
    @FocusState private var credentialFocused: Bool

    init(session: MeetingSession, workspaceURL: Binding<String>, request: IntegrationsRequest, transcribe: @escaping () -> Void) {
        self.session = session
        self._workspaceURL = workspaceURL
        self.transcribe = transcribe
        self._page = State(initialValue: request.page)
        let address = request.suggestedServer?.absoluteString ?? workspaceURL.wrappedValue
        self._server = State(initialValue: address)
        self._accountAddress = State(initialValue: address)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            switch page {
            case .catalog: catalog
            case .agent, .prepare: agentForm
            case .gladia, .transcribe: gladiaForm
            }
            if !issue.isEmpty {
                Text(issue).font(.callout).foregroundStyle(Color.mtWarn).accessibilityAddTraits(.updatesFrequently)
            }
            if checking { ProgressView("Vérification de l’accès…").controlSize(.small) }
        }
        .padding(24)
        .frame(width: 475)
        .background(Color.mtCanvas)
        .foregroundStyle(Color.mtInk)
        .interactiveDismissDisabled(checking)
    }

    private var catalog: some View {
        let trello = session.agent.trelloSetupRequired ? false : session.agentAccess?.trello
        return VStack(alignment: .leading, spacing: 12) {
            Text("Intégrations").font(.title2.bold()).accessibilityAddTraits(.isHeader)
            Text(session.agentAccess == nil
                 ? "Le carnet et l’enregistrement sont disponibles sans compte. Connectez l’agent quand vous en avez besoin."
                 : "Le code de l’équipe est validé pour cette session.")
                .foregroundStyle(Color.mtInk2)
            if session.agentAccess?.planning == false {
                Text("Votre équipe doit activer l’agent sur son serveur. Vous pouvez continuer à utiliser le carnet.")
                    .font(.callout).foregroundStyle(Color.mtInk2)
            }
            toolRow("Gladia", purpose: "Transcrire un enregistrement", status: session.accountConnected ? "Compte connecté" : "Compte requis") {
                Button(session.accountConnected ? "Voir le compte" : "Se connecter") { show(.gladia) }
            }
            toolRow("Trello", purpose: "Créer une fiche après votre confirmation", status: toolStatus(trello)) { EmptyView() }
            toolRow("Google Calendar", purpose: "Retrouver les réunions prévues", status: "À venir") { EmptyView() }
            toolRow("Devin", purpose: "Confier une tâche de code", status: toolStatus(session.agentAccess?.devin)) { EmptyView() }
            if session.agentAccess?.planning == true && trello == false {
                Text("Demandez à votre équipe de relier son tableau Trello, puis vérifiez les accès ici.")
                    .font(.callout).foregroundStyle(Color.mtInk2)
            }
            HStack {
                Button("Fermer") { dismiss() }.keyboardShortcut(.cancelAction).disabled(checking)
                Spacer()
                if session.agentAccess == nil {
                    Button("Connecter l’agent") { show(.agent) }.buttonStyle(.mtPrimary)
                } else {
                    Button("Déconnecter", action: disconnect).disabled(checking || session.agent.busy)
                    Button("Vérifier les accès", action: refresh).buttonStyle(.mtPrimary).disabled(checking || session.agent.busy)
                }
            }
        }
    }

    private var agentForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Connecter l’agent").font(.title2.bold()).accessibilityAddTraits(.isHeader)
            Text("Utilisez le code fourni par votre équipe. Il donne accès aux outils qu’elle a configurés.")
                .foregroundStyle(Color.mtInk2)
            TextField("Adresse du site de l’équipe", text: $server).textFieldStyle(.roundedBorder).disabled(checking)
            SecureField("Code d’accès de l’équipe", text: $code)
                .textFieldStyle(.roundedBorder).focused($credentialFocused).disabled(checking)
                .onSubmit(connect)
            HStack {
                Button(session.agentAccess == nil ? "Continuer sans compte" : "Retour") {
                    if session.agentAccess == nil { dismiss() } else { show(.catalog) }
                }
                .keyboardShortcut(.cancelAction).disabled(checking)
                Spacer()
                Button(page == .prepare ? "Connecter et préparer" : "Connecter", action: connect)
                    .buttonStyle(.mtPrimary).disabled(checking || session.agent.busy || code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .onAppear { credentialFocused = true }
    }

    private var gladiaForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Compte Meetin-OS").font(.title2.bold()).accessibilityAddTraits(.isHeader)
            HostedAccountView(session: session, address: $accountAddress) {
                if workspaceURL != accountAddress {
                    disconnect()
                    workspaceURL = accountAddress
                }
                if page == .transcribe { dismiss(); transcribe() }
            }
            Button(page == .transcribe ? "Revenir au carnet" : "Retour") {
                if page == .transcribe { dismiss() } else { show(.catalog) }
            }.keyboardShortcut(.cancelAction)
        }
    }

    private func toolRow<Action: View>(_ name: String, purpose: String, status: String, @ViewBuilder action: () -> Action) -> some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                Text(name).font(.headline)
                Text(purpose).font(.callout).foregroundStyle(Color.mtInk2)
            }
            Spacer()
            Text(status).font(.caption).foregroundStyle(Color.mtInk2)
            action()
        }
        .padding(.vertical, 6)
    }

    private func toolStatus(_ configured: Bool?) -> String {
        guard let configured else { return "Option agent" }
        return configured ? "Configuré" : "À relier par l’équipe"
    }

    private func show(_ next: IntegrationsPage) {
        issue = ""
        page = next
    }

    private func connect() {
        let accessCode = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !accessCode.isEmpty else { return }
        guard let url = AgentClient.serverURL(server) else {
            issue = "Saisissez l’adresse du site de votre équipe, qui commence par https://."
            return
        }
        verify(AgentClient(baseURL: url, accessCode: accessCode), resume: page == .prepare)
    }

    private func refresh() {
        guard let url = AgentClient.serverURL(workspaceURL), !session.agentAccessCode.isEmpty else { return }
        verify(AgentClient(baseURL: url, accessCode: session.agentAccessCode), resume: false)
    }

    private func verify(_ client: AgentClient, resume: Bool) {
        guard !checking, !session.agent.busy else { return }
        checking = true
        issue = ""
        Task {
            defer { checking = false }
            do {
                let access = try await client.access()
                guard !session.agent.busy else {
                    issue = "Une tâche est en cours. Réessayez quand elle est terminée."
                    return
                }
                if session.agentAccessCode != client.accessCode || AgentClient.serverURL(workspaceURL) != client.baseURL {
                    session.agent.invalidateReview()
                    session.agent.execution = nil
                }
                if session.agent.needsAccess { session.agent.error = "" }
                session.agent.needsAccess = false
                if access.trello && session.agent.trelloSetupRequired {
                    session.agent.trelloSetupRequired = false
                    session.agent.error = ""
                }
                workspaceURL = client.baseURL.absoluteString
                session.agentAccessCode = client.accessCode
                session.agentAccess = access
                code = ""
                if resume && access.planning {
                    dismiss()
                    session.agent.prepare(using: client)
                } else {
                    show(.catalog)
                }
            } catch let failure as AgentClient.Failure {
                issue = failure.message
                if failure.status == 401 && page == .catalog {
                    page = .agent
                }
            } catch {
                issue = "Impossible de joindre le site de votre équipe. Vérifiez son adresse et réessayez."
            }
        }
    }

    private func disconnect() {
        session.agentAccessCode = ""
        session.agentAccess = nil
        session.agent.invalidateReview()
        session.agent.execution = nil
    }
}
