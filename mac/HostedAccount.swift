import Foundation
import Security

struct AccountTokens: Codable, Sendable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Double
    let email: String
}

struct AccountSummary: Decodable, Sendable {
    let email: String
    let plan: String
    let limitMs: Int
    let remainingMs: Int
    let resetsAt: String
    let liveUrl: URL?
    let checkoutAvailable: Bool
    let canManageBilling: Bool

    var planName: String { plan == "premium" ? "Premium" : "Gratuit" }
}

struct AccountClient: Sendable {
    struct Failure: LocalizedError {
        let message: String
        var status: Int? = nil
        var code: String? = nil
        var errorDescription: String? { message }
    }

    private struct Problem: Decodable {
        let error: String
        let code: String?
    }
    private struct Empty: Decodable {}

    private final class NoRedirects: NSObject, URLSessionTaskDelegate {
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
            completionHandler(nil)
        }
    }

    static let http = URLSession(configuration: .ephemeral, delegate: NoRedirects(), delegateQueue: nil)
    let baseURL: URL
    var http: URLSession = Self.http

    func url(_ operation: String) -> URL { baseURL.appendingPathComponent("api").appendingPathComponent(operation) }

    func googleURL(challenge: String) async throws -> URL {
        struct Link: Decodable { let url: URL }
        let link: Link
        do {
            link = try await post("account-auth", ["action": "google_start", "challenge": challenge])
        } catch let failure as Failure where [401, 404, 405].contains(failure.status ?? 0) {
            throw Failure(message: "La connexion Google n’est pas encore disponible sur ce serveur.")
        }
        let url = link.url
        let host = url.host ?? ""
        let hosted = url.scheme == "https" && host.hasSuffix(".supabase.co") && url.port == nil
        let local = baseURL.scheme == "http" && url.scheme == "http" && ["localhost", "127.0.0.1"].contains(host)
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func values(_ name: String) -> [String] { query.filter { $0.name == name }.compactMap(\.value) }
        guard (hosted || local), url.path == "/auth/v1/authorize", url.user == nil, url.password == nil, url.fragment == nil,
              values("provider") == ["google"], values("redirect_to") == ["meetinos-oauth://callback"],
              values("code_challenge") == [challenge], values("code_challenge_method") == ["s256"] else {
            throw Failure(message: "Le lien de connexion Google est invalide.")
        }
        return url
    }

    func exchangeGoogleCode(_ code: String, verifier: String) async throws -> AccountTokens {
        try await post("account-auth", ["action": "google_exchange", "code": code, "verifier": verifier])
    }

    func refresh(_ token: String) async throws -> AccountTokens {
        try await post("account-auth", ["action": "refresh", "refreshToken": token])
    }

    func signOut(_ token: String) async throws {
        let _: Empty = try await post("account-auth", ["action": "sign_out"], token: token)
    }

    func summary(_ token: String) async throws -> AccountSummary {
        try await post("account-status", [:], token: token)
    }

    func billing(_ token: String, manage: Bool) async throws -> URL {
        struct Link: Decodable { let url: URL }
        let result: Link = try await post("account-billing", ["action": manage ? "manage" : "checkout"], token: token)
        guard result.url.scheme == "https", result.url.host == (manage ? "billing.stripe.com" : "checkout.stripe.com"),
              result.url.user == nil, result.url.password == nil, result.url.port == nil else {
            throw Failure(message: "Le lien Stripe est invalide.")
        }
        return result.url
    }

    private func post<Value: Decodable>(_ operation: String, _ payload: [String: String], token: String? = nil) async throws -> Value {
        try await request(url(operation), token: token, body: JSONEncoder().encode(payload), type: "application/json")
    }

    func request<Value: Decodable>(_ url: URL, token: String?, body: Data? = nil, type: String? = nil,
                                  idempotency: UUID? = nil) async throws -> Value {
        var request = URLRequest(url: url, timeoutInterval: 70)
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body {
            request.httpMethod = "POST"
            request.httpBody = body
        }
        if let type { request.setValue(type, forHTTPHeaderField: "Content-Type") }
        if let idempotency { request.setValue(idempotency.uuidString, forHTTPHeaderField: "Idempotency-Key") }
        let (data, response) = try await http.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw Failure(message: "Le serveur Meetin-OS est indisponible.")
        }
        guard (200..<300).contains(response.statusCode) else {
            let problem = try? JSONDecoder().decode(Problem.self, from: data)
            throw Failure(message: problem?.error ?? "Meetin-OS · HTTP \(response.statusCode).",
                          status: response.statusCode, code: problem?.code)
        }
        return try JSONDecoder().decode(Value.self, from: data)
    }
}

// Profil d’affichage du jeton de session déjà accepté par le serveur.
// Ces champs servent uniquement au nom local, jamais à autoriser une action.
enum GoogleProfileName {
    static func read(accessToken: String) -> String? {
        let parts = accessToken.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[1].count < 16_384 else { return nil }
        var payload = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
        guard let data = Data(base64Encoded: payload),
              let claims = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let metadata = claims["user_metadata"] as? [String: Any] else { return nil }
        for key in ["given_name", "full_name", "name"] {
            guard let value = metadata[key] as? String else { continue }
            let clean = value.components(separatedBy: .controlCharacters).joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !clean.isEmpty { return String(clean.prefix(100)) }
        }
        return nil
    }
}

@MainActor @Observable
final class HostedAccount {
    private struct Login: Codable {
        let server: URL
        let tokens: AccountTokens
    }

    private var login: Login? = Store.load()
    private(set) var usage: AccountSummary?
    @ObservationIgnored private var refreshing: Task<AccountTokens, Error>?

    func profileName(for server: URL?) -> String? {
        guard let server, let login, login.server == server else { return nil }
        return GoogleProfileName.read(accessToken: login.tokens.accessToken)
    }

    func connected(to server: URL?) -> Bool { server != nil && login?.server == server }

    func signIn(_ client: AccountClient, googleCode: String, verifier: String) async throws {
        let tokens = try await client.exchangeGoogleCode(googleCode, verifier: verifier)
        refreshing?.cancel()
        refreshing = nil
        usage = nil
        save(Login(server: client.baseURL, tokens: tokens))
    }

    func token(_ client: AccountClient) async throws -> String {
        guard let login, login.server == client.baseURL else {
            throw AccountClient.Failure(message: "Connectez-vous à Meetin-OS pour transcrire.", status: 401)
        }
        if login.tokens.expiresAt > Date().timeIntervalSince1970 + 45 { return login.tokens.accessToken }
        if let refreshing {
            let renewed = try await refreshing.value
            guard connected(to: client.baseURL) else { throw CancellationError() }
            return renewed.accessToken
        }
        let renewal = Task { try await client.refresh(login.tokens.refreshToken) }
        refreshing = renewal
        defer {
            if self.login?.tokens.refreshToken == login.tokens.refreshToken { refreshing = nil }
        }
        do {
            let tokens = try await renewal.value
            guard self.login?.tokens.refreshToken == login.tokens.refreshToken else { throw CancellationError() }
            refreshing = nil
            save(Login(server: client.baseURL, tokens: tokens))
            return tokens.accessToken
        } catch let error as AccountClient.Failure where error.status == 401 {
            forget(client)
            throw error
        }
    }

    @discardableResult
    func refreshUsage(_ client: AccountClient) async throws -> AccountSummary {
        let token = try await token(client)
        let current = try await client.summary(token)
        if connected(to: client.baseURL) { usage = current }
        return current
    }

    func forget(_ client: AccountClient) {
        guard connected(to: client.baseURL) else { return }
        refreshing?.cancel()
        refreshing = nil
        usage = nil
        save(nil)
    }

    func signOut(_ client: AccountClient) async {
        let active = try? await token(client)
        forget(client)
        if let active { try? await client.signOut(active) }
    }

    private func save(_ login: Login?) {
        self.login = login
        Store.save(login)
    }

    private enum Store {
        private static let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Bundle.main.bundleIdentifier ?? "com.meetin-os.capture",
            kSecAttrAccount as String: "meetin-google-session-v1",
        ]

        static func load() -> Login? {
            var lookup = query
            lookup[kSecReturnData as String] = true
            lookup[kSecMatchLimit as String] = kSecMatchLimitOne
            var result: CFTypeRef?
            guard SecItemCopyMatching(lookup as CFDictionary, &result) == errSecSuccess,
                  let data = result as? Data else { return nil }
            return try? JSONDecoder().decode(Login.self, from: data)
        }

        static func save(_ login: Login?) {
            guard let login, let data = try? JSONEncoder().encode(login) else {
                SecItemDelete(query as CFDictionary)
                return
            }
            let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
            guard status == errSecItemNotFound else { return }
            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
            SecItemAdd(item as CFDictionary, nil)
        }
    }
}
