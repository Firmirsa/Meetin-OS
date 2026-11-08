import Foundation
import Observation

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
    @ObservationIgnored var onUpdatedProposal: ((Proposal) -> Void)?

    @ObservationIgnored private let interval: Double
    @ObservationIgnored private let text: () -> String
    @ObservationIgnored private let detect: (String, [KnownTask]) async throws -> [DetectedTask]
    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private var lastSent = ""
    @ObservationIgnored private var running = false
    @ObservationIgnored private var active = false
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var observed = ""

    static let maxTranscript = 5_000
    static let maxKnown = 10
    static let maxKnownTask = 400

    init(interval: Double = 0.35, text: @escaping () -> String, detect: @escaping (String, [KnownTask]) async throws -> [DetectedTask]) {
        self.interval = interval
        self.text = text
        self.detect = detect
    }

    func start() {
        guard !active else { return }
        active = true
        generation += 1
        observe(generation)
    }

    private func observe(_ revision: Int) {
        guard active, generation == revision, !isStopped else { return }
        let current = withObservationTracking { text() } onChange: { [weak self] in
            Task { @MainActor [weak self] in self?.observe(revision) }
        }
        guard current != observed else { return }
        observed = current
        schedule()
    }

    private func schedule() {
        guard active, !running, !isStopped else { return }
        loop?.cancel()
        let revision = generation
        loop = Task { [weak self] in
            guard let self else { return }
            do { try await Task.sleep(for: .seconds(self.interval)) }
            catch { return }
            guard self.active, self.generation == revision else { return }
            await self.tick()
        }
    }

    func stop() {
        active = false
        generation += 1
        loop?.cancel()
        loop = nil
    }

    // Dernier passage à l'arrêt, sur le texte complet : attend l'appel en cours, sans bloquer plus de 40 s.
    func finish() async {
        stop()
        let deadline = Date().addingTimeInterval(40)
        while running, Date() < deadline {
            try? await Task.sleep(for: .milliseconds(200))
        }
        await tick()
    }

    // Sans nouveau texte, aucun appel. Un seul appel à la fois, et le texte n'est marqué envoyé qu'en cas de succès.
    func tick() async {
        guard !running, !isStopped else { return }
        let current = text()
        guard !current.isEmpty, current != lastSent else { return }
        running = true
        defer {
            running = false
            // Une phrase arrivée pendant la requête repart ensuite, sans concurrence.
            if text() != current { schedule() }
        }
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
            KnownTask(ref: $0.id, title: $0.review.title,
                      task: String(decoding: Array($0.review.task.utf16.prefix(Self.maxKnownTask)), as: UTF16.self),
                      fingerprint: $0.review.detectionFingerprint)
        }
    }

    private func apply(_ found: [DetectedTask]) {
        for task in found {
            if let ref = task.replaces {
                guard let index = proposals.firstIndex(where: { $0.id == ref }),
                      proposals[index].review.detectionFingerprint != task.review.detectionFingerprint else { continue }
                proposals[index].review = task.review
                onUpdatedProposal?(proposals[index])
            } else {
                guard !proposals.contains(where: { $0.review.detectionFingerprint == task.review.detectionFingerprint }) else { continue }
                let proposal = Proposal(id: task.id, review: task.review)
                proposals.append(proposal)
                onNewProposal?(proposal)
            }
        }
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
