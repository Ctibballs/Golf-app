import Foundation

public enum HeadToHeadOutcome: String, Hashable, Sendable {
    case win, loss, tie
}

public struct HeadToHeadMatch: Hashable, Identifiable, Sendable {
    public var matchID: UUID
    public var date: Date
    public var courseName: String
    public var holesCompared: Int
    public var myStrokes: Int
    public var theirStrokes: Int
    public var myToPar: Int
    public var theirToPar: Int
    public var holesWon: Int
    public var holesLost: Int
    public var outcome: HeadToHeadOutcome

    public var id: UUID { matchID }
}

/// Everything about how you stack up against one friend, from the matches you both played.
public struct HeadToHeadRecord: Hashable, Identifiable, Sendable {
    public var opponentID: UUID
    public var opponentName: String
    public var opponentAvatar: Avatar
    public var matches: [HeadToHeadMatch]
    public var myStats: ScoringStats
    public var theirStats: ScoringStats

    public var id: UUID { opponentID }

    public var wins: Int { matches.filter { $0.outcome == .win }.count }
    public var losses: Int { matches.filter { $0.outcome == .loss }.count }
    public var ties: Int { matches.filter { $0.outcome == .tie }.count }
    public var holesWon: Int { matches.reduce(0) { $0 + $1.holesWon } }
    public var holesLost: Int { matches.reduce(0) { $0 + $1.holesLost } }
    public var holesHalved: Int { matches.reduce(0) { $0 + $1.holesCompared - $1.holesWon - $1.holesLost } }

    /// Average strokes per 18 holes you beat them by (negative means they are better).
    public var averageMarginPer18: Double? {
        let holes = matches.reduce(0) { $0 + $1.holesCompared }
        guard holes > 0 else { return nil }
        let margin = matches.reduce(0) { $0 + ($1.theirStrokes - $1.myStrokes) }
        return Double(margin) * 18 / Double(holes)
    }

    public var recordText: String { "\(wins)–\(losses)–\(ties)" }
}

/// A row in the friends leaderboard: each player's scoring across every shared match.
public struct FriendStanding: Hashable, Identifiable, Sendable {
    public var playerID: UUID
    public var name: String
    public var avatar: Avatar
    public var isMe: Bool
    public var rounds: Int
    public var stats: ScoringStats

    public var id: UUID { playerID }

    public var averageToPar18: Double? {
        stats.averageToParPerHole.map { $0 * 18 }
    }
}

public enum HeadToHeadEngine {
    /// Head-to-head records against every opponent found in the saved matches.
    public static func records(for me: UUID, in history: [MatchRecord]) -> [HeadToHeadRecord] {
        var byOpponent: [UUID: HeadToHeadRecord] = [:]

        // In scramble and foursomes each card holds a team score, not the player's own.
        for record in history.sorted(by: { $0.snapshot.match.createdAt > $1.snapshot.match.createdAt }) where !record.snapshot.match.isOneBallTeamGame {
            let snapshot = record.snapshot
            let match = snapshot.match
            guard let mine = snapshot.participant(me) else { continue }

            for opponent in snapshot.participants where opponent.id != me {
                // Compare only holes both players finished.
                let common = match.holeNumbers.filter { mine.score(for: $0) != nil && opponent.score(for: $0) != nil }
                guard !common.isEmpty else { continue }

                var myStrokes = 0, theirStrokes = 0, won = 0, lost = 0, par = 0
                var myStats = ScoringStats(), theirStats = ScoringStats()
                for hole in common {
                    let a = mine.score(for: hole)!, b = opponent.score(for: hole)!
                    let holePar = match.course.hole(hole)?.par ?? 0
                    myStrokes += a.strokes
                    theirStrokes += b.strokes
                    par += holePar
                    if a.strokes < b.strokes { won += 1 } else if a.strokes > b.strokes { lost += 1 }
                    myStats.add(a, par: holePar, gameType: match.course.gameType)
                    theirStats.add(b, par: holePar, gameType: match.course.gameType)
                }

                let outcome: HeadToHeadOutcome = myStrokes < theirStrokes ? .win : (myStrokes > theirStrokes ? .loss : .tie)
                let result = HeadToHeadMatch(
                    matchID: match.id, date: match.startedAt ?? match.createdAt, courseName: match.course.name,
                    holesCompared: common.count, myStrokes: myStrokes, theirStrokes: theirStrokes,
                    myToPar: myStrokes - par, theirToPar: theirStrokes - par,
                    holesWon: won, holesLost: lost, outcome: outcome
                )

                var entry = byOpponent[opponent.id] ?? HeadToHeadRecord(
                    opponentID: opponent.id, opponentName: opponent.name, opponentAvatar: opponent.avatar,
                    matches: [], myStats: ScoringStats(), theirStats: ScoringStats()
                )
                entry.matches.append(result)
                entry.myStats = StatsEngine.merge(entry.myStats, myStats, gameType: match.course.gameType)
                entry.theirStats = StatsEngine.merge(entry.theirStats, theirStats, gameType: match.course.gameType)
                byOpponent[opponent.id] = entry
            }
        }

        return byOpponent.values.sorted { $0.matches.count > $1.matches.count }
    }

    /// Everyone you've played with, ranked by average score to par per 18 holes.
    public static func friendsLeaderboard(for me: UUID, in history: [MatchRecord], gameType: GameType? = nil) -> [FriendStanding] {
        var standings: [UUID: FriendStanding] = [:]
        for record in history where !record.snapshot.match.isOneBallTeamGame {
            let match = record.snapshot.match
            if let gameType, match.course.gameType != gameType { continue }
            for participant in record.snapshot.participants {
                var stats = ScoringStats()
                for score in participant.scores {
                    guard let par = match.course.hole(score.holeNumber)?.par else { continue }
                    stats.add(score, par: par, gameType: match.course.gameType)
                }
                guard stats.holesPlayed > 0 else { continue }
                var entry = standings[participant.id] ?? FriendStanding(
                    playerID: participant.id, name: participant.name, avatar: participant.avatar,
                    isMe: participant.id == me, rounds: 0, stats: ScoringStats()
                )
                entry.rounds += 1
                entry.stats = StatsEngine.merge(entry.stats, stats, gameType: match.course.gameType)
                standings[participant.id] = entry
            }
        }
        return standings.values.sorted { ($0.averageToPar18 ?? .infinity) < ($1.averageToPar18 ?? .infinity) }
    }
}
