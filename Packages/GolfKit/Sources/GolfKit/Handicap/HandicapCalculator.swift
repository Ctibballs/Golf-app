import Foundation

/// One score differential that feeds a handicap index.
public struct HandicapDifferential: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var roundIDs: [UUID]
    public var date: Date
    public var courseName: String
    public var adjustedGrossScore: Int
    public var courseRating: Double
    public var slopeRating: Int
    public var value: Double
    /// Rating/slope were missing and estimated from par and the neutral slope of 113.
    public var isEstimatedRating: Bool
    public var isNineHole: Bool
    /// Whether this differential is among the best ones that make up the current index.
    public var usedInIndex: Bool

    public init(
        id: UUID = UUID(),
        roundIDs: [UUID],
        date: Date,
        courseName: String,
        adjustedGrossScore: Int,
        courseRating: Double,
        slopeRating: Int,
        value: Double,
        isEstimatedRating: Bool,
        isNineHole: Bool,
        usedInIndex: Bool = false
    ) {
        self.id = id
        self.roundIDs = roundIDs
        self.date = date
        self.courseName = courseName
        self.adjustedGrossScore = adjustedGrossScore
        self.courseRating = courseRating
        self.slopeRating = slopeRating
        self.value = value
        self.isEstimatedRating = isEstimatedRating
        self.isNineHole = isNineHole
        self.usedInIndex = usedInIndex
    }
}

public struct HandicapHistoryPoint: Codable, Hashable, Sendable {
    public var date: Date
    public var index: Double
}

public struct HandicapResult: Hashable, Sendable {
    public enum Source: Hashable, Sendable {
        case manual
        case calculated
        case notEstablished
        /// The player has switched their handicap off.
        case off
    }

    /// The index to use for play: manual if set, otherwise calculated. Nil when the
    /// handicap is off or not yet established.
    public var index: Double?
    /// The index calculated from rounds, even when a manual index overrides it.
    public var calculatedIndex: Double?
    public var source: Source
    /// Most recent first, at most 20.
    public var differentials: [HandicapDifferential]
    public var eligibleRounds: Int
    public var roundsRequired: Int
    public var history: [HandicapHistoryPoint]

    public var roundsUntilEstablished: Int { max(0, roundsRequired - eligibleRounds) }

    public var isEnabled: Bool { source != .off }

    public var displayIndex: String {
        if source == .off { return "Off" }
        guard let index else { return "—" }
        return HandicapCalculator.format(index)
    }
}

extension HandicapResult {
    static func source(settings: HandicapSettings, manual: Double?, calculated: Double?) -> Source {
        guard settings.isEnabled else { return .off }
        if manual != nil { return .manual }
        return calculated != nil ? .calculated : .notEstablished
    }
}

/// World Handicap System calculations (2024 rules), without the 12-month soft/hard caps
/// which need an official revision history.
public enum HandicapCalculator {
    public static let neutralSlope = 113
    public static let maximumIndex = 54.0
    public static let recentWindow = 20

    // MARK: - Index from differentials

    /// How many of the lowest differentials count, and the adjustment, for a given number of scores.
    public static func lowestCountAndAdjustment(forScores count: Int) -> (count: Int, adjustment: Double)? {
        switch count {
        case ..<3: return nil
        case 3: return (1, -2.0)
        case 4: return (1, -1.0)
        case 5: return (1, 0)
        case 6: return (2, -1.0)
        case 7...8: return (2, 0)
        case 9...11: return (3, 0)
        case 12...14: return (4, 0)
        case 15...16: return (5, 0)
        case 17...18: return (6, 0)
        case 19: return (7, 0)
        default: return (8, 0)
        }
    }

    /// Handicap index from score differentials ordered most recent first.
    public static func handicapIndex(fromDifferentials differentials: [Double]) -> Double? {
        let recent = Array(differentials.prefix(recentWindow))
        guard let rule = lowestCountAndAdjustment(forScores: recent.count) else { return nil }
        let lowest = recent.sorted().prefix(rule.count)
        let average = lowest.reduce(0, +) / Double(lowest.count)
        return min(maximumIndex, roundToTenth(average + rule.adjustment))
    }

    /// Score differential = (113 / slope) × (adjusted gross − course rating − PCC).
    public static func scoreDifferential(adjustedGross: Int, courseRating: Double, slope: Int, pcc: Double = 0) -> Double {
        roundToTenth(Double(neutralSlope) / Double(slope) * (Double(adjustedGross) - courseRating - pcc))
    }

    /// Expected 9-hole differential used to turn a 9-hole score into an 18-hole differential.
    public static func expectedNineHoleDifferential(index: Double) -> Double {
        index * 0.52 + 1.2
    }

    // MARK: - Course handicap and stroke allocation

    /// Course handicap = index × (slope / 113) + (course rating − par), scaled for 9 holes.
    public static func courseHandicap(index: Double, slope: Int?, courseRating: Double?, par: Int, holes: Int = 18) -> Int {
        let fraction = holes <= 9 ? 0.5 : 1.0
        let slopeFactor = Double(slope ?? neutralSlope) / Double(neutralSlope)
        let ratingAdjustment = courseRating.map { $0 * fraction - Double(par) } ?? 0
        return Int((index * fraction * slopeFactor + ratingAdjustment).rounded())
    }

    /// Handicap strokes received on each hole, keyed by hole number. Negative values are
    /// strokes given back by plus-handicap players.
    public static func strokeAllocation(courseHandicap: Int, holes: [HoleInfo]) -> [Int: Int] {
        guard !holes.isEmpty else { return [:] }
        let n = holes.count
        // Rank holes by stroke index (hardest first); fall back to hole order.
        let ranked = holes.enumerated().sorted { a, b in
            let sa = a.element.strokeIndex ?? (1000 + a.offset)
            let sb = b.element.strokeIndex ?? (1000 + b.offset)
            return sa < sb
        }.map(\.element.number)

        var allocation: [Int: Int] = [:]
        let base = abs(courseHandicap) / n
        let extra = abs(courseHandicap) % n
        for (rank, hole) in ranked.enumerated() {
            if courseHandicap >= 0 {
                allocation[hole] = base + (rank < extra ? 1 : 0)
            } else {
                // Plus handicaps give strokes back starting with the easiest hole.
                allocation[hole] = -(base + (rank >= n - extra ? 1 : 0))
            }
        }
        return allocation
    }

    // MARK: - Adjusted gross score

    /// Applies net double bogey (par + 2 + strokes received) per hole. Players without an
    /// established index are capped at par + 5.
    public static func adjustedGrossScore(for round: Round, courseHandicap: Int?) -> Int {
        let allocation = courseHandicap.map { strokeAllocation(courseHandicap: $0, holes: round.holes) } ?? [:]
        return round.scores.reduce(0) { total, score in
            guard let par = round.course.hole(score.holeNumber)?.par else { return total + score.strokes }
            let cap: Int
            if courseHandicap != nil {
                cap = par + 2 + (allocation[score.holeNumber] ?? 0)
            } else {
                cap = par + 5
            }
            return total + min(score.strokes, cap)
        }
    }

    // MARK: - Evaluation

    /// Calculates a player's handicap from their rounds, honouring manual overrides and the
    /// required round count.
    public static func evaluate(rounds: [Round], settings: HandicapSettings) -> HandicapResult {
        let eligible = rounds
            .filter { $0.isComplete && $0.countsForHandicap && $0.gameType == .golf && $0.holeNumbers.count >= 9 }
            .sorted { $0.date < $1.date }

        var differentials: [HandicapDifferential] = []
        var history: [HandicapHistoryPoint] = []
        var pendingNine: (round: Round, value: Double, ags: Int, rating: Double, slope: Int, estimated: Bool)?

        for round in eligible {
            let runningIndex = handicapIndex(fromDifferentials: differentials.reversed().map(\.value))
            let rating = ratingAndSlope(for: round)
            let courseHcp = runningIndex.map {
                courseHandicap(index: $0, slope: rating.slope, courseRating: rating.courseRating, par: round.totalPar, holes: round.holeNumbers.count)
            }
            let ags = adjustedGrossScore(for: round, courseHandicap: courseHcp)
            let rawDifferential = scoreDifferential(adjustedGross: ags, courseRating: rating.courseRating, slope: rating.slope)

            if round.isNineHoles {
                if let runningIndex {
                    let value = roundToTenth(rawDifferential + expectedNineHoleDifferential(index: runningIndex))
                    differentials.append(HandicapDifferential(
                        roundIDs: [round.id], date: round.date, courseName: round.course.name,
                        adjustedGrossScore: ags, courseRating: rating.courseRating, slopeRating: rating.slope,
                        value: value, isEstimatedRating: rating.estimated, isNineHole: true
                    ))
                } else if let pending = pendingNine {
                    // Without an index yet, two 9-hole scores combine into one 18-hole differential.
                    differentials.append(HandicapDifferential(
                        roundIDs: [pending.round.id, round.id], date: round.date,
                        courseName: pending.round.course.name == round.course.name ? round.course.name : "\(pending.round.course.name) + \(round.course.name)",
                        adjustedGrossScore: pending.ags + ags, courseRating: pending.rating + rating.courseRating,
                        slopeRating: (pending.slope + rating.slope) / 2,
                        value: roundToTenth(pending.value + rawDifferential),
                        isEstimatedRating: pending.estimated || rating.estimated, isNineHole: true
                    ))
                    pendingNine = nil
                } else {
                    pendingNine = (round, rawDifferential, ags, rating.courseRating, rating.slope, rating.estimated)
                    continue
                }
            } else {
                differentials.append(HandicapDifferential(
                    roundIDs: [round.id], date: round.date, courseName: round.course.name,
                    adjustedGrossScore: ags, courseRating: rating.courseRating, slopeRating: rating.slope,
                    value: rawDifferential, isEstimatedRating: rating.estimated, isNineHole: false
                ))
            }

            if differentials.count >= settings.roundsRequired,
               let index = handicapIndex(fromDifferentials: differentials.reversed().map(\.value)) {
                history.append(HandicapHistoryPoint(date: round.date, index: index))
            }
        }

        var recent = Array(differentials.reversed().prefix(recentWindow))
        let established = recent.count >= settings.roundsRequired
        let calculated = established ? handicapIndex(fromDifferentials: recent.map(\.value)) : nil
        if established, let rule = lowestCountAndAdjustment(forScores: recent.count) {
            let usedIDs = Set(recent.sorted { $0.value < $1.value }.prefix(rule.count).map(\.id))
            for i in recent.indices { recent[i].usedInIndex = usedIDs.contains(recent[i].id) }
        }

        let manual = settings.mode == .manual ? settings.manualIndex : nil
        let index = settings.isEnabled ? manual ?? calculated : nil
        let source = HandicapResult.source(settings: settings, manual: manual, calculated: calculated)

        return HandicapResult(
            index: index,
            calculatedIndex: calculated,
            source: source,
            differentials: recent,
            eligibleRounds: differentials.count,
            roundsRequired: settings.roundsRequired,
            history: history
        )
    }

    /// Rating and slope for a round, estimating from par when the data source has none.
    public static func ratingAndSlope(for round: Round) -> (courseRating: Double, slope: Int, estimated: Bool) {
        let playedPar = Double(round.totalPar)
        guard let tee = round.tee, let rating = tee.courseRating, let slope = tee.slopeRating, slope > 0 else {
            return (playedPar, neutralSlope, true)
        }
        // Ratings are published for 18 holes; halve for a 9-hole round of an 18-hole course.
        let fullHoles = round.course.holeCount
        if round.holeNumbers.count <= 9 && fullHoles >= 18 {
            return (roundToTenth(rating / 2), slope, false)
        }
        return (rating, slope, false)
    }

    // MARK: - Formatting

    public static func roundToTenth(_ value: Double) -> Double {
        (value * 10).rounded() / 10
    }

    /// Formats an index the way golfers write it: plus handicaps get a "+" sign.
    public static func format(_ index: Double) -> String {
        if index < 0 { return String(format: "+%.1f", -index) }
        return String(format: "%.1f", index)
    }
}

/// A simple index for pitch & putt and mini golf, where official ratings don't exist:
/// the average of the best half of the last ten rounds' scores over par, scaled to 18 holes.
public enum CasualHandicapCalculator {
    public static let window = 10

    public static func differential(for round: Round) -> Double? {
        guard round.holesPlayed > 0 else { return nil }
        return Double(round.toPar) * 18 / Double(round.holesPlayed)
    }

    public static func evaluate(rounds: [Round], gameType: GameType, settings: HandicapSettings) -> HandicapResult {
        let eligible = rounds
            .filter { $0.isComplete && $0.gameType == gameType && $0.countsForHandicap }
            .sorted { $0.date > $1.date }
        let recent = Array(eligible.prefix(window))
        let diffs = recent.compactMap { round -> HandicapDifferential? in
            guard let value = differential(for: round) else { return nil }
            return HandicapDifferential(
                roundIDs: [round.id], date: round.date, courseName: round.course.name,
                adjustedGrossScore: round.totalStrokes, courseRating: Double(round.totalPar),
                slopeRating: HandicapCalculator.neutralSlope, value: HandicapCalculator.roundToTenth(value),
                isEstimatedRating: false, isNineHole: round.isNineHoles
            )
        }

        var calculated: Double?
        var marked = diffs
        if diffs.count >= settings.roundsRequired {
            let best = diffs.sorted { $0.value < $1.value }.prefix(max(1, (diffs.count + 1) / 2))
            calculated = HandicapCalculator.roundToTenth(best.map(\.value).reduce(0, +) / Double(best.count))
            let used = Set(best.map(\.id))
            for i in marked.indices { marked[i].usedInIndex = used.contains(marked[i].id) }
        }

        let manual = settings.mode == .manual ? settings.manualIndex : nil
        return HandicapResult(
            index: settings.isEnabled ? manual ?? calculated : nil,
            calculatedIndex: calculated,
            source: HandicapResult.source(settings: settings, manual: manual, calculated: calculated),
            differentials: marked,
            eligibleRounds: diffs.count,
            roundsRequired: settings.roundsRequired,
            history: []
        )
    }

    /// Strokes a casual-index player receives over `holes` holes.
    public static func courseHandicap(index: Double, holes: Int) -> Int {
        Int((index * Double(holes) / 18).rounded())
    }
}
