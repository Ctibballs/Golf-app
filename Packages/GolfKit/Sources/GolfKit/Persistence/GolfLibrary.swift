import Foundation

public struct OnlineSettings: Codable, Hashable, Sendable {
    /// Supabase project ref or URL. Empty = offline demo mode.
    public var supabaseProject: String
    public var supabaseAnonKey: String
    /// Optional OpenGolfAPI key for higher rate limits.
    public var openGolfAPIKey: String
    /// Share your position with your group while a match is live.
    public var shareLiveLocation: Bool

    public init(supabaseProject: String = "", supabaseAnonKey: String = "", openGolfAPIKey: String = "", shareLiveLocation: Bool = true) {
        self.supabaseProject = supabaseProject
        self.supabaseAnonKey = supabaseAnonKey
        self.openGolfAPIKey = openGolfAPIKey
        self.shareLiveLocation = shareLiveLocation
    }

    public var supabaseConfig: SupabaseConfig? {
        SupabaseConfig(project: supabaseProject, anonKey: supabaseAnonKey)
    }
}

public struct AppSettings: Codable, Hashable, Sendable {
    public var units: UnitSystem
    public var haptics: Bool
    /// Detect the lie (green, bunker, fairway) from the course map when marking shots.
    public var autoDetectLie: Bool
    public var keepScreenAwake: Bool
    public var online: OnlineSettings

    public init(units: UnitSystem = .default, haptics: Bool = true, autoDetectLie: Bool = true, keepScreenAwake: Bool = true, online: OnlineSettings = OnlineSettings()) {
        self.units = units
        self.haptics = haptics
        self.autoDetectLie = autoDetectLie
        self.keepScreenAwake = keepScreenAwake
        self.online = online
    }

    public init(from decoder: Decoder) throws {
        // Tolerate settings saved by older versions that lack newer keys.
        let c = try decoder.container(keyedBy: CodingKeys.self)
        units = try c.decodeIfPresent(UnitSystem.self, forKey: .units) ?? .default
        haptics = try c.decodeIfPresent(Bool.self, forKey: .haptics) ?? true
        autoDetectLie = try c.decodeIfPresent(Bool.self, forKey: .autoDetectLie) ?? true
        keepScreenAwake = try c.decodeIfPresent(Bool.self, forKey: .keepScreenAwake) ?? true
        online = try c.decodeIfPresent(OnlineSettings.self, forKey: .online) ?? OnlineSettings()
    }
}

/// Reference to a live match or tournament this device is part of.
public struct ActiveGame: Codable, Hashable, Identifiable, Sendable {
    public enum Kind: String, Codable, Sendable { case match, tournament }
    public var kind: Kind
    public var id: UUID
    public var code: String
    public var name: String
    public var joinedAt: Date

    public init(kind: Kind, id: UUID, code: String, name: String, joinedAt: Date = Date()) {
        self.kind = kind
        self.id = id
        self.code = code
        self.name = name
        self.joinedAt = joinedAt
    }
}

/// Everything the app persists, in one Codable value.
public struct GolfLibrary: Codable, Hashable, Sendable {
    public static let currentVersion = 1

    public var version: Int
    public var profile: PlayerProfile?
    public var settings: AppSettings
    public var rounds: [Round]
    public var matchHistory: [MatchRecord]
    public var tournaments: [TournamentSnapshot]
    public var customCourses: [Course]
    public var savedCourses: [Course]
    public var favoriteCourseIDs: [String]
    public var activeGames: [ActiveGame]
    /// The round currently being played on this device.
    public var inProgressRoundID: UUID?
    public var supabaseSession: SupabaseSession?
    public var hasSampleData: Bool

    public init(
        profile: PlayerProfile? = nil,
        settings: AppSettings = AppSettings(),
        rounds: [Round] = [],
        matchHistory: [MatchRecord] = [],
        tournaments: [TournamentSnapshot] = [],
        customCourses: [Course] = [],
        savedCourses: [Course] = [],
        favoriteCourseIDs: [String] = [],
        activeGames: [ActiveGame] = [],
        inProgressRoundID: UUID? = nil,
        supabaseSession: SupabaseSession? = nil,
        hasSampleData: Bool = false
    ) {
        self.version = Self.currentVersion
        self.profile = profile
        self.settings = settings
        self.rounds = rounds
        self.matchHistory = matchHistory
        self.tournaments = tournaments
        self.customCourses = customCourses
        self.savedCourses = savedCourses
        self.favoriteCourseIDs = favoriteCourseIDs
        self.activeGames = activeGames
        self.inProgressRoundID = inProgressRoundID
        self.supabaseSession = supabaseSession
        self.hasSampleData = hasSampleData
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? Self.currentVersion
        profile = try c.decodeIfPresent(PlayerProfile.self, forKey: .profile)
        settings = try c.decodeIfPresent(AppSettings.self, forKey: .settings) ?? AppSettings()
        rounds = try c.decodeIfPresent([Round].self, forKey: .rounds) ?? []
        matchHistory = try c.decodeIfPresent([MatchRecord].self, forKey: .matchHistory) ?? []
        tournaments = try c.decodeIfPresent([TournamentSnapshot].self, forKey: .tournaments) ?? []
        customCourses = try c.decodeIfPresent([Course].self, forKey: .customCourses) ?? []
        savedCourses = try c.decodeIfPresent([Course].self, forKey: .savedCourses) ?? []
        favoriteCourseIDs = try c.decodeIfPresent([String].self, forKey: .favoriteCourseIDs) ?? []
        activeGames = try c.decodeIfPresent([ActiveGame].self, forKey: .activeGames) ?? []
        inProgressRoundID = try c.decodeIfPresent(UUID.self, forKey: .inProgressRoundID)
        supabaseSession = try c.decodeIfPresent(SupabaseSession.self, forKey: .supabaseSession)
        hasSampleData = try c.decodeIfPresent(Bool.self, forKey: .hasSampleData) ?? false
    }

    // MARK: - Queries

    public var completedRounds: [Round] {
        rounds.filter(\.isComplete).sorted { $0.date > $1.date }
    }

    public var inProgressRound: Round? {
        inProgressRoundID.flatMap { id in rounds.first { $0.id == id } }
    }

    /// Courses the player has played, saved or created, most recent first, without duplicates.
    public var knownCourses: [Course] {
        var seen = Set<String>()
        let played = rounds.sorted { $0.date > $1.date }.map(\.course)
        return (customCourses + savedCourses + played).filter { seen.insert($0.id).inserted }
    }

    public func course(id: String) -> Course? {
        knownCourses.first { $0.id == id } ?? DemoData.courses.first { $0.id == id }
    }

    public func handicap(for gameType: GameType) -> HandicapResult {
        let settings = profile?.handicapSettings(for: gameType) ?? HandicapSettings()
        if gameType.usesWorldHandicapSystem {
            return HandicapCalculator.evaluate(rounds: rounds, settings: settings)
        }
        return CasualHandicapCalculator.evaluate(rounds: rounds, gameType: gameType, settings: settings)
    }

    // MARK: - Mutations

    public mutating func upsert(_ round: Round) {
        if let index = rounds.firstIndex(where: { $0.id == round.id }) {
            rounds[index] = round
        } else {
            rounds.append(round)
        }
    }

    public mutating func upsert(_ record: MatchRecord) {
        if let index = matchHistory.firstIndex(where: { $0.id == record.id }) {
            matchHistory[index] = record
        } else {
            matchHistory.append(record)
        }
    }

    public mutating func upsert(_ tournament: TournamentSnapshot) {
        if let index = tournaments.firstIndex(where: { $0.tournament.id == tournament.tournament.id }) {
            tournaments[index] = tournament
        } else {
            tournaments.append(tournament)
        }
    }

    public mutating func remember(_ course: Course) {
        if course.source == .custom {
            if let index = customCourses.firstIndex(where: { $0.id == course.id }) { customCourses[index] = course } else { customCourses.append(course) }
        } else if course.source != .demo {
            if let index = savedCourses.firstIndex(where: { $0.id == course.id }) { savedCourses[index] = course } else { savedCourses.append(course) }
        }
    }

    public mutating func toggleFavorite(_ courseID: String) {
        if let index = favoriteCourseIDs.firstIndex(of: courseID) {
            favoriteCourseIDs.remove(at: index)
        } else {
            favoriteCourseIDs.append(courseID)
        }
    }

    public mutating func removeSampleData() {
        rounds.removeAll { $0.notes == DemoData.sampleMarker && $0.id != inProgressRoundID }
        matchHistory.removeAll { $0.snapshot.match.code == "DEMO" }
        hasSampleData = false
    }
}

/// Saves the library as JSON in Application Support, writing atomically.
public actor LibraryStore {
    public let fileURL: URL

    public init(directory: URL, fileName: String = "library.json") {
        self.fileURL = directory.appendingPathComponent(fileName)
    }

    public static func defaultDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("Fairway", isDirectory: true)
    }

    // The default date strategy stores Date's own Double, so dates round-trip exactly
    // (ISO 8601 drops sub-seconds; seconds-since-1970 picks up rounding error).
    static let encoder = JSONEncoder()
    static let decoder = JSONDecoder()

    /// Synchronous so the app can restore state before its first frame; only reads `fileURL`.
    public nonisolated func load() -> GolfLibrary {
        guard let data = try? Data(contentsOf: fileURL) else { return GolfLibrary() }
        do {
            return try Self.decoder.decode(GolfLibrary.self, from: data)
        } catch {
            // Keep the unreadable file for recovery rather than overwriting it.
            let backup = fileURL.deletingPathExtension().appendingPathExtension("corrupt-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.copyItem(at: fileURL, to: backup)
            return GolfLibrary()
        }
    }

    public func save(_ library: GolfLibrary) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try Self.encoder.encode(library)
        try data.write(to: fileURL, options: .atomic)
    }
}

/// Caches course layouts (they rarely change and Overpass is a shared free service).
public actor LayoutCache {
    let directory: URL

    public init(directory: URL) {
        self.directory = directory.appendingPathComponent("layouts", isDirectory: true)
    }

    private func url(for courseID: String) -> URL {
        let safe = courseID.map { $0.isLetter || $0.isNumber || $0 == "-" ? $0 : "_" }
        return directory.appendingPathComponent(String(safe) + ".json")
    }

    public func layout(for courseID: String, maxAge: TimeInterval = 60 * 86_400) -> CourseLayout? {
        guard let data = try? Data(contentsOf: url(for: courseID)),
              let layout = try? LibraryStore.decoder.decode(CourseLayout.self, from: data),
              Date().timeIntervalSince(layout.fetchedAt) < maxAge else { return nil }
        return layout
    }

    public func store(_ layout: CourseLayout, for courseID: String) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let data = try? LibraryStore.encoder.encode(layout) {
            try? data.write(to: url(for: courseID), options: .atomic)
        }
    }
}
