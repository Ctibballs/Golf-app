import Foundation

public enum FairwayResult: String, Codable, CaseIterable, Identifiable, Sendable {
    case left, hit, right

    public var id: String { rawValue }

    public var symbolName: String {
        switch self {
        case .left: return "arrow.up.left"
        case .hit: return "checkmark"
        case .right: return "arrow.up.right"
        }
    }
}

/// The result of one player on one hole. Strokes can be entered directly or derived from
/// GPS-tracked shots.
public struct HoleScore: Codable, Hashable, Identifiable, Sendable {
    public var holeNumber: Int
    /// Total strokes including penalties.
    public var strokes: Int
    public var putts: Int?
    public var penalties: Int
    public var fairway: FairwayResult?
    /// Whether the player played out of a greenside bunker on this hole.
    public var sandShots: Int
    /// GPS-tracked shots, in order. Optional.
    public var shots: [Shot]
    /// Where the ball was holed, if recorded.
    public var holeLocation: GeoPoint?

    public var id: Int { holeNumber }

    public init(
        holeNumber: Int,
        strokes: Int,
        putts: Int? = nil,
        penalties: Int = 0,
        fairway: FairwayResult? = nil,
        sandShots: Int = 0,
        shots: [Shot] = [],
        holeLocation: GeoPoint? = nil
    ) {
        self.holeNumber = holeNumber
        self.strokes = strokes
        self.putts = putts
        self.penalties = penalties
        self.fairway = fairway
        self.sandShots = sandShots
        self.shots = shots
        self.holeLocation = holeLocation
    }

    /// Shots taken to reach the green (strokes minus putts). Nil if putts are unknown.
    public var shotsToGreen: Int? {
        putts.map { max(0, strokes - $0) }
    }

    /// Green in regulation: on the green with at least two strokes to spare for par.
    public func greenInRegulation(par: Int) -> Bool? {
        shotsToGreen.map { $0 <= par - 2 }
    }

    public func scoreType(par: Int) -> ScoreType {
        ScoreType(strokes: strokes, par: par)
    }

    /// Up and down: missed the green but still made par or better with one putt.
    public func upAndDown(par: Int) -> Bool? {
        guard let gir = greenInRegulation(par: par), !gir else { return nil }
        return strokes <= par
    }
}

public enum ScoreType: Int, Codable, CaseIterable, Comparable, Sendable {
    case albatrossOrBetter = -3
    case eagle = -2
    case birdie = -1
    case par = 0
    case bogey = 1
    case doubleBogey = 2
    case tripleOrWorse = 3

    public init(strokes: Int, par: Int) {
        let diff = strokes - par
        switch diff {
        case ...(-3): self = .albatrossOrBetter
        case -2: self = .eagle
        case -1: self = .birdie
        case 0: self = .par
        case 1: self = .bogey
        case 2: self = .doubleBogey
        default: self = .tripleOrWorse
        }
    }

    public static func < (lhs: ScoreType, rhs: ScoreType) -> Bool { lhs.rawValue < rhs.rawValue }

    public var displayName: String {
        switch self {
        case .albatrossOrBetter: return "Albatross+"
        case .eagle: return "Eagle"
        case .birdie: return "Birdie"
        case .par: return "Par"
        case .bogey: return "Bogey"
        case .doubleBogey: return "Double"
        case .tripleOrWorse: return "Triple+"
        }
    }

    public var isUnderPar: Bool { rawValue < 0 }
}
