import Foundation

/// Distances to the front, centre and back of a green along the line of play.
public struct GreenDistances: Hashable, Sendable {
    public var front: Double
    public var center: Double
    public var back: Double
}

/// Mapped geometry of a hole, typically from OpenStreetMap's `golf=*` tags.
public struct HoleLayout: Codable, Hashable, Identifiable, Sendable {
    public var number: Int
    public var par: Int?
    /// Centre line from tee to green (`golf=hole` way).
    public var path: [GeoPoint]
    public var greens: [[GeoPoint]]
    public var tees: [[GeoPoint]]
    public var fairways: [[GeoPoint]]
    public var bunkers: [[GeoPoint]]
    public var water: [[GeoPoint]]
    public var pin: GeoPoint?

    public var id: Int { number }

    public init(
        number: Int,
        par: Int? = nil,
        path: [GeoPoint],
        greens: [[GeoPoint]] = [],
        tees: [[GeoPoint]] = [],
        fairways: [[GeoPoint]] = [],
        bunkers: [[GeoPoint]] = [],
        water: [[GeoPoint]] = [],
        pin: GeoPoint? = nil
    ) {
        self.number = number
        self.par = par
        self.path = path
        self.greens = greens
        self.tees = tees
        self.fairways = fairways
        self.bunkers = bunkers
        self.water = water
        self.pin = pin
    }

    public var teePoint: GeoPoint? {
        if let start = path.first { return start }
        return tees.first.flatMap(GeoMath.centroid(of:))
    }

    public var greenPolygon: [GeoPoint]? {
        guard let end = path.last else { return greens.first }
        return greens.min { a, b in
            GeoMath.distance(GeoMath.centroid(of: a) ?? end, end) < GeoMath.distance(GeoMath.centroid(of: b) ?? end, end)
        }
    }

    public var greenCenter: GeoPoint? {
        pin ?? greenPolygon.flatMap(GeoMath.centroid(of:)) ?? path.last
    }

    /// Playing length along the centre line in metres.
    public var length: Double? {
        if path.count >= 2 { return GeoMath.length(of: path) }
        if let tee = teePoint, let green = greenCenter { return GeoMath.distance(tee, green) }
        return nil
    }

    /// Direction of play from tee to green, used to orient the map with the green at the top.
    public var bearing: Double? {
        guard let tee = teePoint, let green = greenCenter else { return nil }
        return GeoMath.bearing(from: tee, to: green)
    }

    public var allPoints: [GeoPoint] {
        path + greens.flatMap { $0 } + tees.flatMap { $0 } + fairways.flatMap { $0 }
    }

    /// Front/centre/back distances measured along the line from `point` to the green centre.
    public func greenDistances(from point: GeoPoint) -> GreenDistances? {
        guard let center = greenCenter else { return nil }
        let centerDistance = GeoMath.distance(point, center)
        guard let polygon = greenPolygon, polygon.count >= 3 else {
            return GreenDistances(front: max(0, centerDistance - 12), center: centerDistance, back: centerDistance + 12)
        }

        // Intersect the ray point→centre with every green edge in a local flat projection.
        let c = GeoMath.project(center, origin: point)
        let ring = GeoMath.closedRing(polygon).map { GeoMath.project($0, origin: point) }
        var hits: [Double] = []
        for (a, b) in zip(ring, ring.dropFirst()) {
            let ex = b.x - a.x, ey = b.y - a.y
            let denominator = c.x * ey - c.y * ex
            guard abs(denominator) > 1e-9 else { continue }
            let t = (a.x * ey - a.y * ex) / denominator   // along the ray, in units of |c|
            let u = (a.x * c.y - a.y * c.x) / denominator  // along the edge
            if t >= 0, u >= 0, u <= 1 { hits.append(t * centerDistance) }
        }
        guard let front = hits.min(), let back = hits.max(), back > front else {
            return GreenDistances(front: max(0, centerDistance - 12), center: centerDistance, back: centerDistance + 12)
        }
        if GeoMath.contains(polygon, point) {
            return GreenDistances(front: 0, center: centerDistance, back: back)
        }
        return GreenDistances(front: front, center: centerDistance, back: back)
    }

    /// Classifies the lie at a point from the mapped features.
    public func lie(at point: GeoPoint) -> Lie {
        if greens.contains(where: { GeoMath.contains($0, point) }) { return .green }
        if bunkers.contains(where: { GeoMath.contains($0, point) }) { return .sand }
        if tees.contains(where: { GeoMath.contains($0, point) }) { return .tee }
        if fairways.contains(where: { GeoMath.contains($0, point) }) { return .fairway }
        return .rough
    }

    /// Which side of the centre line a point is on: negative = left, positive = right (metres).
    public func lateralOffset(of point: GeoPoint) -> Double? {
        guard let tee = teePoint, let green = greenCenter else { return nil }
        let g = GeoMath.project(green, origin: tee), p = GeoMath.project(point, origin: tee)
        let length = hypot(g.x, g.y)
        guard length > 0 else { return nil }
        // Cross product sign: positive when the point is to the left of tee→green.
        return -((g.x * p.y - g.y * p.x) / length)
    }
}

public struct CourseLayout: Codable, Hashable, Sendable {
    public var holes: [HoleLayout]
    /// Features not tied to a specific hole.
    public var water: [[GeoPoint]]
    public var bunkers: [[GeoPoint]]
    public var boundary: [[GeoPoint]]
    public var fetchedAt: Date

    public init(holes: [HoleLayout], water: [[GeoPoint]] = [], bunkers: [[GeoPoint]] = [], boundary: [[GeoPoint]] = [], fetchedAt: Date = Date()) {
        self.holes = holes.sorted { $0.number < $1.number }
        self.water = water
        self.bunkers = bunkers
        self.boundary = boundary
        self.fetchedAt = fetchedAt
    }

    public func hole(_ number: Int) -> HoleLayout? {
        holes.first { $0.number == number }
    }

    public var isEmpty: Bool { holes.isEmpty }

    public var bounds: GeoBounds? {
        GeoMath.bounds(of: holes.flatMap(\.allPoints) + boundary.flatMap { $0 })
    }
}

/// Turns raw GPS marks into scored shots.
public enum ShotTracking {
    /// Links shots so each ends where the next one starts; the last ends at the hole.
    public static func linked(_ shots: [Shot], holeLocation: GeoPoint?) -> [Shot] {
        var result = shots
        for i in result.indices {
            if i + 1 < result.count {
                result[i].end = result[i + 1].start
            } else if let holeLocation {
                result[i].end = holeLocation
            }
        }
        return result
    }

    /// Derives a hole score (strokes, putts, fairway, sand) from tracked shots.
    public static func holeScore(
        holeNumber: Int,
        par: Int,
        shots: [Shot],
        holeLocation: GeoPoint?,
        layout: HoleLayout?
    ) -> HoleScore {
        let linkedShots = linked(shots, holeLocation: holeLocation)
        let penalties = linkedShots.reduce(0) { $0 + $1.penaltyStrokes }
        let putts = linkedShots.filter(\.isPutt).count
        let sand = linkedShots.filter { $0.lie == .sand }.count

        var fairway: FairwayResult?
        if par >= 4, linkedShots.count >= 2, linkedShots[0].lie == .tee {
            let second = linkedShots[1]
            switch second.lie {
            case .fairway:
                fairway = .hit
            case .green:
                fairway = .hit
            default:
                if let offset = layout?.lateralOffset(of: second.start) {
                    fairway = offset < 0 ? .left : .right
                }
            }
        }

        return HoleScore(
            holeNumber: holeNumber,
            strokes: linkedShots.count + penalties,
            putts: putts,
            penalties: penalties,
            fairway: fairway,
            sandShots: sand,
            shots: linkedShots,
            holeLocation: holeLocation
        )
    }
}
