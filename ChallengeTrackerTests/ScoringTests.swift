import Foundation
import Testing
@testable import ChallengeTracker

@MainActor
struct ScoringTests {

    @Test func higherIsBetter() {
        // Pull-ups 12 → 18, result 15 = 50
        #expect(Scoring.score(result: 15, baseline: 12, target: 18) == 50)
        #expect(Scoring.score(result: 18, baseline: 12, target: 18) == 100)
    }

    @Test func lowerIsBetter() {
        // 5K 23:10 → 21:00, result 21:25 = 81
        #expect(Scoring.score(result: 1285, baseline: 1390, target: 1260) == 81)
        #expect(Scoring.score(result: 1260, baseline: 1390, target: 1260) == 100)
    }

    @Test func clampsBothEnds() {
        #expect(Scoring.score(result: 102.5, baseline: 90, target: 100) == 120)
        #expect(Scoring.score(result: 80, baseline: 90, target: 100) == 0)
        #expect(Scoring.score(result: 1500, baseline: 1390, target: 1260) == 0)
        #expect(Scoring.score(result: 1000, baseline: 1390, target: 1260) == 120)
    }

    @Test func equalBaselineAndTargetScoresZero() {
        #expect(Scoring.score(result: 20, baseline: 10, target: 10) == 0)
    }

    @Test func bestRespectsDirection() {
        #expect(Scoring.best([12, 15, 13], direction: .higher) == 15)
        #expect(Scoring.best([1360, 1285, 1315], direction: .lower) == 1285)
        #expect(Scoring.best([], direction: .higher) == nil)
    }

    @Test func targetValidation() {
        #expect(Scoring.validate(baseline: 12, target: 12, direction: .higher) == .equalsBaseline)
        #expect(Scoring.validate(baseline: 12, target: 10, direction: .higher) == .wrongSide)
        #expect(Scoring.validate(baseline: 1390, target: 1400, direction: .lower) == .wrongSide)
        #expect(Scoring.validate(baseline: 1390, target: 1260, direction: .lower) == nil)
        #expect(Scoring.validate(baseline: nil, target: 18, direction: .higher) == nil)
    }
}

@MainActor
struct ValueFormatTests {

    @Test func parsesTimes() {
        #expect(ValueFormat.parseTime("21:25") == 1285)
        #expect(ValueFormat.parseTime("1:02:03") == 3723)
        #expect(ValueFormat.parseTime(" 7:05 ") == 425)
        #expect(ValueFormat.parseTime("1:75") == nil)
        #expect(ValueFormat.parseTime("abc") == nil)
        #expect(ValueFormat.parseTime("") == nil)
    }

    @Test func formatsTimes() {
        #expect(ValueFormat.formatTime(1285) == "21:25")
        #expect(ValueFormat.formatTime(3723) == "1:02:03")
        #expect(ValueFormat.formatTime(65) == "1:05")
    }

    @Test func parsesDecimalComma() {
        #expect(ValueFormat.parseNumber("12,5") == 12.5)
        #expect(ValueFormat.parseNumber("18") == 18)
        #expect(ValueFormat.parseNumber("x") == nil)
    }

    @Test func e1rmRoundsToHalfKilo() {
        #expect(ValueFormat.e1rm(weightKg: 100, reps: 5) == 116.5)   // 116.67
        #expect(ValueFormat.e1rm(weightKg: 95, reps: 2) == 101.5)    // 101.33
        #expect(ValueFormat.e1rm(weightKg: 80, reps: 1) == 82.5)     // 82.67
    }

    @Test func formatsNumbers() {
        #expect(ValueFormat.formatNumber(15) == "15")
        #expect(ValueFormat.formatNumber(102.5) == "102.5")
        #expect(ValueFormat.formatNumber(12.25) == "12.25")
    }
}

@MainActor
struct BarbellTests {

    @Test func twoHundredOne() {
        let b = BarbellLayout(points: 201)
        #expect(b.plates.map(\.tier) == [0, 0])
        #expect(b.partial == BarbellLayout.Partial(tier: 1, thickness: 9, height: 4, top: 58))
        #expect(b.pointsToNextPlate == 99)
    }

    @Test func fiveSeventyFive() {
        let b = BarbellLayout(points: 575)
        #expect(b.plates.map(\.tier) == [2, 1, 1, 0, 0])
        #expect(b.partial?.tier == 2)
        #expect(b.partial?.height == 90)
    }

    @Test func emptyBarHasDashedFirstPlate() {
        let b = BarbellLayout(points: 0)
        #expect(b.plates.isEmpty)
        #expect(b.partial?.height == 0)
        #expect(b.partial?.tier == 0)
    }

    @Test func fullBarAndBeyond() {
        let full = BarbellLayout(points: 1000)
        #expect(full.plates.count == 10)
        #expect(full.partial == nil)
        #expect(full.plates.first?.tier == 4)
        let over = BarbellLayout(points: 1200)
        #expect(over.plates.count == 10)
        #expect(over.partial == nil)
    }

    @Test func fortyPoints() {
        let b = BarbellLayout(points: 40)
        #expect(b.plates.isEmpty)
        #expect(b.partial?.height == 48)
    }
}
