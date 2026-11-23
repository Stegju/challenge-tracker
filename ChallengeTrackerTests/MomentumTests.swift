import Foundation
import Testing
@testable import ChallengeTracker

@MainActor
struct MomentumTests {
    let cal = T.cal
    let start = T.d(1, 4, 7)   // Monday 4 Jan 2027

    func workouts(weeks: Int, weekdays: [Int], kind: WorkoutKind = .challenge) -> [Workout] {
        var out: [Workout] = []
        for w in 0..<weeks {
            for wd in weekdays {
                out.append(Workout(date: cal.addingDays(w * 7 + wd, to: start), kind: kind))
            }
        }
        return out
    }

    func run(_ w: [Workout], bests: [Date] = [], days: Int) -> MomentumResult {
        MomentumEngine.run(workouts: w, bestDays: bests, dose: { _ in 3 }, start: start,
                           end: cal.addingDays(days, to: start), calendar: cal)
    }

    @Test func threePerWeekIsPumped() {
        let r = run(workouts(weeks: 8, weekdays: [0, 2, 4]), days: 55)
        #expect(r.mood == .pumped)
        #expect(abs(r.m - 1.0) < 0.05)
    }

    @Test func twoPerWeekIsSteady() {
        let r = run(workouts(weeks: 8, weekdays: [0, 3]), days: 55)
        #expect(r.mood == .steady)
    }

    @Test func stoppingDrainsToSlumped() {
        let w = workouts(weeks: 8, weekdays: [0, 2, 4])
        let r = run(w, days: 70)
        // Last session on day 53 (Fri of week 8).
        let lastSession = 53
        func mood(after n: Int) -> Mood { r.days[lastSession + n].mood }
        #expect(mood(after: 0) == .pumped)
        #expect(mood(after: 5) == .steady)
        #expect(mood(after: 7) == .tired)
        #expect(mood(after: 9) == .slumped)
    }

    @Test func fourPerWeekWithBestIsOnFireThenPumped() {
        let w = workouts(weeks: 8, weekdays: [0, 1, 3, 5])
        let bestDay = cal.addingDays(50, to: start)
        let r = run(w, bests: [bestDay], days: 55)
        let moods = r.days.map(\.mood)
        #expect(moods[49] == .pumped)
        #expect(moods[52] == .onfire)
        // Back to 3 sessions a week: on fire fades to pumped within about a week.
        let then3 = w + (8...9).flatMap { wk in [0, 2, 4].map { Workout(date: cal.addingDays(wk * 7 + $0, to: start), kind: .challenge) } }
        let longer = run(then3, bests: [bestDay], days: 68)
        #expect(longer.days[58].mood == .onfire)
        #expect(longer.mood == .pumped)
    }

    @Test func otherWorkoutsCountHalf() {
        let r = run(workouts(weeks: 8, weekdays: [0, 1, 2, 3, 4, 5], kind: .other), days: 55)
        #expect(abs(r.m - 1.0) < 0.05)
    }

    @Test func hysteresisHoldsNearBoundary() {
        // Just above the pumped threshold but within the margin: stay steady.
        #expect(MomentumEngine.nextMood(current: .steady, m: 0.87, daysInMood: 3) == .steady)
        #expect(MomentumEngine.nextMood(current: .steady, m: 0.91, daysInMood: 3) == .pumped)
        #expect(MomentumEngine.nextMood(current: .pumped, m: 0.82, daysInMood: 3) == .pumped)
        #expect(MomentumEngine.nextMood(current: .pumped, m: 0.79, daysInMood: 3) == .steady)
        #expect(MomentumEngine.nextMood(current: .pumped, m: 0.1, daysInMood: 0) == .pumped)
    }

    @Test func finishedMonthOverridesMood() {
        var s = T.fresh()
        T.put(&s, 2, "bench-e1rm", b: 90, t: 100)
        T.finalize(&s, 2, 101)
        let e = T.engine(s, T.d(2, 27))
        let mom = MomentumEngine.compute(engine: e)
        #expect(MomentumEngine.displayMood(momentum: mom, currentMonth: e.resolve(2)) == .pumped)
        var s2 = T.fresh()
        T.put(&s2, 2, "bench-e1rm", b: 90, t: 100)
        T.finalize(&s2, 2, 93)
        let e2 = T.engine(s2, T.d(2, 27))
        #expect(MomentumEngine.displayMood(momentum: mom, currentMonth: e2.resolve(2)) == .tired)
    }

    @Test func newBestDaysUseBaselineAsReference() {
        var s = T.fresh()
        T.put(&s, 3, "pullups-max", b: 12, t: 18)
        s.entries = [
            Entry(month: 3, date: T.d(3, 2), value: 12),
            Entry(month: 3, date: T.d(3, 7), value: 13),
            Entry(month: 3, date: T.d(3, 9), value: 13),
            Entry(month: 3, date: T.d(3, 11), value: 15)
        ]
        let days = MomentumEngine.newBestDays(engine: T.engine(s, T.d(3, 14)))
        #expect(days == [cal.startOfDay(for: T.d(3, 7)), cal.startOfDay(for: T.d(3, 11))])
    }

    @Test func explanationLine() {
        let r = run(workouts(weeks: 2, weekdays: [0, 2, 4]), bests: [cal.addingDays(9, to: start)], days: 13)
        let text = MomentumEngine.explanation(momentum: r, now: cal.addingDays(13, to: start), calendar: cal)
        #expect(text == "3/3 sessions this week · new best 4 days ago")
    }
}

@MainActor
struct WeekTests {
    @Test func weekRunsMondayToSunday() {
        let sunday = T.d(3, 14, 18)
        let w: [Workout] = [
            Workout(date: T.d(3, 8, 7), kind: .other),
            Workout(date: T.d(3, 9, 7), kind: .challenge),
            Workout(date: T.d(3, 11, 7), kind: .challenge),
            Workout(date: T.d(3, 11, 18), kind: .other),
            Workout(date: T.d(3, 7, 7), kind: .challenge)   // previous Sunday, not counted
        ]
        let s = WeekSummary(workouts: w, now: sunday, dose: 3, calendar: T.cal)
        #expect(s.days.count == 7)
        #expect(s.days[0].letter == "M")
        #expect(s.days[6].isToday)
        #expect(s.days[3].blocks == [.challenge, .other])
        #expect(s.label == "2/3 CHALLENGE · 2 OTHER")
    }
}
