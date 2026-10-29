import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
@testable import GolfKit

final class SupabaseMatchServiceTests: XCTestCase {
    let config = SupabaseConfig(project: "abcdefgh", anonKey: "anon-key")!

    func authBody(_ token: String) -> Data {
        Data("""
        {"access_token":"\(token)","token_type":"bearer","expires_in":3600,"refresh_token":"refresh-\(token)","user":{"id":"user-1"}}
        """.utf8)
    }

    func testConfigAcceptsRefHostOrURL() {
        XCTAssertEqual(SupabaseConfig(project: "abcdefgh", anonKey: "k")?.url.absoluteString, "https://abcdefgh.supabase.co")
        XCTAssertEqual(SupabaseConfig(project: "abcdefgh.supabase.co", anonKey: "k")?.url.absoluteString, "https://abcdefgh.supabase.co")
        XCTAssertEqual(SupabaseConfig(project: "https://x.example.com/", anonKey: "k")?.url.absoluteString, "https://x.example.com")
        XCTAssertNil(SupabaseConfig(project: "", anonKey: "k"))
        XCTAssertNil(OnlineSettings().supabaseConfig, "empty settings mean offline demo mode")
    }

    func testCreateMatchSignsInAnonymouslyRetriesCodeClashAndReadsSnapshot() async throws {
        let match = Match(code: "BCDF", hostID: UUID(), name: "Sunday", course: testCourse(holes: 9))
        let host = Participant(id: match.hostID, name: "Host", avatar: Avatar(emoji: "⛳️", colorIndex: 0))
        var matchInserts = 0
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        let transport = MockTransport { request in
            let path = request.url!.path
            switch (request.httpMethod ?? "GET", path) {
            case ("POST", "/auth/v1/signup"):
                XCTAssertEqual(request.value(forHTTPHeaderField: "apikey"), "anon-key")
                return (200, self.authBody("tok1"))
            case ("POST", "/rest/v1/matches"):
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer tok1")
                matchInserts += 1
                if matchInserts == 1 { return (409, Data(#"{"message":"duplicate key value"}"#.utf8)) }
                XCTAssertFalse(request.bodyString.contains("\"code\":\"BCDF\""), "a fresh code is generated after a clash")
                return (201, Data())
            case ("POST", "/rest/v1/participants"):
                XCTAssertEqual(request.queryValue("on_conflict"), "match_id,participant_id")
                XCTAssertTrue(request.value(forHTTPHeaderField: "Prefer")!.contains("merge-duplicates"))
                return (201, Data())
            case ("GET", "/rest/v1/matches"):
                let row = ["payload": match]
                return (200, try encoder.encode([row]))
            case ("GET", "/rest/v1/participants"):
                return (200, try encoder.encode([["payload": host]]))
            default:
                XCTFail("unexpected \(request.httpMethod ?? "") \(path)")
                return (500, Data())
            }
        }

        let saved = SessionBox()
        let service = SupabaseMatchService(config: config, transport: transport, onSessionChange: { saved.value = $0 })
        let snapshot = try await service.createMatch(match, host: host)
        XCTAssertEqual(snapshot.participants.map(\.name), ["Host"])
        XCTAssertEqual(matchInserts, 2)
        XCTAssertEqual(saved.value?.accessToken, "tok1")
        XCTAssertEqual(transport.recorded.filter { $0.url!.path == "/auth/v1/signup" }.count, 1, "the session is reused")
    }

    func testJoinUnknownCodeThrows() async {
        let transport = MockTransport { request in
            if request.url!.path.hasPrefix("/auth") { return (200, self.authBody("t")) }
            return (200, Data("[]".utf8))
        }
        let service = SupabaseMatchService(config: config, transport: transport)
        do {
            _ = try await service.joinMatch(code: "zzzz", as: Participant(id: UUID(), name: "x", avatar: Avatar(emoji: "x", colorIndex: 0)))
            XCTFail("expected error")
        } catch {
            XCTAssertEqual(error as? MatchServiceError, .codeNotFound("ZZZZ"))
        }
    }

    func testExpiredTokenIsRefreshedAnd401ReauthenticatesOnce() async throws {
        let expired = SupabaseSession(accessToken: "old", refreshToken: "r-old", expiresAt: Date(timeIntervalSince1970: 0), userID: "u")
        var restCalls = 0
        let transport = MockTransport { request in
            let path = request.url!.path
            if path == "/auth/v1/token" {
                XCTAssertEqual(request.queryValue("grant_type"), "refresh_token")
                XCTAssertTrue(request.bodyString.contains("r-old"))
                return (200, self.authBody("refreshed"))
            }
            if path == "/auth/v1/signup" { return (200, self.authBody("fresh")) }
            restCalls += 1
            if restCalls == 1 {
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer refreshed")
                return (401, Data(#"{"message":"JWT expired"}"#.utf8))
            }
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer fresh")
            return (204, Data())
        }
        let service = SupabaseMatchService(config: config, session: expired, transport: transport)
        try await service.removeParticipant(UUID(), matchID: UUID())
        XCTAssertEqual(restCalls, 2)
    }

    func testServerErrorsSurfaceTheirMessage() async {
        let transport = MockTransport { request in
            if request.url!.path.hasPrefix("/auth") { return (200, self.authBody("t")) }
            return (400, Data(#"{"message":"new row violates row-level security policy"}"#.utf8))
        }
        let service = SupabaseMatchService(config: config, transport: transport)
        do {
            try await service.updateMatch(Match(code: "BCDF", hostID: UUID(), name: "x", course: testCourse()))
            XCTFail("expected error")
        } catch {
            XCTAssertEqual(error as? MatchServiceError, .server("new row violates row-level security policy"))
        }
    }
}

final class SessionBox: @unchecked Sendable {
    var value: SupabaseSession?
}

final class ReplayTests: XCTestCase {
    func testTimelineOrdersShotsAndInterpolates() {
        let player = UUID()
        let tee = GeoPoint(latitude: 51.5, longitude: -0.1)
        let mid = GeoMath.destination(from: tee, bearing: 0, distance: 200)
        let green = GeoMath.destination(from: mid, bearing: 0, distance: 100)
        let hole2 = GeoMath.destination(from: green, bearing: 90, distance: 30)
        let shots = [
            ReplayShot(playerID: player, holeNumber: 1, strokeNumber: 1, start: tee, end: mid, club: .driver, lie: .tee),
            ReplayShot(playerID: player, holeNumber: 1, strokeNumber: 2, start: mid, end: green, club: .iron9, lie: .fairway),
            ReplayShot(playerID: player, holeNumber: 2, strokeNumber: 1, start: hole2, end: GeoMath.destination(from: hole2, bearing: 90, distance: 150), lie: .tee),
        ]
        let timeline = ReplayTimeline(shots: shots, holeIntro: 1, pause: 0.5)
        XCTAssertEqual(timeline.holeNumbers, [1, 2])
        XCTAssertEqual(timeline.segments[0].start, 1)
        XCTAssertGreaterThan(timeline.segments[0].duration, timeline.segments[1].duration, "longer shots take longer")

        let before = timeline.frame(at: 0)
        XCTAssertNil(before.active)
        XCTAssertEqual(before.ball, tee)

        let midFlight = timeline.frame(at: timeline.segments[0].start + timeline.segments[0].duration / 2)
        XCTAssertEqual(midFlight.active?.strokeNumber, 1)
        XCTAssertGreaterThan(midFlight.height, 0.9)
        let travelled = GeoMath.distance(tee, midFlight.ball!)
        XCTAssertGreaterThan(travelled, 100, "ease-out puts the ball past halfway at half time")

        let afterFirstHole = timeline.frame(at: timeline.segments[1].end + 0.1)
        XCTAssertEqual(afterFirstHole.completed.count, 2)
        XCTAssertNil(afterFirstHole.active)

        let secondHole = timeline.frame(at: timeline.segments[2].start - 0.5)
        XCTAssertEqual(secondHole.holeNumber, 2)
        XCTAssertTrue(secondHole.completed.isEmpty, "a new hole starts with a clean slate")

        XCTAssertEqual(timeline.startTime(ofHole: 2)!, timeline.segments[2].start - 1, accuracy: 0.0001)
        XCTAssertEqual(timeline.frame(at: 10_000).completed.count, 1)
    }

    func testReplayShotsBuiltFromScorecard() {
        let tee = GeoPoint(latitude: 51.5, longitude: -0.1)
        let ball = GeoMath.destination(from: tee, bearing: 0, distance: 150)
        let cup = GeoMath.destination(from: ball, bearing: 0, distance: 4)
        let score = HoleScore(holeNumber: 3, strokes: 2, putts: 1, shots: [Shot(start: tee, lie: .tee), Shot(start: ball, lie: .green)], holeLocation: cup)
        let replay = ReplayShot.from(scores: [score], playerID: UUID())
        XCTAssertEqual(replay.count, 2)
        XCTAssertEqual(replay[1].end, cup)
        XCTAssertTrue(replay[1].isPutt)
    }
}

final class DemoAndLibraryTests: XCTestCase {
    func testDemoLayoutsAreComplete() {
        XCTAssertEqual(DemoData.golfLayout.holes.count, 18)
        XCTAssertEqual(DemoData.pitchAndPuttLayout.holes.count, 18)
        for hole in DemoData.golfLayout.holes {
            XCTAssertEqual(hole.greens.count, 1)
            let par = DemoData.golfCourse.hole(hole.number)!.par
            XCTAssertEqual(hole.length!, DemoData.golfLengths[hole.number - 1], accuracy: par == 5 ? 25 : 1, "hole \(hole.number)")
            XCTAssertEqual(hole.fairways.isEmpty, par == 3)
        }
        XCTAssertEqual(DemoData.golfCourse.par, 72)
        XCTAssertEqual(DemoData.pitchAndPuttCourse.par, 54)
        XCTAssertEqual(DemoData.golfCourse.tees.count, 3)
        // The figure-eight routing keeps the whole course within ~2.5 km.
        let bounds = DemoData.golfLayout.bounds!
        XCTAssertLessThan(bounds.latitudeSpan * 111_000, 2500)
    }

    func testBotScoresAreDeterministicAndConsistent() {
        let hole = DemoData.golfCourse.hole(4)!
        let layout = DemoData.golfLayout.hole(4)
        let id = DemoData.friends[0].id
        let a = BotGolfer.holeScore(playerID: id, handicap: 8, hole: hole, gameType: .golf, layout: layout)
        let b = BotGolfer.holeScore(playerID: id, handicap: 8, hole: hole, gameType: .golf, layout: layout)
        XCTAssertEqual(a.strokes, b.strokes)
        XCTAssertEqual(a.shots.count, a.strokes, "one GPS shot per stroke")
        XCTAssertEqual(a.shots.filter(\.isPutt).count, a.putts)
        XCTAssertEqual(a.shots.first?.lie, .tee)

        let mini = BotGolfer.holeScore(playerID: id, handicap: 30, hole: HoleInfo(number: 1, par: 3), gameType: .miniGolf, layout: nil)
        XCTAssertLessThanOrEqual(mini.strokes, 6)
        XCTAssertNil(mini.putts)
    }

    func testSampleHistoryProducesStatsAndAHandicap() {
        let profile = PlayerProfile(name: "Chris")
        let history = DemoData.sampleHistory(for: profile, now: Date(timeIntervalSince1970: 1_800_000_000))
        XCTAssertGreaterThan(history.rounds.count, 10)
        XCTAssertEqual(history.matches.count, 6)

        var library = GolfLibrary(profile: profile, rounds: history.rounds, matchHistory: history.matches, hasSampleData: true)
        let golf = library.handicap(for: .golf)
        XCTAssertEqual(golf.source, .calculated)
        XCTAssertNotNil(golf.index)
        XCTAssertNotNil(library.handicap(for: .pitchAndPutt).index)

        let h2h = HeadToHeadEngine.records(for: profile.id, in: history.matches)
        XCTAssertGreaterThanOrEqual(h2h.count, 3)
        XCTAssertFalse(StatsEngine.courseStats(rounds: history.rounds).isEmpty)
        XCTAssertFalse(StatsEngine.clubDistances(in: history.rounds).isEmpty)

        library.removeSampleData()
        XCTAssertTrue(library.rounds.isEmpty)
        XCTAssertTrue(library.matchHistory.isEmpty)
    }

    func testLibraryRoundTripsThroughDisk() async throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("golfkit-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = LibraryStore(directory: dir)

        var profile = PlayerProfile(name: "Chris Tibballs")
        profile.setHandicapSettings(HandicapSettings(mode: .manual, manualIndex: 11.2), for: .golf)
        profile.setHandicapSettings(HandicapSettings(roundsRequired: 5), for: .miniGolf)
        var library = GolfLibrary(profile: profile)
        library.settings.units = .imperial
        library.upsert(round(on: testCourse(), strokes: [4, 5, 3]))
        library.remember(Course.custom(name: "Backyard", gameType: .miniGolf, pars: [2, 2, 3]))
        library.toggleFavorite("abc")
        try await store.save(library)

        let loaded = await store.load()
        XCTAssertEqual(loaded, library)
        XCTAssertEqual(loaded.profile?.initials, "CT")
        XCTAssertEqual(loaded.profile?.handicapSettings(for: .miniGolf).roundsRequired, 5)
        XCTAssertEqual(loaded.settings.units, .imperial)
        XCTAssertEqual(loaded.knownCourses.count, 2)

        // Older files without newer keys still load.
        let legacy = try GolfLibrary.decodeLegacy(#"{"settings":{"units":"imperial"}}"#)
        XCTAssertEqual(legacy.settings.units, .imperial)
        XCTAssertTrue(legacy.settings.haptics)
        XCTAssertTrue(legacy.rounds.isEmpty)

        // Dictionaries keyed by game type encode as JSON objects.
        let json = String(decoding: try JSONEncoder().encode(profile), as: UTF8.self)
        XCTAssertTrue(json.contains("\"miniGolf\":{"))
    }
}

extension GolfLibrary {
    static func decodeLegacy(_ json: String) throws -> GolfLibrary {
        try JSONDecoder().decode(GolfLibrary.self, from: Data(json.utf8))
    }
}
