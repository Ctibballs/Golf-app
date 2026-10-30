import Foundation

/// Works out which course you're standing at from your location.
public enum CourseDetector {
    /// How close you need to be to a course's centre to count as being there, when its
    /// grounds and holes aren't mapped.
    public static func radius(for type: GameType) -> Double {
        switch type {
        case .golf: return 700
        case .pitchAndPutt: return 250
        case .miniGolf: return 80
        }
    }

    /// How far outside the mapped holes still counts as being on the course (tees and
    /// greens are rarely mapped right to the edge, and you might be walking between holes).
    public static let holeMargin: Double = 60

    /// Distance in metres from a point to a course's mapped grounds and holes: zero when
    /// inside them. Nil when nothing is mapped.
    public static func distance(from point: GeoPoint, to layout: CourseLayout) -> Double? {
        if layout.boundary.contains(where: { $0.count >= 3 && GeoMath.contains($0, point) }) { return 0 }
        var nearest: Double?
        for hole in layout.holes {
            for area in hole.greens + hole.tees + hole.fairways where area.count >= 3 && GeoMath.contains(area, point) {
                return 0
            }
            if hole.path.count >= 2 {
                let d = GeoMath.distance(from: point, toPath: hole.path)
                nearest = min(nearest ?? d, d)
            }
        }
        return nearest
    }

    /// The course you're at, from courses already on the device. Being on a mapped hole or
    /// inside mapped grounds wins over being near a course's centre.
    public static func course(at point: GeoPoint, among courses: [Course], layouts: [String: CourseLayout]) -> (course: Course, distance: Double)? {
        var best: (course: Course, rank: Double, distance: Double)?
        for course in courses {
            var candidate: (rank: Double, distance: Double)?
            if let layout = layouts[course.id], let d = distance(from: point, to: layout), d <= holeMargin {
                candidate = (d, d)
            } else if let centre = course.location {
                let d = GeoMath.distance(point, centre)
                // Centre matches rank after any mapped match.
                if d <= radius(for: course.gameType) { candidate = (10_000 + d, d) }
            }
            if let candidate, candidate.rank < (best?.rank ?? .infinity) {
                best = (course, candidate.rank, candidate.distance)
            }
        }
        return best.map { ($0.course, $0.distance) }
    }

    /// The course you're at, from what the map and the course directory say about a point.
    /// `containing` are courses whose mapped grounds contain the point, `near` are mapped
    /// courses whose grounds come within a short walk of it, and `listed` are directory
    /// courses with scorecards. A listed course next to the mapped one is preferred, for its
    /// scorecard and tees.
    public static func bestMatch(at point: GeoPoint, containing: [CourseSummary], near: [CourseSummary], listed: [CourseSummary]) -> CourseSummary? {
        // Inside two areas (a mini golf within a golf resort, say): the smaller kind wins.
        let mapped = containing.max { specificity($0) < specificity($1) }
            ?? near.min { distance(point, $0) < distance(point, $1) }

        if let mapped {
            let anchor = mapped.location ?? point
            let type = mapped.inferredGameType
            let withScorecard = listed
                .filter { $0.inferredGameType == type }
                .filter { distance(anchor, $0) < 1_000 }
                .min { distance(anchor, $0) < distance(anchor, $1) }
            return withScorecard ?? mapped
        }
        return listed
            .filter { distance(point, $0) <= radius(for: $0.inferredGameType) }
            .min { distance(point, $0) < distance(point, $1) }
    }

    private static func specificity(_ summary: CourseSummary) -> Int {
        switch summary.inferredGameType {
        case .miniGolf: return 2
        case .pitchAndPutt: return 1
        case .golf: return 0
        }
    }

    private static func distance(_ point: GeoPoint, _ summary: CourseSummary) -> Double {
        summary.location.map { GeoMath.distance(point, $0) } ?? .infinity
    }
}
