import Foundation

/// Which holes a round covers, in the order they're played: nine or eighteen, from any
/// starting hole. Play wraps round the course, so starting on the 10th of 18 plays 10–18
/// then 1–9 (a shotgun start works the same way).
public struct HolePlan: Hashable, Sendable {
    /// Holes to play; capped at the number the course has.
    public var count: Int
    public var startHole: Int

    public init(count: Int = 18, startHole: Int = 1) {
        self.count = count
        self.startHole = startHole
    }

    public func holeNumbers(for course: Course) -> [Int] {
        let numbers = course.holes.map(\.number)
        guard !numbers.isEmpty else { return [] }
        let start = numbers.firstIndex(of: startHole) ?? 0
        return (0..<min(max(1, count), numbers.count)).map { numbers[(start + $0) % numbers.count] }
    }

    /// "Holes 1–18", "Holes 10–18, 1–9", "Holes 4–12".
    public static func describe(_ holes: [Int]) -> String {
        guard !holes.isEmpty else { return "No holes" }
        var runs: [(Int, Int)] = []
        for hole in holes {
            if let last = runs.last, hole == last.1 + 1 {
                runs[runs.count - 1].1 = hole
            } else {
                runs.append((hole, hole))
            }
        }
        let text = runs.map { $0.0 == $0.1 ? "\($0.0)" : "\($0.0)–\($0.1)" }.joined(separator: ", ")
        return holes.count == 1 ? "Hole \(text)" : "Holes \(text)"
    }
}

/// One player's round. Rounds are the source of truth for stats and handicaps.
public struct Round: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var playerID: UUID
    public var playerName: String
    public var course: Course
    public var tee: TeeSet?
    public var holeNumbers: [Int]
    public var date: Date
    public var scores: [HoleScore]
    public var isComplete: Bool
    /// Handicap index when the round started, used for net scoring and ESC adjustments.
    public var handicapIndex: Double?
    public var matchID: UUID?
    public var tournamentID: UUID?
    public var notes: String?
    public var weatherSummary: String?
    /// Players can exclude casual rounds (scrambles, practice) from their handicap.
    public var countsForHandicap: Bool
    /// Set when the round was played as part of a team game.
    public var teamFormat: TeamFormat?

    public init(
        id: UUID = UUID(),
        playerID: UUID,
        playerName: String,
        course: Course,
        tee: TeeSet? = nil,
        holeNumbers: [Int]? = nil,
        date: Date = Date(),
        scores: [HoleScore] = [],
        isComplete: Bool = false,
        handicapIndex: Double? = nil,
        matchID: UUID? = nil,
        tournamentID: UUID? = nil,
        notes: String? = nil,
        weatherSummary: String? = nil,
        countsForHandicap: Bool = true,
        teamFormat: TeamFormat? = nil
    ) {
        self.id = id
        self.playerID = playerID
        self.playerName = playerName
        self.course = course
        self.tee = tee
        self.holeNumbers = holeNumbers ?? course.holes.map(\.number)
        self.date = date
        self.scores = scores
        self.isComplete = isComplete
        self.handicapIndex = handicapIndex
        self.matchID = matchID
        self.tournamentID = tournamentID
        self.notes = notes
        self.weatherSummary = weatherSummary
        self.countsForHandicap = countsForHandicap
        self.teamFormat = teamFormat
    }

    /// Scramble and foursomes cards hold a team score, so they stay out of personal stats.
    public var isTeamBallRound: Bool { teamFormat?.isOneBall == true }

    public var gameType: GameType { course.gameType }

    public var holes: [HoleInfo] {
        holeNumbers.compactMap { course.hole($0) }
    }

    public func score(for hole: Int) -> HoleScore? {
        scores.first { $0.holeNumber == hole }
    }

    public mutating func setScore(_ score: HoleScore) {
        if let index = scores.firstIndex(where: { $0.holeNumber == score.holeNumber }) {
            scores[index] = score
        } else {
            scores.append(score)
            scores.sort { (holeNumbers.firstIndex(of: $0.holeNumber) ?? $0.holeNumber) < (holeNumbers.firstIndex(of: $1.holeNumber) ?? $1.holeNumber) }
        }
    }

    public var holesPlayed: Int { scores.count }
    public var totalStrokes: Int { scores.reduce(0) { $0 + $1.strokes } }

    /// Par of the holes played so far.
    public var parPlayed: Int {
        course.par(for: scores.map(\.holeNumber))
    }

    /// Par of all holes in this round.
    public var totalPar: Int { course.par(for: holeNumbers) }

    public var toPar: Int { totalStrokes - parPlayed }

    public var totalPutts: Int? {
        let putts = scores.compactMap(\.putts)
        return putts.count == scores.count && !putts.isEmpty ? putts.reduce(0, +) : nil
    }

    public var isNineHoles: Bool { holeNumbers.count <= 9 }

    /// The first hole without a score, or nil when every hole is done.
    public var nextHoleToPlay: Int? {
        holeNumbers.first { hole in !scores.contains { $0.holeNumber == hole } }
    }

    public var hasShotData: Bool { scores.contains { !$0.shots.isEmpty } }
}
