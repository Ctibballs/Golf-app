import Foundation

public struct ReplayShot: Hashable, Identifiable, Sendable {
    public var id: UUID
    public var playerID: UUID
    public var holeNumber: Int
    /// 1-based stroke number on the hole.
    public var strokeNumber: Int
    public var start: GeoPoint
    public var end: GeoPoint
    public var club: Club?
    public var lie: Lie

    public var distance: Double { GeoMath.distance(start, end) }
    public var isPutt: Bool { lie == .green || club == .putter }

    public init(id: UUID = UUID(), playerID: UUID, holeNumber: Int, strokeNumber: Int, start: GeoPoint, end: GeoPoint, club: Club? = nil, lie: Lie) {
        self.id = id
        self.playerID = playerID
        self.holeNumber = holeNumber
        self.strokeNumber = strokeNumber
        self.start = start
        self.end = end
        self.club = club
        self.lie = lie
    }

    /// Builds replay shots from a scorecard, skipping shots with no end point.
    public static func from(scores: [HoleScore], playerID: UUID) -> [ReplayShot] {
        scores.flatMap { score in
            ShotTracking.linked(score.shots, holeLocation: score.holeLocation).enumerated().compactMap { index, shot in
                guard let end = shot.end else { return nil }
                return ReplayShot(
                    id: shot.id, playerID: playerID, holeNumber: score.holeNumber, strokeNumber: index + 1,
                    start: shot.start, end: end, club: shot.club, lie: shot.lie
                )
            }
        }
    }
}

/// One moment of a replay.
public struct ReplayFrame: Hashable, Sendable {
    public var holeNumber: Int?
    public var completed: [ReplayShot]
    public var active: ReplayShot?
    /// Progress of the active shot, 0...1 (eased).
    public var progress: Double
    public var ball: GeoPoint?
    /// Visual ball height 0...1 for a flight arc; 0 for putts.
    public var height: Double
}

/// Deterministic schedule for animating shots: every shot gets a start time and a duration
/// that grows with its length, with a pause whenever play moves to a new hole.
public struct ReplayTimeline: Sendable {
    public struct Segment: Hashable, Sendable {
        public var shot: ReplayShot
        public var start: TimeInterval
        public var duration: TimeInterval
        public var end: TimeInterval { start + duration }
    }

    public let segments: [Segment]
    public let totalDuration: TimeInterval
    public let holeIntro: TimeInterval
    public let pause: TimeInterval

    public init(shots: [ReplayShot], holeIntro: TimeInterval = 1.0, pause: TimeInterval = 0.35) {
        self.holeIntro = holeIntro
        self.pause = pause
        var time: TimeInterval = 0
        var segments: [Segment] = []
        var currentHole: Int?
        for shot in shots {
            if shot.holeNumber != currentHole {
                time += holeIntro
                currentHole = shot.holeNumber
            }
            let duration = Self.duration(for: shot)
            segments.append(Segment(shot: shot, start: time, duration: duration))
            time += duration + pause
        }
        self.segments = segments
        self.totalDuration = time
    }

    /// Longer shots take longer, but not linearly, so drives don't drag.
    public static func duration(for shot: ReplayShot) -> TimeInterval {
        shot.isPutt ? 0.5 + sqrt(shot.distance) / 6 : 0.6 + sqrt(shot.distance) / 8
    }

    public var holeNumbers: [Int] {
        var seen: [Int] = []
        for s in segments where seen.last != s.shot.holeNumber { seen.append(s.shot.holeNumber) }
        return seen
    }

    /// When a hole's first shot starts (minus the intro), for scrubbing to a hole.
    public func startTime(ofHole hole: Int) -> TimeInterval? {
        segments.first { $0.shot.holeNumber == hole }.map { max(0, $0.start - holeIntro) }
    }

    public func frame(at time: TimeInterval) -> ReplayFrame {
        guard let first = segments.first else {
            return ReplayFrame(holeNumber: nil, completed: [], active: nil, progress: 0, ball: nil, height: 0)
        }
        let t = max(0, min(time, totalDuration))

        // The active segment is the last one that has started.
        guard let index = segments.lastIndex(where: { $0.start <= t }) else {
            return ReplayFrame(holeNumber: first.shot.holeNumber, completed: [], active: nil, progress: 0, ball: first.shot.start, height: 0)
        }
        let segment = segments[index]
        let hole = segment.shot.holeNumber
        let completedOnHole = segments[..<index].filter { $0.shot.holeNumber == hole }.map(\.shot)

        if t >= segment.end {
            // Resting between shots, or the replay is over.
            let nextIsNewHole = index + 1 < segments.count && segments[index + 1].shot.holeNumber != hole
            if nextIsNewHole, t >= segments[index + 1].start - holeIntro {
                let next = segments[index + 1].shot
                return ReplayFrame(holeNumber: next.holeNumber, completed: [], active: nil, progress: 0, ball: next.start, height: 0)
            }
            return ReplayFrame(holeNumber: hole, completed: completedOnHole + [segment.shot], active: nil, progress: 1, ball: segment.shot.end, height: 0)
        }

        let linear = (t - segment.start) / segment.duration
        let eased = Self.easeOut(linear)
        let ball = GeoMath.interpolate(segment.shot.start, segment.shot.end, fraction: eased)
        let height = segment.shot.isPutt ? 0 : sin(.pi * linear) * min(1, segment.shot.distance / 150)
        return ReplayFrame(holeNumber: hole, completed: completedOnHole, active: segment.shot, progress: eased, ball: ball, height: height)
    }

    static func easeOut(_ x: Double) -> Double {
        1 - pow(1 - max(0, min(1, x)), 2)
    }
}
