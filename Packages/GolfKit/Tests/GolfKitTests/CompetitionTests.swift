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
