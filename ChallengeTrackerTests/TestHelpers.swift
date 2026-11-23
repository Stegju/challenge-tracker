import Foundation
@testable import ChallengeTracker

@MainActor
enum T {
    static let cal = DateProvider.defaultCalendar
    static func d(_ m: Int, _ day: Int, _ h: Int = 12, year: Int = 2027) -> Date {
        cal.date(year: year, month: m, day: day, hour: h)
    }
    static var catalogue: Catalogue { Catalogue.bundled() }
    static func engine(_ s: YearState, _ now: Date) -> YearEngine {
        YearEngine(state: s, catalogue: catalogue, rules: LockRules(), now: now)
    }
    static func fresh() -> YearState { YearState.fresh(catalogue: catalogue) }

    /// Puts a challenge in a month with baseline and target (bypasses lock rules).
    static func put(_ s: inout YearState, _ m: Int, _ id: String, b: Double?, t: Double?) {
        let ch = catalogue.challenge(id: id)
        s.update(m) { slot in
            slot.kind = .new
            slot.challengeId = id
            slot.snapshot = ch
            slot.baseline = b
            slot.target = t
        }
    }

    static func finalize(_ s: inout YearState, _ m: Int, _ result: Double) {
        s.entries.append(Entry(month: m, date: d(m, 15), value: result))
        s.update(m) { $0.finalResult = result; $0.isFinal = true }
    }
}
