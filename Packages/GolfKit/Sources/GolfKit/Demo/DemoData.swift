import Foundation

/// Bundled sample courses, layouts and friends so the whole app (maps, replays, matches,
/// stats) can be explored offline and in the simulator.
public enum DemoData {
    /// Marks generated sample rounds so they can be removed again.
    public static let sampleMarker = "Sample round"
    public static let golfCourseID = "demo-willow-creek"
    public static let pitchAndPuttID = "demo-lakeside-pitch-putt"
    public static let miniGolfID = "demo-pirate-cove"

    static let golfCenter = GeoPoint(latitude: 51.4450, longitude: -0.2745)
    static let pitchCenter = GeoPoint(latitude: 51.4570, longitude: -0.2490)

    // MARK: - Courses

    static let golfPars = [4, 4, 3, 5, 4, 4, 3, 4, 5, 4, 3, 5, 4, 4, 4, 3, 5, 4]
    static let golfLengths: [Double] = [355, 372, 158, 468, 341, 389, 142, 330, 482, 366, 171, 455, 318, 402, 348, 186, 471, 379]
    static let golfStrokeIndex = [7, 3, 15, 11, 13, 1, 17, 9, 5, 4, 16, 8, 14, 2, 10, 18, 6, 12]

    public static let golfLayout: CourseLayout = generateLayout(
        center: golfCenter, pars: golfPars, lengths: golfLengths, holesPerLoop: 9, turn: 40, gap: 35, greenRadius: 15
    )

    public static let golfCourse: Course = {
        let tees = [
            TeeSet(id: "blue", name: "Blue", colorHex: "#1E6BFF", gender: "M", courseRating: 72.4, slopeRating: 131, par: 72),
            TeeSet(id: "white", name: "White", colorHex: "#F2F2F7", gender: "M", courseRating: 70.6, slopeRating: 125, par: 72),
            TeeSet(id: "red", name: "Red", colorHex: "#FF3B30", gender: "F", courseRating: 72.9, slopeRating: 127, par: 72),
        ]
        let factors = ["blue": 1.0, "white": 0.93, "red": 0.82]
        let holes = golfPars.indices.map { i in
            HoleInfo(
                number: i + 1, par: golfPars[i], strokeIndex: golfStrokeIndex[i],
                lengths: factors.mapValues { (golfLengths[i] * $0).rounded() }
            )
        }
        var withTotals = tees
        for i in withTotals.indices {
            withTotals[i].totalLength = holes.compactMap { $0.lengths[withTotals[i].id] }.reduce(0, +)
        }
        return Course(
            id: golfCourseID, name: "Willow Creek Golf Club", city: "Demo Valley", country: "Sample",
            location: golfCenter, gameType: .golf, holes: holes, tees: withTotals, source: .demo,
            accessType: "public", architect: "Fairway Studios", yearBuilt: 1998
        )
    }()

    static let pitchLengths: [Double] = [62, 48, 75, 55, 88, 41, 70, 66, 52, 80, 45, 73, 58, 84, 50, 68, 77, 60]

    public static let pitchAndPuttLayout: CourseLayout = generateLayout(
        center: pitchCenter, pars: Array(repeating: 3, count: 18), lengths: pitchLengths,
        holesPerLoop: 18, turn: 20, gap: 14, greenRadius: 9
    )

    public static let pitchAndPuttCourse: Course = {
        let holes = pitchLengths.indices.map { i in
            HoleInfo(number: i + 1, par: 3, strokeIndex: nil, lengths: ["main": pitchLengths[i]])
        }
        return Course(
            id: pitchAndPuttID, name: "Lakeside Pitch & Putt", city: "Demo Valley", country: "Sample",
            location: pitchCenter, gameType: .pitchAndPutt, holes: holes,
            tees: [TeeSet(id: "main", name: "Main", colorHex: "#34C759", totalLength: pitchLengths.reduce(0, +), par: 54)],
            source: .demo
        )
    }()

    public static let miniGolfCourse: Course = {
        var course = Course.custom(
            name: "Pirate Cove Adventure Golf",
            gameType: .miniGolf,
            pars: [2, 3, 2, 2, 3, 2, 3, 2, 2, 3, 2, 2, 3, 2, 2, 3, 2, 4],
            location: GeoPoint(latitude: 51.4601, longitude: -0.2531),
            id: miniGolfID
        )
        course.source = .demo
        course.city = "Demo Valley"
        course.country = "Sample"
        return course
    }()

    public static let courses: [Course] = [golfCourse, pitchAndPuttCourse, miniGolfCourse]

    public static func layout(forCourseID id: String) -> CourseLayout? {
        switch id {
        case golfCourseID: return golfLayout
        case pitchAndPuttID: return pitchAndPuttLayout
        default: return nil
        }
    }

    // MARK: - Friends

    public static let friends: [Participant] = [
        Participant(id: UUID(uuidString: "0A1E0000-0000-4000-8000-00000000A1E0")!, name: "Alex", avatar: Avatar(emoji: "🦊", colorIndex: 1), handicapIndex: 8.4, isBot: true),
        Participant(id: UUID(uuidString: "0A1E0000-0000-4000-8000-0000000005A0")!, name: "Sam", avatar: Avatar(emoji: "🐻", colorIndex: 3), handicapIndex: 14.2, isBot: true),
        Participant(id: UUID(uuidString: "0A1E0000-0000-4000-8000-000000000D0A")!, name: "Jordan", avatar: Avatar(emoji: "🦄", colorIndex: 5), handicapIndex: 21.5, isBot: true),
        Participant(id: UUID(uuidString: "0A1E0000-0000-4000-8000-0000000071E0")!, name: "Riley", avatar: Avatar(emoji: "🚀", colorIndex: 6), handicapIndex: 4.1, isBot: true),
    ]

    // MARK: - Sample history

    /// A few months of rounds, matches and tournaments so stats screens have something to show.
    public static func sampleHistory(for profile: PlayerProfile, handicap: Double = 13.5, now: Date = Date()) -> (rounds: [Round], matches: [MatchRecord], tournaments: [TournamentSnapshot]) {
        var rounds: [Round] = []
        var matches: [MatchRecord] = []
        var tournaments: [TournamentSnapshot] = []
        let day: TimeInterval = 86_400

        func play(_ participant: Participant, course: Course, holes: [Int], tee: TeeSet?, date: Date, salt: Int) -> [HoleScore] {
            let layout = layout(forCourseID: course.id)
            return holes.compactMap { n in
                course.hole(n).map {
                    BotGolfer.holeScore(
                        playerID: participant.id, handicap: participant.handicapIndex, hole: $0,
                        gameType: course.gameType, layout: layout?.hole(n), salt: salt,
                        startTime: date.addingTimeInterval(Double(n) * 720)
                    )
                }
            }
        }

        let me = Participant(id: profile.id, name: profile.name, avatar: profile.avatar, handicapIndex: handicap)
        let golfTee = golfCourse.tees.first { $0.id == "white" }

        // Solo golf rounds, some nine-hole.
        for (i, daysAgo) in [78, 64, 55, 47, 40, 33, 26, 19, 12, 6].enumerated() {
            let date = now.addingTimeInterval(-Double(daysAgo) * day + 9 * 3600)
            let holes = i % 4 == 3 ? Array(1...9) : Array(1...18)
            let scores = play(me, course: golfCourse, holes: holes, tee: golfTee, date: date, salt: i)
            rounds.append(Round(
                playerID: profile.id, playerName: profile.name, course: golfCourse, tee: golfTee,
                holeNumbers: holes, date: date, scores: scores, isComplete: true, handicapIndex: handicap,
                weatherSummary: ["Clear, 19°C, wind 9 km/h", "Partly cloudy, 16°C, wind 14 km/h", "Overcast, 13°C, wind 21 km/h"][i % 3]
            ))
        }

        // Matches with friends.
        for (i, daysAgo) in [70, 50, 29, 9].enumerated() {
            let date = now.addingTimeInterval(-Double(daysAgo) * day + 13 * 3600)
            let group = [me] + Array(friends.dropFirst(i % 2).prefix(2 + i % 2))
            let match = Match(
                code: "DEMO", hostID: profile.id, name: "Saturday Skins #\(i + 1)", course: golfCourse,
                tee: golfTee, format: i % 2 == 0 ? .strokePlay : .stableford, useHandicaps: i % 2 == 1,
                status: .finished, createdAt: date, startedAt: date, finishedAt: date.addingTimeInterval(4.5 * 3600)
            )
            let participants = group.map { p -> Participant in
                var copy = p
                copy.scores = play(p, course: golfCourse, holes: match.holeNumbers, tee: golfTee, date: date, salt: 100 + i)
                copy.isFinished = true
                copy.currentHole = nil
                return copy
            }
            matches.append(MatchRecord(snapshot: MatchSnapshot(match: match, participants: participants), savedAt: match.finishedAt!))
            rounds.append(participants[0].round(in: match))
        }

        // Pitch & putt and mini golf.
        for (i, daysAgo) in [58, 36, 15].enumerated() {
            let date = now.addingTimeInterval(-Double(daysAgo) * day + 17 * 3600)
            rounds.append(Round(
                playerID: profile.id, playerName: profile.name, course: pitchAndPuttCourse, tee: pitchAndPuttCourse.tees.first,
                date: date, scores: play(me, course: pitchAndPuttCourse, holes: Array(1...18), tee: nil, date: date, salt: 200 + i),
                isComplete: true
            ))
        }
        for (i, daysAgo) in [44, 3].enumerated() {
            let date = now.addingTimeInterval(-Double(daysAgo) * day + 19 * 3600)
            let group = [me, friends[1], friends[2]]
            var match = Match(code: "DEMO", hostID: profile.id, name: "Mini golf night", course: miniGolfCourse,
                              status: .finished, createdAt: date, startedAt: date, finishedAt: date.addingTimeInterval(3600))
            match.format = .strokePlay
            let participants = group.map { p -> Participant in
                var copy = p
                copy.scores = play(p, course: miniGolfCourse, holes: match.holeNumbers, tee: nil, date: date, salt: 300 + i)
                copy.isFinished = true
                return copy
            }
            matches.append(MatchRecord(snapshot: MatchSnapshot(match: match, participants: participants), savedAt: date))
            rounds.append(participants[0].round(in: match))
        }

        // A four-ball team match: you and Riley against Alex and Sam.
        do {
            let date = now.addingTimeInterval(-16 * day + 10 * 3600)
            let blue = [me, friends[3]], red = [friends[0], friends[1]]
            let match = Match(
                code: "DEMO", hostID: profile.id, name: "Fourball Friday", course: golfCourse, tee: golfTee,
                format: .strokePlay, useHandicaps: true, status: .finished, createdAt: date, startedAt: date,
                finishedAt: date.addingTimeInterval(4 * 3600), teamFormat: .fourBall,
                teams: [
                    Team(name: "Blue", colorIndex: 0, memberIDs: blue.map(\.id)),
                    Team(name: "Red", colorIndex: 1, memberIDs: red.map(\.id)),
                ]
            )
            let participants = (blue + red).map { p -> Participant in
                var copy = p
                copy.scores = play(p, course: golfCourse, holes: match.holeNumbers, tee: golfTee, date: date, salt: 500)
                copy.isFinished = true
                copy.currentHole = nil
                return copy
            }
            matches.append(MatchRecord(snapshot: MatchSnapshot(match: match, participants: participants), savedAt: date.addingTimeInterval(4 * 3600)))
            rounds.append(participants[0].round(in: match))
        }

        // Tournaments with a spread of finishes, so the trophy cabinet has a bit of everything.
        let events: [SampleTournament] = [
            SampleTournament(name: "Spring Classic", course: golfCourse, tee: golfTee, format: .strokePlay, useHandicaps: true,
                             field: [0, 1, 2], daysAgo: [86, 85], finish: 1),
            SampleTournament(name: "Summer Medal", course: golfCourse, tee: golfTee, format: .strokePlay, useHandicaps: false,
                             field: [3, 0, 1], daysAgo: [62, 61], finish: 2),
            SampleTournament(name: "Pirate Cove Cup", course: miniGolfCourse, tee: nil, format: .strokePlay, useHandicaps: false,
                             field: [1, 2, 0], daysAgo: [23], finish: 3),
            SampleTournament(name: "Autumn Stableford", course: golfCourse, tee: golfTee, format: .stableford, useHandicaps: true,
                             field: [0, 1, 2, 3], daysAgo: [8], finish: 4),
        ]
        for (i, event) in events.enumerated() {
            let built = sampleTournament(event, me: me, now: now, salt: 400 + i * 10)
            tournaments.append(built.snapshot)
            rounds += built.myRounds
        }

        for i in rounds.indices { rounds[i].notes = sampleMarker }
        return (rounds.sorted { $0.date > $1.date }, matches.sorted { $0.savedAt > $1.savedAt }, tournaments.sorted { $0.tournament.createdAt > $1.tournament.createdAt })
    }

    struct SampleTournament {
        var name: String
        var course: Course
        var tee: TeeSet?
        var format: ScoringFormat
        var useHandicaps: Bool
        /// Indexes into `friends`.
        var field: [Int]
        var daysAgo: [Double]
        /// Where the player should finish.
        var finish: Int
    }

    /// Plays out a finished tournament with bots, then nudges the player's scores until
    /// they finish where the sample wants them.
    static func sampleTournament(_ event: SampleTournament, me: Participant, now: Date, salt: Int) -> (snapshot: TournamentSnapshot, myRounds: [Round]) {
        let day: TimeInterval = 86_400
        let tournamentID = UUID()
        let players = [me] + event.field.map { friends[$0] }
        let entrants = players.map { TournamentEntrant(id: $0.id, name: $0.name, avatar: $0.avatar, handicapIndex: $0.handicapIndex) }

        var matches: [Match] = []
        var cards: [[Participant]] = []
        for (n, daysAgo) in event.daysAgo.enumerated() {
            let date = now.addingTimeInterval(-daysAgo * day + 9 * 3600)
            let match = Match(
                code: "DEMO", hostID: me.id, name: "\(event.name) · Round \(n + 1)", course: event.course, tee: event.tee,
                format: event.format, useHandicaps: event.useHandicaps, status: .finished,
                createdAt: date, startedAt: date, finishedAt: date.addingTimeInterval(4.5 * 3600),
                tournamentID: tournamentID, roundNumber: n + 1
            )
            matches.append(match)
            cards.append(players.map { player in
                var card = player
                card.scores = match.holeNumbers.compactMap { number in
                    event.course.hole(number).map {
                        BotGolfer.holeScore(playerID: player.id, handicap: player.handicapIndex, hole: $0, gameType: event.course.gameType,
                                            layout: nil, salt: salt + n, startTime: date.addingTimeInterval(Double(number) * 720))
                    }
                }
                card.isFinished = true
                card.currentHole = nil
                return card
            })
        }

        let firstDate = matches.first?.createdAt ?? now
        let tournament = Tournament(
            id: tournamentID, code: "DEMO", name: event.name, hostID: me.id, gameType: event.course.gameType,
            format: event.format, useHandicaps: event.useHandicaps,
            rounds: matches.enumerated().map { n, match in
                TournamentRound(number: n + 1, course: event.course, tee: event.tee, scheduledDate: match.createdAt,
                                matchID: match.id, matchCode: match.code, status: .finished)
            },
            status: .finished, createdAt: firstDate.addingTimeInterval(-3 * day)
        )

        func snapshot() -> TournamentSnapshot {
            var rounds: [Int: MatchSnapshot] = [:]
            for (n, match) in matches.enumerated() {
                rounds[n + 1] = MatchSnapshot(match: match, participants: cards[n])
            }
            return TournamentSnapshot(tournament: tournament, entrants: entrants, rounds: rounds)
        }

        // Rank key for a standing, lower is better (the same rule the standings use).
        func key(_ s: TournamentStanding) -> Int {
            if event.format == .stableford { return -(s.points ?? 0) }
            return event.useHandicaps ? (s.totalNetToPar ?? s.totalToPar) : s.totalToPar
        }

        // Space the bots at least two strokes apart so the player can finish outright in
        // any position, rather than tied.
        for step in 0..<120 {
            let others = TournamentStandings.compute(snapshot()).filter { $0.entrant.id != me.id }
            guard let crowded = others.indices.dropFirst().first(where: { key(others[$0]) - key(others[$0 - 1]) < 2 }),
                  let index = players.firstIndex(where: { $0.id == others[crowded].entrant.id }) else { break }
            let round = step % cards.count
            cards[round][index] = nudged(cards[round][index], course: event.course, better: false)
        }
        // Then move the player a stroke at a time until they land in the right place, alone.
        for step in 0..<200 {
            guard let mine = TournamentStandings.compute(snapshot()).first(where: { $0.entrant.id == me.id }) else { break }
            let tied = mine.positionLabel.hasPrefix("T")
            if mine.position == event.finish && !tied { break }
            let round = step % cards.count
            cards[round][0] = nudged(cards[round][0], course: event.course, better: mine.position > event.finish || (mine.position == event.finish && tied))
        }
        return (snapshot(), matches.enumerated().map { n, match in cards[n][0].round(in: match) })
    }

    /// Takes a stroke off the worst hole, or adds one to the best.
    static func nudged(_ card: Participant, course: Course, better: Bool) -> Participant {
        var card = card
        func toPar(_ score: HoleScore) -> Int { score.strokes - (course.hole(score.holeNumber)?.par ?? 3) }
        let cap = course.gameType.maxStrokesPerHole ?? .max
        let candidates = card.scores.indices.filter { better ? card.scores[$0].strokes > 1 : card.scores[$0].strokes < cap }
        guard let index = better
            ? candidates.max(by: { toPar(card.scores[$0]) < toPar(card.scores[$1]) })
            : candidates.min(by: { toPar(card.scores[$0]) < toPar(card.scores[$1]) })
        else { return card }

        var score = card.scores[index]
        score.strokes += better ? -1 : 1
        if let putts = score.putts { score.putts = min(putts, max(0, score.strokes - 1)) }
        score.penalties = min(score.penalties, max(0, score.strokes - 1 - (score.putts ?? 0)))
        score.sandShots = min(score.sandShots, max(0, score.strokes - 1 - (score.putts ?? 0) - score.penalties))
        card.scores[index] = score
        return card
    }

    // MARK: - Layout generation

    /// Lays holes out in loops that turn a fixed angle per hole, with greens, tees,
    /// fairways, bunkers and the odd pond.
    static func generateLayout(
        center: GeoPoint, pars: [Int], lengths: [Double], holesPerLoop: Int,
        turn: Double, gap: Double, greenRadius: Double
    ) -> CourseLayout {
        var holes: [HoleLayout] = []
        var water: [[GeoPoint]] = []
        let loops = Int((Double(pars.count) / Double(holesPerLoop)).rounded(.up))

        for loop in 0..<loops {
            let startBearing = loop == 0 ? 300.0 : 120.0
            var heading = loop == 0 ? 20.0 : 200.0
            var tee = GeoMath.destination(from: center, bearing: startBearing, distance: 40)

            for i in 0..<holesPerLoop {
                let index = loop * holesPerLoop + i
                guard index < pars.count else { break }
                let number = index + 1
                let par = pars[index], length = lengths[index]

                var path = [tee]
                var green: GeoPoint
                if par == 5 {
                    let bend = GeoMath.destination(from: tee, bearing: heading, distance: length * 0.58)
                    green = GeoMath.destination(from: bend, bearing: heading + 14, distance: length * 0.42)
                    path.append(bend)
                } else {
                    green = GeoMath.destination(from: tee, bearing: heading, distance: length)
                }
                path.append(green)
                let finalBearing = GeoMath.bearing(from: path[path.count - 2], to: green)

                var hole = HoleLayout(number: number, par: par, path: path)
                hole.greens = [ellipse(center: green, along: greenRadius, across: greenRadius * 0.8, bearing: finalBearing)]
                hole.tees = [ellipse(center: GeoMath.destination(from: tee, bearing: heading + 180, distance: 4), along: 8, across: 5, bearing: heading, points: 4)]

                if par >= 4 {
                    hole.fairways = [fairway(along: path, from: 75, to: length - 28, halfWidth: 17)]
                }
                let side = number % 2 == 0 ? 70.0 : -70.0
                hole.bunkers.append(ellipse(center: GeoMath.destination(from: green, bearing: finalBearing + side, distance: greenRadius + 5), along: 7, across: 4, bearing: finalBearing + side))
                if number % 3 == 0 {
                    hole.bunkers.append(ellipse(center: GeoMath.destination(from: green, bearing: finalBearing + 180 - side, distance: greenRadius + 4), along: 6, across: 4, bearing: finalBearing))
                }
                if par >= 4, length > 300, let landing = GeoMath.point(along: path, distance: 215) {
                    hole.bunkers.append(ellipse(center: GeoMath.destination(from: landing, bearing: heading + 90, distance: 21), along: 14, across: 6, bearing: heading))
                }
                if number == 7 || number == 13 || (par == 3 && number % 5 == 0) {
                    let pondCenter = GeoMath.point(along: path, distance: length * 0.55).map {
                        GeoMath.destination(from: $0, bearing: heading - 90, distance: par == 3 ? 6 : 26)
                    } ?? green
                    let pond = ellipse(center: pondCenter, along: par == 3 ? length * 0.22 : 45, across: par == 3 ? 16 : 18, bearing: heading - 15, points: 18)
                    hole.water.append(pond)
                    water.append(pond)
                }
                holes.append(hole)

                // Walk off the green to the next tee, turning for the next hole.
                tee = GeoMath.destination(from: green, bearing: finalBearing + turn + 25, distance: gap)
                heading += turn
            }
        }
        return CourseLayout(holes: holes, water: water, fetchedAt: Date(timeIntervalSince1970: 1_700_000_000))
    }

    static func ellipse(center: GeoPoint, along: Double, across: Double, bearing: Double, points: Int = 20) -> [GeoPoint] {
        (0..<points).map { i in
            let theta = Double(i) / Double(points) * 2 * .pi
            let a = along * cos(theta), c = across * sin(theta)
            return GeoMath.destination(from: center, bearing: bearing + atan2(c, a).degrees, distance: hypot(a, c))
        }
    }

    static func fairway(along path: [GeoPoint], from start: Double, to end: Double, halfWidth: Double) -> [GeoPoint] {
        guard end > start else { return [] }
        var left: [GeoPoint] = [], right: [GeoPoint] = []
        var d = start
        while d <= end {
            guard let p = GeoMath.point(along: path, distance: d),
                  let ahead = GeoMath.point(along: path, distance: min(end + 1, d + 5)) else { break }
            let bearing = GeoMath.bearing(from: p, to: ahead)
            // Gentle width variation so fairways don't look like rulers.
            let width = halfWidth * (0.85 + 0.2 * sin(d / 40))
            left.append(GeoMath.destination(from: p, bearing: bearing - 90, distance: width))
            right.append(GeoMath.destination(from: p, bearing: bearing + 90, distance: width))
            d += 20
        }
        return left + right.reversed()
    }
}
