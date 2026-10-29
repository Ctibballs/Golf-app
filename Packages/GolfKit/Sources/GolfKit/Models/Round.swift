import Foundation

/// Which holes of a course are being played.
public enum HoleSelection: String, Codable, CaseIterable, Identifiable, Sendable {
    case all
    case front
    case back

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .all: return "All holes"
        case .front: return "Front 9"
        case .back: return "Back 9"
        }
    }

    public func holeNumbers(for course: Course) -> [Int] {
        let numbers = course.holes.map(\.number)
        guard numbers.count >= 18 else { return numbers }
        switch self {
        case .all: return numbers
        case .front: return Array(numbers.prefix(9))
        case .back: return Array(numbers.dropFirst(9).prefix(9))
        }
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
