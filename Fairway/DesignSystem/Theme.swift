import SwiftUI
import UIKit
import GolfKit

/// Fairway's visual language: quiet page backgrounds, structure from type and hairline
/// rules rather than boxes, one deep-green accent, and scorecard colours kept for scores.
enum Theme {
    // MARK: Colour

    /// The accent: a deep course green (lighter in dark mode so it keeps its contrast).
    static let fairway = Color(light: 0x0E6B45, dark: 0x4CC38A)
    /// Text and icons drawn on top of the accent.
    static let onAccent = Color(light: 0xFFFFFF, dark: 0x05170E)
    static let deepGreen = Color(light: 0x0A3D28, dark: 0x0C2A1C)

    /// Under par, live and destructive.
    static let flag = Color(light: 0xC0392B, dark: 0xFF6A5E)
    /// Eagles and leaders.
    static let gold = Color(light: 0xA97B10, dark: 0xE5B53E)
    /// Bogeys and water.
    static let water = Color(light: 0x2F6690, dark: 0x6CA8D8)
    /// Double bogey or worse.
    static let double = Color(light: 0x27365A, dark: 0xA6B3CF)
    static let sand = Color(light: 0xB8975A, dark: 0xCDB07A)
    /// Trophy metals.
    static let silver = Color(light: 0x8A949C, dark: 0xC3CBD2)
    static let bronze = Color(light: 0x9A6638, dark: 0xD49A66)

    static let background = Color(uiColor: .systemBackground)
    /// The only filled surface: keys, inputs and skeletons.
    static let surface = Color(uiColor: .secondarySystemBackground)
    static let fill = Color(uiColor: .tertiarySystemFill)
    static let hairline = Color(uiColor: .separator)
    /// A slightly firmer line for outlined controls.
    static let outline = Color.primary.opacity(0.16)

    /// Inverted surface for toasts.
    static let toast = Color(light: 0x141816, dark: 0xF1F3F2)
    static let onToast = Color(light: 0xF1F3F2, dark: 0x141816)

    /// Status colours for the inverted toast surface (bright on dark, deep on light).
    enum OnToast {
        static let success = Color(light: 0x4CC38A, dark: 0x0E6B45)
        static let error = Color(light: 0xFF6A5E, dark: 0xC0392B)
        static let info = Color(light: 0x6CA8D8, dark: 0x2F6690)
        static let celebration = Color(light: 0xE5B53E, dark: 0xA97B10)
    }

    // MARK: Layout

    static let gutter: CGFloat = 20
    static let sectionSpacing: CGFloat = 36
    static let corner: CGFloat = 12

    /// Muted avatar tints, indexed by `Avatar.colorIndex`.
    static let avatarPalette: [Color] = [
        Color(hex: 0x2E7D5B), Color(hex: 0xC4703A), Color(hex: 0x3A6EA5), Color(hex: 0x7A5BA6),
        Color(hex: 0xB4473C), Color(hex: 0x2A8A88), Color(hex: 0xAE8A2C), Color(hex: 0x52579F),
    ]

    static func avatarColor(_ index: Int) -> Color {
        avatarPalette[((index % avatarPalette.count) + avatarPalette.count) % avatarPalette.count]
    }

    /// Scorecard colours: red under par, blue over, as on a printed card.
    static func scoreColor(toPar: Int) -> Color {
        switch toPar {
        case ..<(-1): return gold
        case -1: return flag
        case 0: return .primary
        case 1: return water
        default: return double
        }
    }

    /// A small identifying colour per game type, used for dots and icons only.
    static func tint(for type: GameType) -> Color {
        switch type {
        case .golf: return fairway
        case .pitchAndPutt: return water
        case .miniGolf: return Color(light: 0x7A4E9C, dark: 0xB894D6)
        }
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }

    /// Parses "#RRGGBB" strings from course data.
    init?(hexString: String?) {
        guard var s = hexString?.trimmingCharacters(in: .whitespaces) else { return nil }
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let value = UInt32(s, radix: 16) else { return nil }
        self.init(hex: value)
    }

    /// A colour that adapts to light and dark mode.
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(
                red: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: 1
            )
        })
    }
}

extension Font {
    /// The serif display face, for names, titles and headline numbers.
    static func display(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }

    /// Tabular figures, for numbers that line up in columns or change in place.
    static func figure(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight).monospacedDigit()
    }

    /// Small capitals-style labels above values and sections.
    static let eyebrow = Font.system(size: 11, weight: .semibold)
}

extension Animation {
    static let snappySpring = Animation.spring(response: 0.35, dampingFraction: 0.82)
    static let gentle = Animation.easeOut(duration: 0.45)
}

/// Navigation bar styling: serif large titles, plain bars that pick up a hairline once
/// content scrolls underneath.
enum NavigationBarStyle {
    static func apply() {
        let largeDescriptor = UIFont.systemFont(ofSize: 34, weight: .semibold).fontDescriptor.withDesign(.serif)
        let largeFont = largeDescriptor.map { UIFont(descriptor: $0, size: 34) } ?? .systemFont(ofSize: 34, weight: .bold)
        let titleFont = UIFont.systemFont(ofSize: 17, weight: .semibold)

        let scrolled = UINavigationBarAppearance()
        scrolled.configureWithDefaultBackground()
        scrolled.largeTitleTextAttributes = [.font: largeFont]
        scrolled.titleTextAttributes = [.font: titleFont]

        let edge = UINavigationBarAppearance()
        edge.configureWithTransparentBackground()
        edge.largeTitleTextAttributes = [.font: largeFont]
        edge.titleTextAttributes = [.font: titleFont]

        let bar = UINavigationBar.appearance()
        bar.standardAppearance = scrolled
        bar.compactAppearance = scrolled
        bar.scrollEdgeAppearance = edge
    }
}
