import Foundation

func detected(_ id: String, title: String, task: String = "Faire la tâche.", replaces: String? = nil, quote: String = "extrait") throws -> DetectedTask {
    var values: [String: Any] = [
        "id": id, "executor": "devin", "destination": "Firmirsa/Meetin-OS", "title": title, "task": task,
        "quote": quote, "clarifications": [Any](), "approval": "signature-\(id)"
    ]
    if let replaces { values["replaces"] = replaces }
    return try JSONDecoder().decode(DetectedTask.self, from: JSONSerialization.data(withJSONObject: values))
}

@main
struct TaskDetectionSmoke {
    @MainActor
    static func main() async throws {
        var text = ""
        var calls: [(String, [KnownTask])] = []
        var responses: [Result<[DetectedTask], Error>] = []
        var announced: [String] = []
        let detector = TaskDetector(text: { text }) { sent, known in
            calls.append((sent, known))
            return try responses.removeFirst().get()
        }
        detector.onNewProposal = { announced.append($0.review.title) }
        var updated: [String] = []
        detector.onUpdatedProposal = { updated.append($0.id) }

        // Sans texte, puis sans texte nouveau : aucun appel
        await detector.tick()
        precondition(calls.isEmpty, "aucun texte, aucun appel")
        text = "[00:01] Micro · Léa envoie le devis."
        let initial = try detected("a", title: "Envoyer le devis", task: "Léa envoie le devis.")
        responses = [.success([initial])]
        await detector.tick()
        await detector.tick()
        precondition(calls.count == 1, "texte inchangé, aucun nouvel appel")
        precondition(detector.proposals.count == 1 && announced == ["Envoyer le devis"])

        // Une correction met à jour la tâche sans la réannoncer, et le plan signé suit
        text += "\n[00:09] Micro · Finalement, Karim le fait mardi."
        responses = [.success([try detected("b", title: "Devis pour Atlas", task: "Karim envoie le devis mardi.", replaces: "a")])]
        await detector.tick()
        precondition(calls[1].1 == [KnownTask(ref: "a", title: "Envoyer le devis", task: "Léa envoie le devis.",
                                             fingerprint: initial.review.detectionFingerprint)], "tâches connues envoyées")
        precondition(detector.proposals.count == 1 && detector.proposals[0].id == "a", "identifiant stable")
        precondition(detector.proposals[0].review.approval == "signature-b", "dernier plan signé")
        precondition(announced.count == 1, "une seule annonce par tâche")
        precondition(updated == ["a"], "mise à jour signalée")

        // Même acte et même citation avec un autre titre : le plan approuvé ne change pas.
        text += "\n[00:15] Micro · Oui, le devis."
        responses = [.success([try detected("c", title: "DEVIS POUR ATLAS", task: "Karim envoie le devis mardi.")])]
        await detector.tick()
        precondition(detector.proposals.count == 1 && announced.count == 1, "doublon fusionné")
        precondition(detector.proposals[0].review.approval == "signature-b" && updated == ["a"], "le plan signé reste stable")

        // Erreur passagère : le texte sera renvoyé
        text += "\n[00:20] Micro · Autre chose."
        responses = [.failure(URLError(.timedOut)), .success([])]
        await detector.tick()
        precondition(detector.lastError != nil && !detector.isStopped)
        await detector.tick()
        precondition(calls.count == 5 && detector.lastError == nil, "nouvel essai après une panne")

        // Dernier passage à l'arrêt : le texte final part une fois
        let before = calls.count
        text += "\n[00:25] Micro · Dernière phrase."
        responses = [.success([])]
        await detector.finish()
        precondition(calls.count == before + 1, "dernier passage à l'arrêt")

        // Accès refusé : plus aucun appel
        text += "\n[00:30] Micro · Encore."
        responses = [.failure(AgentClient.Failure("Code d’accès incorrect.", status: 401))]
        await detector.tick()
        let count = calls.count
        text += "\n[00:40] Micro · Toujours."
        await detector.tick()
        precondition(detector.isStopped && calls.count == count, "arrêt sur accès refusé")

        // Le titre partagé ne suffit pas à fusionner deux tâches, et le serveur calcule la même empreinte.
        let export = try detected("export", title: "Ajouter un test", task: "Tester l’export.", quote: "Karim ajoute un test pour l’export.")
        let distinct = try detected("import", title: export.review.title, task: "Tester l’import.", quote: "Léa ajoute un test pour l’import.")
        let unknown = try detected("unknown", title: "Correction inconnue", replaces: "absente")
        let sameTitle = TaskDetector(text: { "Deux engagements" }) { _, _ in [export, distinct, unknown] }
        await sameTitle.tick()
        precondition(sameTitle.proposals.map(\.id) == ["export", "import"])
        precondition(export.review.detectionFingerprint == "377ffd88854e6252c5cad6ce5b908040bda194a65964c48f323fdf1030c58762")

        // Fenêtre : lignes entières et limite du serveur
        let long = (0..<400).map { "[00:\($0)] Micro · Une phrase avec des accents éàç." }.joined(separator: "\n")
        let window = TaskDetector.window(long)
        precondition(window.utf16.count <= TaskDetector.maxTranscript, "limite du serveur")
        precondition(window.hasPrefix("[00:") && long.hasSuffix(window), "lignes entières, les plus récentes")
        let single = String(repeating: "é", count: 9_000)
        precondition(TaskDetector.window(single).utf16.count <= TaskDetector.maxTranscript)

        // Notification : le plan affiché doit être le plan courant
        typealias Actions = TaskActions
        precondition(Actions.decide(state: .pending, currentApproval: "a", shownApproval: "a", hasClient: true) == .launch)
        precondition(Actions.decide(state: .pending, currentApproval: "b", shownApproval: "a", hasClient: true) == .stale, "tâche corrigée entre-temps")
        precondition(Actions.decide(state: .pending, currentApproval: "a", shownApproval: nil, hasClient: true) == .stale)
        precondition(Actions.decide(state: .pending, currentApproval: "a", shownApproval: "a", hasClient: false) == .needsAccess)
        precondition(Actions.decide(state: .launched, currentApproval: "a", shownApproval: "a", hasClient: true) == .alreadyHandled, "pas de double lancement")
        precondition(Actions.decide(state: .ignored, currentApproval: "a", shownApproval: "a", hasClient: true) == .alreadyHandled)

        // Contexte : passé à Holo, plan réécrit, question bloquante, limite
        let original = try detected("x", title: "Corriger l’export", task: "Corriger l’export.").review
        var sent: (String, String, [AgentClarification])?
        let rewritten = try await Actions.rewrite(original, context: "  Seulement le Markdown. ") { task, quote, turns in
            sent = (task, quote, turns)
            return .review(try detected("y", title: "Corriger le Markdown").review)
        }
        guard case .review(let updated) = rewritten, updated.title == "Corriger le Markdown" else { fatalError("plan réécrit attendu") }
        precondition(sent?.0 == "Corriger l’export." && sent?.1 == "extrait")
        precondition(sent?.2.last?.answer == "Seulement le Markdown.", "contexte transmis")
        guard case .question(let asked) = try await Actions.rewrite(original, context: "Vite", prepare: { _, _, _ in .question("Quel export ?") }),
              asked == "Quel export ?" else { fatalError("une question doit bloquer") }
        guard case .review(let same) = try await Actions.rewrite(original, context: "   ", prepare: { _, _, _ in fatalError("pas d'appel sans contexte") }),
              same.approval == original.approval else { fatalError("contexte vide : plan inchangé") }
        do {
            _ = try await Actions.rewrite(original, context: String(repeating: "x", count: 601), prepare: { _, _, _ in fatalError("pas d'appel") })
            fatalError("contexte trop long refusé")
        } catch is AgentClient.Failure {}

        print("Détection de tâches : tests réussis")
    }
}
