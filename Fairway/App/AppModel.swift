import SwiftUI
import Observation
import GolfKit

/// A transient message shown at the top of the screen.
struct Banner: Identifiable, Equatable {
    enum Style { case info, success, error, celebration }
    let id = UUID()
    var title: String
    var message: String?
    var style: Style = .info
}

/// Full-screen flows presented from the root.
enum Presentation: Identifiable, Hashable {
    case round(UUID)
    case match(UUID)
    case tournament(UUID)

    var id: String {
        switch self {
        case .round(let id): return "round-\(id)"
        case .match(let id): return "match-\(id)"
        case .tournament(let id): return "tournament-\(id)"
        }
    }
}

enum JoinResult {
    case match(MatchSession)
    case tournament(TournamentSession)
}

/// App-wide state: the persisted library plus the services that talk to the outside world.
/// All mutations of `library` go through `update(_:)` so they are saved.
@Observable
@MainActor
final class AppModel {
    private(set) var library: GolfLibrary
    let location = LocationService()
    private(set) var matchService: any MatchService
    private(set) var layouts: [String: CourseLayout] = [:]
    private(set) var sessions: [UUID: MatchSession] = [:]
    private(set) var tournamentSessions: [UUID: TournamentSession] = [:]
    var banner: Banner?
    var presentation: Presentation?

    @ObservationIgnored private var weatherCache: [String: WeatherReport] = [:]
    @ObservationIgnored private let store: LibraryStore
    @ObservationIgnored private let layoutCache: LayoutCache
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var bannerTask: Task<Void, Never>?
    @ObservationIgnored private let demoService: InMemoryMatchService
    @ObservationIgnored let weatherClient = OpenMeteoClient()
    @ObservationIgnored let overpass = OverpassClient()

    init(directory: URL = LibraryStore.defaultDirectory()) {
        let store = LibraryStore(directory: directory)
        let library = store.load()
        let demo = InMemoryMatchService()
        self.store = store
        self.layoutCache = LayoutCache(directory: directory)
        self.library = library
        self.demoService = demo
        self.matchService = demo
        reconfigureOnline()
    }

    // MARK: - Library access

    func update(_ mutate: (inout GolfLibrary) -> Void) {
        mutate(&library)
        scheduleSave()
    }

    /// A binding into the library that saves on change, for settings forms.
    func binding<Value>(_ keyPath: WritableKeyPath<GolfLibrary, Value>) -> Binding<Value> {
        Binding(
            get: { self.library[keyPath: keyPath] },
            set: { newValue in self.update { $0[keyPath: keyPath] = newValue } }
        )
    }

    private func scheduleSave() {
        saveTask?.cancel()
        let snapshot = library
        let store = self.store
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            try? await store.save(snapshot)
        }
    }

    func saveNow() {
        saveTask?.cancel()
        let snapshot = library
        let store = self.store
        Task { try? await store.save(snapshot) }
    }

    var isOnboarded: Bool { library.profile != nil }
    var profile: PlayerProfile { library.profile ?? PlayerProfile(name: "Golfer") }
    var units: UnitFormatter { UnitFormatter(system: library.settings.units) }
    var hapticsEnabled: Bool { library.settings.haptics }

    func handicap(for type: GameType) -> HandicapResult {
        library.handicap(for: type)
    }

    /// The player as a match participant, with their current index for the game type.
    func meAsParticipant(for type: GameType) -> Participant {
        var me = Participant(profile: profile, handicapIndex: handicap(for: type).index)
        me.scoredBy = profile.id
        return me
    }

    // MARK: - Navigation

    /// Presents a full-screen flow, optionally waiting for a sheet to finish dismissing.
    func present(_ presentation: Presentation, afterDismissing: Bool = false) {
        guard afterDismissing else {
            self.presentation = presentation
            return
        }
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(450))
            self?.presentation = presentation
        }
    }

    // MARK: - Banners

    func show(_ banner: Banner, for seconds: Double = 3) {
        withAnimation(.snappySpring) { self.banner = banner }
        bannerTask?.cancel()
        bannerTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            withAnimation(.snappySpring) { self?.banner = nil }
        }
    }

    func showError(_ error: Error) {
        show(Banner(title: "Something went wrong", message: error.localizedDescription, style: .error), for: 4)
    }

    // MARK: - Online play

    var onlineConfig: SupabaseConfig? {
        library.settings.online.supabaseConfig
            ?? SupabaseConfig(project: OnlineConfig.supabaseProject, anonKey: OnlineConfig.supabaseAnonKey)
    }

    var isOnline: Bool { matchService.isOnline }

    /// Switches between Supabase and the offline demo whenever settings change.
    func reconfigureOnline() {
        if let config = onlineConfig {
            matchService = SupabaseMatchService(
                config: config,
                session: library.supabaseSession,
                onSessionChange: { [weak self] session in
                    Task { @MainActor in self?.update { $0.supabaseSession = session } }
                }
            )
        } else {
            matchService = demoService
        }
    }

    // MARK: - Weather

    func weather(at point: GeoPoint) async -> WeatherReport? {
        let key = String(format: "%.2f,%.2f", point.latitude, point.longitude)
        if let cached = weatherCache[key], Date().timeIntervalSince(cached.fetchedAt) < 20 * 60 {
            return cached
        }
        do {
            let report = try await weatherClient.forecast(at: point)
            weatherCache[key] = report
            return report
        } catch {
            return weatherCache[key]
        }
    }

    // MARK: - Courses

    var courseAPI: OpenGolfAPIClient {
        OpenGolfAPIClient(apiKey: library.settings.online.openGolfAPIKey)
    }

    func layout(for course: Course) async -> CourseLayout? {
        if let layout = layouts[course.id] { return layout }
        if let demo = DemoData.layout(forCourseID: course.id) {
            layouts[course.id] = demo
            return demo
        }
        guard course.gameType != .miniGolf, let location = course.location else { return nil }
        if let cached = await layoutCache.layout(for: course.id) {
            layouts[course.id] = cached
            return cached
        }
        guard let fetched = try? await overpass.courseLayout(near: location), !fetched.isEmpty else { return nil }
        layouts[course.id] = fetched
        await layoutCache.store(fetched, for: course.id)
        return fetched
    }

    /// Courses matching a name: your own and demo courses first, then OpenGolfAPI.
    func searchCourses(_ query: String) async throws -> [CourseSummary] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2 else { return [] }
        let local = (library.knownCourses + DemoData.courses)
            .filter { $0.name.localizedCaseInsensitiveContains(trimmed) }
            .map(\.summary)
        let remote = try await courseAPI.searchCourses(query: trimmed)
        return deduplicated(local + remote)
    }

    /// Courses near a point from OpenGolfAPI and OpenStreetMap (which covers the whole
    /// world, plus pitch & putts and mini golf).
    func nearbyCourses(around point: GeoPoint) async -> [CourseSummary] {
        let apiClient = courseAPI
        let osmClient = overpass
        async let api = try? apiClient.searchCourses(near: point, radiusKilometres: 30)
        async let osm = try? osmClient.courses(near: point, radius: 30_000)
        let (fromAPI, fromOSM) = await (api, osm)
        return deduplicated((fromAPI ?? []) + (fromOSM ?? []))
            .sorted { ($0.distance ?? .infinity) < ($1.distance ?? .infinity) }
    }

    /// Merges results that are the same place from different sources, keeping the one with a scorecard.
    private func deduplicated(_ courses: [CourseSummary]) -> [CourseSummary] {
        var result: [CourseSummary] = []
        for course in courses {
            let duplicate = result.firstIndex { existing in
                if existing.id == course.id { return true }
                guard let a = existing.location, let b = course.location else { return false }
                let sameName = existing.name.lowercased().prefix(8) == course.name.lowercased().prefix(8)
                return sameName && GeoMath.distance(a, b) < 600
            }
            if duplicate == nil { result.append(course) }
        }
        return result
    }

    func loadCourse(_ summary: CourseSummary) async throws -> Course {
        if let known = library.course(id: summary.id) { return known }
        switch summary.source {
        case .openGolfAPI:
            return try await courseAPI.course(id: summary.id)
        case .openStreetMap:
            let (course, layout) = try await overpass.course(for: summary)
            if let layout {
                layouts[course.id] = layout
                await layoutCache.store(layout, for: course.id)
            }
            return course
        case .custom, .demo:
            throw MatchServiceError.notFound
        }
    }

    func saveCourse(_ course: Course) {
        update { $0.remember(course) }
    }

    func isFavorite(_ courseID: String) -> Bool {
        library.favoriteCourseIDs.contains(courseID)
    }

    func toggleFavorite(_ course: Course) {
        update {
            $0.remember(course)
            $0.toggleFavorite(course.id)
        }
    }

    // MARK: - Rounds

    func round(_ id: UUID) -> Round? {
        library.rounds.first { $0.id == id }
    }

    @discardableResult
    func startSoloRound(course: Course, tee: TeeSet?, holes: [Int]) -> Round {
        let round = Round(
            playerID: profile.id, playerName: profile.name, course: course, tee: tee, holeNumbers: holes,
            handicapIndex: handicap(for: course.gameType).index
        )
        update {
            $0.remember(course)
            $0.upsert(round)
            $0.inProgressRoundID = round.id
        }
        return round
    }

    /// Finds or creates this player's round for a match.
    @discardableResult
    func startRound(for session: MatchSession) -> Round {
        if let existing = library.rounds.first(where: { $0.matchID == session.id }) {
            update { $0.inProgressRoundID = existing.id }
            return existing
        }
        let match = session.match
        var round = Round(
            playerID: profile.id, playerName: profile.name, course: match.course, tee: match.tee,
            holeNumbers: match.holeNumbers, handicapIndex: session.me?.handicapIndex,
            matchID: match.id, tournamentID: match.tournamentID
        )
        if let me = session.me { round.scores = me.scores }
        update {
            $0.remember(match.course)
            $0.upsert(round)
            $0.inProgressRoundID = round.id
        }
        return round
    }

    func saveRound(_ round: Round) {
        update { $0.upsert(round) }
    }

    /// Completes a round. Short rounds (under nine holes) are kept but don't count for handicap.
    func finishRound(_ id: UUID, weather: WeatherReport? = nil) {
        guard var round = self.round(id) else { return }
        let played = round.holeNumbers.filter { hole in round.scores.contains { $0.holeNumber == hole } }
        if played.count < round.holeNumbers.count {
            if played.count >= 9 {
                round.holeNumbers = played
            } else {
                round.countsForHandicap = false
            }
        }
        round.isComplete = true
        if let weather { round.weatherSummary = weather.summary(units: units) }
        let finished = round
        update {
            $0.upsert(finished)
            if $0.inProgressRoundID == id { $0.inProgressRoundID = nil }
        }
    }

    func deleteRound(_ id: UUID) {
        update {
            $0.rounds.removeAll { $0.id == id }
            if $0.inProgressRoundID == id { $0.inProgressRoundID = nil }
        }
    }

    // MARK: - Matches

    func createMatch(name: String, course: Course, tee: TeeSet?, holes: [Int], format: ScoringFormat, useHandicaps: Bool) async throws -> MatchSession {
        let match = Match(
            code: JoinCode.generate(), hostID: profile.id, name: name, course: course, tee: tee,
            holeNumbers: holes, format: format, useHandicaps: useHandicaps
        )
        let snapshot = try await matchService.createMatch(match, host: meAsParticipant(for: course.gameType))
        let session = register(snapshot)
        update {
            $0.remember(course)
            $0.activeGames.append(ActiveGame(kind: .match, id: snapshot.match.id, code: snapshot.match.code, name: name))
        }
        return session
    }

    func joinMatch(code: String) async throws -> MatchSession {
        let normalized = JoinCode.normalize(code)
        // Already in this game? Just reopen it.
        if let existing = sessions.values.first(where: { $0.match.code == normalized && $0.match.status != .finished }) {
            return existing
        }
        // Use a provisional game type; the index is refreshed once we know the course.
        var snapshot = try await matchService.joinMatch(code: normalized, as: meAsParticipant(for: .golf))
        let gameType = snapshot.match.course.gameType
        if gameType != .golf, var me = snapshot.participant(profile.id) {
            me.handicapIndex = handicap(for: gameType).index
            try? await matchService.upsertParticipant(me, matchID: snapshot.match.id)
            if let i = snapshot.participants.firstIndex(where: { $0.id == me.id }) { snapshot.participants[i] = me }
        }
        let session = register(snapshot)
        if !library.activeGames.contains(where: { $0.id == snapshot.match.id }) {
            update {
                $0.activeGames.append(ActiveGame(kind: .match, id: snapshot.match.id, code: snapshot.match.code, name: snapshot.match.name))
            }
        }
        return session
    }

    /// One code box for everything: tries a match first, then a tournament.
    func join(code: String) async throws -> JoinResult {
        do {
            return .match(try await joinMatch(code: code))
        } catch MatchServiceError.codeNotFound {
            return .tournament(try await joinTournament(code: code))
        }
    }

    private func register(_ snapshot: MatchSnapshot) -> MatchSession {
        let session = MatchSession(service: matchService, snapshot: snapshot, myID: profile.id)
        session.onFinished = { [weak self] final in self?.recordFinished(final) }
        sessions[snapshot.match.id] = session
        return session
    }

    /// Reconnects to a game this device was part of (after relaunch).
    func session(for game: ActiveGame) async throws -> MatchSession {
        if let session = sessions[game.id] { return session }
        let snapshot = try await matchService.snapshot(matchID: game.id)
        return register(snapshot)
    }

    func session(forMatchID id: UUID) -> MatchSession? {
        sessions[id]
    }

    func recordFinished(_ snapshot: MatchSnapshot) {
        let roundID = library.rounds.first { $0.matchID == snapshot.match.id }?.id
        update {
            $0.upsert(MatchRecord(snapshot: snapshot))
            $0.activeGames.removeAll { $0.id == snapshot.match.id }
        }
        if let roundID, self.round(roundID)?.isComplete == false {
            finishRound(roundID)
        }
    }

    func leave(_ game: ActiveGame) async {
        if game.kind == .match {
            if let session = sessions[game.id] {
                session.stopPolling()
                if session.match.status == .lobby {
                    try? await matchService.removeParticipant(profile.id, matchID: game.id)
                }
            }
            sessions[game.id] = nil
        } else {
            tournamentSessions[game.id]?.stopPolling()
            tournamentSessions[game.id] = nil
        }
        update { $0.activeGames.removeAll { $0.id == game.id } }
    }

    // MARK: - Tournaments

    func createTournament(name: String, gameType: GameType, format: ScoringFormat, useHandicaps: Bool, rounds: [TournamentRound]) async throws -> TournamentSession {
        let tournament = Tournament(
            code: JoinCode.generate(), name: name, hostID: profile.id, gameType: gameType,
            format: format, useHandicaps: useHandicaps, rounds: rounds
        )
        let entrant = TournamentEntrant(profile: profile, handicapIndex: handicap(for: gameType).index)
        let snapshot = try await matchService.createTournament(tournament, host: entrant)
        let session = register(snapshot)
        update {
            $0.upsert(snapshot)
            $0.activeGames.append(ActiveGame(kind: .tournament, id: tournament.id, code: snapshot.tournament.code, name: name))
            for round in rounds { if let course = round.course { $0.remember(course) } }
        }
        return session
    }

    func joinTournament(code: String) async throws -> TournamentSession {
        let normalized = JoinCode.normalize(code)
        if let existing = tournamentSessions.values.first(where: { $0.tournament.code == normalized }) {
            return existing
        }
        let entrant = TournamentEntrant(profile: profile, handicapIndex: handicap(for: .golf).index)
        let snapshot = try await matchService.joinTournament(code: normalized, as: entrant)
        let session = register(snapshot)
        update {
            $0.upsert(snapshot)
            if !$0.activeGames.contains(where: { $0.id == snapshot.tournament.id }) {
                $0.activeGames.append(ActiveGame(kind: .tournament, id: snapshot.tournament.id, code: snapshot.tournament.code, name: snapshot.tournament.name))
            }
        }
        return session
    }

    private func register(_ snapshot: TournamentSnapshot) -> TournamentSession {
        let session = TournamentSession(service: matchService, snapshot: snapshot, myID: profile.id)
        session.onUpdate = { [weak self] latest in
            self?.update { $0.upsert(latest) }
        }
        tournamentSessions[snapshot.tournament.id] = session
        return session
    }

    func tournamentSession(for game: ActiveGame) async throws -> TournamentSession {
        if let session = tournamentSessions[game.id] { return session }
        let snapshot = try await matchService.tournamentSnapshot(id: game.id)
        return register(snapshot)
    }

    /// Joins (or reopens) the match for a live tournament round.
    func joinTournamentRound(_ round: TournamentRound) async throws -> MatchSession {
        if let matchID = round.matchID, let session = sessions[matchID] { return session }
        guard let code = round.matchCode else { throw MatchServiceError.notFound }
        return try await joinMatch(code: code)
    }

    func adopt(_ session: MatchSession) {
        session.onFinished = { [weak self] final in self?.recordFinished(final) }
        sessions[session.id] = session
    }

    // MARK: - Sample data

    func loadSampleData() {
        let history = DemoData.sampleHistory(for: profile, handicap: handicap(for: .golf).index ?? 13.5)
        update {
            $0.rounds += history.rounds
            for record in history.matches { $0.upsert(record) }
            $0.hasSampleData = true
        }
    }

    func removeSampleData() {
        update { $0.removeSampleData() }
    }

    // MARK: - Previews

    static var preview: AppModel {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("fairway-preview-\(UUID().uuidString)")
        let model = AppModel(directory: directory)
        model.update { $0.profile = PlayerProfile(name: "Chris", avatar: Avatar(emoji: "🦅", colorIndex: 0)) }
        model.loadSampleData()
        return model
    }
}
