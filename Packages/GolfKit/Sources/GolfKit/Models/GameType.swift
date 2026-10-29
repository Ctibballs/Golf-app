import Foundation

/// The flavour of golf being played. Each type has its own par conventions,
/// stat set and handicap pool.
public enum GameType: String, Codable, CaseIterable, Identifiable, Sendable {
    case golf
    case pitchAndPutt
    case miniGolf

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .golf: return "Golf"
        case .pitchAndPutt: return "Pitch & Putt"
        case .miniGolf: return "Mini Golf"
        }
    }

    public var symbolName: String {
        switch self {
        case .golf: return "figure.golf"
        case .pitchAndPutt: return "flag.fill"
        case .miniGolf: return "smallcircle.filled.circle"
        }
    }

    public var tagline: String {
        switch self {
        case .golf: return "Full course with GPS shot tracking"
        case .pitchAndPutt: return "Short par-3 holes, perfect for a quick round"
        case .miniGolf: return "Putt-putt with friends, no GPS needed"
        }
    }

    public var defaultHoleCount: Int {
        switch self {
        case .golf, .pitchAndPutt: return 18
        case .miniGolf: return 18
        }
    }

    public var defaultPar: Int {
        switch self {
        case .golf: return 4
        case .pitchAndPutt: return 3
        case .miniGolf: return 2
        }
    }

    public var allowedPars: ClosedRange<Int> {
        switch self {
        case .golf: return 3...6
        case .pitchAndPutt: return 2...4
        case .miniGolf: return 1...5
        }
    }

    /// Mini golf normally caps strokes per hole (commonly 6).
    public var maxStrokesPerHole: Int? {
        switch self {
        case .miniGolf: return 6
        case .golf, .pitchAndPutt: return nil
        }
    }

    /// GPS shot tracking makes sense outdoors on real grass.
    public var supportsShotTracking: Bool { self != .miniGolf }

    /// Fairways only exist on par 4s and 5s of a full course.
    public var tracksFairways: Bool { self == .golf }

    /// Greens-in-regulation and putts are meaningful for golf and pitch & putt.
    public var tracksGreens: Bool { self != .miniGolf }

    /// Only full golf uses the World Handicap System; other types use a casual index.
    public var usesWorldHandicapSystem: Bool { self == .golf }
}

/// Lets `[GameType: T]` encode as a JSON object rather than a key/value array.
extension GameType: CodingKeyRepresentable {}
