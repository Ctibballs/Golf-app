import Foundation

public enum Club: String, Codable, CaseIterable, Identifiable, Sendable {
    case driver, wood3, wood5, hybrid
    case iron3, iron4, iron5, iron6, iron7, iron8, iron9
    case pitchingWedge, gapWedge, sandWedge, lobWedge
    case putter

    public var id: String { rawValue }

    public var shortName: String {
        switch self {
        case .driver: return "Dr"
        case .wood3: return "3W"
        case .wood5: return "5W"
        case .hybrid: return "Hy"
        case .iron3: return "3i"
        case .iron4: return "4i"
        case .iron5: return "5i"
        case .iron6: return "6i"
        case .iron7: return "7i"
        case .iron8: return "8i"
        case .iron9: return "9i"
        case .pitchingWedge: return "PW"
        case .gapWedge: return "GW"
        case .sandWedge: return "SW"
        case .lobWedge: return "LW"
        case .putter: return "Pt"
        }
    }

    public var displayName: String {
        switch self {
        case .driver: return "Driver"
        case .wood3: return "3 Wood"
        case .wood5: return "5 Wood"
        case .hybrid: return "Hybrid"
        case .iron3: return "3 Iron"
        case .iron4: return "4 Iron"
        case .iron5: return "5 Iron"
        case .iron6: return "6 Iron"
        case .iron7: return "7 Iron"
        case .iron8: return "8 Iron"
        case .iron9: return "9 Iron"
        case .pitchingWedge: return "Pitching Wedge"
        case .gapWedge: return "Gap Wedge"
        case .sandWedge: return "Sand Wedge"
        case .lobWedge: return "Lob Wedge"
        case .putter: return "Putter"
        }
    }

    /// Typical carry for an average amateur, in metres. Used to suggest a club.
    public var typicalDistance: Double {
        switch self {
        case .driver: return 200
        case .wood3: return 180
        case .wood5: return 165
        case .hybrid: return 155
        case .iron3: return 150
        case .iron4: return 145
        case .iron5: return 137
        case .iron6: return 128
        case .iron7: return 119
        case .iron8: return 110
        case .iron9: return 100
        case .pitchingWedge: return 90
        case .gapWedge: return 78
        case .sandWedge: return 65
        case .lobWedge: return 50
        case .putter: return 5
        }
    }

    /// Suggest the club whose typical distance is closest to `metres`, optionally using
    /// the player's own averages.
    public static func suggested(for metres: Double, averages: [Club: Double] = [:]) -> Club {
        let candidates = Club.allCases.filter { $0 != .putter }
        return candidates.min { a, b in
            abs((averages[a] ?? a.typicalDistance) - metres) < abs((averages[b] ?? b.typicalDistance) - metres)
        } ?? .iron7
    }
}

/// Where the ball lay when a shot was played.
public enum Lie: String, Codable, CaseIterable, Identifiable, Sendable {
    case tee, fairway, rough, sand, green, recovery

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .tee: return "Tee"
        case .fairway: return "Fairway"
        case .rough: return "Rough"
        case .sand: return "Bunker"
        case .green: return "Green"
        case .recovery: return "Trees"
        }
    }

    public var symbolName: String {
        switch self {
        case .tee: return "arrow.up.circle"
        case .fairway: return "leaf"
        case .rough: return "leaf.fill"
        case .sand: return "beach.umbrella"
        case .green: return "flag"
        case .recovery: return "tree"
        }
    }
}

/// A single GPS-tracked shot. A shot starts where the ball lay and ends where the
/// next shot was played from (or the hole, for the final putt).
public struct Shot: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var start: GeoPoint
    public var end: GeoPoint?
    public var club: Club?
    public var lie: Lie
    public var timestamp: Date
    /// Penalty strokes incurred by this shot (water, OB, unplayable).
    public var penaltyStrokes: Int

    public init(
        id: UUID = UUID(),
        start: GeoPoint,
        end: GeoPoint? = nil,
        club: Club? = nil,
        lie: Lie,
        timestamp: Date = Date(),
        penaltyStrokes: Int = 0
    ) {
        self.id = id
        self.start = start
        self.end = end
        self.club = club
        self.lie = lie
        self.timestamp = timestamp
        self.penaltyStrokes = penaltyStrokes
    }

    /// Shot distance in metres, once the end is known.
    public var distance: Double? {
        end.map { GeoMath.distance(start, $0) }
    }

    public var isPutt: Bool { lie == .green || club == .putter }
}
