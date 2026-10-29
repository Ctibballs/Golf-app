import Foundation

/// Where a course's data came from. Used for attribution and refresh logic.
public enum CourseSource: String, Codable, Sendable {
    /// api.opengolfapi.org (ODbL)
    case openGolfAPI
    /// OpenStreetMap via the Overpass API (ODbL)
    case openStreetMap
    /// Created by the player in the app
    case custom
    /// Bundled demo data
    case demo
}

public struct HoleInfo: Codable, Hashable, Identifiable, Sendable {
    public var number: Int
    public var par: Int
    /// Stroke index (1 = hardest). Used to allocate handicap strokes.
    public var strokeIndex: Int?
    /// Hole length in metres per tee id.
    public var lengths: [String: Double]

    public var id: Int { number }

    public init(number: Int, par: Int, strokeIndex: Int? = nil, lengths: [String: Double] = [:]) {
        self.number = number
        self.par = par
        self.strokeIndex = strokeIndex
        self.lengths = lengths
    }

    public func length(for tee: TeeSet?) -> Double? {
        if let tee, let value = lengths[tee.id] { return value }
        return lengths.values.max()
    }
}

public struct TeeSet: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var name: String
    /// Hex colour such as "#1E6BFF", if known.
    public var colorHex: String?
    public var gender: String?
    public var courseRating: Double?
    public var slopeRating: Int?
    public var totalLength: Double?
    public var par: Int?

    public init(
        id: String,
        name: String,
        colorHex: String? = nil,
        gender: String? = nil,
        courseRating: Double? = nil,
        slopeRating: Int? = nil,
        totalLength: Double? = nil,
        par: Int? = nil
    ) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.gender = gender
        self.courseRating = courseRating
        self.slopeRating = slopeRating
        self.totalLength = totalLength
        self.par = par
    }

    /// True when both rating and slope came from the data source.
    public var hasOfficialRating: Bool { courseRating != nil && slopeRating != nil }
}

public struct Course: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var city: String?
    public var region: String?
    public var country: String?
    public var location: GeoPoint?
    public var gameType: GameType
    public var holes: [HoleInfo]
    public var tees: [TeeSet]
    public var source: CourseSource
    public var accessType: String?
    public var website: String?
    public var phone: String?
    public var architect: String?
    public var yearBuilt: Int?
    public var osmID: Int64?

    public init(
        id: String,
        name: String,
        city: String? = nil,
        region: String? = nil,
        country: String? = nil,
        location: GeoPoint? = nil,
        gameType: GameType = .golf,
        holes: [HoleInfo],
        tees: [TeeSet] = [],
        source: CourseSource,
        accessType: String? = nil,
        website: String? = nil,
        phone: String? = nil,
        architect: String? = nil,
        yearBuilt: Int? = nil,
        osmID: Int64? = nil
    ) {
        self.id = id
        self.name = name
        self.city = city
        self.region = region
        self.country = country
        self.location = location
        self.gameType = gameType
        self.holes = holes.sorted { $0.number < $1.number }
        self.tees = tees
        self.source = source
        self.accessType = accessType
        self.website = website
        self.phone = phone
        self.architect = architect
        self.yearBuilt = yearBuilt
        self.osmID = osmID
    }

    public var par: Int { holes.reduce(0) { $0 + $1.par } }
    public var holeCount: Int { holes.count }

    public var locality: String {
        [city, region, country].compactMap { $0?.isEmpty == false ? $0 : nil }.joined(separator: ", ")
    }

    public func hole(_ number: Int) -> HoleInfo? {
        holes.first { $0.number == number }
    }

    public func par(for holeNumbers: [Int]) -> Int {
        holeNumbers.compactMap { hole($0)?.par }.reduce(0, +)
    }

    /// Total length for a tee, summing hole lengths if no total is recorded.
    public func totalLength(for tee: TeeSet?) -> Double? {
        if let total = tee?.totalLength { return total }
        let lengths = holes.compactMap { $0.length(for: tee) }
        return lengths.count == holes.count && !lengths.isEmpty ? lengths.reduce(0, +) : nil
    }

    /// The tee most players use when none is chosen: the middle-length tee.
    public var defaultTee: TeeSet? {
        let sorted = tees.sorted { ($0.totalLength ?? 0) > ($1.totalLength ?? 0) }
        guard !sorted.isEmpty else { return nil }
        return sorted[sorted.count / 2]
    }

    /// Builds a simple course with uniform pars, for custom courses and mini golf.
    public static func custom(
        name: String,
        gameType: GameType,
        pars: [Int],
        location: GeoPoint? = nil,
        id: String = "custom-\(UUID().uuidString)"
    ) -> Course {
        let holes = pars.enumerated().map { HoleInfo(number: $0.offset + 1, par: $0.element) }
        return Course(id: id, name: name, location: location, gameType: gameType, holes: holes, source: .custom)
    }
}

/// Lightweight search result.
public struct CourseSummary: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var city: String?
    public var region: String?
    public var country: String?
    public var location: GeoPoint?
    public var holeCount: Int?
    public var par: Int?
    public var accessType: String?
    public var source: CourseSource
    /// Distance from the search origin in metres, when searching nearby.
    public var distance: Double?

    public init(
        id: String,
        name: String,
        city: String? = nil,
        region: String? = nil,
        country: String? = nil,
        location: GeoPoint? = nil,
        holeCount: Int? = nil,
        par: Int? = nil,
        accessType: String? = nil,
        source: CourseSource,
        distance: Double? = nil
    ) {
        self.id = id
        self.name = name
        self.city = city
        self.region = region
        self.country = country
        self.location = location
        self.holeCount = holeCount
        self.par = par
        self.accessType = accessType
        self.source = source
        self.distance = distance
    }

    public var locality: String {
        [city, region, country].compactMap { $0?.isEmpty == false ? $0 : nil }.joined(separator: ", ")
    }

    /// A par-3 or pitch & putt course, judging by its data.
    public var looksLikePitchAndPutt: Bool {
        if let type = accessType?.lowercased(), type.contains("par3") || type.contains("par 3") || type.contains("pitch") {
            return true
        }
        if let par, let holeCount, holeCount > 0 { return Double(par) / Double(holeCount) <= 3.05 }
        return false
    }
}

extension Course {
    public var summary: CourseSummary {
        CourseSummary(
            id: id, name: name, city: city, region: region, country: country, location: location,
            holeCount: holeCount, par: par, accessType: accessType, source: source
        )
    }
}
