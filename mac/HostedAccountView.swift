import AppKit
import SwiftUI

struct HostedAccountView: View {
    let session: MeetingSession
    @Binding var address: String
    var onConnected: () -> Void = {}

    @State private var busy = false
    @State private var issue = ""

    private var client: AccountClient? { MeetinSite.baseURL(address).map { AccountClient(baseURL: $0) } }
    private var connected: Bool { session.account.connected(to: client?.baseURL) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if connected {
                usage
            } else {
                GoogleSignInButton(account: session.account, client: client, onConnected: onConnected)
            }
            if busy { ProgressView().controlSize(.small) }
            if !issue.isEmpty { Text(issue).foregroundStyle(Color.mtWarn).textSelection(.enabled) }
        }
        .task(id: client?.baseURL) { if connected && !session.billingLaunchPending { refresh() } }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            if connected && !session.billingRequestBusy { refresh() }
        }
    }

    private var usage: some View {
        VStack(alignment: .leading, spacing: 9) {
            Label("Google connecté", systemImage: "checkmark.circle")
                .foregroundStyle(Color.mtInk)
            if let plan = session.account.usage {
                LabeledContent("E-mail", value: plan.email)
                LabeledContent("Plan", value: plan.planName)
                LabeledContent("Audio restant", value: "\(duration(plan.remainingMs)) sur \(duration(plan.limitMs)) ce mois-ci")
                if plan.plan != "premium" && plan.checkoutAvailable {
                    Button("Passer à Premium") { openBilling(manage: false) }.buttonStyle(.mtPrimary).disabled(billingDisabled)
                }
                if plan.canManageBilling {
                    Button("Gérer l’abonnement") { openBilling(manage: true) }.buttonStyle(.mtGhost).disabled(billingDisabled)
                }
                if plan.plan != "premium" && !plan.checkoutAvailable {
                    Text("Le passage à Premium n’est pas configuré sur ce serveur.")
                        .font(.mtSans(13)).foregroundStyle(Color.mtInk2)
                }
                if !plan.canManageBilling {
                    Text("Aucun portail de gestion disponible pour ce compte sur ce serveur.")
                        .font(.mtSans(13)).foregroundStyle(Color.mtInk2)
                }
            } else {
                Text("L’identité et le quota n’ont pas encore été actualisés.")
                    .font(.mtSans(13)).foregroundStyle(Color.mtInk2)
            }
            if session.billingLaunchPending {
                Text("Stripe est ouvert dans le navigateur. Reviens ici après paiement ou annulation, puis actualise le quota si nécessaire.")
                    .font(.mtSans(13)).foregroundStyle(Color.mtInk2)
            }
            HStack {
                Button("Actualiser le quota", action: refresh).buttonStyle(.mtGhost).disabled(busy || session.billingRequestBusy)
                Button("Se déconnecter") {
                    run { client in
                        await session.account.signOut(client)
                    }
                }.buttonStyle(.mtGhost)
                    .disabled(busy || session.billingRequestBusy || session.billingLaunchPending || session.busy || session.capture != nil)
            }
            Text("La déconnexion conserve les réunions et les brouillons sur ce Mac.")
                .font(.mtSans(12)).foregroundStyle(Color.mtInk2)
        }
    }

    private func duration(_ ms: Int) -> String {
        let minutes = ms / 60_000
        let seconds = (ms / 1_000) % 60
        return seconds == 0 ? "\(minutes) min" : "\(minutes) min \(seconds) s"
    }

    private func refresh() {
        run { client in
            defer { session.billingLaunchPending = false }
            _ = try await session.account.refreshUsage(client)
        }
    }

    private var billingDisabled: Bool { busy || session.billingRequestBusy || session.billingLaunchPending }

    private func openBilling(manage: Bool) {
        guard !billingDisabled else { return }
        guard client != nil else {
            issue = "Saisis une adresse HTTPS, ou HTTP sur ce Mac."
            return
        }
        session.billingRequestBusy = true
        run { client in
            defer { session.billingRequestBusy = false }
            let url = try await client.billing(session.account.token(client), manage: manage)
            guard NSWorkspace.shared.open(url) else {
                throw AccountClient.Failure(message: "Impossible d’ouvrir Stripe dans le navigateur. Réessaie après avoir vérifié ton navigateur par défaut.")
            }
            session.billingLaunchPending = true
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
