import SwiftUI

struct AgentExecutionView: View {
    let execution: AgentExecution
    let client: AgentClient?
    let connect: () -> Void
    let saveResult: (TrelloExecutionResult) -> Void

    @State private var issue: String?
    @State private var refresh = 0

    private struct FollowKey: Equatable {
        let token: String?
        let server: URL?
        let refresh: Int
    }

    private var trackingClient: AgentClient? {
        guard let client, client.canTrack(execution) else { return nil }
        return client
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            if let url = execution.trelloResult?.verifiedURL {
                let result = execution.trelloResult
                Label(result?.commentURL != nil ? "Commentaire vérifié" : (result?.pageURL != nil ? "Page ouverte par H" : "Fiche vérifiée"), systemImage: "checkmark.circle")
                Link(result?.commentURL != nil ? "Voir le commentaire YouTube" : (result?.pageURL != nil ? "Ouvrir la page YouTube" : "Ouvrir la fiche dans Trello"), destination: url)
            } else if execution.trelloResult != nil {
                Text(execution.trelloResult?.message ?? "H n’a pas confirmé le résultat. Consultez la session pour voir ce qui manque.")
                    .foregroundStyle(Color.mtWarn)
            } else if execution.statusEndpoint != nil {
                if trackingClient == nil {
                    Text("Reconnectez l’agent au serveur utilisé pour suivre cette tâche.")
                        .foregroundStyle(Color.mtInk2)
                    Button("Vérifier les accès", action: connect).buttonStyle(.mtGhost)
                } else if let issue {
                    Text(issue).foregroundStyle(Color.mtWarn)
                    Button("Actualiser le suivi") { refresh += 1 }.buttonStyle(.mtGhost)
                } else {
                    ProgressView("En cours").controlSize(.small)
                }
            }
            Link("Suivre dans \(execution.executor.name)", destination: execution.url)
        }
        .task(id: FollowKey(token: execution.trackingToken, server: trackingClient?.baseURL, refresh: refresh)) {
            await follow()
        }
    }

    @MainActor private func follow() async {
        guard execution.trelloResult == nil, let client = trackingClient else { return }
        issue = nil
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(270))
        do {
            repeat {
                let result = try await client.trelloStatus(execution)
                try Task.checkCancellation()
                switch result.status {
                case .verified, .unverified:
                    saveResult(result)
                    return
                case .attention:
                    issue = "H attend une intervention. Ouvrez la session pour voir la demande."
                    return
                case .pending:
                    try await Task.sleep(for: .seconds(4))
                }
            } while clock.now < deadline
            issue = "La session H est toujours en cours. Vous pouvez actualiser son suivi."
        } catch {
            if !Task.isCancelled { issue = error.localizedDescription }
        }
    }
}
