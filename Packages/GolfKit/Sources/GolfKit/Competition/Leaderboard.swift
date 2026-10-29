import Foundation

public struct LeaderboardEntry: Identifiable, Hashable, Sendable {
    public var participant: Participant
    public var position: Int
    public var positionLabel: String
    /// Holes completed.
    public var thru: Int
    public var gross: Int
    public var grossToPar: Int
    public var courseHandicap: Int?
    public var netToPar: Int?
    /// Stableford points, skins won or holes won, depending on format.
    public var points: Int?
    /// The headline value for the row: "-2", "E", "36 pts", "2 UP", "3 skins".
    public var statusText: String
    public var isFinished: Bool

    public var id: UUID { participant.id }
}

/// Playing handicaps for a match, using WHS for golf and the casual index otherwise.
public enum PlayingHandicap {
    public static func courseHandicap(for participant: Participant, in match: Match) -> Int? {
        guard match.useHandicaps, let index = participant.handicapIndex else { return nil }
        let holes = match.holeNumbers.count
        if match.course.gameType == .golf {
            var rating = match.tee?.courseRating
            if let r = rating, holes <= 9, match.course.holeCount >= 18 { rating = r / 2 }
            return HandicapCalculator.courseHandicap(
                index: index, slope: match.tee?.slopeRating, courseRating: rating,
                par: match.totalPar, holes: holes
            )
        }
        return CasualHandicapCalculator.courseHandicap(index: index, holes: holes)
    }

    public static func strokeAllocation(for participant: Participant, in match: Match) -> [Int: Int] {
        guard let ch = courseHandicap(for: participant, in: match) else { return [:] }
        return HandicapCalculator.strokeAllocation(courseHandicap: ch, holes: match.holes)
    }

    /// Strokes on each hole for everyone in an individual match. In match play the lowest
    /// handicap plays off scratch and the others receive the difference, on the hardest holes.
    public static func allocations(in match: Match, participants: [Participant]) -> [UUID: [Int: Int]] {
        let courseHandicaps = participants.compactMap { p in courseHandicap(for: p, in: match).map { (p.id, $0) } }
        let offset = match.format == .matchPlay ? courseHandicaps.map(\.1).min() ?? 0 : 0
        var result: [UUID: [Int: Int]] = [:]
        for (id, ch) in courseHandicaps {
            result[id] = HandicapCalculator.strokeAllocation(courseHandicap: ch - offset, holes: match.holes)
        }
        return result
    }
}

public enum Leaderboard {
    public static func entries(for snapshot: MatchSnapshot) -> [LeaderboardEntry] {
        let match = snapshot.match
        let players = snapshot.participants
        guard !players.isEmpty else { return [] }

        let allocations = PlayingHandicap.allocations(in: match, participants: players)

        func par(_ hole: Int) -> Int { match.course.hole(hole)?.par ?? 0 }
        func net(_ p: Participant, _ s: HoleScore) -> Int { s.strokes - (allocations[p.id]?[s.holeNumber] ?? 0) }

        var base: [LeaderboardEntry] = players.map { p in
            let scored = p.scores.filter { match.holeNumbers.contains($0.holeNumber) }
            let gross = scored.reduce(0) { $0 + $1.strokes }
            let parPlayed = scored.reduce(0) { $0 + par($1.holeNumber) }
            let received = scored.reduce(0) { $0 + (allocations[p.id]?[$1.holeNumber] ?? 0) }
            let ch = PlayingHandicap.courseHandicap(for: p, in: match)
            return LeaderboardEntry(
                participant: p, position: 0, positionLabel: "", thru: scored.count,
                gross: gross, grossToPar: gross - parPlayed, courseHandicap: ch,
                netToPar: ch == nil ? nil : gross - parPlayed - received,
                points: nil, statusText: "",
                isFinished: p.isFinished || scored.count == match.holeNumbers.count
            )
        }

        // Format-specific scoring. Lower `sortKey` ranks higher.
        var sortKeys: [UUID: Int] = [:]
        switch match.format {
        case .strokePlay:
            for i in base.indices {
                let value = match.useHandicaps ? (base[i].netToPar ?? base[i].grossToPar) : base[i].grossToPar
                sortKeys[base[i].id] = value
                base[i].statusText = base[i].thru == 0 ? "–" : formatToPar(value)
            }

        case .stableford:
            for i in base.indices {
                let p = base[i].participant
                let points = p.scores.filter { match.holeNumbers.contains($0.holeNumber) }.reduce(0) { total, s in
                    let strokes = match.useHandicaps ? net(p, s) : s.strokes
                    return total + stablefordPoints(strokes: strokes, par: par(s.holeNumber))
                }
                base[i].points = points
                base[i].statusText = "\(points) pts"
                sortKeys[base[i].id] = -points
            }

        case .skins:
            let skins = skinsWon(match: match, players: players, netScore: { p, s in match.useHandicaps ? net(p, s) : s.strokes })
            for i in base.indices {
                let won = skins.won[base[i].id] ?? 0
                base[i].points = won
                base[i].statusText = won == 1 ? "1 skin" : "\(won) skins"
                sortKeys[base[i].id] = -won
            }

        case .matchPlay:
            let holesWon = holesWonOutright(match: match, players: players, netScore: { p, s in match.useHandicaps ? net(p, s) : s.strokes })
            if players.count == 2 {
                let a = players[0].id, b = players[1].id
                let diff = (holesWon.won[a] ?? 0) - (holesWon.won[b] ?? 0)
                let remaining = match.holeNumbers.count - holesWon.holesCompared
                for i in base.indices {
                    let mine = base[i].id == a ? diff : -diff
                    base[i].points = holesWon.won[base[i].id] ?? 0
                    base[i].statusText = matchPlayStatus(lead: mine, remaining: remaining, played: holesWon.holesCompared)
                    sortKeys[base[i].id] = -mine
                }
            } else {
                for i in base.indices {
                    let won = holesWon.won[base[i].id] ?? 0
                    base[i].points = won
                    base[i].statusText = won == 1 ? "1 hole" : "\(won) holes"
                    sortKeys[base[i].id] = -won
                }
            }
        }

        // Rank: format key, then more holes played, then name for stability.
        let sorted = base.sorted { l, r in
            let lk = sortKeys[l.id] ?? 0, rk = sortKeys[r.id] ?? 0
            if (l.thru == 0) != (r.thru == 0) { return r.thru == 0 }
            if lk != rk { return lk < rk }
            if l.thru != r.thru { return l.thru > r.thru }
            return l.participant.name < r.participant.name
        }
        return assignPositions(sorted) { sortKeys[$0.id] ?? 0 }
    }

    // MARK: - Formats

    public static func stablefordPoints(strokes: Int, par: Int) -> Int {
        max(0, 2 + par - strokes)
    }

    /// Skins with carry-overs. Only holes every player has finished are decided.
    static func skinsWon(match: Match, players: [Participant], netScore: (Participant, HoleScore) -> Int) -> (won: [UUID: Int], carry: Int) {
        var won: [UUID: Int] = [:]
        var carry = 0
        for hole in match.holeNumbers {
            let results = players.compactMap { p in p.score(for: hole).map { (p.id, netScore(p, $0)) } }
            guard results.count == players.count else { break }
            carry += 1
            let best = results.map(\.1).min()!
            let winners = results.filter { $0.1 == best }
            if winners.count == 1 {
                won[winners[0].0, default: 0] += carry
                carry = 0
            }
        }
        return (won, carry)
    }

    static func holesWonOutright(match: Match, players: [Participant], netScore: (Participant, HoleScore) -> Int) -> (won: [UUID: Int], holesCompared: Int) {
        var won: [UUID: Int] = [:]
        var compared = 0
        for hole in match.holeNumbers {
            let results = players.compactMap { p in p.score(for: hole).map { (p.id, netScore(p, $0)) } }
            guard results.count == players.count else { continue }
            compared += 1
            let best = results.map(\.1).min()!
            let winners = results.filter { $0.1 == best }
            if winners.count == 1 { won[winners[0].0, default: 0] += 1 }
        }
        return (won, compared)
    }

    /// "AS", "2 UP", "1 DN", "3&2", "2 UP" (final) etc.
    public static func matchPlayStatus(lead: Int, remaining: Int, played: Int) -> String {
        if played == 0 { return "–" }
        if lead == 0 { return "AS" }
        if abs(lead) > remaining && remaining > 0 {
            return lead > 0 ? "Won \(lead)&\(remaining)" : "Lost \(-lead)&\(remaining)"
        }
        return lead > 0 ? "\(lead) UP" : "\(-lead) DN"
    }

    public static func formatToPar(_ value: Int) -> String {
        value == 0 ? "E" : (value > 0 ? "+\(value)" : "\(value)")
    }

    static func assignPositions(_ sorted: [LeaderboardEntry], key: (LeaderboardEntry) -> Int) -> [LeaderboardEntry] {
        var result = sorted
        var i = 0
        while i < result.count {
            var j = i
            while j + 1 < result.count,
                  key(result[j + 1]) == key(result[i]),
                  (result[j + 1].thru == 0) == (result[i].thru == 0) {
                j += 1
            }
            let tied = j > i
            for k in i...j {
                result[k].position = i + 1
                result[k].positionLabel = result[k].thru == 0 ? "–" : (tied ? "T\(i + 1)" : "\(i + 1)")
            }
            i = j + 1
        }
        return result
    }
}
