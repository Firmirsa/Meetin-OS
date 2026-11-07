import AppKit
import SwiftUI

struct HostedAccountView: View {
    let session: MeetingSession
    @Binding var address: String
    var onConnected: () -> Void = {}

    @State private var email = ""
    @State private var code = ""
    @State private var codeSent = false
    @State private var busy = false
    @State private var issue = ""

    private var client: AccountClient? { MeetinSite.baseURL(address).map { AccountClient(baseURL: $0) } }
    private var connected: Bool { session.account.connected(to: client?.baseURL) }
    private var normalizedEmail: String { email.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if connected {
                usage
            } else {
                Text("Un compte Meetin-OS est nécessaire pour transcrire, même avec le plan Gratuit.")
                    .foregroundStyle(Color.mtInk2)
                if codeSent {
                    Text("Saisis le code à six chiffres envoyé à \(normalizedEmail).")
                    SecureField("Code reçu par e-mail", text: $code)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(verify)
                    HStack {
                        Button("Se connecter", action: verify).buttonStyle(.mtPrimary)
                            .disabled(code.count != 6 || busy)
                        Button("Renvoyer le code", action: send).buttonStyle(.mtGhost)
                        Button("Changer d’adresse") {
                            codeSent = false
                            code = ""
                            issue = ""
                        }.buttonStyle(.link).disabled(busy)
                    }
                } else {
                    TextField("Adresse e-mail", text: $email)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(send)
                    Button("Recevoir un code", action: send).buttonStyle(.mtPrimary)
                        .disabled(normalizedEmail.isEmpty || busy)
                    DisclosureGroup("Adresse du serveur") {
                        TextField("Adresse du serveur Meetin-OS", text: $address)
                            .textFieldStyle(.roundedBorder)
                    }
                    .disabled(busy)
                }
            }
            if busy { ProgressView().controlSize(.small) }
            if !issue.isEmpty { Text(issue).foregroundStyle(Color.mtWarn).textSelection(.enabled) }
        }
        .task(id: client?.baseURL) { if connected { refresh() } }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            if connected { refresh() }
        }
    }

    private var usage: some View {
        VStack(alignment: .leading, spacing: 9) {
            if let plan = session.account.usage {
                LabeledContent("E-mail", value: plan.email)
                LabeledContent("Plan", value: plan.planName)
                LabeledContent("Audio restant", value: "\(duration(plan.remainingMs)) sur \(duration(plan.limitMs)) ce mois-ci")
                if plan.plan != "premium" && plan.checkoutAvailable {
                    Button("Passer à Premium") { openBilling(manage: false) }.buttonStyle(.mtPrimary).disabled(busy)
                }
                if plan.canManageBilling {
                    Button("Gérer l’abonnement") { openBilling(manage: true) }.buttonStyle(.mtGhost).disabled(busy)
                }
            }
            HStack {
                Button("Actualiser le quota", action: refresh).buttonStyle(.mtGhost).disabled(busy)
                Button("Se déconnecter") {
                    run { client in
                        await session.account.signOut(client)
                        code = ""
                        codeSent = false
                    }
                }.buttonStyle(.mtGhost)
                    .disabled(busy || session.busy || session.capture != nil)
            }
        }
    }

    private func duration(_ ms: Int) -> String {
        let minutes = ms / 60_000
        let seconds = (ms / 1_000) % 60
        return seconds == 0 ? "\(minutes) min" : "\(minutes) min \(seconds) s"
    }

    private func send() {
        guard !normalizedEmail.isEmpty else { return }
        run { client in
            try await client.sendCode(to: normalizedEmail)
            codeSent = true
        }
    }

    private func verify() {
        guard code.count == 6 else { return }
        run { client in
            try await session.account.signIn(client, email: normalizedEmail, code: code)
            code = ""
            onConnected()
            _ = try? await session.account.refreshUsage(client)
        }
    }

    private func refresh() {
        run { client in _ = try await session.account.refreshUsage(client) }
    }

    private func openBilling(manage: Bool) {
        run { client in
            let url = try await client.billing(session.account.token(client), manage: manage)
            NSWorkspace.shared.open(url)
        }
    }

    private func run(_ action: @escaping (AccountClient) async throws -> Void) {
        guard !busy else { return }
        guard let client else {
            issue = "Saisis une adresse HTTPS, ou HTTP sur ce Mac."
            return
        }
        busy = true
        issue = ""
        Task {
            defer { busy = false }
            do { try await action(client) }
            catch let error as AccountClient.Failure where error.status == 401 {
                session.account.forget(client)
                issue = error.localizedDescription
            } catch { issue = error.localizedDescription }
        }
    }
}
