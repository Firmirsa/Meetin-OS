import AppKit
import SwiftUI

struct Sidebar: View {
    @Bindable var session: MeetingSession

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                MTLogo(size: 28)
                Text("Meetin-OS").font(.mtSerif(22)).fixedSize()
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 20)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            row("Accueil", icon: "house", selected: session.route == .home) { session.route = .home }
            row("Réunions", icon: "doc.text", selected: [.meetings, .meetingDetail].contains(session.route)) {
                session.route = .meetings
            }

            Spacer(minLength: 24)

            Text("COMPTE")
                .font(.mtSans(11, weight: .medium))
                .tracking(1.2)
                .foregroundStyle(Color.mtInk2)
                .padding(.horizontal, 10)
                .padding(.bottom, 4)
                .accessibilityAddTraits(.isHeader)
            row("Intégrations", icon: "puzzlepiece.extension", selected: session.route == .integrations) {
                session.integrationsRequest = IntegrationsRequest(page: .catalog)
            }
            row("Paramètres", icon: "gearshape", selected: session.route == .settings) { session.route = .settings }
            row(session.accountConnected ? "Compte" : "Se connecter", icon: "person", selected: session.route == .account) { session.route = .account }
            row("Facturation et abonnement", icon: "creditcard", selected: session.route == .billing) { session.route = .billing }
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.mtSidebarVeil.ignoresSafeArea())
    }

    private func row(_ title: String, icon: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundStyle(selected ? Color.mtAccentText : Color.mtInk2)
                    .frame(width: 18)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.mtSans(14))
                    .foregroundStyle(selected ? Color.mtInk : Color.mtInk2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(minHeight: 34)
            .background(selected ? Color.mtAccentTint : Color.clear, in: RoundedRectangle(cornerRadius: MTRadius.input))
            .contentShape(RoundedRectangle(cornerRadius: MTRadius.input))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
