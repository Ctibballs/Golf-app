import Foundation

public enum TournamentStatus: String, Codable, Sendable {
    case registration
    case inProgress
    case finished
}

public struct TournamentRound: Codable, Hashable, Identifiable, Sendable {
    public var number: Int
    public var course: Course?
    public var tee: TeeSet?
    public var scheduledDate: Date?
    /// The match created when the host starts this round.
    public var matchID: UUID?
    public var matchCode: String?
    public var status: MatchStatus?
    /// The holes this round covers, in playing order; nil plays the whole course from the 1st.
    public var holeNumbers: [Int]?

    public var id: Int { number }

    public init(
        number: Int,
        course: Course? = nil,
        tee: TeeSet? = nil,
        scheduledDate: Date? = nil,
        matchID: UUID? = nil,
        matchCode: String? = nil,
        status: MatchStatus? = nil,
        holeNumbers: [Int]? = nil
    ) {
        self.number = number
        self.course = course
        self.tee = tee
        self.scheduledDate = scheduledDate
        self.matchID = matchID
        self.matchCode = matchCode
        self.status = status
        self.holeNumbers = holeNumbers
    }
}

/// A multi-round event. Each round is played as a `Match` linked back to the tournament.
public struct Tournament: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var code: String
    public var name: String
    public var hostID: UUID
    public var gameType: GameType
    public var format: ScoringFormat
    public var useHandicaps: Bool
    public var rounds: [TournamentRound]
    public var status: TournamentStatus
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        code: String,
        name: String,
        hostID: UUID,
        gameType: GameType = .golf,
        format: ScoringFormat = .strokePlay,
        useHandicaps: Bool = true,
        rounds: [TournamentRound],
        status: TournamentStatus = .registration,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.code = code
        self.name = name
        self.hostID = hostID
        self.gameType = gameType
        self.format = format
        self.useHandicaps = useHandicaps
        self.rounds = rounds
        self.status = status
        self.createdAt = createdAt
    }

    /// The round currently being played, or the next one to start.
    public var currentRound: TournamentRound? {
        rounds.first { $0.status == .live } ?? rounds.first { $0.status != .finished }
    }
}

public struct TournamentEntrant: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var avatar: Avatar
    public var handicapIndex: Double?
    public var joinedAt: Date

    public init(id: UUID, name: String, avatar: Avatar, handicapIndex: Double? = nil, joinedAt: Date = Date()) {
        self.id = id
        self.name = name
        self.avatar = avatar
        self.handicapIndex = handicapIndex
        self.joinedAt = joinedAt
    }

    public init(profile: PlayerProfile, handicapIndex: Double?) {
        self.init(id: profile.id, name: profile.name, avatar: profile.avatar, handicapIndex: handicapIndex)
    }
}

public struct TournamentSnapshot: Codable, Hashable, Identifiable, Sendable {
    public var tournament: Tournament
    public var entrants: [TournamentEntrant]
    /// Snapshots of every round that has started, keyed by round number.
    public var rounds: [Int: MatchSnapshot]

    public var id: UUID { tournament.id }

    public init(tournament: Tournament, entrants: [TournamentEntrant], rounds: [Int: MatchSnapshot] = [:]) {
        self.tournament = tournament
        self.entrants = entrants
        self.rounds = rounds
    }
}
