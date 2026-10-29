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

    /// A few months of rounds and matches so stats screens have something to show.
    public static func sampleHistory(for profile: PlayerProfile, handicap: Double = 13.5, now: Date = Date()) -> (rounds: [Round], matches: [MatchRecord]) {
        var rounds: [Round] = []
        var matches: [MatchRecord] = []
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

        for i in rounds.indices { rounds[i].notes = sampleMarker }
        return (rounds.sorted { $0.date > $1.date }, matches.sorted { $0.savedAt > $1.savedAt })
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
