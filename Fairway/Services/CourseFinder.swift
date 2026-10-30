import Foundation
import Observation
import GolfKit

/// Recognises the course you're at from your location, so setup screens can fill it in.
/// Courses already on the device are checked first (instant, offline); otherwise the map
/// and the course directory are asked, but not more than every few minutes.
@Observable
@MainActor
final class CourseFinder {
    struct Detection: Equatable {
        let course: Course
        /// Metres from the course's mapped holes or centre.
        let distance: Double
        let detectedAt: Date
    }

    private(set) var detection: Detection?
    private(set) var isSearching = false

    @ObservationIgnored var knownCourses: () -> [Course] = { [] }
    @ObservationIgnored var layouts: () -> [String: CourseLayout] = { [:] }
    @ObservationIgnored var remoteLookup: (GeoPoint) async -> Course? = { _ in nil }

    @ObservationIgnored private var lastPoint: GeoPoint?
    @ObservationIgnored private var lastRemote: (point: GeoPoint, date: Date, found: Bool)?
    @ObservationIgnored private var dismissed: Set<String> = []
    @ObservationIgnored private var lookup: Task<Void, Never>?

    /// Ignore GPS jitter smaller than this.
    private let jitter: Double = 40
    /// Don't ask the network again within this time unless you've moved a fair way.
    private let remoteInterval: TimeInterval = 10 * 60

    func update(location point: GeoPoint, now: Date = Date()) {
        if let last = lastPoint, GeoMath.distance(last, point) < jitter, detection != nil || lookup != nil { return }
        lastPoint = point

        if let local = CourseDetector.course(at: point, among: knownCourses(), layouts: layouts()) {
            show(local.course, distance: local.distance)
            return
        }
        // Still nearby (walking back to the car park): keep what we found.
        if let current = detection, let centre = current.course.location,
           GeoMath.distance(centre, point) <= CourseDetector.radius(for: current.course.gameType) * 1.5 {
            return
        }
        if let last = lastRemote,
           GeoMath.distance(last.point, point) < (last.found ? 300 : 800),
           now.timeIntervalSince(last.date) < remoteInterval {
            if !last.found { detection = nil }
            return
        }

        lookup?.cancel()
        lookup = Task { [weak self] in
            guard let self else { return }
            self.isSearching = true
            let course = await self.remoteLookup(point)
            self.isSearching = false
            self.lookup = nil
            guard !Task.isCancelled else { return }
            self.lastRemote = (point, Date(), course != nil)
            if let course {
                let distance = course.location.map { GeoMath.distance($0, point) } ?? 0
                self.show(course, distance: distance)
            } else {
                self.detection = nil
            }
        }
    }

    /// "Not here": hides this course until the app is next opened.
    func dismiss() {
        if let id = detection?.course.id { dismissed.insert(id) }
        detection = nil
    }

    func clear() {
        lookup?.cancel()
        lookup = nil
        detection = nil
        lastPoint = nil
    }

    private func show(_ course: Course, distance: Double) {
        guard !dismissed.contains(course.id) else { return }
        if detection?.course.id != course.id {
            detection = Detection(course: course, distance: distance, detectedAt: Date())
        }
    }
}
