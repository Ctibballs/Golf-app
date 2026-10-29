import SwiftUI
import UIKit
import GolfKit

/// Colours, gradients and type used across the app. Greens lean fresh rather than
/// country-club, with a coral flag accent and adaptive light/dark variants.
enum Theme {
    static let fairway = Color(light: 0x1E9E57, dark: 0x41CE7A)
    static let deepGreen = Color(light: 0x0B4D33, dark: 0x0E3A27)
    static let lime = Color(light: 0x8BD346, dark: 0xA7E86A)
    static let sand = Color(light: 0xE9D4A4, dark: 0xC9B07B)
    static let water = Color(light: 0x2D8CFF, dark: 0x4FA3FF)
    static let flag = Color(light: 0xFF5A4E, dark: 0xFF6B5F)
    static let gold = Color(light: 0xF5B400, dark: 0xFFC83D)

    static let background = Color(uiColor: .systemGroupedBackground)
    static let card = Color(uiColor: .secondarySystemGroupedBackground)

    static let heroGradient = LinearGradient(
        colors: [Color(hex: 0x2BC46E), Color(hex: 0x0B6B45), Color(hex: 0x074A31)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    static let skyGradient = LinearGradient(
        colors: [Color(hex: 0x4FA3FF), Color(hex: 0x2D6CDF)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    static let sunsetGradient = LinearGradient(
        colors: [Color(hex: 0xFF8A5B), Color(hex: 0xFF5A4E)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    static let goldGradient = LinearGradient(
        colors: [Color(hex: 0xFFD45E), Color(hex: 0xF5A300)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    /// Avatar backgrounds, indexed by `Avatar.colorIndex`.
    static let avatarPalette: [Color] = [
        Color(hex: 0x1E9E57), Color(hex: 0xFF8A3D), Color(hex: 0x2D8CFF), Color(hex: 0xAF52DE),
        Color(hex: 0xFF5A4E), Color(hex: 0x14B8A6), Color(hex: 0xF5B400), Color(hex: 0x5E5CE6),
    ]

    static func avatarColor(_ index: Int) -> Color {
        avatarPalette[((index % avatarPalette.count) + avatarPalette.count) % avatarPalette.count]
    }

    /// Scorecard colours: red for under par, blue for over, as on a printed card.
    static func scoreColor(toPar: Int) -> Color {
        switch toPar {
        case ..<(-1): return gold
        case -1: return flag
        case 0: return .primary
        case 1: return water
        default: return Color(hex: 0x5E5CE6)
        }
    }

    static func tint(for type: GameType) -> Color {
        switch type {
        case .golf: return fairway
        case .pitchAndPutt: return water
        case .miniGolf: return Color(hex: 0xAF52DE)
        }
    }

    static func gradient(for type: GameType) -> LinearGradient {
        switch type {
        case .golf: return heroGradient
        case .pitchAndPutt: return skyGradient
        case .miniGolf:
            return LinearGradient(colors: [Color(hex: 0xC56CF0), Color(hex: 0x7B3FE4)], startPoint: .topLeading, endPoint: .bottomTrailing)
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
    static func rounded(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}

extension Animation {
    static let snappySpring = Animation.spring(response: 0.35, dampingFraction: 0.78)
    static let playful = Animation.spring(response: 0.45, dampingFraction: 0.62)
}
