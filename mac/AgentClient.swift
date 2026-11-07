import Foundation

struct AgentClarification: Codable {
    let question: String
    let answer: String
}

enum AgentExecutor: String, Decodable {
    case devin
    case computerUse = "computer_use"

    var name: String { self == .devin ? "Devin" : "H Computer Use" }
    var sessionHost: String { self == .devin ? "app.devin.ai" : "platform.hcompany.ai" }
}

struct AgentReview: Decodable {
    let executor: AgentExecutor
    let destination: String
    let title: String
    let task: String
    let quote: String
    let clarifications: [AgentClarification]
    let approval: String
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

struct AgentExecution: Decodable {
    let executor: AgentExecutor
    let url: URL
}

struct AgentClient {
    struct Failure: LocalizedError {
        let message: String
        init(_ message: String) { self.message = message }
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

    private struct ErrorResponse: Decodable { let error: String }

    private final class NoRedirects: NSObject, URLSessionTaskDelegate {
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
            completionHandler(nil)
        }
    }

    private static let session = URLSession(configuration: .ephemeral, delegate: NoRedirects(), delegateQueue: nil)
    let baseURL: URL
    let accessCode: String
    var session: URLSession = Self.session

    func prepare(task: String, transcript: String, clarifications: [AgentClarification]) async throws -> AgentPreparation {
        try await post("agent-prepare", Preparation(task: task, transcript: transcript, clarifications: clarifications))
    }

    func launch(_ review: AgentReview) async throws -> AgentExecution {
        let result: AgentExecution = try await post("agent-execute", Confirmation(approval: review.approval))
        guard result.executor == review.executor, result.url.scheme == "https", result.url.host == result.executor.sessionHost,
              result.url.user == nil, result.url.password == nil, result.url.port == nil || result.url.port == 443 else {
            throw Failure("Le service n’a pas renvoyé de lien de session valide.")
        }
        return result
    }

    private func post<Body: Encodable, Result: Decodable>(_ operation: String, _ body: Body) async throws -> Result {
        var request = URLRequest(url: baseURL.appendingPathComponent("api").appendingPathComponent(operation), timeoutInterval: 35)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(accessCode)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw Failure("Réponse de l’agent indisponible.") }
        guard (200..<300).contains(http.statusCode) else {
            let message = (try? JSONDecoder().decode(ErrorResponse.self, from: data))?.error
            throw Failure(message ?? "L’agent n’a pas confirmé la requête (HTTP \(http.statusCode)).")
        }
        do { return try JSONDecoder().decode(Result.self, from: data) }
        catch { throw Failure("Réponse de l’agent illisible.") }
    }
}
