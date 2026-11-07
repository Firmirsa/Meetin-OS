import Foundation

// Cherche des tâches dans le texte définitif du direct. Ne lance jamais rien : chaque tâche attend une validation.
@MainActor
@Observable
final class TaskDetector {
    struct Proposal: Identifiable {
        // Identifiant stable, même quand une correction remplace le plan signé.
        let id: String
        var review: AgentReview
    }

    private(set) var proposals: [Proposal] = []
    private(set) var isStopped = false
    private(set) var lastError: String?
    // Une seule fois par tâche : pas à chaque mise à jour.
    @ObservationIgnored var onNewProposal: ((Proposal) -> Void)?

    @ObservationIgnored private let interval: Double
    @ObservationIgnored private let text: () -> String
    @ObservationIgnored private let detect: (String, [KnownTask]) async throws -> [DetectedTask]
    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private var lastSent = ""
    @ObservationIgnored private var running = false

    static let maxTranscript = 5_000
    static let maxKnown = 10
    static let maxKnownTask = 400

    init(interval: Double = 15, text: @escaping () -> String, detect: @escaping (String, [KnownTask]) async throws -> [DetectedTask]) {
        self.interval = interval
        self.text = text
        self.detect = detect
    }

    func start() {
        guard loop == nil else { return }
        let interval = interval
        loop = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval))
                guard !Task.isCancelled, let self, !self.isStopped else { return }
                await self.tick()
            }
        }
    }

    func stop() {
        loop?.cancel()
        loop = nil
    }

    // Sans nouveau texte, aucun appel. Un seul appel à la fois, et le texte n'est marqué envoyé qu'en cas de succès.
    func tick() async {
        guard !running, !isStopped else { return }
        let current = text()
        guard !current.isEmpty, current != lastSent else { return }
        running = true
        defer { running = false }
        do {
            let found = try await detect(Self.window(current), known())
            lastSent = current
            lastError = nil
            apply(found)
        } catch let failure as AgentClient.Failure where failure.status == 401 || failure.status == 503 {
            lastError = failure.message
            isStopped = true
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func known() -> [KnownTask] {
        proposals.suffix(Self.maxKnown).map {
            KnownTask(ref: $0.id, title: $0.review.title, task: String(decoding: Array($0.review.task.utf16.prefix(Self.maxKnownTask)), as: UTF16.self))
        }
    }

    private func apply(_ found: [DetectedTask]) {
        for task in found {
            if let index = proposals.firstIndex(where: { $0.id == task.replaces || Self.sameTitle($0.review.title, task.review.title) }) {
                proposals[index].review = task.review
            } else {
                let proposal = Proposal(id: task.id, review: task.review)
                proposals.append(proposal)
                onNewProposal?(proposal)
            }
        }
    }

    private static func sameTitle(_ first: String, _ second: String) -> Bool {
        first.compare(second, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
    }

    // Les dernières lignes entières qui tiennent dans la limite du serveur : les citations restent exactes.
    static func window(_ text: String) -> String {
        guard text.utf16.count > maxTranscript else { return text }
        var kept: [Substring] = []
        var size = 0
        for line in text.split(separator: "\n").reversed() {
            let cost = line.utf16.count + 1
            guard size + cost <= maxTranscript else { break }
            kept.append(line)
            size += cost
        }
        if kept.isEmpty { return String(decoding: Array(text.utf16.suffix(maxTranscript)), as: UTF16.self) }
        return kept.reversed().joined(separator: "\n")
    }
}
