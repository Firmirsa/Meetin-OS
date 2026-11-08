import SwiftUI

struct WelcomeView: View {
    let account: HostedAccount
    let client: AccountClient?
    let openNotebook: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false
    @State private var drift = false

    var body: some View {
        ZStack {
            MTMist()
            SignalBackdrop(drift: drift)
                .ignoresSafeArea()
                .accessibilityHidden(true)
                .allowsHitTesting(false)

            VStack(spacing: 18) {
                MTLogo(size: 72)
                    .padding(.bottom, 3)
                    .offset(y: drift ? -4 : 3)
                Text("Meetin-OS")
                    .font(.mtSerif(52))
                    .accessibilityAddTraits(.isHeader)
                Text("Ton carnet de réunion, avec ou sans compte.")
                    .font(.mtSans(16))
                    .foregroundStyle(Color.mtInk2)
                    .multilineTextAlignment(.center)
                VStack(alignment: .leading, spacing: 12) {
                    step("1", "Enregistre sur ce Mac et prends des notes.")
                    step("2", "Connecte Google si tu veux transcrire ou préparer des tâches.")
                    step("3", "Relis chaque action avant de la lancer.")
                }
                .padding(.vertical, 10)
                Button("Ouvrir mon carnet", systemImage: "book.closed", action: openNotebook)
                    .buttonStyle(WorkspaceButtonStyle(prominent: true))
                    .keyboardShortcut("o", modifiers: .command)
                GoogleSignInButton(account: account, client: client, onConnected: openNotebook)
                Text("Google est facultatif pour les notes et l’audio local.\nLes connexions aux autres outils se font plus tard.")
                    .font(.mtSans(12))
                    .foregroundStyle(Color.mtInk2)
                    .multilineTextAlignment(.center)
            }
            .padding(36)
            .opacity(reduceMotion || appeared ? 1 : 0)
            .offset(x: reduceMotion || appeared ? 0 : 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear(perform: animate)
        .onChange(of: reduceMotion) { animate() }
    }

    private func step(_ number: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number).font(.mtSans(12, weight: .semibold))
                .frame(width: 24, height: 24)
                .background(Color.mtAccentTint, in: Circle())
            Text(text).font(.mtSans(14)).padding(.top, 2)
        }
    }

    private func animate() {
        if reduceMotion {
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) { appeared = true; drift = false }
        } else {
            withAnimation(.easeOut(duration: 0.20)) { appeared = true }
            withAnimation(.easeInOut(duration: 6).repeatForever(autoreverses: true)) { drift = true }
        }
    }
}

private struct SignalBackdrop: View {
    let drift: Bool

    var body: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height)
            let origin = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2 - 100)
            RadialGradient(colors: [.mtAccent.opacity(0.17), .clear], center: .center,
                           startRadius: 0, endRadius: size * 0.46)
                .frame(width: size, height: size)
                .position(x: origin.x, y: origin.y)
                .scaleEffect(drift ? 1.13 : 0.94)

            ForEach(0..<5) { ring in
                Circle()
                    .strokeBorder(Color.mtAccent.opacity(ring.isMultiple(of: 2) ? 0.10 : 0.055),
                                  style: StrokeStyle(lineWidth: 1, dash: ring == 2 ? [2, 7] : []))
                    .frame(width: size * (0.40 + Double(ring) * 0.20))
                    .scaleEffect(drift ? 1.045 : 0.96)
                    .position(x: origin.x, y: origin.y)
            }
        }
    }
}
