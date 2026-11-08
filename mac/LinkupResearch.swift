import SwiftUI

struct LinkupResearch: View {
    let client: AgentClient?
    let available: Bool?
    @State private var query = ""
    @State private var result: AgentResearch?
    @State private var error = ""
    @State private var request: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("Recherche publique avec Linkup").font(.headline).accessibilityAddTraits(.isHeader)
            if client == nil {
                Text("Connectez-vous avec Google pour utiliser la recherche.").font(.callout).foregroundStyle(Color.mtInk2)
            } else if available != true {
                Text(available == false ? "La recherche est indisponible : le service doit être activé par l’équipe Meetin-OS. Aucune clé ni compte Linkup ne vous est demandé." : "La disponibilité de la recherche n’a pas encore été confirmée par le serveur. Aucune configuration Linkup n’est nécessaire de votre côté.")
                    .font(.callout).foregroundStyle(Color.mtInk2)
            } else {
                Text("Le bouton Envoyer transmet votre question à Linkup. Posez une question sur des informations publiques.")
                    .font(.callout).foregroundStyle(Color.mtInk2)
                TextField("Question publique (500 caractères max.)", text: $query, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(2...4)
                    .disabled(request != nil)
                Button("Envoyer à Linkup", action: send)
                    .buttonStyle(.mtGhost)
                    .disabled(request != nil || query.utf16.count > 500 || query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if query.utf16.count > 500 {
                    Text("Raccourcissez la question à 500 caractères.").font(.callout).foregroundStyle(Color.mtWarn)
                }
                if request != nil {
                    ProgressView("Recherche en cours").controlSize(.small)
                }
                if !error.isEmpty {
                    Text(error).font(.callout).foregroundStyle(Color.mtWarn).textSelection(.enabled)
                }
                if let result {
                    Text("Réponse de Linkup").font(.headline)
                    Text(verbatim: result.answer).textSelection(.enabled)
                    let sources = result.sources.compactMap { source in source.safeURL.map { (source.name, $0) } }
                    if !sources.isEmpty {
                        Text("Sources").font(.headline)
                        ForEach(Array(sources.enumerated()), id: \.offset) { _, source in
                            Link(destination: source.1) {
                                Text(verbatim: source.0)
                            }
                            .help(source.1.absoluteString)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .mtCard()
        .onDisappear { request?.cancel() }
    }

    private func send() {
        let question = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let client, available == true, request == nil, !question.isEmpty, query.utf16.count <= 500 else { return }
        result = nil
        error = ""
        request = Task {
            defer { request = nil }
            do {
                let response = try await client.research(query: question)
                if !Task.isCancelled { result = response }
            } catch {
                if !Task.isCancelled { self.error = error.localizedDescription }
            }
        }
    }
}
