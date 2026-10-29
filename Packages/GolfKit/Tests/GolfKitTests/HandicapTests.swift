import XCTest
@testable import GolfKit

final class HandicapTests: XCTestCase {
    func testWHSTableOfLowestDifferentials() {
        XCTAssertNil(HandicapCalculator.lowestCountAndAdjustment(forScores: 2))
        XCTAssertEqual(HandicapCalculator.lowestCountAndAdjustment(forScores: 3)?.count, 1)
        XCTAssertEqual(HandicapCalculator.lowestCountAndAdjustment(forScores: 3)?.adjustment, -2.0)
        XCTAssertEqual(HandicapCalculator.lowestCountAndAdjustment(forScores: 6)?.count, 2)
        XCTAssertEqual(HandicapCalculator.lowestCountAndAdjustment(forScores: 6)?.adjustment, -1.0)
        XCTAssertEqual(HandicapCalculator.lowestCountAndAdjustment(forScores: 10)?.count, 3)
        XCTAssertEqual(HandicapCalculator.lowestCountAndAdjustment(forScores: 20)?.count, 8)
        XCTAssertEqual(HandicapCalculator.lowestCountAndAdjustment(forScores: 35)?.count, 8)
    }

    func testIndexFromDifferentials() {
        XCTAssertNil(HandicapCalculator.handicapIndex(fromDifferentials: [12, 14]))
        // 3 scores: lowest one minus 2.0
        XCTAssertEqual(HandicapCalculator.handicapIndex(fromDifferentials: [15.2, 12.1, 18.0]), 10.1)
        // 20 scores: average of lowest 8
        let diffs: [Double] = [10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29]
        XCTAssertEqual(HandicapCalculator.handicapIndex(fromDifferentials: diffs), 13.5)
        // Only the most recent 20 count.
        XCTAssertEqual(HandicapCalculator.handicapIndex(fromDifferentials: diffs + [0, 0, 0]), 13.5)
        // Capped at 54.
        XCTAssertEqual(HandicapCalculator.handicapIndex(fromDifferentials: [80, 90, 99]), 54)
    }

    func testScoreDifferentialAndCourseHandicap() {
        // (113 / 130) × (90 − 71.5) = 16.08 → 16.1
        XCTAssertEqual(HandicapCalculator.scoreDifferential(adjustedGross: 90, courseRating: 71.5, slope: 130), 16.1)
        // 12.4 × 130/113 + (71.5 − 72) = 13.77 → 14
        XCTAssertEqual(HandicapCalculator.courseHandicap(index: 12.4, slope: 130, courseRating: 71.5, par: 72), 14)
        // Nine holes use half the index and a nine-hole rating.
        XCTAssertEqual(HandicapCalculator.courseHandicap(index: 12.4, slope: 130, courseRating: 71.5, par: 36, holes: 9), 7)
        XCTAssertEqual(HandicapCalculator.format(-1.4), "+1.4")
        XCTAssertEqual(HandicapCalculator.format(9.0), "9.0")
    }

    func testStrokeAllocationUsesStrokeIndex() {
        let holes = testCourse(holes: 18).holes
        let ten = HandicapCalculator.strokeAllocation(courseHandicap: 10, holes: holes)
        XCTAssertEqual(ten[1], 1)
        XCTAssertEqual(ten[10], 1)
        XCTAssertEqual(ten[11], 0)
        XCTAssertEqual(ten.values.reduce(0, +), 10)

        let twenty = HandicapCalculator.strokeAllocation(courseHandicap: 20, holes: holes)
        XCTAssertEqual(twenty[1], 2)
        XCTAssertEqual(twenty[2], 2)
        XCTAssertEqual(twenty[3], 1)
        XCTAssertEqual(twenty.values.reduce(0, +), 20)

        // A +2 player gives strokes back on the two easiest holes.
        let plus = HandicapCalculator.strokeAllocation(courseHandicap: -2, holes: holes)
        XCTAssertEqual(plus[18], -1)
        XCTAssertEqual(plus[17], -1)
        XCTAssertEqual(plus[1], 0)
    }

    func testNetDoubleBogeyCapsBlowUpHoles() {
        let course = testCourse(holes: 9)
        var r = round(on: course, strokes: [4, 4, 3, 5, 4, 4, 3, 4, 12])
        // No index yet: par + 5 cap → 10 on the par 5.
        XCTAssertEqual(HandicapCalculator.adjustedGrossScore(for: r, courseHandicap: nil), 31 + 10)
        // Course handicap 9 → one stroke per hole → cap = par + 3 → 8 on the par 5.
        XCTAssertEqual(HandicapCalculator.adjustedGrossScore(for: r, courseHandicap: 9), 31 + 8)
        r.scores[0].strokes = 9
        XCTAssertEqual(HandicapCalculator.adjustedGrossScore(for: r, courseHandicap: 0), 6 + 27 + 7)
    }

    func testAutomaticHandicapNeedsRequiredRounds() {
        let course = testCourse(holes: 18)
        let tee = TeeSet(id: "w", name: "White", courseRating: 70.0, slopeRating: 113)
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let all = [84, 88, 80, 90].enumerated().map { i, total -> Round in
            // Spread over par 72: add the extra strokes to the first holes, one each.
            var strokes = course.holes.map(\.par)
            for j in 0..<(total - 72) { strokes[j % 18] += 1 }
            return round(on: course, strokes: strokes, date: base.addingTimeInterval(Double(i) * 86_400), tee: tee)
        }

        let settings = HandicapSettings(roundsRequired: 3)
        let two = HandicapCalculator.evaluate(rounds: Array(all.prefix(2)), settings: settings)
        XCTAssertNil(two.index)
        XCTAssertEqual(two.source, .notEstablished)
        XCTAssertEqual(two.roundsUntilEstablished, 1)

        let three = HandicapCalculator.evaluate(rounds: Array(all.prefix(3)), settings: settings)
        // Differentials 14, 18, 10 → lowest (10) − 2 = 8.0
        XCTAssertEqual(three.index, 8.0)
        XCTAssertEqual(three.source, .calculated)
        XCTAssertEqual(three.differentials.filter(\.usedInIndex).count, 1)

        // Requiring five rounds delays the automatic index.
        let strict = HandicapCalculator.evaluate(rounds: all, settings: HandicapSettings(roundsRequired: 5))
        XCTAssertNil(strict.index)
        XCTAssertEqual(strict.roundsUntilEstablished, 1)
    }

    func testManualHandicapOverridesCalculated() {
        let course = testCourse(holes: 18)
        let rounds = (0..<3).map { _ in round(on: course, strokes: course.holes.map { $0.par + 1 }) }
        let result = HandicapCalculator.evaluate(rounds: rounds, settings: HandicapSettings(mode: .manual, manualIndex: 5.3))
        XCTAssertEqual(result.index, 5.3)
        XCTAssertEqual(result.source, .manual)
        XCTAssertNotNil(result.calculatedIndex)
    }

    func testNineHoleRoundsCombineBeforeIndexExists() {
        let nine = testCourse(holes: 9)
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let rounds = (0..<6).map { i in
            round(on: nine, strokes: nine.holes.map { $0.par + 1 }, date: base.addingTimeInterval(Double(i) * 86_400))
        }
        let result = HandicapCalculator.evaluate(rounds: rounds, settings: HandicapSettings())
        // Six nines → three combined 18-hole differentials of 18.0 each → 18 − 2 = 16.0
        XCTAssertEqual(result.eligibleRounds, 3)
        XCTAssertEqual(result.index, 16.0)
        XCTAssertTrue(result.differentials.allSatisfy { $0.isNineHole && $0.roundIDs.count == 2 })
        XCTAssertTrue(result.differentials.allSatisfy(\.isEstimatedRating))
    }

    func testCasualHandicapForPitchAndPutt() {
        let course = testCourse(holes: 9, gameType: .pitchAndPutt)
        let rounds = [2, 4, 6, 8].map { over -> Round in
            var strokes = course.holes.map(\.par)
            for j in 0..<over { strokes[j] += 1 }
            return round(on: course, strokes: strokes)
        }
        let result = CasualHandicapCalculator.evaluate(rounds: rounds, gameType: .pitchAndPutt, settings: HandicapSettings())
        // Scaled to 18: 4, 8, 12, 16 → best half (4, 8) → 6.0
        XCTAssertEqual(result.index, 6.0)
        XCTAssertEqual(CasualHandicapCalculator.courseHandicap(index: 6.0, holes: 9), 3)
        // Golf rounds don't leak into the pitch & putt index.
        XCTAssertNil(CasualHandicapCalculator.evaluate(rounds: rounds, gameType: .miniGolf, settings: HandicapSettings()).index)
    }
}
