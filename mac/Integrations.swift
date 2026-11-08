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
    let dismiss: () -> Void
    @Bindable var session: MeetingSession
    @Binding var workspaceURL: String
    let transcribe: () -> Void
    @State private var page: IntegrationsPage
    @State private var accountAddress: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var checking = false
    @State private var issue = ""

    init(session: MeetingSession, workspaceURL: Binding<String>, request: IntegrationsRequest, transcribe: @escaping () -> Void,
         dismiss: @escaping () -> Void) {
        self.dismiss = dismiss
        self.session = session
        self._workspaceURL = workspaceURL
        self.transcribe = transcribe
        self._page = State(initialValue: request.page)
        let address = request.suggestedServer?.absoluteString ?? workspaceURL.wrappedValue
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
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.mtCanvas)
        .foregroundStyle(Color.mtInk)
    }

    private var catalog: some View {
        return VStack(alignment: .leading, spacing: 12) {
            Text("Intégrations").font(.title2.bold()).accessibilityAddTraits(.isHeader)
            Text(session.accountConnected
                 ? session.account.usage.map { "Compte Google : \($0.email)" } ?? "Google connecté. Actualise le compte pour afficher ton identité."
                 : "Aucun compte connecté. Le carnet et l’audio local restent disponibles.")
                .foregroundStyle(Color.mtInk2)
            if session.agentAccess?.planning == false {
                Text("Votre équipe doit activer l’agent sur son serveur. Vous pouvez continuer à utiliser le carnet.")
                    .font(.callout).foregroundStyle(Color.mtInk2)
            }
            toolRow("Google Meetin-OS", purpose: "Compte, quota de transcription et accès à l’agent", status: session.accountConnected ? "Connecté" : "Facultatif") {
                if session.accountConnected {
                    Button("Gérer", systemImage: "person.crop.circle") { show(.gladia) }
                        .buttonStyle(.mtGhost).help("Afficher le compte Google lié")
                } else {
                    GoogleSignInButton(account: session.account, client: session.accountClient, onConnected: refresh)
                }
            }
            toolRow("Trello", purpose: "Connexion personnelle non disponible dans cette version", status: "À venir") { EmptyView() }
            toolRow("Google Calendar", purpose: "Google Meetin-OS ne connecte pas ton agenda", status: "À venir") { EmptyView() }
            toolRow("Devin", purpose: "Service de code via le serveur, pas un compte personnel relié ici", status: toolStatus(session.agentAccess?.devin)) { EmptyView() }
            toolRow("H Company", purpose: "Préparation des propositions via Holo, service fourni par le serveur", status: toolStatus(session.agentAccess?.planning)) { EmptyView() }
            toolRow("Linkup", purpose: "Recherche publique facultative, envoyée uniquement après clic", status: toolStatus(session.agentAccess?.linkup)) { EmptyView() }
            Text("Aucune clé d’équipe à saisir. Trello et Calendar attendent leur propre parcours de consentement.")
                .font(.callout).foregroundStyle(Color.mtInk2)
            HStack {
                Button("Fermer") { dismiss() }.keyboardShortcut(.cancelAction).disabled(checking)
                Spacer()
                if session.agentAccess == nil {
                    Button("Connecter l’agent") { show(.agent) }.buttonStyle(.mtPrimary)
                } else {
                    Button("Vérifier les accès", systemImage: "arrow.clockwise", action: refresh).buttonStyle(.mtPrimary).disabled(checking || session.agent.busy)
                }
            }
        }
    }

    private var agentForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Accès à l’agent").font(.title2.bold()).accessibilityAddTraits(.isHeader)
            Text("L’agent utilise votre connexion Google Meetin-OS.")
                .foregroundStyle(Color.mtInk2)
            HStack {
                Button(session.agentAccess == nil ? "Plus tard" : "Retour") {
                    if session.agentAccess == nil { dismiss() } else { show(.catalog) }
                }
                .keyboardShortcut(.cancelAction).disabled(checking)
                Spacer()
                Button(page == .prepare ? "Vérifier et préparer" : "Vérifier les accès", action: connect)
                    .buttonStyle(.mtPrimary).disabled(checking || session.agent.busy)
            }
        }
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
        HStack(alignment: .center, spacing: 14) {
            providerLogo(name)
            VStack(alignment: .leading, spacing: 3) {
                Text(name).font(.headline)
                Text(purpose).font(.callout).foregroundStyle(Color.mtInk2)
            }
            Spacer()
            Text(status).font(.caption).foregroundStyle(Color.mtInk2)
            action()
        }
        .padding(16)
        .background(Color.mtGlass, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.mtLine, lineWidth: 1))
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.16), value: status)
    }

    @ViewBuilder private func providerLogo(_ name: String) -> some View {
        let resource = ["Google Meetin-OS": "GoogleG", "Google Calendar": "Calendar", "Trello": "Trello",
                        "Devin": "Devin", "H Company": "HCompany", "Linkup": "Linkup"][name]
        if let resource,
           let url = Bundle.main.url(forResource: resource, withExtension: "png",
                                     subdirectory: resource == "GoogleG" ? nil : "Integrations"),
           let logo = NSImage(contentsOf: url) {
            Image(nsImage: logo).resizable().scaledToFit()
                .frame(width: 32, height: 32).padding(8)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 10))
                .accessibilityHidden(true)
        }
    }

    private func toolStatus(_ configured: Bool?) -> String {
        guard session.accountConnected else { return "Google requis" }
        guard let configured else { return "Non vérifié" }
        return configured ? "Disponible" : "Indisponible"
    }

    private func show(_ next: IntegrationsPage) {
        issue = ""
        page = next
    }

    private func connect() {
        guard let client = session.agentClient else { show(.gladia); return }
        verify(client, resume: page == .prepare)
    }

    private func refresh() {
        guard let client = session.agentClient else { show(.gladia); return }
        verify(client, resume: false)
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
                guard session.accountConnected, session.accountClient?.baseURL == client.baseURL else { return }
                if session.agent.needsAccess { session.agent.error = "" }
                session.agent.needsAccess = false
                if access.trello && session.agent.trelloSetupRequired {
                    session.agent.trelloSetupRequired = false
                    session.agent.error = ""
                }
                session.agentAccess = access
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
        session.agentAccess = nil
        session.agent.invalidateReview()
        session.agent.execution = nil
    }
}

struct IntegrationsNativePage: View {
    let session: MeetingSession
    @Binding var workspaceURL: String
    let request: IntegrationsRequest
    let back: () -> Void
    let transcribe: () -> Void
    var showsBack = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if showsBack {
                    Button(session.route == .integrations && session.pageReturnRoute != .meetingDetail ? "Retour" : "Retour à la réunion",
                           systemImage: "chevron.left", action: back)
                        .buttonStyle(.mtGhost)
                }
                IntegrationsView(session: session, workspaceURL: $workspaceURL, request: request,
                                 transcribe: transcribe, dismiss: back)
                    .id(request.id)
            }
            .frame(maxWidth: 620, alignment: .leading)
            .padding(20)
            .frame(maxWidth: .infinity)
        }
    }
}
