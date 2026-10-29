import Foundation

/// A rate such as 7 of 14 fairways.
public struct Ratio: Hashable, Sendable {
    public var made: Int
    public var attempts: Int

    public init(made: Int = 0, attempts: Int = 0) {
        self.made = made
        self.attempts = attempts
    }

    public var fraction: Double? { attempts > 0 ? Double(made) / Double(attempts) : nil }

    public var percentText: String {
        fraction.map { "\(Int(($0 * 100).rounded()))%" } ?? "—"
    }

    public static func + (lhs: Ratio, rhs: Ratio) -> Ratio {
        Ratio(made: lhs.made + rhs.made, attempts: lhs.attempts + rhs.attempts)
    }
}

/// Stats over any collection of holes: one round, many rounds, or one hole across rounds.
public struct ScoringStats: Hashable, Sendable {
    public var holesPlayed = 0
    public var strokes = 0
    public var par = 0
    public var puttsTotal = 0
    public var holesWithPutts = 0
    public var greensInRegulation = Ratio()
    public var fairways = Ratio()
    public var fairwayMissLeft = 0
    public var fairwayMissRight = 0
    public var scrambling = Ratio()
    public var sandSaves = Ratio()
    public var penalties = 0
    public var onePutts = 0
    public var threePuttsOrWorse = 0
    public var distribution: [ScoreType: Int] = [:]
    /// Total strokes and count per par value, for par-3/4/5 averages.
    public var strokesByPar: [Int: ParTally] = [:]
    public var shotsToGreenTotal = 0

    public init() {}

    public var toPar: Int { strokes - par }

    public var puttsPerHole: Double? {
        holesWithPutts > 0 ? Double(puttsTotal) / Double(holesWithPutts) : nil
    }

    /// Putts scaled to an 18-hole round.
    public var puttsPerRound: Double? { puttsPerHole.map { $0 * 18 } }

    public var averageShotsToGreen: Double? {
        holesWithPutts > 0 ? Double(shotsToGreenTotal) / Double(holesWithPutts) : nil
    }

    /// Average strokes over par per hole.
    public var averageToParPerHole: Double? {
        holesPlayed > 0 ? Double(toPar) / Double(holesPlayed) : nil
    }

    public func averageStrokes(onPar par: Int) -> Double? {
        guard let entry = strokesByPar[par], entry.count > 0 else { return nil }
        return Double(entry.total) / Double(entry.count)
    }

    public func count(_ type: ScoreType) -> Int { distribution[type] ?? 0 }

    public var birdiesOrBetter: Int {
        distribution.filter { $0.key.isUnderPar }.reduce(0) { $0 + $1.value }
    }

    public mutating func add(_ score: HoleScore, par: Int, gameType: GameType) {
        holesPlayed += 1
        strokes += score.strokes
        self.par += par
        penalties += score.penalties
        distribution[score.scoreType(par: par), default: 0] += 1
        strokesByPar[par, default: ParTally()].total += score.strokes
        strokesByPar[par, default: ParTally()].count += 1

        if let putts = score.putts {
            puttsTotal += putts
            holesWithPutts += 1
            shotsToGreenTotal += score.shotsToGreen ?? 0
            if putts == 1 { onePutts += 1 }
            if putts >= 3 { threePuttsOrWorse += 1 }
        }

        if gameType.tracksGreens, let gir = score.greenInRegulation(par: par) {
            greensInRegulation.attempts += 1
            if gir { greensInRegulation.made += 1 }
            if !gir {
                scrambling.attempts += 1
                if score.strokes <= par { scrambling.made += 1 }
            }
        }

        if gameType.tracksFairways, par >= 4, let fairway = score.fairway {
            fairways.attempts += 1
            switch fairway {
            case .hit: fairways.made += 1
            case .left: fairwayMissLeft += 1
            case .right: fairwayMissRight += 1
            }
        }

        if score.sandShots > 0 {
            sandSaves.attempts += 1
            if score.strokes <= par { sandSaves.made += 1 }
        }
    }
}

public struct ParTally: Hashable, Sendable {
    public var total = 0
    public var count = 0
}

public struct ClubDistance: Hashable, Identifiable, Sendable {
    public var club: Club
    public var average: Double
    public var longest: Double
    public var shots: Int

    public var id: Club { club }
}

public struct TrendPoint: Hashable, Identifiable, Sendable {
    public var roundID: UUID
    public var date: Date
    public var strokes: Int
    public var toPar: Int
    /// Over-par scaled to 18 holes, so 9-hole and 18-hole rounds compare.
    public var toPar18: Double
    public var courseName: String

    public var id: UUID { roundID }
}

public struct PlayerStats: Hashable, Sendable {
    public var rounds: Int
    public var scoring: ScoringStats
    /// Average strokes scaled to 18 holes.
    public var scoringAverage: Double?
    public var averageToPar18: Double?
    public var bestRound: Round?
    public var trend: [TrendPoint]
    public var clubDistances: [ClubDistance]
    public var longestDrive: Double?
    public var averageDrive: Double?
}

public struct HoleStats: Hashable, Identifiable, Sendable {
    public var number: Int
    public var par: Int
    public var strokeIndex: Int?
    public var scoring: ScoringStats
    public var best: Int?

    public var id: Int { number }
    public var timesPlayed: Int { scoring.holesPlayed }
    public var averageStrokes: Double? {
        scoring.holesPlayed > 0 ? Double(scoring.strokes) / Double(scoring.holesPlayed) : nil
    }
    public var averageToPar: Double? { averageStrokes.map { $0 - Double(par) } }
}

public struct CourseStats: Hashable, Identifiable, Sendable {
    public var courseID: String
    public var courseName: String
    public var gameType: GameType
    public var rounds: [Round]
    public var holes: [HoleStats]
    public var scoring: ScoringStats

    public var id: String { courseID }
    public var roundsPlayed: Int { rounds.count }

    public var completeRounds: [Round] { rounds.filter(\.isComplete) }

    public var bestRound: Round? {
        completeRounds.min { $0.totalStrokes < $1.totalStrokes }
    }

    public var averageScore: Double? {
        let complete = completeRounds.filter { $0.holeNumbers.count == (rounds.first?.course.holeCount ?? 0) }
        guard !complete.isEmpty else { return nil }
        return Double(complete.reduce(0) { $0 + $1.totalStrokes }) / Double(complete.count)
    }

    /// Holes ordered from hardest to easiest relative to par.
    public var holesByDifficulty: [HoleStats] {
        holes.filter { $0.timesPlayed > 0 }.sorted { ($0.averageToPar ?? 0) > ($1.averageToPar ?? 0) }
    }
}

public enum StatsEngine {
    public static func scoring(for round: Round) -> ScoringStats {
        var stats = ScoringStats()
        for score in round.scores {
            guard let par = round.course.hole(score.holeNumber)?.par else { continue }
            stats.add(score, par: par, gameType: round.gameType)
        }
        return stats
    }

    public static func playerStats(rounds: [Round], gameType: GameType? = nil) -> PlayerStats {
        let relevant = rounds
            .filter { gameType == nil || $0.gameType == gameType }
            .filter { $0.holesPlayed > 0 && !$0.isTeamBallRound }
            .sorted { $0.date < $1.date }

        var scoring = ScoringStats()
        var trend: [TrendPoint] = []
        for round in relevant {
            let roundStats = Self.scoring(for: round)
            scoring = merge(scoring, roundStats, gameType: round.gameType)
            if round.isComplete {
                trend.append(TrendPoint(
                    roundID: round.id, date: round.date, strokes: round.totalStrokes, toPar: round.toPar,
                    toPar18: Double(round.toPar) * 18 / Double(max(1, round.holesPlayed)),
                    courseName: round.course.name
                ))
            }
        }

        let complete = relevant.filter(\.isComplete)
        let scoringAverage: Double? = complete.isEmpty ? nil :
            complete.map { Double($0.totalStrokes) * 18 / Double(max(1, $0.holesPlayed)) }.reduce(0, +) / Double(complete.count)
        let averageToPar18: Double? = trend.isEmpty ? nil : trend.map(\.toPar18).reduce(0, +) / Double(trend.count)

        let best = complete.min { a, b in
            let la = Double(a.toPar) / Double(max(1, a.holesPlayed)), lb = Double(b.toPar) / Double(max(1, b.holesPlayed))
            if a.holeNumbers.count != b.holeNumbers.count { return a.holeNumbers.count > b.holeNumbers.count }
            return la < lb
        }

        let drives = driveDistances(in: relevant)
        return PlayerStats(
            rounds: relevant.count,
            scoring: scoring,
            scoringAverage: scoringAverage,
            averageToPar18: averageToPar18,
            bestRound: best,
            trend: trend,
            clubDistances: clubDistances(in: relevant),
            longestDrive: drives.max(),
            averageDrive: drives.isEmpty ? nil : drives.reduce(0, +) / Double(drives.count)
        )
    }

    /// Per-course and per-hole stats.
    public static func courseStats(rounds: [Round]) -> [CourseStats] {
        let grouped = Dictionary(grouping: rounds.filter { $0.holesPlayed > 0 && !$0.isTeamBallRound }, by: { $0.course.id })
        return grouped.values.compactMap { courseRounds -> CourseStats? in
            guard let latest = courseRounds.max(by: { $0.date < $1.date }) else { return nil }
            let course = latest.course
            var holes: [Int: HoleStats] = Dictionary(uniqueKeysWithValues: course.holes.map {
                ($0.number, HoleStats(number: $0.number, par: $0.par, strokeIndex: $0.strokeIndex, scoring: ScoringStats(), best: nil))
            })
            var scoring = ScoringStats()
            for round in courseRounds {
                for score in round.scores {
                    guard var hole = holes[score.holeNumber] else { continue }
                    hole.scoring.add(score, par: hole.par, gameType: course.gameType)
                    hole.best = min(hole.best ?? .max, score.strokes)
                    holes[score.holeNumber] = hole
                    scoring.add(score, par: hole.par, gameType: course.gameType)
                }
            }
            return CourseStats(
                courseID: course.id, courseName: course.name, gameType: course.gameType,
                rounds: courseRounds.sorted { $0.date > $1.date },
                holes: holes.values.sorted { $0.number < $1.number },
                scoring: scoring
            )
        }
        .sorted { $0.rounds.count > $1.rounds.count }
    }

    /// Average and longest distance per club from GPS-tracked, non-putt shots.
    public static func clubDistances(in rounds: [Round]) -> [ClubDistance] {
        var byClub: [Club: [Double]] = [:]
        for round in rounds {
            for score in round.scores {
                for shot in score.shots where !shot.isPutt && shot.penaltyStrokes == 0 {
                    guard let club = shot.club, let distance = shot.distance, distance > 5 else { continue }
                    byClub[club, default: []].append(distance)
                }
            }
        }
        return byClub.map { club, distances in
            ClubDistance(club: club, average: distances.reduce(0, +) / Double(distances.count), longest: distances.max() ?? 0, shots: distances.count)
        }
        .sorted { Club.allCases.firstIndex(of: $0.club)! < Club.allCases.firstIndex(of: $1.club)! }
    }

    /// Tee-shot distances on par 4s and 5s.
    public static func driveDistances(in rounds: [Round]) -> [Double] {
        rounds.flatMap { round in
            round.scores.compactMap { score -> Double? in
                guard let par = round.course.hole(score.holeNumber)?.par, par >= 4,
                      let first = score.shots.first, first.lie == .tee, first.penaltyStrokes == 0,
                      let d = first.distance, d > 20 else { return nil }
                return d
            }
        }
    }

    static func merge(_ a: ScoringStats, _ b: ScoringStats, gameType: GameType) -> ScoringStats {
        var m = a
        m.holesPlayed += b.holesPlayed
        m.strokes += b.strokes
        m.par += b.par
        m.puttsTotal += b.puttsTotal
        m.holesWithPutts += b.holesWithPutts
        m.greensInRegulation = m.greensInRegulation + b.greensInRegulation
        m.fairways = m.fairways + b.fairways
        m.fairwayMissLeft += b.fairwayMissLeft
        m.fairwayMissRight += b.fairwayMissRight
        m.scrambling = m.scrambling + b.scrambling
        m.sandSaves = m.sandSaves + b.sandSaves
        m.penalties += b.penalties
        m.onePutts += b.onePutts
        m.threePuttsOrWorse += b.threePuttsOrWorse
        m.shotsToGreenTotal += b.shotsToGreenTotal
        for (k, v) in b.distribution { m.distribution[k, default: 0] += v }
        for (k, v) in b.strokesByPar {
            m.strokesByPar[k, default: ParTally()].total += v.total
            m.strokesByPar[k, default: ParTally()].count += v.count
        }
        return m
    }
}
