import XCTest
@testable import GolfKit

final class StatsTests: XCTestCase {
    func testRoundStatsGIRFairwaysPuttsScrambling() {
        let course = testCourse(holes: 9)  // pars 4,4,3,5,4,4,3,4,5
        let scores = [
            HoleScore(holeNumber: 1, strokes: 4, putts: 2, fairway: .hit),                // GIR, par
            HoleScore(holeNumber: 2, strokes: 5, putts: 2, penalties: 1, fairway: .left), // missed GIR, bogey
            HoleScore(holeNumber: 3, strokes: 2, putts: 1),                               // GIR, birdie
            HoleScore(holeNumber: 4, strokes: 5, putts: 1, fairway: .right),              // missed GIR (4 to green), scrambled par
            HoleScore(holeNumber: 5, strokes: 5, putts: 3, fairway: .hit, sandShots: 1),  // GIR, 3-putt bogey
        ]
        let r = Round(playerID: UUID(), playerName: "Me", course: course, scores: scores)
        let stats = StatsEngine.scoring(for: r)

        XCTAssertEqual(stats.holesPlayed, 5)
        XCTAssertEqual(stats.strokes, 21)
        XCTAssertEqual(stats.toPar, 1)
        XCTAssertEqual(stats.puttsTotal, 9)
        XCTAssertEqual(stats.greensInRegulation, Ratio(made: 3, attempts: 5))
        XCTAssertEqual(stats.fairways, Ratio(made: 2, attempts: 4))
        XCTAssertEqual(stats.fairwayMissLeft, 1)
        XCTAssertEqual(stats.scrambling, Ratio(made: 1, attempts: 2))
        XCTAssertEqual(stats.sandSaves, Ratio(made: 0, attempts: 1))
        XCTAssertEqual(stats.penalties, 1)
        XCTAssertEqual(stats.onePutts, 2)
        XCTAssertEqual(stats.threePuttsOrWorse, 1)
        XCTAssertEqual(stats.count(.birdie), 1)
        XCTAssertEqual(stats.count(.bogey), 2)
        XCTAssertEqual(stats.averageStrokes(onPar: 4)!, 14.0 / 3, accuracy: 0.001)
        XCTAssertEqual(stats.greensInRegulation.percentText, "60%")
        XCTAssertEqual(scores[3].shotsToGreen, 4)
    }

    func testPlayerStatsTrendAndBestRound() {
        let course = testCourse(holes: 9)
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let r1 = round(on: course, strokes: course.holes.map { $0.par + 1 }, date: base)
        let r2 = round(on: course, strokes: course.holes.map(\.par), date: base.addingTimeInterval(86_400))
        let stats = StatsEngine.playerStats(rounds: [r2, r1])
        XCTAssertEqual(stats.rounds, 2)
        XCTAssertEqual(stats.trend.map(\.toPar), [9, 0])
        XCTAssertEqual(stats.trend[0].toPar18, 18)
        XCTAssertEqual(stats.bestRound?.id, r2.id)
        XCTAssertEqual(stats.scoringAverage!, 81, accuracy: 0.001)  // (90 + 72) / 2 scaled to 18
    }

    func testCourseAndHoleStats() {
        let course = testCourse(holes: 9)
        let rounds = [
            round(on: course, strokes: [5, 4, 3, 5, 4, 4, 3, 4, 8]),
            round(on: course, strokes: [6, 4, 2, 5, 4, 4, 3, 4, 6]),
        ]
        let stats = StatsEngine.courseStats(rounds: rounds)
        XCTAssertEqual(stats.count, 1)
        let course1 = stats[0]
        XCTAssertEqual(course1.roundsPlayed, 2)
        XCTAssertEqual(course1.averageScore!, 39.0, accuracy: 0.001)
        let hole1 = course1.holes[0]
        XCTAssertEqual(hole1.averageStrokes!, 5.5, accuracy: 0.001)
        XCTAssertEqual(hole1.best, 5)
        XCTAssertEqual(course1.holesByDifficulty.first?.number, 9)   // +2 avg
        XCTAssertEqual(course1.holesByDifficulty.last?.number, 3)    // -0.5 avg
    }

    func testClubDistancesFromShots() {
        let course = testCourse(holes: 1)
        let tee = GeoPoint(latitude: 51.5, longitude: -0.1)
        let landing = GeoMath.destination(from: tee, bearing: 0, distance: 220)
        let green = GeoMath.destination(from: landing, bearing: 0, distance: 120)
        let shots = [
            Shot(start: tee, club: .driver, lie: .tee),
            Shot(start: landing, club: .iron8, lie: .fairway),
            Shot(start: green, club: .putter, lie: .green),
        ]
        let score = ShotTracking.holeScore(holeNumber: 1, par: 4, shots: shots, holeLocation: GeoMath.destination(from: green, bearing: 10, distance: 3), layout: nil)
        XCTAssertEqual(score.strokes, 3)
        XCTAssertEqual(score.putts, 1)
        XCTAssertEqual(score.fairway, .hit)
        XCTAssertEqual(score.shotsToGreen, 2)

        let r = Round(playerID: UUID(), playerName: "Me", course: course, scores: [score], isComplete: true)
        let clubs = StatsEngine.clubDistances(in: [r])
        XCTAssertEqual(clubs.map(\.club), [.driver, .iron8])
        XCTAssertEqual(clubs[0].average, 220, accuracy: 1)
        XCTAssertEqual(StatsEngine.driveDistances(in: [r]).first!, 220, accuracy: 1)
    }

    func testHeadToHeadAndFriendsLeaderboard() {
        let course = testCourse(holes: 9)
        let me = UUID(), alex = UUID()
        func card(_ id: UUID, _ name: String, _ strokes: [Int]) -> Participant {
            var p = Participant(id: id, name: name, avatar: Avatar(emoji: "⛳️", colorIndex: 0))
            for (i, s) in strokes.enumerated() { p.setScore(HoleScore(holeNumber: i + 1, strokes: s, putts: 2)) }
            return p
        }
        let m1 = Match(code: "BCDF", hostID: me, name: "1", course: course, status: .finished)
        let m2 = Match(code: "GHJK", hostID: me, name: "2", course: course, status: .finished)
        let history = [
            MatchRecord(snapshot: MatchSnapshot(match: m1, participants: [
                card(me, "Me", [4, 4, 3, 5, 4, 4, 3, 4, 5]), card(alex, "Alex", [5, 4, 3, 5, 4, 4, 3, 4, 5]),
            ])),
            MatchRecord(snapshot: MatchSnapshot(match: m2, participants: [
                card(me, "Me", [5, 5, 3]), card(alex, "Alex", [4, 4, 3, 4]),   // only 3 holes in common
            ])),
        ]

        let records = HeadToHeadEngine.records(for: me, in: history)
        XCTAssertEqual(records.count, 1)
        let vsAlex = records[0]
        XCTAssertEqual(vsAlex.opponentName, "Alex")
        XCTAssertEqual(vsAlex.recordText, "1–1–0")
        XCTAssertEqual(vsAlex.holesWon, 1)
        XCTAssertEqual(vsAlex.holesLost, 2)
        XCTAssertEqual(vsAlex.holesHalved, 9)
        XCTAssertEqual(vsAlex.matches.first { $0.matchID == m2.id }?.holesCompared, 3)
        XCTAssertEqual(vsAlex.averageMarginPer18!, -1.5, accuracy: 0.001)

        let board = HeadToHeadEngine.friendsLeaderboard(for: me, in: history)
        XCTAssertEqual(board.count, 2)
        XCTAssertEqual(board.first?.name, "Alex")
        XCTAssertTrue(board.contains { $0.isMe })
    }
}
