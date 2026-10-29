import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Reads golf course geometry from OpenStreetMap through the free Overpass API.
///
/// OSM mappers tag holes (`golf=hole` with `ref` and `par`), greens, tees, fairways,
/// bunkers and water. That's enough to draw every hole and measure distances to the green.
public struct OverpassClient: Sendable {
    public static let attribution = "Map data © OpenStreetMap contributors (ODbL 1.0)"
    public static let defaultEndpoint = URL(string: "https://overpass-api.de/api/interpreter")!

    let endpoint: URL
    let transport: HTTPTransport

    public init(endpoint: URL = OverpassClient.defaultEndpoint, transport: HTTPTransport = URLSessionTransport()) {
        self.endpoint = endpoint
        self.transport = transport
    }

    /// Hole-by-hole layout of the course at `center`.
    public func courseLayout(near center: GeoPoint, radius: Double = 1600) async throws -> CourseLayout {
        let around = "around:\(Int(radius)),\(center.latitude),\(center.longitude)"
        let query = """
        [out:json][timeout:30];
        (
          way["golf"](\(around));
          relation["golf"](\(around));
          way["natural"="water"](\(around));
          way["leisure"="golf_course"](\(around));
          relation["leisure"="golf_course"](\(around));
        );
        out geom;
        """
        let data = try await run(query)
        return try Self.parseLayout(data, center: center)
    }

    /// Golf courses, pitch & putts and mini golf near a point, anywhere in the world.
    public func courses(near center: GeoPoint, radius: Double = 25_000) async throws -> [CourseSummary] {
        let around = "around:\(Int(radius)),\(center.latitude),\(center.longitude)"
        let query = """
        [out:json][timeout:25];
        (
          nwr["leisure"="golf_course"](\(around));
          nwr["leisure"="miniature_golf"](\(around));
        );
        out center tags;
        """
        let data = try await run(query)
        return try Self.parseCourses(data, origin: center)
    }

    /// Builds a playable course from OSM hole data (pars from `golf=hole` ways).
    public func course(for summary: CourseSummary) async throws -> (Course, CourseLayout?) {
        guard let location = summary.location else { throw HTTPError.decoding("Course has no location.") }
        var layout: CourseLayout?
        if summary.accessType != "miniature_golf" {
            layout = try? await courseLayout(near: location)
        }
        return (Self.course(from: summary, layout: layout), layout)
    }

    func run(_ query: String) async throws -> Data {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("Fairway-Golf-iOS/1.0", forHTTPHeaderField: "User-Agent")
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        let body = "data=" + (query.addingPercentEncoding(withAllowedCharacters: allowed) ?? query)
        request.httpBody = Data(body.utf8)
        request.timeoutInterval = 40
        return try await transport.data(for: request)
    }

    // MARK: - Parsing

    struct Response: Decodable {
        var elements: [Element]
    }

    struct Element: Decodable {
        var type: String
        var id: Int64
        var lat: Double?
        var lon: Double?
        var center: LatLon?
        var tags: [String: String]?
        var geometry: [LatLon?]?
        var members: [Member]?

        struct LatLon: Decodable {
            var lat: Double
            var lon: Double
            var point: GeoPoint { GeoPoint(latitude: lat, longitude: lon) }
        }

        struct Member: Decodable {
            var type: String
            var role: String?
            var geometry: [LatLon?]?
        }

        /// Polygons for a closed way, or the outer rings of a multipolygon relation.
        var polygons: [[GeoPoint]] {
            if let geometry {
                let ring = geometry.compactMap { $0?.point }
                return ring.count >= 3 ? [ring] : []
            }
            return (members ?? [])
                .filter { $0.type == "way" && ($0.role ?? "outer") != "inner" }
                .compactMap { member -> [GeoPoint]? in
                    let ring = (member.geometry ?? []).compactMap { $0?.point }
                    return ring.count >= 3 ? ring : nil
                }
        }

        var line: [GeoPoint] {
            (geometry ?? []).compactMap { $0?.point }
        }

        var position: GeoPoint? {
            if let lat, let lon { return GeoPoint(latitude: lat, longitude: lon) }
            return center?.point
        }
    }

    static func decode(_ data: Data) throws -> [Element] {
        do {
            return try JSONDecoder().decode(Response.self, from: data).elements
        } catch {
            throw HTTPError.decoding(String(describing: error))
        }
    }

    static func parseCourses(_ data: Data, origin: GeoPoint) throws -> [CourseSummary] {
        try decode(data).compactMap { element -> CourseSummary? in
            guard let tags = element.tags, let position = element.position else { return nil }
            let isMini = tags["leisure"] == "miniature_golf"
            let name = tags["name"] ?? (isMini ? "Mini golf" : "Golf course")
            let lowerName = name.lowercased()
            let pitch = lowerName.contains("pitch") || lowerName.contains("par 3") || lowerName.contains("par-3")
                || (tags["golf:course"] ?? "").contains("pitch") || tags["golf:course"] == "par3"
            return CourseSummary(
                id: "osm-\(element.type)-\(element.id)",
                name: name,
                city: tags["addr:city"],
                region: tags["addr:state"] ?? tags["addr:county"],
                country: tags["addr:country"],
                location: position,
                holeCount: tags["golf:holes"].flatMap(Int.init) ?? tags["holes"].flatMap(Int.init),
                par: tags["golf:par"].flatMap(Int.init) ?? tags["par"].flatMap(Int.init),
                accessType: isMini ? "miniature_golf" : (pitch ? "pitch_and_putt" : tags["access"]),
                source: .openStreetMap,
                distance: GeoMath.distance(origin, position)
            )
        }
        .sorted { ($0.distance ?? 0) < ($1.distance ?? 0) }
    }

    static func parseLayout(_ data: Data, center: GeoPoint) throws -> CourseLayout {
        let elements = try decode(data)

        // Restrict to the course boundary containing (or nearest to) the requested point,
        // so neighbouring courses don't bleed in.
        let boundaries = elements.filter { $0.tags?["leisure"] == "golf_course" }.flatMap(\.polygons)
        let boundary = boundaries.first { GeoMath.contains($0, center) }
            ?? boundaries.min { a, b in
                GeoMath.distance(GeoMath.centroid(of: a) ?? center, center) < GeoMath.distance(GeoMath.centroid(of: b) ?? center, center)
            }
        func inCourse(_ point: GeoPoint?) -> Bool {
            guard let boundary, let point else { return true }
            return GeoMath.contains(boundary, point) || GeoMath.distance(from: point, toPath: boundary) < 40
        }

        var holeWays: [Int: HoleLayout] = [:]
        var greens: [[GeoPoint]] = [], tees: [[GeoPoint]] = [], fairways: [[GeoPoint]] = []
        var bunkers: [[GeoPoint]] = [], water: [[GeoPoint]] = []

        for element in elements {
            guard let tags = element.tags else { continue }
            switch tags["golf"] {
            case "hole":
                let path = element.line
                guard path.count >= 2, let ref = tags["ref"].flatMap({ Int($0.trimmingCharacters(in: .whitespaces)) }),
                      inCourse(path.first) || inCourse(path.last) else { continue }
                let candidate = HoleLayout(number: ref, par: tags["par"].flatMap(Int.init), path: path)
                if let existing = holeWays[ref] {
                    // Duplicate hole numbers (e.g. a second course): keep the one nearer the centre.
                    let d1 = GeoMath.distance(from: center, toPath: existing.path)
                    let d2 = GeoMath.distance(from: center, toPath: path)
                    if d2 < d1 { holeWays[ref] = candidate }
                } else {
                    holeWays[ref] = candidate
                }
            case "green": greens += element.polygons.filter { inCourse(GeoMath.centroid(of: $0)) }
            case "tee": tees += element.polygons.filter { inCourse(GeoMath.centroid(of: $0)) }
            case "fairway": fairways += element.polygons.filter { inCourse(GeoMath.centroid(of: $0)) }
            case "bunker": bunkers += element.polygons.filter { inCourse(GeoMath.centroid(of: $0)) }
            case "water_hazard", "lateral_water_hazard": water += element.polygons.filter { inCourse(GeoMath.centroid(of: $0)) }
            default:
                if tags["natural"] == "water" { water += element.polygons.filter { inCourse(GeoMath.centroid(of: $0)) } }
            }
        }

        var holes = holeWays
        var looseBunkers: [[GeoPoint]] = []

        func nearestHole(to point: GeoPoint, using metric: (HoleLayout) -> Double, within limit: Double) -> Int? {
            let best = holes.values.map { ($0.number, metric($0)) }.min { $0.1 < $1.1 }
            guard let best, best.1 <= limit else { return nil }
            return best.0
        }

        for polygon in greens {
            guard let c = GeoMath.centroid(of: polygon),
                  let n = nearestHole(to: c, using: { GeoMath.distance($0.path.last!, c) }, within: 80) else { continue }
            holes[n]?.greens.append(polygon)
        }
        for polygon in tees {
            guard let c = GeoMath.centroid(of: polygon),
                  let n = nearestHole(to: c, using: { GeoMath.distance($0.path.first!, c) }, within: 80) else { continue }
            holes[n]?.tees.append(polygon)
        }
        for polygon in fairways {
            guard let c = GeoMath.centroid(of: polygon),
                  let n = nearestHole(to: c, using: { GeoMath.distance(from: c, toPath: $0.path) }, within: 70) else { continue }
            holes[n]?.fairways.append(polygon)
        }
        for polygon in bunkers {
            if let c = GeoMath.centroid(of: polygon),
               let n = nearestHole(to: c, using: { GeoMath.distance(from: c, toPath: $0.path) }, within: 45) {
                holes[n]?.bunkers.append(polygon)
            } else {
                looseBunkers.append(polygon)
            }
        }
        for polygon in water {
            guard let c = GeoMath.centroid(of: polygon) else { continue }
            for (number, hole) in holes where GeoMath.distance(from: c, toPath: hole.path) < 60 {
                holes[number]?.water.append(polygon)
            }
        }

        return CourseLayout(
            holes: Array(holes.values),
            water: water,
            bunkers: looseBunkers,
            boundary: boundary.map { [$0] } ?? []
        )
    }

    /// A course built from OSM data, falling back to sensible defaults when holes aren't mapped.
    public static func course(from summary: CourseSummary, layout: CourseLayout?) -> Course {
        let gameType: GameType
        switch summary.accessType {
        case "miniature_golf": gameType = .miniGolf
        case "pitch_and_putt": gameType = .pitchAndPutt
        default: gameType = .golf
        }

        var holes: [HoleInfo]
        if let layout, !layout.holes.isEmpty {
            let maxHole = layout.holes.map(\.number).max() ?? 0
            let count = maxHole <= 9 ? 9 : (maxHole <= 18 ? 18 : maxHole)
            holes = (1...count).map { n in
                let mapped = layout.hole(n)
                let length = mapped?.length
                return HoleInfo(
                    number: n,
                    par: mapped?.par ?? estimatedPar(length: length, gameType: gameType),
                    lengths: length.map { ["osm": $0] } ?? [:]
                )
            }
        } else {
            let count = summary.holeCount.flatMap { [9, 18, 12, 27, 36].contains($0) ? $0 : nil } ?? gameType.defaultHoleCount
            holes = (1...count).map { HoleInfo(number: $0, par: gameType.defaultPar) }
        }

        return Course(
            id: summary.id,
            name: summary.name,
            city: summary.city,
            region: summary.region,
            country: summary.country,
            location: summary.location,
            gameType: gameType,
            holes: holes,
            tees: [],
            source: .openStreetMap
        )
    }

    /// Par from length using common guidelines (men's yardage converted to metres).
    static func estimatedPar(length: Double?, gameType: GameType) -> Int {
        guard let length else { return gameType.defaultPar }
        if gameType == .pitchAndPutt { return 3 }
        switch length {
        case ..<230: return 3
        case ..<430: return 4
        default: return 5
        }
    }
}
