import XCTest
@testable import GolfKit

final class CourseDetectorTests: XCTestCase {
    private let london = GeoPoint(latitude: 51.5074, longitude: -0.1278)

    private func summary(_ name: String, at point: GeoPoint, type: String? = nil, source: CourseSource = .openStreetMap) -> CourseSummary {
        CourseSummary(id: name, name: name, location: point, accessType: type, source: source)
    }

    func testOnAMappedHoleFindsTheCourse() throws {
        let tee = try XCTUnwrap(DemoData.golfLayout.hole(1)?.teePoint)
        let layouts = [DemoData.golfCourseID: DemoData.golfLayout]
        let found = CourseDetector.course(at: tee, among: DemoData.courses, layouts: layouts)
        XCTAssertEqual(found?.course.id, DemoData.golfCourseID)
        XCTAssertLessThanOrEqual(found?.distance ?? .infinity, CourseDetector.holeMargin)

        XCTAssertNil(CourseDetector.course(at: london, among: DemoData.courses, layouts: layouts), "nowhere near")
    }

    func testUnmappedCoursesUseTheirCentreAndTheirKind() {
        let golf = Course.custom(name: "Heath Golf", gameType: .golf, pars: Array(repeating: 4, count: 18), location: london)
        let mini = Course.custom(name: "Crazy Golf", gameType: .miniGolf, pars: Array(repeating: 2, count: 18), location: london)
        let fiveHundredAway = GeoMath.destination(from: london, bearing: 90, distance: 500)
        let fiftyAway = GeoMath.destination(from: london, bearing: 90, distance: 50)

        XCTAssertEqual(CourseDetector.course(at: fiveHundredAway, among: [golf], layouts: [:])?.course.name, "Heath Golf")
        XCTAssertNil(CourseDetector.course(at: fiveHundredAway, among: [mini], layouts: [:]), "a mini golf is small")
        XCTAssertEqual(CourseDetector.course(at: fiftyAway, among: [mini], layouts: [:])?.course.name, "Crazy Golf")
        // Nearest centre wins between two unmapped courses.
        let miniHere = Course.custom(name: "Putt Shack", gameType: .miniGolf, pars: Array(repeating: 2, count: 9), location: fiftyAway)
        XCTAssertEqual(CourseDetector.course(at: fiftyAway, among: [golf, miniHere], layouts: [:])?.course.name, "Putt Shack")
    }

    func testBeingOnAHoleBeatsBeingNearAnotherCoursesCentre() throws {
        let tee = try XCTUnwrap(DemoData.golfLayout.hole(1)?.teePoint)
        let neighbour = Course.custom(name: "Next Door", gameType: .golf, pars: Array(repeating: 4, count: 18),
                                      location: GeoMath.destination(from: tee, bearing: 0, distance: 100))
        let found = CourseDetector.course(at: tee, among: [neighbour, DemoData.golfCourse], layouts: [DemoData.golfCourseID: DemoData.golfLayout])
        XCTAssertEqual(found?.course.id, DemoData.golfCourseID)
    }

    func testBestMatchPrefersTheGroundsYouAreInAndAScorecard() {
        let golf = summary("Royal Links", at: GeoMath.destination(from: london, bearing: 45, distance: 600))
        let mini = summary("Pirate Mini", at: GeoMath.destination(from: london, bearing: 0, distance: 30), type: "miniature_golf")
        let listed = summary("Royal Links Golf Club", at: GeoMath.destination(from: golf.location!, bearing: 180, distance: 300), source: .openGolfAPI)
        let farListed = summary("Elsewhere GC", at: GeoMath.destination(from: london, bearing: 270, distance: 1_500), source: .openGolfAPI)

        // Inside both a golf course and a mini golf: the mini golf.
        XCTAssertEqual(CourseDetector.bestMatch(at: london, containing: [golf, mini], near: [], listed: [])?.name, "Pirate Mini")
        // Inside the golf course, and the directory has its scorecard.
        XCTAssertEqual(CourseDetector.bestMatch(at: london, containing: [golf], near: [], listed: [listed, farListed])?.name, "Royal Links Golf Club")
        // Just outside the mapped grounds.
        XCTAssertEqual(CourseDetector.bestMatch(at: london, containing: [], near: [golf], listed: [])?.name, "Royal Links")
        // Nothing mapped: a listed course counts only when you're close to it.
        let closeListed = summary("Park GC", at: GeoMath.destination(from: london, bearing: 90, distance: 400), source: .openGolfAPI)
        XCTAssertEqual(CourseDetector.bestMatch(at: london, containing: [], near: [], listed: [farListed, closeListed])?.name, "Park GC")
        XCTAssertNil(CourseDetector.bestMatch(at: london, containing: [], near: [], listed: [farListed]))
    }

    func testContainmentQueryAndSettings() throws {
        let query = OverpassClient.containingQuery(GeoPoint(latitude: 51.5, longitude: -0.1))
        XCTAssertTrue(query.contains("is_in(51.5,-0.1)"))
        XCTAssertTrue(query.contains("pivot.inside"))
        XCTAssertTrue(query.contains("miniature_golf"))

        // Settings saved before detection existed have it switched on.
        let legacy = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"units":"imperial"}"#.utf8))
        XCTAssertTrue(legacy.detectCourse)
        XCTAssertEqual(legacy.units, .imperial)
    }
}

final class HolePlanTests: XCTestCase {
    func testNineOrEighteenFromAnyStartingHole() {
        let eighteen = testCourse(holes: 18)
        XCTAssertEqual(HolePlan().holeNumbers(for: eighteen), Array(1...18))
        XCTAssertEqual(HolePlan(count: 18, startHole: 10).holeNumbers(for: eighteen), Array(10...18) + Array(1...9))
        XCTAssertEqual(HolePlan(count: 9, startHole: 10).holeNumbers(for: eighteen), Array(10...18), "the back nine")
        XCTAssertEqual(HolePlan(count: 9, startHole: 15).holeNumbers(for: eighteen), [15, 16, 17, 18, 1, 2, 3, 4, 5], "wraps round")
        XCTAssertEqual(HolePlan(count: 9, startHole: 99).holeNumbers(for: eighteen), Array(1...9), "unknown hole starts at the 1st")

        let nine = testCourse(holes: 9)
        XCTAssertEqual(HolePlan(count: 18, startHole: 4).holeNumbers(for: nine), [4, 5, 6, 7, 8, 9, 1, 2, 3], "a nine-hole course plays nine")

        XCTAssertEqual(HolePlan.describe(Array(1...18)), "Holes 1–18")
        XCTAssertEqual(HolePlan.describe(Array(10...18) + Array(1...9)), "Holes 10–18, 1–9")
        XCTAssertEqual(HolePlan.describe([7]), "Hole 7")
    }
}
