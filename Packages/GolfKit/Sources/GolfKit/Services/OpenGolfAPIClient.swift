import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Client for OpenGolfAPI (https://opengolfapi.org): free, open (ODbL) golf course data.
/// Anonymous use allows 1,000 requests a day; a free key raises that.
///
/// Field names have shifted between API versions, so responses are read through `JSONValue`
/// with several fallback keys rather than strict `Codable` models.
public struct OpenGolfAPIClient: Sendable {
    public static let defaultBaseURL = URL(string: "https://api.opengolfapi.org")!
    public static let attribution = "Course data © OpenStreetMap contributors (ODbL 1.0) via OpenGolfAPI"

    public var baseURL: URL
    public var apiKey: String?
    let transport: HTTPTransport

    public init(baseURL: URL = OpenGolfAPIClient.defaultBaseURL, apiKey: String? = nil, transport: HTTPTransport = URLSessionTransport()) {
        self.baseURL = baseURL
        self.apiKey = apiKey?.isEmpty == true ? nil : apiKey
        self.transport = transport
    }

    // MARK: - Endpoints

    public func searchCourses(query: String, region: String? = nil, limit: Int = 25) async throws -> [CourseSummary] {
        var items = [URLQueryItem(name: "q", value: query), URLQueryItem(name: "limit", value: String(limit))]
        if let region, !region.isEmpty { items.append(URLQueryItem(name: "state", value: region)) }
        let json = try await get(["/v1/courses/search", "/api/v1/courses/search"], query: items)
        return Self.courseList(from: json).compactMap { Self.summary(from: $0, origin: nil) }
    }

    public func searchCourses(near point: GeoPoint, radiusKilometres: Double = 25, limit: Int = 25) async throws -> [CourseSummary] {
        let items = [
            URLQueryItem(name: "lat", value: String(point.latitude)),
            URLQueryItem(name: "lng", value: String(point.longitude)),
            URLQueryItem(name: "radius_mi", value: String(Int((radiusKilometres / UnitConversion.kilometresPerMile).rounded(.up)))),
            URLQueryItem(name: "limit", value: String(limit)),
        ]
        let json = try await get(["/api/v1/courses/search", "/v1/courses/search"], query: items)
        return Self.courseList(from: json)
            .compactMap { Self.summary(from: $0, origin: point) }
            .filter { ($0.distance ?? 0) <= radiusKilometres * 1000 * 1.5 }
            .sorted { ($0.distance ?? .infinity) < ($1.distance ?? .infinity) }
    }

    /// Full course: scorecard, tees and per-hole lengths, merged from three endpoints.
    public func course(id: String) async throws -> Course {
        let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        let detail = try await get(["/v1/courses/\(encoded)", "/api/v1/courses/\(encoded)"], query: [])
        // Tees and hole lengths are optional extras; a failure shouldn't hide the scorecard.
        async let teesJSON = try? get(["/v1/courses/\(encoded)/tees", "/api/v1/courses/\(encoded)/tees"], query: [])
        async let holesJSON = try? get(["/v1/courses/\(encoded)/holes", "/api/v1/courses/\(encoded)/holes"], query: [])
        let (tees, holes) = await (teesJSON, holesJSON)
        guard let course = Self.course(detail: detail, tees: tees, holes: holes) else {
            throw HTTPError.decoding("Course \(id) has no name.")
        }
        return course
    }

    // MARK: - Networking

    func get(_ paths: [String], query: [URLQueryItem]) async throws -> JSONValue {
        var lastError: Error = HTTPError.invalidResponse
        for path in paths {
            var request = URLRequest(url: baseURL.appendingPathComponent(path).appendingQuery(query))
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            if let apiKey { request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization") }
            request.timeoutInterval = 20
            do {
                let data = try await transport.data(for: request)
                return try JSONDecoder().decode(JSONValue.self, from: data)
            } catch HTTPError.status(let code, let body) where code == 404 || code == 405 {
                // Try the next API version's path.
                lastError = HTTPError.status(code, body)
                continue
            }
        }
        throw lastError
    }

    // MARK: - Parsing

    static func courseList(from json: JSONValue) -> [JSONValue] {
        if let array = json.array { return array }
        for key in ["courses", "results", "data", "items"] {
            if let array = json[key]?.array { return array }
        }
        return []
    }

    static func location(of json: JSONValue) -> GeoPoint? {
        if let lat = json.first("latitude", "lat")?.double, let lon = json.first("longitude", "lng", "lon")?.double {
            return GeoPoint(latitude: lat, longitude: lon)
        }
        if let loc = json["location"], let lat = loc.first("latitude", "lat")?.double, let lon = loc.first("longitude", "lng", "lon")?.double {
            return GeoPoint(latitude: lat, longitude: lon)
        }
        if let coords = json["geometry"]?["coordinates"]?.array, coords.count >= 2,
           let lon = coords[0].double, let lat = coords[1].double {
            return GeoPoint(latitude: lat, longitude: lon)
        }
        return nil
    }

    static func summary(from raw: JSONValue, origin: GeoPoint?) -> CourseSummary? {
        let json = raw["properties"] ?? raw
        guard let id = (json["id"] ?? raw["id"])?.string,
              let name = json.first("course_name", "name", "club_name")?.string else { return nil }
        let location = location(of: json) ?? location(of: raw)
        let scorecardPar = json.first("scorecard")?.array?.compactMap { $0["par"]?.int }.reduce(0, +)
        var distance: Double?
        if let origin, let location {
            distance = GeoMath.distance(origin, location)
        } else if let metres = json.first("distance_m")?.double {
            distance = metres
        } else if let km = json.first("distance_km")?.double {
            distance = km * 1000
        } else if let miles = json.first("distance_mi", "distance_miles", "distance")?.double {
            distance = miles * UnitConversion.kilometresPerMile * 1000
        }
        return CourseSummary(
            id: id,
            name: name,
            city: json.first("city", "town")?.string,
            region: json.first("state", "region", "state_code", "province")?.string,
            country: json.first("country", "country_code")?.string,
            location: location,
            holeCount: json.first("holes", "hole_count", "number_of_holes")?.int,
            par: json.first("par_total", "par", "total_par")?.int ?? (scorecardPar == 0 ? nil : scorecardPar),
            accessType: json.first("course_type", "type")?.string,
            source: .openGolfAPI,
            distance: distance
        )
    }

    static func course(detail raw: JSONValue, tees teesJSON: JSONValue?, holes holesJSON: JSONValue?) -> Course? {
        let json = raw["course"] ?? raw
        guard let summary = summary(from: json, origin: nil) else { return nil }

        let tees = parseTees(teesJSON.map { $0["tees"] ?? $0 }?.array ?? json["tees"]?.array ?? [])
        let holeRows = (holesJSON.map { $0["holes"] ?? $0 }?.array ?? [])
        let scorecardRows = json.first("scorecard", "holes_data")?.array ?? []

        var pars: [Int: Int] = [:]
        var strokeIndexes: [Int: Int] = [:]
        var lengths: [Int: [String: Double]] = [:]
        for row in scorecardRows + holeRows {
            guard let number = row.first("hole_number", "hole", "number")?.int, number > 0 else { continue }
            if let par = row["par"]?.int, par > 0 { pars[number] = par }
            if let si = row.first("handicap_index", "stroke_index", "handicap", "hcp")?.int, si > 0 { strokeIndexes[number] = si }
            let holeLengths = parseHoleLengths(row, tees: tees)
            if !holeLengths.isEmpty { lengths[number, default: [:]].merge(holeLengths) { $1 } }
        }

        let declaredHoles = summary.holeCount ?? 0
        let maxNumber = max(pars.keys.max() ?? 0, lengths.keys.max() ?? 0)
        let expected: Int
        switch max(maxNumber, [9, 18, 27, 36].contains(declaredHoles) ? declaredHoles : 0) {
        case 0: expected = 18
        case 1...9: expected = 9
        case 10...18: expected = 18
        case let n: expected = n
        }

        // Spread any unaccounted par across holes missing from the scorecard.
        let knownPar = pars.values.reduce(0, +)
        let missing = (1...expected).filter { pars[$0] == nil }
        var fill: [Int: Int] = [:]
        if !missing.isEmpty {
            if let total = summary.par, total > knownPar {
                let remaining = total - knownPar
                let base = max(3, min(5, remaining / missing.count))
                var leftover = remaining - base * missing.count
                for hole in missing {
                    var value = base
                    if leftover > 0, value < 5 { value += 1; leftover -= 1 }
                    if leftover < 0, value > 3 { value -= 1; leftover += 1 }
                    fill[hole] = value
                }
            } else {
                let average = pars.isEmpty ? 4 : Int((Double(knownPar) / Double(pars.count)).rounded())
                for hole in missing { fill[hole] = average }
            }
        }

        let holes = (1...expected).map { n in
            HoleInfo(number: n, par: pars[n] ?? fill[n] ?? 4, strokeIndex: strokeIndexes[n], lengths: lengths[n] ?? [:])
        }

        var allTees = tees
        if allTees.isEmpty, let yards = json.first("total_yardage", "yardage")?.double, yards > 0 {
            allTees = [TeeSet(id: "default", name: "Default", totalLength: UnitConversion.metres(fromYards: yards))]
        }

        let averagePar = Double(holes.reduce(0) { $0 + $1.par }) / Double(max(1, holes.count))
        let looksPitchAndPutt = summary.looksLikePitchAndPutt || averagePar <= 3.05

        return Course(
            id: summary.id,
            name: summary.name,
            city: summary.city,
            region: summary.region,
            country: summary.country,
            location: summary.location,
            gameType: looksPitchAndPutt ? .pitchAndPutt : .golf,
            holes: holes,
            tees: allTees,
            source: .openGolfAPI,
            accessType: summary.accessType,
            website: json.first("website", "url")?.string,
            phone: json["phone"]?.string,
            architect: json["architect"]?.string,
            yearBuilt: json.first("year_built", "opened")?.int,
            osmID: json["osm_id"]?.double.map { Int64($0) }
        )
    }

    static func parseTees(_ rows: [JSONValue]) -> [TeeSet] {
        rows.enumerated().compactMap { index, row in
            let name = row.first("tee_name", "name", "tee", "tee_color", "color")?.string ?? "Tee \(index + 1)"
            let id = row.first("id", "tee_id")?.string ?? name.lowercased()
            let metres = row.first("total_meters", "meters", "total_metres", "metres")?.double
            let yards = row.first("total_yardage", "yardage", "yards", "total_yards")?.double
            let gender = row.first("gender", "sex")?.string
            var rating = row.first("course_rating", "rating")?.double
            var slope = row.first("slope_rating", "slope")?.int
            // Some sources nest ratings per gender: {"ratings": {"male": {"rating":..,"slope":..}}}
            if rating == nil, let ratings = row.first("ratings")?.object?.values.first {
                rating = ratings.first("course_rating", "rating")?.double
                slope = slope ?? ratings.first("slope_rating", "slope")?.int
            }
            return TeeSet(
                id: id,
                name: name.capitalized,
                colorHex: row.first("color_hex", "hex")?.string ?? TeeSet.hex(forColorName: row.first("tee_color", "color", "tee_name", "name")?.string),
                gender: gender,
                courseRating: rating.flatMap { $0 > 0 ? $0 : nil },
                slopeRating: slope.flatMap { (55...155).contains($0) ? $0 : nil },
                totalLength: metres ?? yards.map(UnitConversion.metres(fromYards:)),
                par: row.first("par", "par_total")?.int
            )
        }
    }

    static func parseHoleLengths(_ row: JSONValue, tees: [TeeSet]) -> [String: Double] {
        var result: [String: Double] = [:]
        func teeID(for key: String) -> String {
            tees.first { $0.id.lowercased() == key.lowercased() || $0.name.lowercased() == key.lowercased() }?.id ?? key.lowercased()
        }
        func read(_ value: JSONValue?, toMetres: (Double) -> Double) {
            guard let value else { return }
            if let n = value.double, n > 0 {
                result[tees.first?.id ?? "default"] = toMetres(n)
            } else if let object = value.object {
                for (key, v) in object { if let n = v.double, n > 0 { result[teeID(for: key)] = toMetres(n) } }
            } else if let array = value.array {
                for (i, v) in array.enumerated() {
                    if let n = v.double, n > 0 {
                        result[i < tees.count ? tees[i].id : "tee\(i + 1)"] = toMetres(n)
                    } else if let name = v.first("tee", "tee_name", "name")?.string, let n = v.first("yards", "yardage", "length")?.double {
                        result[teeID(for: name)] = toMetres(n)
                    }
                }
            }
        }
        read(row.first("yardages", "yards", "yardage"), toMetres: UnitConversion.metres(fromYards:))
        // Metre values win when both exist.
        read(row.first("meters", "metres"), toMetres: { $0 })
        return result
    }
}

extension TeeSet {
    /// Best-guess colour for common tee names.
    public static func hex(forColorName name: String?) -> String? {
        guard let name = name?.lowercased() else { return nil }
        let table: [(String, String)] = [
            ("black", "#1C1C1E"), ("blue", "#1E6BFF"), ("white", "#F2F2F7"), ("yellow", "#FFD60A"),
            ("red", "#FF3B30"), ("gold", "#D4A017"), ("green", "#34C759"), ("silver", "#C7C7CC"),
            ("orange", "#FF9500"), ("purple", "#AF52DE"), ("championship", "#1C1C1E"),
        ]
        return table.first { name.contains($0.0) }?.1
    }
}
