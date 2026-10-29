import XCTest
@testable import GolfKit

final class GeoMathTests: XCTestCase {
    func testHaversineDistanceLondonToParis() {
        let london = GeoPoint(latitude: 51.5074, longitude: -0.1278)
        let paris = GeoPoint(latitude: 48.8566, longitude: 2.3522)
        XCTAssertEqual(GeoMath.distance(london, paris) / 1000, 343.5, accuracy: 1.0)
    }

    func testDestinationRoundTripsDistanceAndBearing() {
        let origin = GeoPoint(latitude: -33.8688, longitude: 151.2093)
        let target = GeoMath.destination(from: origin, bearing: 72, distance: 246)
        XCTAssertEqual(GeoMath.distance(origin, target), 246, accuracy: 0.5)
        XCTAssertEqual(GeoMath.bearing(from: origin, to: target), 72, accuracy: 0.2)
    }

    func testBearingCardinalDirections() {
        let a = GeoPoint(latitude: 10, longitude: 10)
        XCTAssertEqual(GeoMath.bearing(from: a, to: GeoPoint(latitude: 11, longitude: 10)), 0, accuracy: 0.01)
        XCTAssertEqual(GeoMath.bearing(from: a, to: GeoPoint(latitude: 10, longitude: 11)), 90, accuracy: 0.2)
        XCTAssertEqual(GeoMath.bearing(from: a, to: GeoPoint(latitude: 9, longitude: 10)), 180, accuracy: 0.01)
    }

    func testPolygonContainsAndCentroid() {
        let square = [
            GeoPoint(latitude: 0, longitude: 0), GeoPoint(latitude: 0, longitude: 1),
            GeoPoint(latitude: 1, longitude: 1), GeoPoint(latitude: 1, longitude: 0),
        ]
        XCTAssertTrue(GeoMath.contains(square, GeoPoint(latitude: 0.5, longitude: 0.5)))
        XCTAssertFalse(GeoMath.contains(square, GeoPoint(latitude: 1.5, longitude: 0.5)))
        let c = GeoMath.centroid(of: square)!
        XCTAssertEqual(c.latitude, 0.5, accuracy: 1e-9)
        XCTAssertEqual(c.longitude, 0.5, accuracy: 1e-9)
    }

    func testDistanceToSegmentAndPointAlongPath() {
        let a = GeoPoint(latitude: 51.5, longitude: -0.1)
        let b = GeoMath.destination(from: a, bearing: 0, distance: 300)
        let side = GeoMath.destination(from: GeoMath.destination(from: a, bearing: 0, distance: 150), bearing: 90, distance: 20)
        XCTAssertEqual(GeoMath.distance(from: side, toSegment: a, b), 20, accuracy: 0.5)
        let mid = GeoMath.point(along: [a, b], distance: 100)!
        XCTAssertEqual(GeoMath.distance(a, mid), 100, accuracy: 0.5)
        XCTAssertEqual(GeoMath.angleDifference(350, 10), 20)
        XCTAssertEqual(GeoMath.angleDifference(10, 350), -20)
    }
}

final class UnitTests: XCTestCase {
    func testMetricIsDefault() {
        XCTAssertEqual(UnitSystem.default, .metric)
        XCTAssertEqual(UnitFormatter().system, .metric)
        XCTAssertEqual(AppSettings().units, .metric)
    }

    func testDistanceFormatting() {
        let metric = UnitFormatter(system: .metric)
        let imperial = UnitFormatter(system: .imperial)
        XCTAssertEqual(metric.distance(152), "152 m")
        XCTAssertEqual(imperial.distance(152), "166 yd")
        XCTAssertEqual(metric.shortDistance(4.24), "4.2 m")
        XCTAssertEqual(imperial.shortDistance(4.24), "14 ft")
        XCTAssertEqual(metric.courseLength(6012), "6,012 m")
        XCTAssertEqual(imperial.courseLength(6012), "6,575 yd")
        XCTAssertEqual(imperial.metres(fromDisplay: 100), 91.44, accuracy: 0.001)
    }

    func testWeatherUnitFormatting() {
        let metric = UnitFormatter(system: .metric)
        let imperial = UnitFormatter(system: .imperial)
        XCTAssertEqual(metric.temperature(18, includeUnit: true), "18°C")
        XCTAssertEqual(imperial.temperature(18, includeUnit: true), "64°F")
        XCTAssertEqual(metric.windSpeed(16), "16 km/h")
        XCTAssertEqual(imperial.windSpeed(16), "10 mph")
        XCTAssertEqual(imperial.precipitation(25.4), "1.00 in")
    }
}

final class JoinCodeTests: XCTestCase {
    func testGeneratedCodesAreValidAndVowelFree() {
        var rng = SplitMix64(seed: 42)
        for _ in 0..<500 {
            let code = JoinCode.generate(using: &rng)
            XCTAssertTrue(JoinCode.isValid(code), code)
            XCTAssertFalse(code.contains { "AEIOU".contains($0) })
        }
    }

    func testNormalizeStripsJunk() {
        XCTAssertEqual(JoinCode.normalize(" k-p l t "), "KPLT")
        XCTAssertEqual(JoinCode.normalize("kpltxz"), "KPLT")
        XCTAssertFalse(JoinCode.isValid("KPL"))
        XCTAssertFalse(JoinCode.isValid("KAPL"))
        XCTAssertEqual(JoinCode.spaced("KPLT"), "K P L T")
    }
}
