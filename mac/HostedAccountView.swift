import AppKit
import SwiftUI

struct HostedAccountView: View {
    let session: MeetingSession
    @Binding var address: String
    var showsSignOut = false
    var showsPlans = false
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
                if showsPlans { planCards(current: plan) }
                if plan.plan != "premium" && plan.checkoutAvailable {
                    Button("Passer à Premium", systemImage: "sparkles") { openBilling(manage: false) }.buttonStyle(.mtPrimary).disabled(billingDisabled)
                }
                if plan.canManageBilling {
                    Button("Gérer l’abonnement", systemImage: "creditcard") { openBilling(manage: true) }.buttonStyle(.mtGhost).disabled(billingDisabled)
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
                Button("Actualiser le quota", systemImage: "arrow.clockwise", action: refresh).buttonStyle(.mtGhost).disabled(busy || session.billingRequestBusy)
                    .help("Vérifier le plan et le quota auprès du serveur")
                if showsSignOut {
                Button("Se déconnecter", systemImage: "rectangle.portrait.and.arrow.right") {
                    run { client in
                        await session.account.signOut(client)
                    }
                }.buttonStyle(.mtGhost)
                    .disabled(busy || session.billingRequestBusy || session.billingLaunchPending || session.busy || session.capture != nil)
                    .help("Déconnecter le compte Google de ce Mac")
                }
            }
            if showsSignOut { Text("La déconnexion conserve les réunions et les brouillons sur ce Mac.")
                .font(.mtSans(12)).foregroundStyle(Color.mtInk2) }
        }
    }

    private struct Offer: Decodable, Identifiable {
        let id: String
        let name: String
        let limitMs: Int
    }

    private var offers: [Offer] {
        guard let url = Bundle.main.url(forResource: "BillingPlans", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let plans = try? JSONDecoder().decode([Offer].self, from: data) else { return [] }
        return plans
    }

    private func planCards(current: AccountSummary) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), alignment: .top)], spacing: 12) {
            ForEach(offers) { offer in
                let selected = current.plan == offer.id
                VStack(alignment: .leading, spacing: 12) {
                    Label(offer.name, systemImage: offer.id == "free" ? "leaf" : "sparkles")
                        .font(.mtSans(20, weight: .medium))
                    Text(selected ? "Votre offre" : "Offre du catalogue")
                        .font(.mtSans(12)).foregroundStyle(selected ? Color.mtAccent : Color.mtInk2)
                    Text("\(duration(selected ? current.limitMs : offer.limitMs)) d’audio / mois")
                        .font(.mtSans(15))
                    if offer.id == "premium" && !selected {
                        Text(current.checkoutAvailable ? "Tarif confirmé sur Stripe avant paiement" : "Souscription indisponible sur ce serveur")
                            .font(.mtSans(12)).foregroundStyle(Color.mtInk2)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)
                .padding(16)
                .background(Color.mtGlass, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(selected ? Color.mtAccent : Color.mtLine, lineWidth: 1))
                .accessibilityElement(children: .combine)
            }
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
