import Foundation

// Décisions d'une action reçue depuis une notification de tâche, sans dépendance à l'interface.
enum TaskActions {
    enum Decision: Equatable {
        case launch
        case stale
        case alreadyHandled
        case needsAccess
    }

    static let maxContext = 600

    // Une notification porte le plan qu'elle affiche : si une correction l'a remplacé, rien ne part.
    static func decide(state: TaskProposal.State, currentApproval: String, shownApproval: String?, hasClient: Bool) -> Decision {
        guard state == .pending else { return .alreadyHandled }
        guard shownApproval == currentApproval else { return .stale }
        return hasClient ? .launch : .needsAccess
    }

    enum Rewrite {
        case review(AgentReview)
        case question(String)
    }

    // Demande à Holo d'intégrer le contexte. Une question de Holo bloque le lancement.
    static func rewrite(
        _ review: AgentReview, context: String,
        prepare: (String, String, [AgentClarification]) async throws -> AgentPreparation
    ) async throws -> Rewrite {
        let text = context.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return .review(review) }
        guard text.utf16.count <= maxContext else {
            throw AgentClient.Failure("Contexte trop long : \(maxContext) caractères au maximum. La tâche n’a pas été lancée.")
        }
        let turns = review.clarifications + [AgentClarification(question: "Contexte ajouté par l’utilisateur", answer: text)]
        switch try await prepare(review.task, review.quote, Array(turns.suffix(4))) {
        case .review(let updated): return .review(updated)
        case .question(let question): return .question(question)
        }
    }
}
