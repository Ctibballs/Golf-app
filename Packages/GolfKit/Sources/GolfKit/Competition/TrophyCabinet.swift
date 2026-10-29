import Foundation

/// What a player took home from a tournament.
public enum TrophyKind: String, Codable, CaseIterable, Sendable {
    case champion
    case runnerUp
    case thirdPlace
    /// Played and finished outside the top three.
    case finisher
    /// Entered but never hit a shot.
    case entered

    public var displayName: String {
        switch self {
        case .champion: return "Champion"
        case .runnerUp: return "Runner-up"
        case .thirdPlace: return "Third place"
        case .finisher: return "Finisher"
        case .entered: return "Entered"
        }
    }

    public var isPodium: Bool {
        switch self {
        case .champion, .runnerUp, .thirdPlace: return true
        case .finisher, .entered: return false
        }
    }
}

/// One tournament in a player's cabinet.
public struct TrophyCabinetEntry: Identifiable, Hashable, Sendable {
    public var tournamentID: UUID
    public var name: String
    public var gameType: GameType
    public var format: ScoringFormat
    public var useHandicaps: Bool
    /// When the last round finished (or the event was created, if nothing was played).
    public var date: Date
    public var courseNames: [String]
    public var roundCount: Int
    /// Rounds in which the player scored at least one hole.
    public var roundsPlayed: Int
    /// Entrants who scored at least one hole.
    public var fieldSize: Int
    public var position: Int?
    public var positionLabel: String
    /// Total to par, or points for stableford.
    public var resultText: String
    /// The leader's name when it isn't this player.
    public var leaderName: String?
    /// Nil while the tournament is still being played.
    public var trophy: TrophyKind?

    public var id: UUID { tournamentID }
    public var isFinished: Bool { trophy != nil }
}

/// Every tournament a player has entered, with the trophies they won.
public struct TrophyCabinet: Hashable, Sendable {
    public var playerID: UUID
    /// Most recent first.
    public var entries: [TrophyCabinetEntry]

    public init(playerID: UUID, entries: [TrophyCabinetEntry]) {
        self.playerID = playerID
        self.entries = entries
    }

    public var isEmpty: Bool { entries.isEmpty }
    public var finished: [TrophyCabinetEntry] { entries.filter(\.isFinished) }
    public var inProgress: [TrophyCabinetEntry] { entries.filter { !$0.isFinished } }
    public var eventsEntered: Int { entries.count }
    public var titles: Int { count(.champion) }
    public var podiums: Int { entries.filter { $0.trophy?.isPodium == true }.count }

    public func count(_ kind: TrophyKind) -> Int {
        entries.filter { $0.trophy == kind }.count
    }

    /// The highest finish in a completed event, most recent on ties.
    public var bestFinish: TrophyCabinetEntry? {
        finished
            .filter { $0.trophy != .entered && $0.position != nil }
            .min { a, b in
                let pa = a.position ?? .max, pb = b.position ?? .max
                return pa != pb ? pa < pb : a.date > b.date
            }
    }

    /// Builds a cabinet from every tournament this device knows about.
    public static func build(for playerID: UUID, from tournaments: [TournamentSnapshot]) -> TrophyCabinet {
        let entries = tournaments.compactMap { entry(for: playerID, in: $0) }
        return TrophyCabinet(playerID: playerID, entries: entries.sorted { $0.date > $1.date })
    }

    static func entry(for playerID: UUID, in snapshot: TournamentSnapshot) -> TrophyCabinetEntry? {
        let standings = TournamentStandings.compute(snapshot)
        guard let mine = standings.first(where: { $0.entrant.id == playerID }) else { return nil }
        let field = standings.filter { $0.holesPlayed > 0 }
        let tournament = snapshot.tournament
        let leader = field.first

        var courseNames: [String] = []
        for name in tournament.rounds.compactMap(\.course?.name) where !courseNames.contains(name) {
            courseNames.append(name)
        }
        let roundsPlayed = snapshot.rounds.values.filter { round in
            round.participant(playerID).map { !$0.scores.isEmpty } ?? false
        }.count

        return TrophyCabinetEntry(
            tournamentID: tournament.id,
            name: tournament.name,
            gameType: tournament.gameType,
            format: tournament.format,
            useHandicaps: tournament.useHandicaps,
            date: finishDate(snapshot),
            courseNames: courseNames,
            roundCount: tournament.rounds.count,
            roundsPlayed: roundsPlayed,
            fieldSize: field.count,
            position: mine.holesPlayed > 0 ? mine.position : nil,
            positionLabel: mine.positionLabel,
            resultText: mine.statusText,
            leaderName: leader.flatMap { $0.entrant.id == playerID ? nil : $0.entrant.name },
            trophy: tournament.status == .finished ? trophy(for: mine, fieldSize: field.count) : nil
        )
    }

    static func trophy(for standing: TournamentStanding, fieldSize: Int) -> TrophyKind {
        guard standing.holesPlayed > 0 else { return .entered }
        // Winning a field of one isn't a title.
        guard fieldSize > 1 else { return .finisher }
        switch standing.position {
        case 1: return .champion
        case 2: return .runnerUp
        case 3: return .thirdPlace
        default: return .finisher
        }
    }

    static func finishDate(_ snapshot: TournamentSnapshot) -> Date {
        let dates = snapshot.rounds.values.compactMap { $0.match.finishedAt ?? $0.match.startedAt }
        return dates.max() ?? snapshot.tournament.createdAt
    }
}
