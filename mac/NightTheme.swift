import SwiftUI

// Thème nuit de l'app, aligné sur web/theme-nuit.css : fond encre, brume citron et olive, verre fumé.
extension Color {
    static let mtGlass = Color(.sRGB, red: 24 / 255, green: 33 / 255, blue: 29 / 255, opacity: 0.62)
    static let mtWell = Color(.sRGB, red: 15 / 255, green: 22 / 255, blue: 19 / 255, opacity: 0.72)
    static let mtControlTint = Color(.sRGB, red: 92 / 255, green: 107 / 255, blue: 15 / 255)
    static let mtSidebarVeil = Color(.sRGB, red: 15 / 255, green: 22 / 255, blue: 19 / 255, opacity: 0.45)
}

struct MTMist: View {
    private let ink = Color(.sRGB, red: 15 / 255, green: 22 / 255, blue: 19 / 255)
    private let lime = Color(.sRGB, red: 207 / 255, green: 232 / 255, blue: 107 / 255)
    private let olive = Color(.sRGB, red: 92 / 255, green: 107 / 255, blue: 15 / 255)
    private let moss = Color(.sRGB, red: 42 / 255, green: 51 / 255, blue: 32 / 255)

    var body: some View {
        ZStack {
            ink
            glow(lime.opacity(0.13), x: 0.18, y: 0.96, radius: 0.5)
            glow(olive.opacity(0.34), x: 0.86, y: 1.0, radius: 0.55)
            glow(lime.opacity(0.05), x: 0.92, y: 0.06, radius: 0.42)
            glow(moss.opacity(0.55), x: 0, y: 0, radius: 0.5)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func glow(_ color: Color, x: CGFloat, y: CGFloat, radius: CGFloat) -> some View {
        EllipticalGradient(
            colors: [color, color.opacity(0)],
            center: UnitPoint(x: x, y: y),
            startRadiusFraction: 0,
            endRadiusFraction: radius
        )
    }
}

extension View {
    func meetinNight() -> some View {
        self
            .font(.mtSans(14))
            .foregroundStyle(Color.mtInk)
            .background(MTMist().ignoresSafeArea())
            .preferredColorScheme(.dark)
    }

    func mtGlass(cornerRadius: CGFloat = MTRadius.card) -> some View {
        self
            .background(Color.mtGlass, in: RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius).strokeBorder(Color.mtLine, lineWidth: 1))
    }
}

// Logo de marque, embarqué dans l'app par build.sh.
struct MTLogo: View {
    var size: CGFloat = 32

    var body: some View {
        Group {
            if let url = Bundle.main.url(forResource: "MeetinOS", withExtension: "png"),
               let logo = NSImage(contentsOf: url) {
                Image(nsImage: logo).resizable().scaledToFit()
            } else {
                Image(systemName: "waveform").foregroundStyle(Color.mtAccentText)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct MTCapsuleLinkStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.mtSans(13))
            .foregroundStyle(Color.mtInk)
            .padding(.horizontal, 14)
            .frame(height: 30)
            .background(configuration.isPressed ? Color.mtSurface : Color.clear, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.mtLineStrong, lineWidth: 1))
            .contentShape(Capsule())
    }
}
