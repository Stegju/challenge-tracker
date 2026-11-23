import Foundation

enum Scoring {
    static let maxScore = 120.0
    static let fullBar = 1000

    /// clamp[0,120]( 100 · (result − baseline) / (target − baseline) ), rounded to whole points.
    /// Works for both directions because of the sign of target − baseline.
    /// Returns 0 when target equals baseline.
    static func score(result: Double, baseline: Double, target: Double) -> Int {
        let span = target - baseline
        guard span != 0 else { return 0 }
        let raw = 100 * (result - baseline) / span
        let clamped = min(maxScore, max(0, raw))
        return Int(clamped.rounded())
    }

    /// Best entry: highest if direction is higher, lowest if lower.
    static func best(_ values: [Double], direction: Direction) -> Double? {
        switch direction {
        case .higher: return values.max()
        case .lower: return values.min()
        }
    }

    static func isBetter(_ a: Double, than b: Double, direction: Direction) -> Bool {
        direction == .higher ? a > b : a < b
    }

    enum TargetProblem: Equatable {
        case equalsBaseline
        case wrongSide
    }

    /// Refuse a target equal to the baseline, or on the wrong side for the direction.
    static func validate(baseline: Double?, target: Double?, direction: Direction) -> TargetProblem? {
        guard let b = baseline, let t = target else { return nil }
        if t == b { return .equalsBaseline }
        switch direction {
        case .higher: return t < b ? .wrongSide : nil
        case .lower: return t > b ? .wrongSide : nil
        }
    }
}
