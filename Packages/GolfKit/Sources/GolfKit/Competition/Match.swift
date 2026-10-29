import Foundation

public enum ScoringFormat: String, Codable, CaseIterable, Identifiable, Sendable {
    case strokePlay
    case stableford
    case matchPlay
    case skins

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .strokePlay: return "Stroke Play"
        case .stableford: return "Stableford"
        case .matchPlay: return "Match Play"
        case .skins: return "Skins"
        }
    }

    public var summary: String {
        switch self {
        case .strokePlay: return "Lowest total score wins"
        case .stableford: return "Points per hole: par = 2, birdie = 3"
        case .matchPlay: return "Win holes head-to-head"
        case .skins: return "Win a hole outright to take the skin"
        }
    }

    public var symbolName: String {
        switch self {
        case .strokePlay: return "list.number"
        case .stableford: return "star.circle"
        case .matchPlay: return "person.2"
        case .skins: return "dollarsign.circle"
        }
    }
}

public enum MatchStatus: String, Codable, Sendable {
    case lobby
    case live
    case finished
}

/// A group round that friends join with a four-letter code.
public struct Match: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var code: String
    public var hostID: UUID
    public var name: String
    public var course: Course
    public var tee: TeeSet?
    public var holeNumbers: [Int]
    public var format: ScoringFormat
    public var useHandicaps: Bool
    public var status: MatchStatus
    public var createdAt: Date
    public var startedAt: Date?
    public var finishedAt: Date?
    public var tournamentID: UUID?
    public var roundNumber: Int?

    public init(
        id: UUID = UUID(),
        code: String,
        hostID: UUID,
        name: String,
        course: Course,
        tee: TeeSet? = nil,
        holeNumbers: [Int]? = nil,
        format: ScoringFormat = .strokePlay,
        useHandicaps: Bool = false,
        status: MatchStatus = .lobby,
        createdAt: Date = Date(),
        startedAt: Date? = nil,
        finishedAt: Date? = nil,
        tournamentID: UUID? = nil,
        roundNumber: Int? = nil
    ) {
        self.id = id
        self.code = code
        self.hostID = hostID
        self.name = name
        self.course = course
        self.tee = tee
        self.holeNumbers = holeNumbers ?? course.holes.map(\.number)
        self.format = format
        self.useHandicaps = useHandicaps
        self.status = status
        self.createdAt = createdAt
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.tournamentID = tournamentID
        self.roundNumber = roundNumber
    }

    public var holes: [HoleInfo] { holeNumbers.compactMap { course.hole($0) } }
    public var totalPar: Int { course.par(for: holeNumbers) }
}

/// One player's live state inside a match. Each participant row is written only by the
/// device that owns it, so syncing never conflicts.
public struct Participant: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var avatar: Avatar
    public var handicapIndex: Double?
    public var scores: [HoleScore]
    /// The hole the player is currently on.
    public var currentHole: Int?
    /// Last known position, shared while playing if the player allows it.
    public var lastLocation: GeoPoint?
    public var updatedAt: Date
    public var isFinished: Bool
    /// The participant whose device scores for this one (guests are scored by the host).
    public var scoredBy: UUID?
    /// Simulated player in offline demo mode.
    public var isBot: Bool

    public init(
        id: UUID,
        name: String,
        avatar: Avatar,
        handicapIndex: Double? = nil,
        scores: [HoleScore] = [],
        currentHole: Int? = nil,
        lastLocation: GeoPoint? = nil,
        updatedAt: Date = Date(),
        isFinished: Bool = false,
        scoredBy: UUID? = nil,
        isBot: Bool = false
    ) {
        self.id = id
        self.name = name
        self.avatar = avatar
        self.handicapIndex = handicapIndex
        self.scores = scores
        self.currentHole = currentHole
        self.lastLocation = lastLocation
        self.updatedAt = updatedAt
        self.isFinished = isFinished
        self.scoredBy = scoredBy
        self.isBot = isBot
    }

    public init(profile: PlayerProfile, handicapIndex: Double?) {
        self.init(id: profile.id, name: profile.name, avatar: profile.avatar, handicapIndex: handicapIndex)
    }

    public var isGuest: Bool { scoredBy != nil && scoredBy != id }

    public func score(for hole: Int) -> HoleScore? {
        scores.first { $0.holeNumber == hole }
    }

    public mutating func setScore(_ score: HoleScore) {
        if let index = scores.firstIndex(where: { $0.holeNumber == score.holeNumber }) {
            scores[index] = score
        } else {
            scores.append(score)
        }
        updatedAt = Date()
    }

    /// Builds a round from this participant's scorecard in `match`.
    public func round(in match: Match) -> Round {
        let ordered = match.holeNumbers.compactMap { score(for: $0) }
        return Round(
            playerID: id,
            playerName: name,
            course: match.course,
            tee: match.tee,
            holeNumbers: match.holeNumbers,
            date: match.startedAt ?? match.createdAt,
            scores: ordered,
            isComplete: ordered.count == match.holeNumbers.count,
            handicapIndex: handicapIndex,
            matchID: match.id,
            tournamentID: match.tournamentID
        )
    }
}

public struct MatchSnapshot: Codable, Hashable, Sendable {
    public var match: Match
    public var participants: [Participant]

    public init(match: Match, participants: [Participant]) {
        self.match = match
        self.participants = participants
    }

    public func participant(_ id: UUID) -> Participant? {
        participants.first { $0.id == id }
    }
}

/// A completed or in-progress match stored on this device. Keeps every player's scorecard
/// so head-to-head stats can be computed later, offline.
public struct MatchRecord: Codable, Hashable, Identifiable, Sendable {
    public var snapshot: MatchSnapshot
    public var savedAt: Date

    public var id: UUID { snapshot.match.id }

    public init(snapshot: MatchSnapshot, savedAt: Date = Date()) {
        self.snapshot = snapshot
        self.savedAt = savedAt
    }
}
