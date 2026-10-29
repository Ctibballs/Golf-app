import Foundation

/// How a team's score on each hole is made up.
public enum TeamFormat: String, Codable, CaseIterable, Identifiable, Sendable {
    /// Pairs, each playing their own ball; the better score of the two counts.
    case fourBall
    /// Teams of three or four, each playing their own ball; the lowest score counts.
    case bestBall
    /// Own balls; the best two scores on each hole count.
    case bestTwo
    /// Own balls; every score counts.
    case aggregate
    /// Everyone hits, the team plays from the best shot: one team score.
    case scramble
    /// Foursomes: partners take turns hitting one ball.
    case alternateShot
    /// Pinehurst: both drive, swap balls for the second shot, pick one, then alternate.
    case chapman

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .fourBall: return "Four-ball"
        case .bestBall: return "Best ball"
        case .bestTwo: return "Best two"
        case .aggregate: return "Aggregate"
        case .scramble: return "Scramble"
        case .alternateShot: return "Foursomes"
        case .chapman: return "Chapman"
        }
    }

    public var summary: String {
        switch self {
        case .fourBall: return "Pairs play their own balls; the better score counts"
        case .bestBall: return "Teams of three or four; the lowest score counts"
        case .bestTwo: return "Own ball each; the best two scores count"
        case .aggregate: return "Own ball each; every score counts"
        case .scramble: return "Everyone hits and the team plays the best shot"
        case .alternateShot: return "Partners take turns hitting one ball"
        case .chapman: return "Both drive, swap for the second shot, then alternate"
        }
    }

    public var symbolName: String {
        switch self {
        case .fourBall: return "person.2"
        case .bestBall: return "person.3"
        case .bestTwo: return "person.3.sequence"
        case .aggregate: return "sum"
        case .scramble: return "arrow.triangle.merge"
        case .alternateShot: return "arrow.left.arrow.right"
        case .chapman: return "arrow.triangle.swap"
        }
    }

    /// One ball per team, so there is a single team score per hole.
    public var isOneBall: Bool {
        switch self {
        case .scramble, .alternateShot, .chapman: return true
        case .fourBall, .bestBall, .bestTwo, .aggregate: return false
        }
    }

    /// The usual team size, used to suggest how many teams to make.
    public var usualTeamSize: Int {
        switch self {
        case .fourBall, .alternateShot, .chapman: return 2
        case .bestBall, .bestTwo, .scramble, .aggregate: return 4
        }
    }

    /// How many scores count on each hole, for formats where everyone plays their own ball.
    public func countingScores(teamSize: Int) -> Int {
        switch self {
        case .fourBall, .bestBall, .scramble, .alternateShot, .chapman: return 1
        case .bestTwo: return min(2, teamSize)
        case .aggregate: return teamSize
        }
    }
}

public struct Team: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    /// Index into the app's team colours.
    public var colorIndex: Int
    public var memberIDs: [UUID]

    public init(id: UUID = UUID(), name: String, colorIndex: Int, memberIDs: [UUID] = []) {
        self.id = id
        self.name = name
        self.colorIndex = colorIndex
        self.memberIDs = memberIDs
    }

    public static let defaultNames = ["Blue", "Red", "Green", "Gold"]

    /// Two to four empty teams with distinct names and colours.
    public static func defaults(count: Int) -> [Team] {
        (0..<max(2, min(count, defaultNames.count))).map { Team(name: defaultNames[$0], colorIndex: $0) }
    }
}

/// Putting players into teams.
public enum TeamBuilder {
    /// Index assumed for players without a handicap when balancing sides.
    static let unknownIndex = 28.0

    /// Puts anyone not on a team yet onto the smallest team.
    public static func placingNewPlayers(_ participants: [Participant], in teams: [Team]) -> [Team] {
        guard !teams.isEmpty else { return teams }
        var teams = teams
        let placed = Set(teams.flatMap(\.memberIDs))
        for player in participants where !placed.contains(player.id) {
            let smallest = teams.indices.min { teams[$0].memberIDs.count < teams[$1].memberIDs.count } ?? 0
            teams[smallest].memberIDs.append(player.id)
        }
        return teams
    }

    /// Everyone shared out into sides of even strength: a snake draft from the lowest
    /// handicap, so the best player and the weakest end up together.
    public static func balanced(_ participants: [Participant], into teams: [Team]) -> [Team] {
        guard !teams.isEmpty else { return teams }
        var result = teams.map { team -> Team in
            var empty = team
            empty.memberIDs = []
            return empty
        }
        let ordered = participants.sorted {
            ($0.handicapIndex ?? unknownIndex, $0.name) < ($1.handicapIndex ?? unknownIndex, $1.name)
        }
        let count = result.count
        for (i, player) in ordered.enumerated() {
            let lap = i / count, slot = i % count
            result[lap.isMultiple(of: 2) ? slot : count - 1 - slot].memberIDs.append(player.id)
        }
        return result
    }

    /// Moves a player onto another team.
    public static func moving(_ playerID: UUID, to teamID: UUID, in teams: [Team]) -> [Team] {
        teams.map { team in
            var copy = team
            copy.memberIDs.removeAll { $0 == playerID }
            if team.id == teamID { copy.memberIDs.append(playerID) }
            return copy
        }
    }
}

/// Handicap allowances for team formats, following the World Handicap System
/// recommendations.
public enum TeamHandicap {
    /// The share of each player's course handicap used when everyone plays their own ball.
    public static func ownBallAllowance(format: TeamFormat, scoring: ScoringFormat) -> Double {
        switch format {
        case .fourBall: return scoring == .matchPlay ? 0.9 : 0.85
        case .bestBall: return 0.75
        case .bestTwo: return 0.85
        case .aggregate, .scramble, .alternateShot, .chapman: return 1
        }
    }

    /// Shares of the members' course handicaps, lowest handicap first, that make up a
    /// one-ball team's handicap.
    public static func oneBallWeights(format: TeamFormat, teamSize: Int) -> [Double] {
        switch format {
        case .alternateShot:
            return Array(repeating: 0.5, count: teamSize)
        case .chapman:
            return teamSize <= 1 ? [1] : [0.6, 0.4] + Array(repeating: 0, count: teamSize - 2)
        case .scramble:
            switch teamSize {
            case ...1: return [1]
            case 2: return [0.35, 0.15]
            case 3: return [0.3, 0.2, 0.1]
            default: return [0.25, 0.2, 0.15, 0.1] + Array(repeating: 0, count: teamSize - 4)
            }
        case .fourBall, .bestBall, .bestTwo, .aggregate:
            return Array(repeating: 1, count: teamSize)
        }
    }

    /// Strokes each player receives in an own-ball team game, or empty without handicaps.
    /// Match play gives strokes off the lowest handicap in the match.
    public static func playerHandicaps(in match: Match, participants: [Participant]) -> [UUID: Int] {
        guard match.useHandicaps, let format = match.teamFormat, !format.isOneBall else { return [:] }
        let allowance = ownBallAllowance(format: format, scoring: match.format)
        var result: [UUID: Int] = [:]
        for player in participants {
            let course = PlayingHandicap.courseHandicap(for: player, in: match) ?? 0
            result[player.id] = Int((Double(course) * allowance).rounded())
        }
        if match.format == .matchPlay, let lowest = result.values.min() {
            result = result.mapValues { $0 - lowest }
        }
        return result
    }

    /// Strokes each one-ball team receives, keyed by team, or empty without handicaps.
    public static func teamHandicaps(in match: Match, participants: [Participant]) -> [UUID: Int] {
        guard match.useHandicaps, let format = match.teamFormat, format.isOneBall else { return [:] }
        let byID = Dictionary(participants.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var result: [UUID: Int] = [:]
        for team in match.teams {
            let courses = team.memberIDs.compactMap { byID[$0] }
                .map { PlayingHandicap.courseHandicap(for: $0, in: match) ?? 0 }
                .sorted()
            let weights = oneBallWeights(format: format, teamSize: courses.count)
            let total = zip(courses, weights).reduce(0.0) { $0 + Double($1.0) * $1.1 }
            result[team.id] = Int(total.rounded())
        }
        if match.format == .matchPlay, let lowest = result.values.min() {
            result = result.mapValues { $0 - lowest }
        }
        return result
    }
}

public struct TeamLeaderboardEntry: Identifiable, Hashable, Sendable {
    public var team: Team
    public var members: [Participant]
    public var position: Int
    public var positionLabel: String
    /// Holes with a complete team score.
    public var thru: Int
    /// Counting strokes on those holes.
    public var gross: Int
    public var grossToPar: Int
    /// Nil when the match isn't played off handicaps.
    public var netToPar: Int?
    /// Stableford points or holes won, depending on the scoring format.
    public var points: Int?
    /// The headline value: "-3", "E", "71 pts", "2 UP".
    public var statusText: String
    public var isFinished: Bool
    public var currentHole: Int?
    /// The team's gross score on each completed hole: its ball, or its counting scores added up.
    public var holeScores: [Int: Int]

    public var id: UUID { team.id }
}

/// Rankings for team games.
public enum TeamLeaderboard {
    struct HoleResult {
        var gross: Int
        var net: Int
        var points: Int
        /// Par for the counting scores (par times the number that count).
        var par: Int
    }

    /// For one-ball formats any member can enter the team's score; the latest entry wins.
    public static func teamBallScore(for hole: Int, members: [Participant]) -> HoleScore? {
        members
            .compactMap { member in member.score(for: hole).map { (member.updatedAt, $0) } }
            .max { $0.0 < $1.0 }?
            .1
    }

    public static func entries(for snapshot: MatchSnapshot) -> [TeamLeaderboardEntry] {
        let match = snapshot.match
        guard let format = match.teamFormat, match.teams.count >= 2 else { return [] }
        let byID = Dictionary(snapshot.participants.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let playerStrokes = TeamHandicap.playerHandicaps(in: match, participants: snapshot.participants)
        let teamStrokes = TeamHandicap.teamHandicaps(in: match, participants: snapshot.participants)
        let holes = match.holes
        let stableford = match.format == .stableford

        var results: [UUID: [Int: HoleResult]] = [:]
        var entries: [TeamLeaderboardEntry] = []

        for team in match.teams {
            let members = team.memberIDs.compactMap { byID[$0] }
            guard !members.isEmpty else { continue }
            var perHole: [Int: HoleResult] = [:]

            if format.isOneBall {
                let allocation = HandicapCalculator.strokeAllocation(courseHandicap: teamStrokes[team.id] ?? 0, holes: holes)
                for hole in holes {
                    guard let score = teamBallScore(for: hole.number, members: members) else { continue }
                    let net = score.strokes - (allocation[hole.number] ?? 0)
                    let points = Leaderboard.stablefordPoints(strokes: match.useHandicaps ? net : score.strokes, par: hole.par)
                    perHole[hole.number] = HoleResult(gross: score.strokes, net: net, points: points, par: hole.par)
                }
            } else {
                let counting = format.countingScores(teamSize: members.count)
                let allocations = Dictionary(members.map {
                    ($0.id, HandicapCalculator.strokeAllocation(courseHandicap: playerStrokes[$0.id] ?? 0, holes: holes))
                }, uniquingKeysWith: { first, _ in first })
                for hole in holes {
                    let scores = members.compactMap { member in
                        member.score(for: hole.number).map { (gross: $0.strokes, net: $0.strokes - (allocations[member.id]?[hole.number] ?? 0)) }
                    }
                    guard counting > 0, scores.count >= counting else { continue }
                    let gross = scores.map { $0.gross }.sorted().prefix(counting).reduce(0, +)
                    let net = scores.map { $0.net }.sorted().prefix(counting).reduce(0, +)
                    let points = scores
                        .map { Leaderboard.stablefordPoints(strokes: match.useHandicaps ? $0.net : $0.gross, par: hole.par) }
                        .sorted(by: >)
                        .prefix(counting)
                        .reduce(0, +)
                    perHole[hole.number] = HoleResult(gross: gross, net: net, points: points, par: hole.par * counting)
                }
            }

            results[team.id] = perHole
            let completed = perHole.values
            let gross = completed.reduce(0) { $0 + $1.gross }
            let par = completed.reduce(0) { $0 + $1.par }
            let net = completed.reduce(0) { $0 + $1.net }
            entries.append(TeamLeaderboardEntry(
                team: team,
                members: members,
                position: 0,
                positionLabel: "",
                thru: perHole.count,
                gross: gross,
                grossToPar: gross - par,
                netToPar: match.useHandicaps ? net - par : nil,
                points: stableford ? completed.reduce(0) { $0 + $1.points } : nil,
                statusText: "",
                isFinished: perHole.count == holes.count || members.allSatisfy(\.isFinished),
                currentHole: members.compactMap(\.currentHole).max(),
                holeScores: perHole.mapValues(\.gross)
            ))
        }

        // Lower keys rank higher.
        var keys: [UUID: Int] = [:]
        if match.format == .matchPlay && entries.count == 2 {
            let a = entries[0].id, b = entries[1].id
            var lead = 0, played = 0
            for hole in holes {
                guard let ra = results[a]?[hole.number], let rb = results[b]?[hole.number] else { continue }
                played += 1
                let sa = match.useHandicaps ? ra.net : ra.gross
                let sb = match.useHandicaps ? rb.net : rb.gross
                if sa < sb { lead += 1 } else if sb < sa { lead -= 1 }
            }
            let remaining = holes.count - played
            for i in entries.indices {
                let mine = entries[i].id == a ? lead : -lead
                entries[i].points = max(0, mine)
                entries[i].statusText = Leaderboard.matchPlayStatus(lead: mine, remaining: remaining, played: played)
                keys[entries[i].id] = -mine
            }
        } else if stableford {
            for i in entries.indices {
                let points = entries[i].points ?? 0
                entries[i].statusText = entries[i].thru == 0 ? "–" : "\(points) pts"
                keys[entries[i].id] = -points
            }
        } else {
            for i in entries.indices {
                let value = entries[i].netToPar ?? entries[i].grossToPar
                entries[i].statusText = entries[i].thru == 0 ? "–" : Leaderboard.formatToPar(value)
                keys[entries[i].id] = value
            }
        }

        entries.sort { l, r in
            let lk = keys[l.id] ?? 0, rk = keys[r.id] ?? 0
            if (l.thru == 0) != (r.thru == 0) { return r.thru == 0 }
            if lk != rk { return lk < rk }
            if l.thru != r.thru { return l.thru > r.thru }
            return l.team.name < r.team.name
        }

        var i = 0
        while i < entries.count {
            var j = i
            while j + 1 < entries.count,
                  keys[entries[j + 1].id] == keys[entries[i].id],
                  (entries[j + 1].thru == 0) == (entries[i].thru == 0) {
                j += 1
            }
            for k in i...j {
                entries[k].position = i + 1
                entries[k].positionLabel = entries[k].thru == 0 ? "–" : (j > i ? "T\(i + 1)" : "\(i + 1)")
            }
            i = j + 1
        }
        return entries
    }
}
