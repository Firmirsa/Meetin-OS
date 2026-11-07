import SwiftUI

struct WelcomeView: View {
    let account: HostedAccount
    let client: AccountClient?
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
                MTLogo(size: 94)
                    .padding(.bottom, 3)
                    .offset(y: drift ? -4 : 3)
                Text("Meetin-OS")
                    .font(.mtSerif(62))
                    .accessibilityAddTraits(.isHeader)
                Text("Transcris tes réunions et valide les actions à suivre.")
                    .font(.mtSans(16))
                    .foregroundStyle(Color.mtInk2)
                    .multilineTextAlignment(.center)
                GoogleSignInButton(account: account, client: client)
                    .padding(.top, 14)
            }
            .padding(36)
            .opacity(reduceMotion || appeared ? 1 : 0)
            .offset(y: reduceMotion || appeared ? 0 : 14)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear(perform: animate)
        .onChange(of: reduceMotion) { animate() }
    }

    private func animate() {
        if reduceMotion {
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) { appeared = true; drift = false }
        } else {
            withAnimation(.easeOut(duration: 0.42)) { appeared = true }
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
