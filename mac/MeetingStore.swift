import AppKit
import Foundation

// Tâche proposée pendant une réunion. Rien ne part sans validation.
struct TaskProposal: Codable, Identifiable {
    enum State: String, Codable { case pending, launched, ignored }

    let id: String
    var review: AgentReview
    var state: State = .pending
    var sessionURL: URL?
    var execution: AgentExecution?
}

struct MeetingRecord: Codable, Identifiable {
    struct StoredTracks: Codable, Hashable {
        var microphonePath: String
        var systemPath: String
        var microphoneOffset: Double
        var systemOffset: Double
    }

    let id: UUID
    var title: String
    var date: Date
    var duration: TimeInterval
    var audioPath: String
    var transcript: String
    var notes: String
    var tracks: StoredTracks?
    var source: String?
    var transcriptIncomplete: Bool?
    var proposals: [TaskProposal]?

    var pendingProposals: Int { proposals?.filter { $0.state == .pending }.count ?? 0 }
}

// Historique local : Application Support/Meetin-OS/meetings.json et un dossier audio par réunion.
@MainActor
@Observable
final class MeetingStore {
    private(set) var meetings: [MeetingRecord] = []
    private(set) var lastError: String?

    @ObservationIgnored private let folder: URL
    @ObservationIgnored private var pendingSave: Task<Void, Never>?
    @ObservationIgnored private var canSave = true
    @ObservationIgnored private var terminationObserver: NSObjectProtocol?

    nonisolated static var defaultFolder: URL {
        URL.applicationSupportDirectory.appendingPathComponent("Meetin-OS", isDirectory: true)
    }

    private var fileURL: URL { folder.appendingPathComponent("meetings.json") }
    private var recordingsFolder: URL { folder.appendingPathComponent("recordings", isDirectory: true) }

    init(folder: URL = MeetingStore.defaultFolder) {
        self.folder = folder
        load()
        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.saveNow() }
        }
    }

    func recent(limit: Int = 5) -> [MeetingRecord] { Array(meetings.prefix(limit)) }

    func meeting(id: UUID?) -> MeetingRecord? { meetings.first { $0.id == id } }

    func add(_ record: MeetingRecord) {
        meetings.append(record)
        meetings.sort { $0.date > $1.date }
        saveNow()
    }

    func update(_ id: UUID, _ change: (inout MeetingRecord) -> Void) {
        guard let index = meetings.firstIndex(where: { $0.id == id }) else { return }
        change(&meetings[index])
        scheduleSave()
    }

    // Déplace le dossier temporaire d'une capture vers le stockage durable.
    func adoptRecording(from source: URL, id: UUID) throws -> URL {
        try prepareFolder(recordingsFolder)
        let destination = recordingsFolder.appendingPathComponent(id.uuidString, isDirectory: true)
        try FileManager.default.moveItem(at: source, to: destination)
        return destination
    }

    func saveNow() {
        pendingSave?.cancel()
        pendingSave = nil
        guard canSave else { return }
        do {
            try prepareFolder(folder)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(meetings).write(to: fileURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
            lastError = nil
        } catch {
            lastError = "Historique non enregistré : \(error.localizedDescription)"
        }
    }

    private func scheduleSave() {
        pendingSave?.cancel()
        pendingSave = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let loaded = try decoder.decode([MeetingRecord].self, from: Data(contentsOf: fileURL))
            meetings = loaded.sorted { $0.date > $1.date }
        } catch {
            // Un fichier illisible reste récupérable : il n'est jamais écrasé.
            let stamp = Int(Date().timeIntervalSince1970)
            let backup = folder.appendingPathComponent("meetings.illisible-\(stamp).json")
            do {
                try FileManager.default.moveItem(at: fileURL, to: backup)
                lastError = "Historique illisible, copie conservée : \(backup.lastPathComponent)"
            } catch {
                canSave = false
                lastError = "Historique illisible et non modifié : \(error.localizedDescription)"
            }
        }
    }

    private func prepareFolder(_ url: URL) throws {
        try FileManager.default.createDirectory(
            at: url, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]
        )
    }
}
