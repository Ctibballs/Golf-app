import XCTest
@testable import GolfKit

final class LeaderboardTests: XCTestCase {
    let course = testCourse(holes: 9)

    func participant(_ name: String, _ strokes: [Int], handicap: Double? = nil) -> Participant {
        var p = Participant(id: UUID(), name: name, avatar: Avatar(emoji: "⛳️", colorIndex: 0), handicapIndex: handicap)
        for (i, s) in strokes.enumerated() { p.setScore(HoleScore(holeNumber: i + 1, strokes: s)) }
        return p
    }

    func match(_ format: ScoringFormat, handicaps: Bool = false) -> Match {
        Match(code: "BCDF", hostID: UUID(), name: "Test", course: course, format: format, useHandicaps: handicaps, status: .live)
    }

    func testStrokePlayRanksByToParWithTies() {
        let a = participant("Ann", [4, 4, 3])           // E thru 3
        let b = participant("Ben", [3, 4, 3, 5])        // -1 thru 4
        let c = participant("Cat", [5, 4, 2])           // E thru 3
        let d = participant("Dan", [])
        let entries = Leaderboard.entries(for: MatchSnapshot(match: match(.strokePlay), participants: [a, b, c, d]))
        XCTAssertEqual(entries.map(\.participant.name), ["Ben", "Ann", "Cat", "Dan"])
        XCTAssertEqual(entries.map(\.positionLabel), ["1", "T2", "T2", "–"])
        XCTAssertEqual(entries[0].statusText, "-1")
        XCTAssertEqual(entries[1].statusText, "E")
        XCTAssertEqual(entries[0].thru, 4)
    }

    func testNetStrokePlayUsesHandicapStrokes() {
        let scratch = participant("Pro", [4, 4, 3, 5, 4, 4, 3, 4, 5], handicap: 0)
        let hacker = participant("Hack", [5, 5, 4, 6, 5, 5, 4, 5, 6], handicap: 18)
        let entries = Leaderboard.entries(for: MatchSnapshot(match: match(.strokePlay, handicaps: true), participants: [scratch, hacker]))
        // 18 index over 9 holes → 9 strokes → net level par: a tie.
        XCTAssertEqual(entries.first { $0.participant.name == "Hack" }?.courseHandicap, 9)
        XCTAssertEqual(entries.map(\.positionLabel), ["T1", "T1"])
    }

    func testStablefordPoints() {
        XCTAssertEqual(Leaderboard.stablefordPoints(strokes: 4, par: 4), 2)
        XCTAssertEqual(Leaderboard.stablefordPoints(strokes: 3, par: 4), 3)
        XCTAssertEqual(Leaderboard.stablefordPoints(strokes: 7, par: 4), 0)
        let a = participant("Ann", [3, 4, 3])   // 3 + 2 + 2 = 7
        let b = participant("Ben", [4, 6, 2])   // 2 + 0 + 3 = 5
        let entries = Leaderboard.entries(for: MatchSnapshot(match: match(.stableford), participants: [b, a]))
        XCTAssertEqual(entries.map(\.participant.name), ["Ann", "Ben"])
        XCTAssertEqual(entries[0].statusText, "7 pts")
    }

    func testSkinsCarryOver() {
        let a = participant("Ann", [4, 4, 3, 5])
        let b = participant("Ben", [4, 4, 2, 6])
        let c = participant("Cat", [4, 5, 4, 4])
        // Holes 1-2 tied/carry (hole 2: Ann & Ben tie), hole 3 Ben wins 3 skins, hole 4 Cat wins 1.
        let entries = Leaderboard.entries(for: MatchSnapshot(match: match(.skins), participants: [a, b, c]))
        let byName = Dictionary(uniqueKeysWithValues: entries.map { ($0.participant.name, $0.points ?? 0) })
        XCTAssertEqual(byName["Ben"], 3)
        XCTAssertEqual(byName["Cat"], 1)
        XCTAssertEqual(byName["Ann"], 0)
        XCTAssertEqual(entries.first?.participant.name, "Ben")
    }

    func testMatchPlayStatus() {
        let a = participant("Ann", [3, 4, 3, 4, 4, 4, 3])
        let b = participant("Ben", [4, 5, 4, 4, 4, 4, 3])
        let entries = Leaderboard.entries(for: MatchSnapshot(match: match(.matchPlay), participants: [a, b]))
        // Ann won 3 holes, 2 to play → won 3&2.
        XCTAssertEqual(entries[0].participant.name, "Ann")
        XCTAssertEqual(entries[0].statusText, "Won 3&2")
        XCTAssertEqual(entries[1].statusText, "Lost 3&2")
        XCTAssertEqual(Leaderboard.matchPlayStatus(lead: 0, remaining: 5, played: 4), "AS")
        XCTAssertEqual(Leaderboard.matchPlayStatus(lead: 2, remaining: 5, played: 4), "2 UP")
        XCTAssertEqual(Leaderboard.matchPlayStatus(lead: -1, remaining: 0, played: 18), "1 DN")
    }

    func testMatchPlayStrokesComeOffTheLowestHandicap() {
        let low = participant("Low", [], handicap: 8)
        let high = participant("High", [], handicap: 18)
        var m = match(.matchPlay, handicaps: true)
        let strokes = PlayingHandicap.allocations(in: m, participants: [low, high])
        // Over nine holes the course handicaps are 4 and 9: High gets the 5-stroke
        // difference on the five hardest holes, Low plays off scratch.
        XCTAssertEqual(strokes[low.id]?.values.reduce(0, +), 0)
        XCTAssertEqual(strokes[high.id]?.values.reduce(0, +), 5)
        XCTAssertEqual(strokes[high.id]?[1], 1, "stroke index 1 gets a stroke")
        XCTAssertEqual(strokes[high.id]?[9], 0)
        m.format = .strokePlay
        XCTAssertEqual(PlayingHandicap.allocations(in: m, participants: [low, high])[low.id]?.values.reduce(0, +), 4, "stroke play keeps full strokes")
    }
}

final class TournamentStandingsTests: XCTestCase {
    func testAggregatesAcrossRoundsAndTracksCurrentHole() {
        let course = testCourse(holes: 9)
        let ann = TournamentEntrant(id: UUID(), name: "Ann", avatar: Avatar(emoji: "🦊", colorIndex: 0))
        let ben = TournamentEntrant(id: UUID(), name: "Ben", avatar: Avatar(emoji: "🐻", colorIndex: 1))

        var r1 = Match(code: "BCDF", hostID: ann.id, name: "R1", course: course, status: .finished, roundNumber: 1)
        r1.useHandicaps = false
        var r2 = Match(code: "GHJK", hostID: ann.id, name: "R2", course: course, status: .live, roundNumber: 2)
        r2.useHandicaps = false

        func card(_ e: TournamentEntrant, _ strokes: [Int], current: Int? = nil) -> Participant {
            var p = Participant(id: e.id, name: e.name, avatar: e.avatar)
            for (i, s) in strokes.enumerated() { p.setScore(HoleScore(holeNumber: i + 1, strokes: s, putts: 2)) }
            p.currentHole = current
            return p
        }

        let tournament = Tournament(
            code: "LMNP", name: "Club Champs", hostID: ann.id, useHandicaps: false,
            rounds: [
                TournamentRound(number: 1, course: course, matchID: r1.id, status: .finished),
                TournamentRound(number: 2, course: course, matchID: r2.id, status: .live),
            ],
            status: .inProgress
        )
        let snapshot = TournamentSnapshot(tournament: tournament, entrants: [ann, ben], rounds: [
            1: MatchSnapshot(match: r1, participants: [card(ann, [4, 4, 3, 5, 4, 4, 3, 4, 5]), card(ben, [4, 4, 3, 5, 4, 4, 3, 4, 4])]),
            2: MatchSnapshot(match: r2, participants: [card(ann, [3, 4], current: 3), card(ben, [5, 5, 3], current: 4)]),
        ])

        let standings = TournamentStandings.compute(snapshot)
        XCTAssertEqual(standings.map(\.entrant.name), ["Ann", "Ben"])

        // With handicaps, "today" is net like the total: Ben's 18 index gives a stroke a hole.
        var netTournament = tournament
        netTournament.useHandicaps = true
        var netR2 = r2
        netR2.useHandicaps = true
        var benNet = card(ben, [5, 5, 3], current: 4)
        benNet.handicapIndex = 18
        let netSnapshot = TournamentSnapshot(tournament: netTournament, entrants: [ann, ben], rounds: [
            1: snapshot.rounds[1]!,
            2: MatchSnapshot(match: netR2, participants: [card(ann, [3, 4], current: 3), benNet]),
        ])
        let netBen = TournamentStandings.compute(netSnapshot).first { $0.entrant.name == "Ben" }!
        XCTAssertEqual(netBen.today, -1, "+2 gross minus 3 handicap strokes")
        XCTAssertEqual(standings[0].totalToPar, -1)
        XCTAssertEqual(standings[0].today, -1)
        XCTAssertEqual(standings[0].thru, 2)
        XCTAssertEqual(standings[0].currentHole, 3)
        XCTAssertEqual(standings[1].totalToPar, 1)
        XCTAssertEqual(standings[1].roundToPar[1], -1)
        XCTAssertEqual(standings[1].currentHole, 4)
        XCTAssertEqual(standings[0].stats.holesPlayed, 11)
    }
}

final class TeamTests: XCTestCase {
    private let par9 = [4, 4, 3, 5, 4, 4, 3, 4, 5]

    private func player(_ name: String, index: Double? = nil) -> Participant {
        Participant(id: UUID(), name: name, avatar: Avatar(emoji: "🦊", colorIndex: 0), handicapIndex: index)
    }

    private func scored(_ p: Participant, _ strokes: [Int], updatedAt: Date = Date(timeIntervalSince1970: 0)) -> Participant {
        var copy = p
        for (i, s) in strokes.enumerated() { copy.setScore(HoleScore(holeNumber: i + 1, strokes: s)) }
        copy.updatedAt = updatedAt
        return copy
    }

    private func teamMatch(_ format: TeamFormat, scoring: ScoringFormat = .strokePlay, teams: [[Participant]], course: Course? = nil, handicaps: Bool = false) -> Match {
        Match(code: "BCDF", hostID: teams[0][0].id, name: "Fourball", course: course ?? testCourse(holes: 9), format: scoring,
              useHandicaps: handicaps, status: .live, teamFormat: format,
              teams: teams.enumerated().map { Team(name: Team.defaultNames[$0.offset], colorIndex: $0.offset, memberIDs: $0.element.map(\.id)) })
    }

    func testBetterBallAndAggregateStrokePlay() {
        let a = scored(player("Ann"), par9)                                          // level
        let b = scored(player("Ben"), [5, 5, 4, 6, 3, 4, 3, 4, 5])                   // birdie on 5
        let c = scored(player("Cat"), par9.map { $0 + 1 })                           // +9
        let d = scored(player("Dan"), [4, 4, 3, 5, 4, 4, 3, 4, 6])                   // bogey on 9
        let players = [a, b, c, d]

        let bestBall = TeamLeaderboard.entries(for: MatchSnapshot(match: teamMatch(.fourBall, teams: [[a, b], [c, d]]), participants: players))
        XCTAssertEqual(bestBall.map(\.team.name), ["Blue", "Red"])
        XCTAssertEqual(bestBall[0].statusText, "-1")
        XCTAssertEqual(bestBall[1].statusText, "+1")
        XCTAssertEqual(bestBall[0].holeScores[5], 3, "the birdie is Blue's ball on 5")
        XCTAssertEqual(bestBall[0].thru, 9)
        XCTAssertTrue(bestBall[0].isFinished)

        let aggregate = TeamLeaderboard.entries(for: MatchSnapshot(match: teamMatch(.aggregate, teams: [[a, b], [c, d]]), participants: players))
        XCTAssertEqual(aggregate[0].statusText, "+3")
        XCTAssertEqual(aggregate[1].statusText, "+10")
    }

    func testTeamMatchPlayAndStableford() {
        let a = scored(player("Ann"), par9)
        let b = scored(player("Ben"), [5, 5, 4, 6, 3, 4, 3, 4, 5])
        let c = scored(player("Cat"), par9.map { $0 + 1 })
        let d = scored(player("Dan"), [4, 4, 3, 5, 4, 4, 3, 4, 6])
        let players = [a, b, c, d]

        let match = TeamLeaderboard.entries(for: MatchSnapshot(match: teamMatch(.fourBall, scoring: .matchPlay, teams: [[a, b], [c, d]]), participants: players))
        XCTAssertEqual(match[0].team.name, "Blue")
        XCTAssertEqual(match[0].statusText, "2 UP", "won 5 and 9, halved the rest")
        XCTAssertEqual(match[1].statusText, "2 DN")

        let points = TeamLeaderboard.entries(for: MatchSnapshot(match: teamMatch(.fourBall, scoring: .stableford, teams: [[a, b], [c, d]]), participants: players))
        XCTAssertEqual(points[0].points, 19, "eight pars and a birdie")
        XCTAssertEqual(points[0].statusText, "19 pts")
        XCTAssertEqual(points[1].points, 17)
    }

    func testOneBallFormatsUseTheLatestEntryAndTeamAllowances() {
        let early = Date(timeIntervalSince1970: 100), late = Date(timeIntervalSince1970: 200)
        let a = scored(player("Ann", index: 10), [5], updatedAt: early)
        let b = scored(player("Ben", index: 20), [4], updatedAt: late)
        XCTAssertEqual(TeamLeaderboard.teamBallScore(for: 1, members: [a, b])?.strokes, 4, "the most recent entry wins")

        XCTAssertEqual(TeamHandicap.oneBallWeights(format: .scramble, teamSize: 2), [0.35, 0.15])
        XCTAssertEqual(TeamHandicap.oneBallWeights(format: .scramble, teamSize: 4), [0.25, 0.2, 0.15, 0.1])
        XCTAssertEqual(TeamHandicap.oneBallWeights(format: .alternateShot, teamSize: 2), [0.5, 0.5])
        XCTAssertEqual(TeamHandicap.oneBallWeights(format: .chapman, teamSize: 2), [0.6, 0.4])
        XCTAssertEqual(TeamHandicap.ownBallAllowance(format: .bestBall, scoring: .strokePlay), 0.75)

        let c = player("Cat", index: 4), d = player("Dan", index: 6)
        let course = testCourse(holes: 18)
        let scramble = teamMatch(.scramble, teams: [[a, b], [c, d]], course: course, handicaps: true)
        // Course handicaps 10 and 20: 35% of 10 + 15% of 20 = 6.5, rounded to 7.
        XCTAssertEqual(TeamHandicap.teamHandicaps(in: scramble, participants: [a, b, c, d])[scramble.teams[0].id], 7)
        let foursomes = teamMatch(.alternateShot, teams: [[a, b], [c, d]], course: course, handicaps: true)
        XCTAssertEqual(TeamHandicap.teamHandicaps(in: foursomes, participants: [a, b, c, d])[foursomes.teams[0].id], 15)
        // Chapman: 60% of the lower course handicap and 40% of the higher: 6 + 8.
        let chapman = teamMatch(.chapman, teams: [[a, b], [c, d]], course: course, handicaps: true)
        XCTAssertEqual(TeamHandicap.teamHandicaps(in: chapman, participants: [a, b, c, d])[chapman.teams[0].id], 14)
        // Four-ball stroke play gives 85%; match play 90% off the lowest.
        let fourball = teamMatch(.fourBall, teams: [[a, b], [c, d]], course: course, handicaps: true)
        XCTAssertEqual(TeamHandicap.playerHandicaps(in: fourball, participants: [a, b, c, d])[b.id], 17)
        var fourballMatch = fourball
        fourballMatch.format = .matchPlay
        let off = TeamHandicap.playerHandicaps(in: fourballMatch, participants: [a, b, c, d])
        XCTAssertEqual(off[c.id], 0)
        XCTAssertEqual(off[b.id], 14, "18 strokes at 90%, less Cat's 4")

        // A scramble team scores from its single ball.
        let entries = TeamLeaderboard.entries(for: MatchSnapshot(match: scramble, participants: [a, b, scored(c, [3]), d]))
        XCTAssertEqual(entries.first { $0.team.name == "Blue" }?.holeScores[1], 4)
    }

    func testBuildingTeams() {
        let players = [player("Ann", index: 2), player("Ben", index: 10), player("Cat", index: 18), player("Dan", index: 30)]
        let teams = TeamBuilder.balanced(players, into: Team.defaults(count: 2))
        XCTAssertEqual(teams[0].memberIDs, [players[0].id, players[3].id], "best and weakest together")
        XCTAssertEqual(teams[1].memberIDs, [players[1].id, players[2].id])

        let late = player("Eve")
        let placed = TeamBuilder.placingNewPlayers([players[0], players[1], players[3], late], in: [teams[0], Team(name: "Red", colorIndex: 1, memberIDs: [players[1].id])])
        XCTAssertEqual(placed[1].memberIDs, [players[1].id, late.id], "newcomers join the smallest team")
        XCTAssertEqual(placed[0].memberIDs.count, 2)

        let moved = TeamBuilder.moving(players[0].id, to: teams[1].id, in: teams)
        XCTAssertFalse(moved[0].memberIDs.contains(players[0].id))
        XCTAssertTrue(moved[1].memberIDs.contains(players[0].id))
    }

    func testMatchesSavedBeforeTeamsStillDecode() throws {
        let match = Match(code: "BCDF", hostID: UUID(), name: "Old", course: testCourse())
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(match)) as! [String: Any]
        json.removeValue(forKey: "teams")
        json.removeValue(forKey: "teamFormat")
        let decoded = try JSONDecoder().decode(Match.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(decoded.id, match.id)
        XCTAssertTrue(decoded.teams.isEmpty)
        XCTAssertFalse(decoded.isTeamGame)
    }
}

final class TrophyCabinetTests: XCTestCase {
    private func entrant(_ name: String) -> TournamentEntrant {
        TournamentEntrant(id: UUID(), name: name, avatar: Avatar(emoji: "🦊", colorIndex: 0))
    }

    private func card(_ e: TournamentEntrant, _ strokes: [Int]) -> Participant {
        var p = Participant(id: e.id, name: e.name, avatar: e.avatar)
        for (i, s) in strokes.enumerated() { p.setScore(HoleScore(holeNumber: i + 1, strokes: s)) }
        return p
    }

    private func event(_ name: String, status: TournamentStatus, entrants: [TournamentEntrant], cards: [Participant], finishedAt: Date) -> TournamentSnapshot {
        let course = testCourse(holes: 9)
        let match = Match(code: "BCDF", hostID: entrants[0].id, name: name, course: course,
                          status: status == .finished ? .finished : .live, startedAt: finishedAt.addingTimeInterval(-3600),
                          finishedAt: status == .finished ? finishedAt : nil, roundNumber: 1)
        let tournament = Tournament(code: "LMNP", name: name, hostID: entrants[0].id, useHandicaps: false,
                                    rounds: [TournamentRound(number: 1, course: course, matchID: match.id, status: match.status)],
                                    status: status)
        return TournamentSnapshot(tournament: tournament, entrants: entrants, rounds: [1: MatchSnapshot(match: match, participants: cards)])
    }

    func testTrophiesFollowFinishingPositions() {
        let ann = entrant("Ann"), ben = entrant("Ben"), cat = entrant("Cat"), dan = entrant("Dan"), eve = entrant("Eve")
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        let par = [4, 4, 3, 5, 4, 4, 3, 4, 5]
        let finished = event("Club Champs", status: .finished, entrants: [ann, ben, cat, dan, eve], cards: [
            card(ann, par.map { $0 + 1 }),   // +9
            card(ben, par),                  // E, wins
            card(cat, par.map { $0 + 2 }),   // +18
            card(dan, par.map { $0 + 3 }),   // +27
            // Eve entered but never played.
        ], finishedAt: base)
        let live = event("Midweek Medal", status: .inProgress, entrants: [ann, ben], cards: [card(ann, [4, 4]), card(ben, [5])], finishedAt: base.addingTimeInterval(86_400))

        let annCabinet = TrophyCabinet.build(for: ann.id, from: [finished, live])
        XCTAssertEqual(annCabinet.eventsEntered, 2)
        XCTAssertEqual(annCabinet.entries.first?.name, "Midweek Medal", "most recent first")
        XCTAssertNil(annCabinet.inProgress.first?.trophy)
        XCTAssertEqual(annCabinet.finished.first?.trophy, .runnerUp)
        XCTAssertEqual(annCabinet.finished.first?.leaderName, "Ben")
        XCTAssertEqual(annCabinet.finished.first?.fieldSize, 4)
        XCTAssertEqual(annCabinet.podiums, 1)
        XCTAssertEqual(annCabinet.titles, 0)

        let benCabinet = TrophyCabinet.build(for: ben.id, from: [finished])
        XCTAssertEqual(benCabinet.titles, 1)
        XCTAssertNil(benCabinet.entries.first?.leaderName)
        XCTAssertEqual(benCabinet.bestFinish?.position, 1)

        XCTAssertEqual(TrophyCabinet.build(for: cat.id, from: [finished]).entries.first?.trophy, .thirdPlace)
        XCTAssertEqual(TrophyCabinet.build(for: dan.id, from: [finished]).entries.first?.trophy, .finisher)
        let eveEntry = TrophyCabinet.build(for: eve.id, from: [finished]).entries.first
        XCTAssertEqual(eveEntry?.trophy, .entered)
        XCTAssertNil(eveEntry?.position)
        XCTAssertNil(TrophyCabinet.build(for: eve.id, from: [finished]).bestFinish)

        // Someone who isn't in an event has nothing from it.
        XCTAssertTrue(TrophyCabinet.build(for: UUID(), from: [finished, live]).isEmpty)

        // Winning a field of one isn't a title.
        let solo = event("Solo Cup", status: .finished, entrants: [ann, ben], cards: [card(ann, par)], finishedAt: base)
        XCTAssertEqual(TrophyCabinet.build(for: ann.id, from: [solo]).entries.first?.trophy, .finisher)
    }
}

final class InMemoryMatchServiceTests: XCTestCase {
    final class Clock: @unchecked Sendable {
        private let lock = NSLock()
        private var value = Date(timeIntervalSince1970: 1_800_000_000)
        func now() -> Date { lock.lock(); defer { lock.unlock() }; return value }
        func advance(_ seconds: TimeInterval) { lock.lock(); value += seconds; lock.unlock() }
    }

    func testFriendsJoinLobbyThenPlayAlongWithoutRunningAway() async throws {
        let clock = Clock()
        let service = InMemoryMatchService(botJoinDelays: [2, 4, 6], secondsPerHole: 10, now: { clock.now() })
        let me = Participant(id: UUID(), name: "Me", avatar: Avatar(emoji: "⛳️", colorIndex: 0), handicapIndex: 10)
        let match = Match(code: "BCDF", hostID: me.id, name: "Demo", course: DemoData.golfCourse, createdAt: clock.now())

        var snapshot = try await service.createMatch(match, host: me)
        XCTAssertEqual(snapshot.participants.count, 1)

        clock.advance(4.5)
        snapshot = try await service.snapshot(matchID: match.id)
        XCTAssertEqual(snapshot.participants.count, 3, "two friends join after 4.5s")

        // Joining by code works for another human too.
        let guest = Participant(id: UUID(), name: "Guest", avatar: Avatar(emoji: "🐸", colorIndex: 2))
        snapshot = try await service.joinMatch(code: "bcdf", as: guest)
        XCTAssertTrue(snapshot.participants.contains { $0.id == guest.id })

        var live = snapshot.match
        live.status = .live
        live.startedAt = clock.now()
        try await service.updateMatch(live)

        clock.advance(500)
        snapshot = try await service.snapshot(matchID: match.id)
        let bots = snapshot.participants.filter(\.isBot)
        XCTAssertFalse(bots.isEmpty)
        // Humans haven't scored, so bots can only finish the first hole.
        XCTAssertTrue(bots.allSatisfy { $0.scores.count == 1 })
        XCTAssertTrue(bots.allSatisfy { $0.currentHole == 2 })
        // Bots record GPS shots on mapped demo holes, so replays work.
        XCTAssertTrue(bots.allSatisfy { !$0.scores[0].shots.isEmpty })

        var meLive = snapshot.participant(me.id)!
        for hole in 1...3 { meLive.setScore(HoleScore(holeNumber: hole, strokes: 4)) }
        try await service.upsertParticipant(meLive, matchID: match.id)
        snapshot = try await service.snapshot(matchID: match.id)
        XCTAssertTrue(snapshot.participants.filter(\.isBot).allSatisfy { $0.scores.count == 4 })
    }

    func testUnknownCodeThrows() async {
        let service = InMemoryMatchService(simulateFriends: false)
        do {
            _ = try await service.joinMatch(code: "ZZZZ", as: Participant(id: UUID(), name: "x", avatar: Avatar(emoji: "x", colorIndex: 0)))
            XCTFail("expected error")
        } catch {
            XCTAssertEqual(error as? MatchServiceError, .codeNotFound("ZZZZ"))
        }
    }

    func testTournamentJoinAndRounds() async throws {
        let service = InMemoryMatchService(simulateFriends: true)
        let host = TournamentEntrant(id: UUID(), name: "Host", avatar: Avatar(emoji: "👑", colorIndex: 0))
        var tournament = Tournament(code: "KLMN", name: "Cup", hostID: host.id, rounds: [TournamentRound(number: 1, course: DemoData.golfCourse)])
        var snapshot = try await service.createTournament(tournament, host: host)
        XCTAssertEqual(snapshot.entrants.count, 4, "host plus three simulated friends")

        let me = TournamentEntrant(id: UUID(), name: "Me", avatar: Avatar(emoji: "🦅", colorIndex: 3))
        snapshot = try await service.joinTournament(code: "klmn", as: me)
        XCTAssertEqual(snapshot.entrants.count, 5)

        let match = Match(code: "PQRS", hostID: host.id, name: "Cup R1", course: DemoData.golfCourse, status: .lobby, tournamentID: tournament.id, roundNumber: 1)
        _ = try await service.createMatch(match, host: Participant(id: host.id, name: host.name, avatar: host.avatar))
        tournament.rounds[0].matchID = match.id
        tournament.rounds[0].status = .lobby
        try await service.updateTournament(tournament)
        snapshot = try await service.tournamentSnapshot(id: tournament.id)
        XCTAssertEqual(snapshot.rounds[1]?.participants.count, 4, "tournament bots join their round immediately")
    }
}
