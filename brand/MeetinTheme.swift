import SwiftUI
import AppKit

// Meetin-OS · thème SwiftUI (base B crème + accent citron vert)
//
// Règle d'or : le citron vert (mtAccent) est un FOND, avec du texte mtOnAccent dessus.
// Jamais en texte ni en icône sur fond clair (contraste 1,28:1) : utiliser mtAccentText.
//
// Remplacements dans MeetinOS.swift :
//   Color.accentColor        -> Color.mtAccent (fonds) ou Color.mtAccentText (icône, lien)
//   Color.red (enregistrement) -> Color.mtRec
//   Color(nsColor: .textBackgroundColor) -> Color.mtCanvas
//   .font(.system(size: 32, weight: .semibold, design: .serif)) -> .font(.mtSerif(32))

extension Color {
    init(mtLight: String, mtDark: String) {
        self.init(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(mtHex: isDark ? mtDark : mtLight)
        }))
    }

    static let mtCanvas = Color(mtLight: "#FAF8F1", mtDark: "#0F1613")
    static let mtSurface = Color(mtLight: "#EDE9DA", mtDark: "#18211D")
    static let mtInk = Color(mtLight: "#14201C", mtDark: "#F3F1E6")
    static let mtInk2 = Color(mtLight: "#5E675F", mtDark: "#A3ADA5")

    static let mtAccent = Color(mtLight: "#CFE86B", mtDark: "#CFE86B")
    static let mtAccentHover = Color(mtLight: "#C3DE55", mtDark: "#DDF083")
    static let mtAccentTint = Color(mtLight: "#EEF3C7", mtDark: "#2A3320")
    static let mtOnAccent = Color(mtLight: "#14201C", mtDark: "#14201C")
    static let mtAccentText = Color(mtLight: "#5C6B0F", mtDark: "#CFE86B")

    static let mtRec = Color(mtLight: "#C8341C", mtDark: "#FF6A4D")
    static let mtRecTint = Color(mtLight: "#FBEAE6", mtDark: "#3A1F1A")
    static let mtWarn = Color(mtLight: "#8A5A0B", mtDark: "#F0B94F")
    static let mtWarnTint = Color(mtLight: "#F6E7C8", mtDark: "#33281A")
}

extension Color {
    // Traits fins : encre à faible opacité, valable en clair et en sombre.
    static let mtLine = Color.mtInk.opacity(0.14)
    static let mtLineStrong = Color.mtInk.opacity(0.32)
}

fileprivate extension NSColor {
    convenience init(mtHex hex: String) {
        let s = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        self.init(
            srgbRed: CGFloat((v >> 16) & 0xFF) / 255,
            green: CGFloat((v >> 8) & 0xFF) / 255,
            blue: CGFloat(v & 0xFF) / 255,
            alpha: 1
        )
    }
}

// Polices : EB Garamond (titres) et Figtree (interface).
// Si elles ne sont pas installées ni embarquées dans l'app, repli sur le serif et le sans système.
extension Font {
    static func mtSerif(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        let name = weight == .regular ? "EBGaramond-Regular" : "EBGaramond-Medium"
        if NSFont(name: name, size: size) != nil { return .custom(name, size: size) }
        return .system(size: size, weight: weight, design: .serif)
    }

    static func mtSans(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        let name = weight == .regular ? "Figtree-Regular" : "Figtree-Medium"
        if NSFont(name: name, size: size) != nil { return .custom(name, size: size) }
        return .system(size: size, weight: weight, design: .default)
    }
}

// Rayons
enum MTRadius {
    static let input: CGFloat = 8
    static let button: CGFloat = 12
    static let card: CGFloat = 16
}

// Boutons : un seul .mtPrimary par écran
struct MTPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.mtSans(14, weight: .medium))
            .foregroundStyle(Color.mtOnAccent)
            .padding(.horizontal, 16)
            .frame(height: 40)
            .background(
                configuration.isPressed ? Color.mtAccentHover : Color.mtAccent,
                in: RoundedRectangle(cornerRadius: MTRadius.button)
            )
    }
}

struct MTGhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.mtSans(14, weight: .medium))
            .foregroundStyle(Color.mtInk)
            .padding(.horizontal, 16)
            .frame(height: 40)
            .background(
                configuration.isPressed ? Color.mtSurface : Color.clear,
                in: RoundedRectangle(cornerRadius: MTRadius.button)
            )
            .overlay(
                RoundedRectangle(cornerRadius: MTRadius.button)
                    .stroke(Color.mtLineStrong, lineWidth: 1)
            )
    }
}

extension ButtonStyle where Self == MTPrimaryButtonStyle {
    static var mtPrimary: MTPrimaryButtonStyle { MTPrimaryButtonStyle() }
}

extension ButtonStyle where Self == MTGhostButtonStyle {
    static var mtGhost: MTGhostButtonStyle { MTGhostButtonStyle() }
}

// Carte : couche de crème, pas d'ombre
extension View {
    func mtCard() -> some View {
        self.padding(16)
            .background(Color.mtSurface, in: RoundedRectangle(cornerRadius: MTRadius.card))
    }
}
