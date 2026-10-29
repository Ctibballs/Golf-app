import Foundation

/// A playful avatar: an emoji on a coloured disc.
public struct Avatar: Codable, Hashable, Sendable {
    public var emoji: String
    /// Index into the app's avatar palette.
    public var colorIndex: Int

    public init(emoji: String, colorIndex: Int) {
        self.emoji = emoji
        self.colorIndex = colorIndex
    }

    public static let emojiChoices = ["🏌️", "⛳️", "🦅", "🐦", "🔥", "🌟", "🦊", "🐻", "🐯", "🦁", "🐼", "🐸", "🦄", "🚀", "👑", "🍀"]
    public static let paletteCount = 8

    public static func random<G: RandomNumberGenerator>(using generator: inout G) -> Avatar {
        Avatar(
            emoji: emojiChoices.randomElement(using: &generator) ?? "⛳️",
            colorIndex: Int.random(in: 0..<paletteCount, using: &generator)
        )
    }

    public static func random() -> Avatar {
        var g = SystemRandomNumberGenerator()
        return random(using: &g)
    }
}

public enum HandicapMode: String, Codable, CaseIterable, Identifiable, Sendable {
    /// Calculated from rounds once enough have been played.
    case automatic
    /// Entered by the player (e.g. their official club handicap).
    case manual

    public var id: String { rawValue }
}

public struct HandicapSettings: Codable, Hashable, Sendable {
    /// When false the player has no handicap: nothing is shown, and they play off
    /// scratch in net games. Rounds are still recorded, so turning it back on is instant.
    public var isEnabled: Bool
    public var mode: HandicapMode
    public var manualIndex: Double?
    /// Rounds needed before an automatic handicap is generated. WHS minimum is 3.
    public var roundsRequired: Int

    public static let minimumRounds = 3
    public static let maximumRounds = 20

    public init(mode: HandicapMode = .automatic, manualIndex: Double? = nil, roundsRequired: Int = 3, isEnabled: Bool = true) {
        self.isEnabled = isEnabled
        self.mode = mode
        self.manualIndex = manualIndex
        self.roundsRequired = min(Self.maximumRounds, max(Self.minimumRounds, roundsRequired))
    }

    enum CodingKeys: String, CodingKey {
        case isEnabled, mode, manualIndex, roundsRequired
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Libraries saved before the on/off switch existed had handicaps on.
        isEnabled = try c.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        mode = try c.decodeIfPresent(HandicapMode.self, forKey: .mode) ?? .automatic
        manualIndex = try c.decodeIfPresent(Double.self, forKey: .manualIndex)
        let rounds = try c.decodeIfPresent(Int.self, forKey: .roundsRequired) ?? Self.minimumRounds
        roundsRequired = min(Self.maximumRounds, max(Self.minimumRounds, rounds))
    }
}

public struct PlayerProfile: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var avatar: Avatar
    public var handicap: HandicapSettings
    /// Separate settings per non-WHS game type (pitch & putt, mini golf).
    public var casualHandicaps: [GameType: HandicapSettings]

    public init(
        id: UUID = UUID(),
        name: String,
        avatar: Avatar = .random(),
        handicap: HandicapSettings = HandicapSettings(),
        casualHandicaps: [GameType: HandicapSettings] = [:]
    ) {
        self.id = id
        self.name = name
        self.avatar = avatar
        self.handicap = handicap
        self.casualHandicaps = casualHandicaps
    }

    public func handicapSettings(for type: GameType) -> HandicapSettings {
        type == .golf ? handicap : (casualHandicaps[type] ?? HandicapSettings())
    }

    public mutating func setHandicapSettings(_ settings: HandicapSettings, for type: GameType) {
        if type == .golf { handicap = settings } else { casualHandicaps[type] = settings }
    }

    public var initials: String {
        let parts = name.split(separator: " ").prefix(2)
        return parts.compactMap { $0.first.map(String.init) }.joined().uppercased()
    }
}
