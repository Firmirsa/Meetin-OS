import Foundation

func detected(_ id: String, title: String, task: String = "Faire la tâche.", replaces: String? = nil) throws -> DetectedTask {
    var values: [String: Any] = [
        "id": id, "executor": "devin", "destination": "Firmirsa/Meetin-OS", "title": title, "task": task,
        "quote": "extrait", "clarifications": [Any](), "approval": "signature-\(id)"
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
        responses = [.success([try detected("a", title: "Envoyer le devis", task: "Léa envoie le devis.")])]
        await detector.tick()
        await detector.tick()
        precondition(calls.count == 1, "texte inchangé, aucun nouvel appel")
        precondition(detector.proposals.count == 1 && announced == ["Envoyer le devis"])

        // Une correction met à jour la tâche sans la réannoncer, et le plan signé suit
        text += "\n[00:09] Micro · Finalement, Karim le fait mardi."
        responses = [.success([try detected("b", title: "Devis pour Atlas", task: "Karim envoie le devis mardi.", replaces: "a")])]
        await detector.tick()
        precondition(calls[1].1 == [KnownTask(ref: "a", title: "Envoyer le devis", task: "Léa envoie le devis.")], "tâches connues envoyées")
        precondition(detector.proposals.count == 1 && detector.proposals[0].id == "a", "identifiant stable")
        precondition(detector.proposals[0].review.approval == "signature-b", "dernier plan signé")
        precondition(announced.count == 1, "une seule annonce par tâche")
        precondition(updated == ["a"], "mise à jour signalée")

        // Doublon de titre : mise à jour, pas de nouvelle tâche
        text += "\n[00:15] Micro · Oui, le devis."
        responses = [.success([try detected("c", title: "DEVIS POUR ATLAS")])]
        await detector.tick()
        precondition(detector.proposals.count == 1 && announced.count == 1, "doublon fusionné")

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

        // Fenêtre : lignes entières et limite du serveur
        let long = (0..<400).map { "[00:\($0)] Micro · Une phrase avec des accents éàç." }.joined(separator: "\n")
        let window = TaskDetector.window(long)
        precondition(window.utf16.count <= TaskDetector.maxTranscript, "limite du serveur")
        precondition(window.hasPrefix("[00:") && long.hasSuffix(window), "lignes entières, les plus récentes")
        let single = String(repeating: "é", count: 9_000)
        precondition(TaskDetector.window(single).utf16.count <= TaskDetector.maxTranscript)

        print("Détection de tâches : tests réussis")
    }
}
