import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
@testable import GolfKit

final class OpenGolfAPITests: XCTestCase {
    func testSearchParsesBothFieldNamingStyles() async throws {
        let transport = MockTransport { request in
            XCTAssertEqual(request.url?.path, "/v1/courses/search")
            XCTAssertEqual(request.queryValue("q"), "hills")
            return (200, try Fixture.data("opengolfapi-search"))
        }
        let client = OpenGolfAPIClient(transport: transport)
        let results = try await client.searchCourses(query: "hills")
        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(results[0].name, "The Hills Golf Club")
        XCTAssertEqual(results[0].par, 72)
        XCTAssertEqual(results[0].region, "IL")
        XCTAssertEqual(results[1].name, "Short Course Par 3")
        XCTAssertEqual(results[1].location?.latitude, 37.75)
        XCTAssertTrue(results[1].looksLikePitchAndPutt)
        XCTAssertFalse(results[0].looksLikePitchAndPutt)
    }

    func testCourseMergesScorecardTeesAndHoleLengthsAndFillsGaps() async throws {
        let transport = MockTransport { request in
            let path = request.url!.path
            if path.hasSuffix("/tees") { return (200, try Fixture.data("opengolfapi-tees")) }
            if path.hasSuffix("/holes") { return (200, try Fixture.data("opengolfapi-holes")) }
            return (200, try Fixture.data("opengolfapi-course"))
        }
        let client = OpenGolfAPIClient(apiKey: "ogapi_test", transport: transport)
        let course = try await client.course(id: "0e1e596d-8e86-4ff8-90e9-6a439a0ba271")

        XCTAssertEqual(course.name, "Egyptian Country Club")
        XCTAssertEqual(course.gameType, .golf)
        // Scorecard skipped hole 4; the holes endpoint supplies it.
        XCTAssertEqual(course.holeCount, 9)
        XCTAssertEqual(course.hole(4)?.par, 3)
        XCTAssertEqual(course.hole(4)?.strokeIndex, 16)
        XCTAssertEqual(course.par, 35)
        XCTAssertEqual(course.hole(3)?.strokeIndex, 4)

        XCTAssertEqual(course.tees.map(\.name), ["Blue", "Red"])
        XCTAssertEqual(course.tees[0].slopeRating, 121)
        XCTAssertEqual(course.tees[0].courseRating, 35.4)
        XCTAssertEqual(course.tees[0].colorHex, "#1E6BFF")
        XCTAssertEqual(course.tees[0].totalLength!, 3042 * 0.9144, accuracy: 0.1)
        let blueID = course.tees[0].id
        XCTAssertEqual(course.hole(1)?.lengths[blueID] ?? 0, 360 * 0.9144, accuracy: 0.1)

        XCTAssertTrue(transport.recorded.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == "Bearer ogapi_test" })
    }

    func testFallsBackToNewerAPIPathOn404() async throws {
        let transport = MockTransport { request in
            if request.url!.path.hasPrefix("/v1/") { return (404, Data("{}".utf8)) }
            return (200, try Fixture.data("opengolfapi-search"))
        }
        let results = try await OpenGolfAPIClient(transport: transport).searchCourses(query: "x")
        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(transport.recorded.last?.url?.path, "/api/v1/courses/search")
    }

    func testRateLimitMapsToFriendlyError() async {
        let client = OpenGolfAPIClient(transport: MockTransport { _ in (429, Data()) })
        do {
            _ = try await client.searchCourses(query: "x")
            XCTFail("expected rate limit")
        } catch {
            XCTAssertEqual(error as? HTTPError, .rateLimited)
        }
    }

    func testPitchAndPuttDetectionFromPars() {
        let json = try! JSONDecoder().decode(JSONValue.self, from: Data("""
        {"id":"p1","name":"Tiny Links","holes":9,"scorecard":[{"hole":1,"par":3},{"hole":2,"par":3},{"hole":3,"par":3},{"hole":4,"par":3},{"hole":5,"par":3},{"hole":6,"par":3},{"hole":7,"par":3},{"hole":8,"par":3},{"hole":9,"par":3}]}
        """.utf8))
        let course = OpenGolfAPIClient.course(detail: json, tees: nil, holes: nil)
        XCTAssertEqual(course?.gameType, .pitchAndPutt)
        XCTAssertEqual(course?.par, 27)
    }
}

final class WeatherTests: XCTestCase {
    func testParsesOpenMeteoResponse() throws {
        let report = try OpenMeteoClient.parse(try Fixture.data("open-meteo"), location: GeoPoint(latitude: 51.5, longitude: -0.12))
        XCTAssertEqual(report.current.temperature, 14.2)
        XCTAssertEqual(report.current.windDirection, 225)
        XCTAssertEqual(report.current.condition.description, "Partly cloudy")
        XCTAssertEqual(report.hourly.count, 3, "the hour with a null temperature is skipped")
        XCTAssertEqual(report.daily.count, 2)
        XCTAssertEqual(report.daily[0].precipitationProbability, 60)
        XCTAssertEqual(report.timezone, "Europe/London")

        // 09:00 at UTC+1 is 08:00 UTC.
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        XCTAssertEqual(utc.component(.hour, from: report.current.time), 8)

        XCTAssertEqual(report.summary(units: UnitFormatter(system: .metric)), "Partly cloudy, 14°C, wind 18 km/h")
        XCTAssertEqual(report.summary(units: UnitFormatter(system: .imperial)), "Partly cloudy, 58°F, wind 11 mph")
    }

    func testWindEffectRelativeToShot() {
        // Wind from the south (180°) on a shot heading north is a tailwind.
        let tail = WindEffect(windSpeed: 20, windFromDirection: 180, shotBearing: 0)
        XCTAssertEqual(tail.along, 20, accuracy: 0.001)
        XCTAssertEqual(tail.description, "Downwind")
        XCTAssertLessThan(tail.playsLike(distance: 150), 150)

        let head = WindEffect(windSpeed: 20, windFromDirection: 0, shotBearing: 0)
        XCTAssertEqual(head.along, -20, accuracy: 0.001)
        XCTAssertEqual(head.description, "Into the wind")
        XCTAssertEqual(head.playsLike(distance: 150), 180, accuracy: 0.001)

        // Wind from the west on a northward shot blows left to right.
        let cross = WindEffect(windSpeed: 20, windFromDirection: 270, shotBearing: 0)
        XCTAssertEqual(cross.across, 20, accuracy: 0.001)
        XCTAssertEqual(cross.description, "Left to right")
    }

    func testPlayability() {
        func weather(code: Int, wind: Double, temp: Double = 18) -> CurrentWeather {
            CurrentWeather(time: Date(), temperature: temp, apparentTemperature: temp, humidity: 50, precipitation: 0, weatherCode: code, windSpeed: wind, windGusts: nil, windDirection: 0, isDay: true)
        }
        XCTAssertGreaterThanOrEqual(Playability(current: weather(code: 0, wind: 8), nextHours: []).score, 85)
        XCTAssertLessThanOrEqual(Playability(current: weather(code: 95, wind: 10), nextHours: []).score, 10)
        XCTAssertLessThan(Playability(current: weather(code: 2, wind: 45), nextHours: []).score, 70)
    }
}

final class OverpassTests: XCTestCase {
    func testLayoutAssignsFeaturesToHolesAndIgnoresNeighbourCourse() throws {
        let center = GeoPoint(latitude: 51.5017, longitude: -0.0985)
        let layout = try OverpassClient.parseLayout(try Fixture.data("overpass-layout"), center: center)

        XCTAssertEqual(layout.holes.map(\.number), [1, 2])
        let hole1 = layout.hole(1)!
        XCTAssertEqual(hole1.par, 4, "the par-5 hole 1 from the neighbouring course is outside the boundary")
        XCTAssertEqual(hole1.greens.count, 1)
        XCTAssertEqual(hole1.tees.count, 1)
        XCTAssertEqual(hole1.fairways.count, 1)
        XCTAssertEqual(hole1.bunkers.count, 1)
        XCTAssertEqual(hole1.length!, 350, accuracy: 2)
        XCTAssertEqual(hole1.bearing!, 0, accuracy: 0.5)

        let hole2 = layout.hole(2)!
        XCTAssertEqual(hole2.par, 3)
        XCTAssertEqual(hole2.greens.count, 1)
        XCTAssertEqual(hole2.water.count, 1)
        XCTAssertEqual(hole2.bunkers.count, 1, "multipolygon bunker relation is parsed")
        XCTAssertEqual(layout.boundary.count, 1)
    }

    func testGreenDistancesAndLie() throws {
        let layout = try OverpassClient.parseLayout(try Fixture.data("overpass-layout"), center: GeoPoint(latitude: 51.5017, longitude: -0.0985))
        let hole1 = layout.hole(1)!
        let tee = hole1.teePoint!
        let d = hole1.greenDistances(from: tee)!
        // Green is a 24m-deep square centred 350m away.
        XCTAssertEqual(d.center, 350, accuracy: 2)
        XCTAssertEqual(d.front, 338, accuracy: 2)
        XCTAssertEqual(d.back, 362, accuracy: 2)

        XCTAssertEqual(hole1.lie(at: hole1.greenCenter!), .green)
        XCTAssertEqual(hole1.lie(at: GeoPoint(latitude: 51.5018, longitude: -0.1000)), .fairway)
        XCTAssertEqual(hole1.lie(at: GeoPoint(latitude: 51.503148, longitude: -0.10026)), .sand)
        XCTAssertEqual(hole1.lie(at: GeoPoint(latitude: 51.5018, longitude: -0.1010)), .rough)
        // West of a northbound hole is the golfer's left.
        XCTAssertLessThan(hole1.lateralOffset(of: GeoPoint(latitude: 51.5018, longitude: -0.1005))!, 0)
    }

    func testNearbyCoursesIncludeMiniGolfAndPitchAndPutt() throws {
        let origin = GeoPoint(latitude: 51.5, longitude: -0.1)
        let courses = try OverpassClient.parseCourses(try Fixture.data("overpass-courses"), origin: origin)
        XCTAssertEqual(courses.count, 3, "element without tags is skipped")
        XCTAssertEqual(courses.first?.name, "Fixture Golf Club")
        XCTAssertEqual(courses.first { $0.name == "Crazy Golf" }?.accessType, "miniature_golf")
        XCTAssertEqual(courses.first { $0.name.contains("Pitch") }?.accessType, "pitch_and_putt")

        let mini = OverpassClient.course(from: courses.first { $0.name == "Crazy Golf" }!, layout: nil)
        XCTAssertEqual(mini.gameType, .miniGolf)
        XCTAssertEqual(mini.holeCount, 18)
        XCTAssertEqual(mini.par, 36)
    }

    func testCourseFromLayoutEstimatesMissingPars() throws {
        let layout = try OverpassClient.parseLayout(try Fixture.data("overpass-layout"), center: GeoPoint(latitude: 51.5017, longitude: -0.0985))
        let summary = CourseSummary(id: "osm-way-1", name: "Fixture", location: GeoPoint(latitude: 51.5017, longitude: -0.0985), source: .openStreetMap)
        let course = OverpassClient.course(from: summary, layout: layout)
        XCTAssertEqual(course.holeCount, 9)
        XCTAssertEqual(course.hole(1)?.par, 4)
        XCTAssertEqual(course.hole(2)?.par, 3)
        XCTAssertEqual(OverpassClient.estimatedPar(length: 480, gameType: .golf), 5)
    }
}
