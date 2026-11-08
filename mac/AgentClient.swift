import Foundation

struct AgentClarification: Codable {
    let question: String
    let answer: String
}

enum AgentExecutor: String, Codable {
    case devin
    case computerUse = "computer_use"

    var name: String { self == .devin ? "Devin" : "H Computer Use" }
    var sessionHost: String { self == .devin ? "app.devin.ai" : "platform.hcompany.ai" }
}

struct AgentReview: Codable {
    let executor: AgentExecutor
    let destination: String
    let title: String
    let task: String
    let quote: String
    let clarifications: [AgentClarification]
    let approval: String

    var usesTrello: Bool {
        executor == .computerUse && ["trello.com", "www.trello.com"].contains(URL(string: destination)?.host ?? "")
    }
}

enum AgentPreparation: Decodable {
    case question(String)
    case review(AgentReview)

    private enum Keys: CodingKey { case status, question }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: Keys.self)
        switch try values.decode(String.self, forKey: .status) {
        case "needs_clarification": self = .question(try values.decode(String.self, forKey: .question))
        case "ready": self = .review(try AgentReview(from: decoder))
        default: throw AgentClient.Failure("Le serveur n’a pas renvoyé de proposition exploitable.")
        }
    }
}

struct DetectedTask: Decodable {
    let id: String
    let replaces: String?
    let review: AgentReview

    private enum Keys: CodingKey { case id, replaces }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: Keys.self)
        id = try values.decode(String.self, forKey: .id)
        replaces = try values.decodeIfPresent(String.self, forKey: .replaces)
        review = try AgentReview(from: decoder)
    }
}

struct KnownTask: Encodable, Equatable {
    let ref: String
    let title: String
    let task: String
}

struct AgentExecution: Codable {
    let executor: AgentExecutor
    let url: URL
    let trackingToken: String?
    var statusEndpoint: URL?
    var trelloResult: TrelloExecutionResult?
}

struct TrelloExecutionResult: Codable {
    enum State: String, Codable { case pending, attention, verified, unverified }

    let status: State
    let cardURL: URL?

    private enum CodingKeys: String, CodingKey { case status, cardURL = "cardUrl" }

    var verifiedURL: URL? {
        guard status == .verified, let url = cardURL, url.scheme == "https", url.host == "trello.com",
              url.port == nil, url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
              url.path.range(of: "^/c/[A-Za-z0-9]{1,64}$", options: .regularExpression) != nil else { return nil }
        return url
    }
}

struct AgentAccess: Decodable {
    let planning: Bool
    let trello: Bool
    let devin: Bool
}

struct AgentClient {
    struct Failure: LocalizedError {
        let message: String
        let status: Int?
        let code: String?

        init(_ message: String, status: Int? = nil, code: String? = nil) {
            self.message = message
            self.status = status
            self.code = code
        }

        var errorDescription: String? { message }
    }

    private struct Preparation: Encodable {
        let task: String
        let transcript: String
        let clarifications: [AgentClarification]
    }

    private struct Confirmation: Encodable {
        let approval: String
        let confirmed = true
    }

    private struct ErrorResponse: Decodable {
        let error: String
        let code: String?
    }

    private final class NoRedirects: NSObject, URLSessionTaskDelegate {
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
            completionHandler(nil)
        }
    }

    private static let session = URLSession(configuration: .ephemeral, delegate: NoRedirects(), delegateQueue: nil)
    let baseURL: URL
    let token: @MainActor () async throws -> String
    var session: URLSession = Self.session

    static func serverURL(_ address: String) -> URL? {
        guard let base = URL(string: address.trimmingCharacters(in: .whitespacesAndNewlines)),
              let host = base.host, !host.isEmpty, base.user == nil, base.password == nil,
              base.query == nil, base.fragment == nil, base.path.isEmpty || base.path == "/",
              base.scheme == "https" || (base.scheme == "http" && ["localhost", "127.0.0.1"].contains(host))
        else { return nil }
        return base
    }

    func access() async throws -> AgentAccess {
        try await post("agent-access", [String: String]())
    }

    func prepare(task: String, transcript: String, clarifications: [AgentClarification]) async throws -> AgentPreparation {
        try await post("agent-prepare", Preparation(task: task, transcript: transcript, clarifications: clarifications))
    }

    func detect(transcript: String, known: [KnownTask]) async throws -> [DetectedTask] {
        struct Request: Encodable {
            let transcript: String
            let known: [KnownTask]
        }
        struct Response: Decodable { let tasks: [DetectedTask] }
        let response: Response = try await post("agent-detect", Request(transcript: transcript, known: known))
        return response.tasks
    }

    func launch(_ review: AgentReview) async throws -> AgentExecution {
        var result: AgentExecution = try await post("agent-execute", Confirmation(approval: review.approval))
        guard result.executor == review.executor, result.url.scheme == "https", result.url.host == result.executor.sessionHost,
              result.url.user == nil, result.url.password == nil, result.url.port == nil || result.url.port == 443 else {
            throw Failure("Le service n’a pas renvoyé de lien de session valide.")
        }
        result.statusEndpoint = review.usesTrello && result.trackingToken != nil ? trelloStatusEndpoint : nil
        result.trelloResult = nil
        return result
    }

    private var trelloStatusEndpoint: URL {
        baseURL.appendingPathComponent("api").appendingPathComponent("agent-trello-status")
    }

    func canTrack(_ execution: AgentExecution) -> Bool {
        execution.statusEndpoint == trelloStatusEndpoint && execution.trackingToken != nil
    }

    func trelloStatus(_ execution: AgentExecution) async throws -> TrelloExecutionResult {
        guard canTrack(execution), let token = execution.trackingToken else {
            throw Failure("Connectez l’agent au serveur utilisé pour cette tâche.")
        }
        let result: TrelloExecutionResult = try await post("agent-trello-status", ["trackingToken": token])
        guard result.status != .verified || result.verifiedURL != nil else {
            throw Failure("Le serveur n’a pas renvoyé de lien Trello valide.")
        }
        return result
    }

    private func post<Body: Encodable, Result: Decodable>(_ operation: String, _ body: Body) async throws -> Result {
        var request = URLRequest(url: baseURL.appendingPathComponent("api").appendingPathComponent(operation), timeoutInterval: 35)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(try await token())", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw Failure("Réponse de l’agent indisponible.") }
        guard (200..<300).contains(http.statusCode) else {
            let problem = try? JSONDecoder().decode(ErrorResponse.self, from: data)
            throw Failure(problem?.error ?? "L’agent n’a pas confirmé la requête (HTTP \(http.statusCode)).",
                          status: http.statusCode, code: problem?.code)
        }
        do { return try JSONDecoder().decode(Result.self, from: data) }
        catch { throw Failure("Réponse de l’agent illisible.") }
    }
}
