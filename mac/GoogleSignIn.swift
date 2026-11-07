import AppKit
import AuthenticationServices
import CryptoKit
import Security
import SwiftUI

@MainActor
private final class GoogleBrowserSession: NSObject, ASWebAuthenticationPresentationContextProviding {
    private let window: NSWindow
    private var browser: ASWebAuthenticationSession?
    private var pendingCallback: CheckedContinuation<URL, Error>?
    private static let scheme = "meetinos-oauth"

    init(window: NSWindow) { self.window = window }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor { window }

    func signIn(_ account: HostedAccount, client: AccountClient) async throws {
        var bytes = Data(count: 32)
        let randomStatus = bytes.withUnsafeMutableBytes { buffer in
            guard let address = buffer.baseAddress else { return errSecAllocate }
            return SecRandomCopyBytes(kSecRandomDefault, buffer.count, address)
        }
        guard randomStatus == errSecSuccess else {
            throw AccountClient.Failure(message: "Impossible de préparer la connexion Google.")
        }
        let verifier = Self.base64URL(bytes)
        let challenge = Self.base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
        let url = try await client.googleURL(challenge: challenge)
        let callback = try await open(url)
        let parts = URLComponents(url: callback, resolvingAgainstBaseURL: false)
        let codes = parts?.queryItems?.filter { $0.name == "code" } ?? []
        guard parts?.scheme == Self.scheme, parts?.host == "callback", parts?.user == nil,
              parts?.password == nil, parts?.port == nil, parts?.fragment == nil,
              let path = parts?.path, path.isEmpty || path == "/",
              codes.count == 1, let code = codes[0].value, UUID(uuidString: code) != nil,
              parts?.queryItems?.contains(where: { $0.name == "error" }) != true else {
            throw AccountClient.Failure(message: "Google n’a pas terminé la connexion. Réessaie.")
        }
        try await account.signIn(client, googleCode: code, verifier: verifier)
    }

    private func open(_ url: URL) async throws -> URL {
        return try await withCheckedThrowingContinuation { continuation in
            pendingCallback = continuation
            let session = ASWebAuthenticationSession(url: url, callback: .customScheme(Self.scheme)) { [weak self] url, error in
                let result = url.map { Result<URL, Error>.success($0) } ?? .failure(error ?? CancellationError())
                Task { @MainActor in self?.finish(result) }
            }
            session.presentationContextProvider = self
            browser = session
            if !session.start() {
                finish(.failure(AccountClient.Failure(message: "Impossible d’ouvrir la connexion Google.")))
            }
        }
    }

    private func finish(_ result: Result<URL, Error>) {
        let callback = pendingCallback
        pendingCallback = nil
        browser = nil
        callback?.resume(with: result)
    }

    private static func base64URL(_ bytes: Data) -> String {
        bytes.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}

struct GoogleSignInButton: View {
    let account: HostedAccount
    let client: AccountClient?
    var onConnected: () -> Void = {}

    @State private var busy = false
    @State private var issue = ""

    var body: some View {
        VStack(spacing: 12) {
            Button(action: connect) {
                HStack(spacing: 10) {
                    Group {
                        if busy { ProgressView().controlSize(.small).colorScheme(.light) }
                        else if let url = Bundle.main.url(forResource: "GoogleG", withExtension: "png"),
                                let logo = NSImage(contentsOf: url) {
                            Image(nsImage: logo).resizable().scaledToFit()
                        }
                    }
                    .frame(width: 18, height: 18)
                    .accessibilityHidden(true)
                    Text(busy ? "Connexion en cours…" : "Se connecter avec Google")
                }
            }
            .buttonStyle(GoogleButtonStyle())
            .keyboardShortcut(.defaultAction)
            .disabled(busy)
            if !issue.isEmpty {
                Text(issue).font(.mtSans(13)).foregroundStyle(Color.mtWarn)
                    .multilineTextAlignment(.center).accessibilityAddTraits(.updatesFrequently)
            }
        }
    }

    private func connect() {
        guard !busy else { return }
        guard let client, let window = NSApp.keyWindow else {
            issue = "La connexion Meetin-OS est indisponible."
            return
        }
        busy = true
        issue = ""
        let browser = GoogleBrowserSession(window: window)
        Task {
            defer { busy = false }
            do {
                try await browser.signIn(account, client: client)
                onConnected()
            } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
                return
            } catch {
                issue = error.localizedDescription
            }
        }
    }
}

// https://developers.google.com/identity/branding-guidelines
private struct GoogleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.custom("GoogleSans-Medium", size: 14))
            .foregroundStyle(Color(.sRGB, white: 31.0 / 255, opacity: 1))
            .padding(.horizontal, 16)
            .frame(height: 44)
            .background(configuration.isPressed ? Color(.sRGB, white: 0.94, opacity: 1) : .white, in: Capsule())
            .overlay(Capsule().strokeBorder(Color(.sRGB, red: 116.0 / 255, green: 119.0 / 255, blue: 117.0 / 255), lineWidth: 1))
            .contentShape(Capsule())
    }
}
