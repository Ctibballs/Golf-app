import Foundation

public struct TournamentStanding: Identifiable, Hashable, Sendable {
    public var entrant: TournamentEntrant
    public var position: Int
    public var positionLabel: String
    /// Gross strokes per round number (partial while a round is live).
    public var roundStrokes: [Int: Int]
    public var roundToPar: [Int: Int]
    public var totalStrokes: Int
    public var totalToPar: Int
    public var totalNetToPar: Int?
    public var points: Int?
    /// Score to par in the live round.
    public var today: Int?
    /// Holes completed in the live round.
    public var thru: Int?
    public var currentHole: Int?
    public var lastLocation: GeoPoint?
    public var isPlaying: Bool
    public var stats: ScoringStats
    public var holesPlayed: Int
    public var statusText: String

    public var id: UUID { entrant.id }
}

public enum TournamentStandings {
    public static func compute(_ snapshot: TournamentSnapshot) -> [TournamentStanding] {
        let tournament = snapshot.tournament
        let liveRound = tournament.rounds.first { $0.status == .live }?.number

        var standings: [TournamentStanding] = snapshot.entrants.map { entrant in
            var standing = TournamentStanding(
                entrant: entrant, position: 0, positionLabel: "", roundStrokes: [:], roundToPar: [:],
                totalStrokes: 0, totalToPar: 0, totalNetToPar: tournament.useHandicaps ? 0 : nil,
                points: tournament.format == .stableford ? 0 : nil, today: nil, thru: nil,
                currentHole: nil, lastLocation: nil, isPlaying: false, stats: ScoringStats(), holesPlayed: 0, statusText: ""
            )

            for round in tournament.rounds {
                guard let snap = snapshot.rounds[round.number], let p = snap.participant(entrant.id) else { continue }
                let match = snap.match
                let scored = p.scores.filter { match.holeNumbers.contains($0.holeNumber) }
                guard !scored.isEmpty || round.number == liveRound else { continue }
                let allocation = PlayingHandicap.strokeAllocation(for: p, in: match)

                var strokes = 0, par = 0, received = 0, points = 0
                for s in scored {
                    let holePar = match.course.hole(s.holeNumber)?.par ?? 0
                    let given = allocation[s.holeNumber] ?? 0
                    strokes += s.strokes
                    par += holePar
                    received += given
                    points += Leaderboard.stablefordPoints(strokes: tournament.useHandicaps ? s.strokes - given : s.strokes, par: holePar)
                    standing.stats.add(s, par: holePar, gameType: match.course.gameType)
                }
                standing.holesPlayed += scored.count
                standing.roundStrokes[round.number] = strokes
                standing.roundToPar[round.number] = strokes - par
                standing.totalStrokes += strokes
                standing.totalToPar += strokes - par
                if tournament.useHandicaps { standing.totalNetToPar = (standing.totalNetToPar ?? 0) + strokes - par - received }
                if tournament.format == .stableford { standing.points = (standing.points ?? 0) + points }

                if round.number == liveRound {
                    standing.today = scored.isEmpty ? nil : strokes - par
                    standing.thru = scored.count
                    standing.currentHole = p.currentHole
                    standing.lastLocation = p.lastLocation
                    standing.isPlaying = !p.isFinished && scored.count < match.holeNumbers.count
                }
            }
            return standing
        }

        func key(_ s: TournamentStanding) -> Int {
            switch tournament.format {
            case .stableford: return -(s.points ?? 0)
            default: return tournament.useHandicaps ? (s.totalNetToPar ?? s.totalToPar) : s.totalToPar
            }
        }

        for i in standings.indices {
            standings[i].statusText = standings[i].holesPlayed == 0 ? "–" :
                (tournament.format == .stableford ? "\(standings[i].points ?? 0) pts" : Leaderboard.formatToPar(key(standings[i])))
        }

        standings.sort { a, b in
            if (a.holesPlayed == 0) != (b.holesPlayed == 0) { return b.holesPlayed == 0 }
            if key(a) != key(b) { return key(a) < key(b) }
            if a.holesPlayed != b.holesPlayed { return a.holesPlayed > b.holesPlayed }
            return a.entrant.name < b.entrant.name
        }

        var i = 0
        while i < standings.count {
            var j = i
            while j + 1 < standings.count, key(standings[j + 1]) == key(standings[i]),
                  (standings[j + 1].holesPlayed == 0) == (standings[i].holesPlayed == 0) {
                j += 1
            }
            for k in i...j {
                standings[k].position = i + 1
                standings[k].positionLabel = standings[k].holesPlayed == 0 ? "–" : (j > i ? "T\(i + 1)" : "\(i + 1)")
            }
            i = j + 1
        }
        return standings
    }

    /// One entrant's scorecard for a round, if they have played it.
    public static func scorecard(for entrantID: UUID, round: Int, in snapshot: TournamentSnapshot) -> (Match, Participant)? {
        guard let snap = snapshot.rounds[round], let p = snap.participant(entrantID) else { return nil }
        return (snap.match, p)
    }
}
