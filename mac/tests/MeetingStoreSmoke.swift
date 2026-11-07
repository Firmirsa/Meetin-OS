import Foundation

@main
struct MeetingStoreSmoke {
    @MainActor
    static func main() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        func record(_ title: String, secondsAgo: TimeInterval) -> MeetingRecord {
            MeetingRecord(
                id: UUID(), title: title, date: Date(timeIntervalSinceNow: -secondsAgo), duration: 60,
                audioPath: "/tmp/\(title).m4a", transcript: "", notes: "", tracks: nil, source: nil, transcriptIncomplete: nil, proposals: nil
            )
        }

        let store = MeetingStore(folder: folder)
        precondition(store.meetings.isEmpty, "un dossier neuf ne contient aucune réunion")
        for index in 0..<7 { store.add(record("r\(index)", secondsAgo: Double(index) * 60)) }
        precondition(store.recent().count == 5, "récentes limitées à 5")
        precondition(store.recent().first?.title == "r0", "la plus récente en premier")

        let first = store.meetings[0].id
        store.update(first) { $0.transcript = "Bonjour."; $0.notes = "Décision" }
        store.saveNow()

        let reloaded = MeetingStore(folder: folder)
        precondition(reloaded.meetings.count == 7, "historique relu après relance")
        precondition(reloaded.meeting(id: first)?.transcript == "Bonjour.", "transcription relue")
        precondition(reloaded.meeting(id: first)?.notes == "Décision", "notes relues")

        // Tâches proposées : relues après relance, et ancien fichier sans ce champ toujours lisible
        let review = AgentReview(
            executor: .devin, destination: "Firmirsa/Meetin-OS", title: "Corriger l’export", task: "Corriger l’export.",
            quote: "extrait", clarifications: [], approval: "signature"
        )
        reloaded.update(first) {
            $0.proposals = [
                TaskProposal(id: "a", review: review),
                TaskProposal(id: "b", review: review, state: .ignored),
                TaskProposal(id: "c", review: review, state: .launched, sessionURL: URL(string: "https://app.devin.ai/sessions/x"))
            ]
        }
        reloaded.saveNow()
        let withTasks = MeetingStore(folder: folder).meeting(id: first)
        precondition(withTasks?.pendingProposals == 1, "seules les tâches en attente comptent")
        precondition(withTasks?.proposals?[0].review.approval == "signature", "plan signé relu")
        precondition(withTasks?.proposals?[2].sessionURL?.host == "app.devin.ai", "lien de session relu")
        precondition(reloaded.meetings.last?.pendingProposals == 0, "réunion sans tâche")

        let capture = folder.appendingPathComponent("capture", isDirectory: true)
        try FileManager.default.createDirectory(at: capture, withIntermediateDirectories: true)
        try Data("audio".utf8).write(to: capture.appendingPathComponent("reunion.m4a"))
        let adopted = try reloaded.adoptRecording(from: capture, id: first)
        precondition(FileManager.default.fileExists(atPath: adopted.appendingPathComponent("reunion.m4a").path), "audio déplacé")
        precondition(!FileManager.default.fileExists(atPath: capture.path), "dossier temporaire vidé")

        let file = folder.appendingPathComponent("meetings.json")
        try Data("pas du json".utf8).write(to: file)
        let damaged = MeetingStore(folder: folder)
        precondition(damaged.meetings.isEmpty && damaged.lastError != nil, "fichier illisible signalé")
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        precondition(names.contains { $0.hasPrefix("meetings.illisible-") }, "fichier illisible conservé")

        precondition(
            MeetinSite.subscriptionURL("https://exemple.test/")?.absoluteString == "https://exemple.test/onboarding#subscription",
            "lien d'abonnement"
        )
        precondition(
            MeetinSite.subscriptionURL("http://localhost:3000")?.absoluteString == "http://localhost:3000/onboarding#subscription",
            "lien d'abonnement en local"
        )
        precondition(MeetinSite.baseURL("http://exemple.test") == nil, "http refusé hors local")

        print("MeetingStore : tests réussis")
    }
}
