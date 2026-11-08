import AVFoundation
import AppKit
import Foundation

// Frontières système simulées : aucun trousseau, aucune notification ni action externe.
enum GladiaKeyStore {
    static func load() -> String? { nil }
    @discardableResult static func save(_ key: String) -> Bool { false }
    @discardableResult static func delete() -> Bool { false }
}

@MainActor final class TaskNotifications {
    static let shared = TaskNotifications()
    func attach(_ session: MeetingSession) {}
    func post(_ proposal: TaskProposal) {}
    func remove(_ id: String) {}
}

enum LiveAlerts {
    static func requestPermission(onStatus: @escaping @MainActor @Sendable (Bool) -> Void = { _ in }) {
        readPermission(onStatus)
    }
    static func readPermission(_ onStatus: @escaping @MainActor @Sendable (Bool) -> Void) {
        Task { @MainActor in onStatus(true) }
    }
    static func post(_ text: String) {}
    static func postTask(_ title: String, _ text: String) {}
}

final class FlowAgentStub: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var rewritten = Data()
    nonisolated(unsafe) static var launches = 0
    nonisolated(unsafe) static var executionStatus = 200
    nonisolated(unsafe) static var failNetwork = false
    nonisolated(unsafe) static var approvals: [String] = []
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}
    override func startLoading() {
        let body: Data
        switch request.url!.lastPathComponent {
        case "agent-prepare": body = Self.rewritten
        case "agent-execute":
            Self.launches += 1
            var sent = request.httpBody ?? Data()
            if let stream = request.httpBodyStream {
                stream.open()
                defer { stream.close() }
                var buffer = [UInt8](repeating: 0, count: 4096)
                while stream.hasBytesAvailable {
                    let count = stream.read(&buffer, maxLength: buffer.count)
                    guard count > 0 else { break }
                    sent.append(contentsOf: buffer.prefix(count))
                }
            }
            let payload = try! JSONSerialization.jsonObject(with: sent) as! [String: Any]
            Self.approvals.append(payload["approval"] as! String)
            if Self.failNetwork {
                client?.urlProtocol(self, didFailWithError: URLError(.networkConnectionLost))
                return
            }
            body = Data(#"{"executor":"devin","url":"https://app.devin.ai/sessions/fixture"}"#.utf8)
        default: fatalError("requête inattendue")
        }
        let status = request.url!.lastPathComponent == "agent-execute" ? Self.executionStatus : 200
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }
}

@MainActor final class TerminationApp: NSApplication {
    var replies = 0
    override func reply(toApplicationShouldTerminate shouldTerminate: Bool) {
        precondition(shouldTerminate)
        replies += 1
    }
}

@main struct MeetingFlowSmoke {
    @MainActor static func main() async throws {
        let previousAudioState = UserDefaults.standard.object(forKey: MeetingSession.systemAudioStateKey)
        defer {
            if let previousAudioState {
                UserDefaults.standard.set(previousAudioState, forKey: MeetingSession.systemAudioStateKey)
            } else {
                UserDefaults.standard.removeObject(forKey: MeetingSession.systemAudioStateKey)
            }
        }
        func plan(executor: String = "devin", destination: String = "Firmirsa/Meetin-OS", approval: String) throws -> Data {
            try JSONSerialization.data(withJSONObject: [
                "status": "ready", "executor": executor, "destination": destination, "title": "Tâche simulée",
                "task": "Corriger l’export.", "quote": "extrait simulé", "clarifications": [], "approval": approval
            ])
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FlowAgentStub.self]
        let client = AgentClient(baseURL: URL(string: "https://fixture.invalid")!, accessCode: "fixture", session: URLSession(configuration: configuration))
        let session = MeetingSession()
        session.refreshNotificationPermission()
        let permissionDeadline = Date().addingTimeInterval(5)
        while !session.notificationsDenied {
            precondition(Date() < permissionDeadline, "statut des notifications non reçu")
            try await Task.sleep(for: .milliseconds(10))
        }
        let original = try JSONDecoder().decode(AgentReview.self, from: plan(approval: "initial"))
        for (executor, destination, shouldLaunch) in [
            ("computer_use", "Firmirsa/Meetin-OS", false),
            ("devin", "Firmirsa/autre", false),
            ("devin", "Firmirsa/Meetin-OS", true)
        ] {
            session.proposals = [TaskProposal(id: "fixture", review: original)]
            FlowAgentStub.rewritten = try plan(executor: executor, destination: destination, approval: "réécrit")
            let before = FlowAgentStub.launches
            session.launch(session.proposals[0], using: client, context: "Contexte simulé")
            precondition(!session.canSwitchMeeting, "la réunion ne peut pas changer pendant un lancement")
            let deadline = Date().addingTimeInterval(5)
            while !session.launchingProposals.isEmpty {
                precondition(Date() < deadline, "lancement bloqué")
                try await Task.sleep(for: .milliseconds(10))
            }
            precondition(session.proposals[0].review.approval == "réécrit", "le plan réécrit reste sur la carte")
            precondition(FlowAgentStub.launches == before + (shouldLaunch ? 1 : 0), "aucun lancement si l’outil ou la destination change")
            if !shouldLaunch {
                precondition(session.proposals[0].state == .pending && session.proposalIssues["fixture"] != nil)
            } else {
                precondition(session.proposals[0].state == .launched, "le contexte peut toujours lancer sans relecture à destination inchangée")
            }
        }

        // Arrêt en échec simulé : aucun moteur démarré, seulement des pistes synthétiques.
        for withAudio in [true, false] {
            let capture = AudioCapture()
            try FileManager.default.createDirectory(at: capture.folder, withIntermediateDirectories: true)
            if withAudio {
                let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)!
                let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 480)!
                buffer.frameLength = 480
                for index in 0..<480 { buffer.floatChannelData![0][index] = 0.1 }
                for url in [capture.microphone, capture.system] {
                    let file = try AVAudioFile(forWriting: url, settings: format.settings)
                    try file.write(from: buffer)
                }
            }
            session.meetingID = nil
            session.recording = nil
            session.recordedTracks = nil
            session.notes = "Note simulée à conserver"
            session.transcript = "Texte simulé du direct"
            session.startedAt = Date()
            session.capture = capture
            session.busy = true
            try await CaptureView.stopRecording(capture, session: session)
            session.busy = false
            precondition(session.capture == nil && session.meetingID != nil)
            let record = session.currentMeeting!
            precondition(record.notes == session.notes && record.transcript == session.transcript, "notes et direct conservés malgré l’échec")
            if withAudio {
                precondition(URL(fileURLWithPath: record.audioPath).pathExtension == "caf", "le CAF n’est pas renommé M4A")
                precondition(record.tracks != nil && FileManager.default.fileExists(atPath: record.tracks!.systemPath), "les deux pistes sont déplacées dans l’historique")
            } else {
                precondition(record.audioPath.isEmpty && session.recording == nil, "la réunion reste accessible sans fichier audio fictif")
            }
            session.meetingDidStart()
            precondition(session.notes.isEmpty, "les notes d’un arrêt en erreur ne passent pas dans la prochaine réunion")
        }
        let saved = MeetingStore(folder: URL(fileURLWithPath: ProcessInfo.processInfo.environment["MEETIN_SMOKE_FOLDER"]!))
        precondition(saved.meetings.count == 2 && saved.meetings.allSatisfy { !$0.notes.isEmpty && !$0.transcript.isEmpty }, "relecture de l’historique après les arrêts simulés")
        let workspace = AgentWorkspaceState()
        for (status, network, retained) in [(502, false, true), (200, true, true), (409, false, false)] {
            workspace.preparation = .review(original)
            FlowAgentStub.executionStatus = status
            FlowAgentStub.failNetwork = network
            workspace.launch(original, using: client)
            let deadline = Date().addingTimeInterval(5)
            while workspace.busy {
                precondition(Date() < deadline, "validation du plan bloquée")
                try await Task.sleep(for: .milliseconds(10))
            }
            if retained {
                guard case .review(let review) = workspace.preparation else { fatalError("plan perdu après une panne incertaine") }
                precondition(review.approval == original.approval, "même validation à réutiliser")
            } else {
                precondition(workspace.preparation == nil, "le refus définitif retire le plan")
            }
            precondition(FlowAgentStub.approvals.last == original.approval)
        }
        print("Session : destinations, verrouillage et conservation après arrêt en erreur vérifiés en simulé.")
        print("Validation : plan signé conservé sur 502 et coupure réseau, retiré sur 409.")
        let app = TerminationApp()
        session.capture = nil
        let idleDelegate = MeetinAppDelegate()
        precondition(idleDelegate.applicationShouldTerminate(app) == .terminateNow, "sans capture, quitter immédiatement")
        session.capture = AudioCapture()
        session.notes = "Note au moment de quitter"
        let stopDelegate = MeetinAppDelegate()
        precondition(stopDelegate.applicationShouldTerminate(app) == .terminateLater)
        let stopDeadline = Date().addingTimeInterval(5)
        while app.replies < 1 {
            precondition(Date() < stopDeadline, "absence de réponse après un arrêt en échec")
            try await Task.sleep(for: .milliseconds(10))
        }
        precondition(session.currentMeeting?.notes == "Note au moment de quitter", "notes conservées avant la réponse de fermeture")
        session.capture = AudioCapture()
        session.busy = true
        let timeoutDelegate = MeetinAppDelegate()
        precondition(timeoutDelegate.applicationShouldTerminate(app) == .terminateLater)
        precondition(timeoutDelegate.applicationShouldTerminate(app) == .terminateLater, "double demande sans second arrêt")
        let timeoutDeadline = Date().addingTimeInterval(5)
        while app.replies < 2 {
            precondition(Date() < timeoutDeadline, "absence de réponse après expiration du délai")
            try await Task.sleep(for: .milliseconds(10))
        }
        session.capture = nil
        session.busy = false
        print("Fermeture : réponse immédiate, arrêt en erreur et timeout vérifiés (délai réduit à 0,1 s dans le test).")
    }
}
