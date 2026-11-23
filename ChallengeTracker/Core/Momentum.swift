import Foundation

/// All tunable momentum numbers in one place (spec section 5).
struct MomentumConfig: Sendable {
    var otherWorkoutWeight = 0.5
    /// Other workouts in a normal week. Added (weighted) to the weekly dose so a normal
    /// training week scores a = 1.0, whatever the volume. 0 = spec formula.
    var expectedOtherPerWeek = 0.0
    var activityCap = 1.1
    var progressDecay = 0.8
    var progressWeight = 0.5   // spec had 0.25; 0.5 makes a new best give about a week of "on fire" on a normal week
    var smoothing = 0.3          // m_t = smoothing · x_t + (1 − smoothing) · m_{t−1}
    var initial = 0.6
    var onFire = 1.15
    var pumped = 0.85
    var steady = 0.60
    var tired = 0.30
    var hysteresis = 0.05
    var minHoldDays = 1
    var windowDays = 7

    static let standard = MomentumConfig()
}

enum Mood: String, CaseIterable, Codable, Sendable {
    case onfire, pumped, steady, tired, slumped

    var label: String {
        switch self {
        case .onfire: return "ON FIRE"
        case .pumped: return "PUMPED"
        case .steady: return "STEADY"
        case .tired: return "TIRED"
        case .slumped: return "SLUMPED"
        }
    }

    /// Order from lowest to highest.
    var rank: Int {
        switch self {
        case .slumped: return 0
        case .tired: return 1
        case .steady: return 2
        case .pumped: return 3
        case .onfire: return 4
        }
    }
}

struct MomentumDay: Equatable, Sendable {
    var date: Date
    var challengeSessions: Int
    var otherWorkouts: Int
    var dose: Double
    var a: Double
    var g: Double
    var m: Double
    var mood: Mood
    var newBest: Bool
}

enum Trend: Sendable {
    case up, down, flat

    var arrow: String {
        switch self {
        case .up: return "↑"
        case .down: return "↓"
        case .flat: return "→"
        }
    }
}

struct MomentumResult: Equatable, Sendable {
    var days: [MomentumDay]
    var lastBestDate: Date?

    var today: MomentumDay? { days.last }
    var m: Double { days.last?.m ?? MomentumConfig.standard.initial }
    var mood: Mood { days.last?.mood ?? .steady }

    var trend: Trend {
        guard days.count >= 2 else { return .flat }
        let d = days[days.count - 1].m - days[days.count - 2].m
        if d > 0.005 { return .up }
        if d < -0.005 { return .down }
        return .flat
    }
}

enum MomentumEngine {

    static func band(_ m: Double, _ c: MomentumConfig = .standard) -> Mood {
        if m >= c.onFire { return .onfire }
        if m >= c.pumped { return .pumped }
        if m >= c.steady { return .steady }
        if m >= c.tired { return .tired }
        return .slumped
    }

    /// Lower and upper bounds of a mood's band.
    static func bounds(_ mood: Mood, _ c: MomentumConfig) -> (lo: Double, hi: Double) {
        switch mood {
        case .onfire: return (c.onFire, .infinity)
        case .pumped: return (c.pumped, c.onFire)
        case .steady: return (c.steady, c.pumped)
        case .tired: return (c.tired, c.steady)
        case .slumped: return (-.infinity, c.tired)
        }
    }

    /// Mood with hysteresis: only change when m leaves the current band by at least `hysteresis`,
    /// and only after holding the current mood for `minHoldDays`.
    static func nextMood(current: Mood, m: Double, daysInMood: Int, _ c: MomentumConfig = .standard) -> Mood {
        guard daysInMood >= c.minHoldDays else { return current }
        let (lo, hi) = bounds(current, c)
        if m >= hi + c.hysteresis || m < lo - c.hysteresis {
            return band(m, c)
        }
        return current
    }

    /// Days (start of day) on which an entry beat the previous best of its month
    /// (the baseline counts as the first reference; without one the first entry sets it).
    static func newBestDays(engine: YearEngine) -> [Date] {
        var days: [Date] = []
        let cal = engine.rules.calendar
        for m in 1...12 {
            let r = engine.resolve(m)
            guard let ch = r.challenge else { continue }
            var ref = r.baseline
            for e in r.entries {
                if let cur = ref {
                    if Scoring.isBetter(e.value, than: cur, direction: ch.direction) {
                        days.append(cal.startOfDay(for: e.date))
                        ref = e.value
                    }
                } else {
                    ref = e.value
                }
            }
        }
        return days
    }

    /// Runs the daily update from `start` to `end` (inclusive), one step per calendar day.
    static func run(workouts: [Workout],
                    bestDays: [Date],
                    dose: (Date) -> Double,
                    start: Date,
                    end: Date,
                    calendar: Calendar,
                    config c: MomentumConfig = .standard) -> MomentumResult {
        let first = calendar.startOfDay(for: min(start, end))
        let last = calendar.startOfDay(for: end)
        let total = min(1000, max(0, calendar.dayCount(from: first, to: last)))

        // Count workouts per day index for quick windows.
        var challengeByDay = [Int: Int]()
        var otherByDay = [Int: Int]()
        for w in workouts {
            let i = calendar.dayCount(from: first, to: w.date)
            if w.kind == .challenge { challengeByDay[i, default: 0] += 1 } else { otherByDay[i, default: 0] += 1 }
        }
        var bestSet = Set<Int>()
        var lastBest: Date? = nil
        for d in bestDays {
            let i = calendar.dayCount(from: first, to: d)
            bestSet.insert(i)
            if i <= total, lastBest == nil || d > lastBest! { lastBest = d }
        }

        var m = c.initial
        var g = 0.0
        var mood = band(m, c)
        var daysInMood = c.minHoldDays
        var out: [MomentumDay] = []
        out.reserveCapacity(total + 1)

        for t in 0...total {
            let day = calendar.addingDays(t, to: first)
            var cs = 0, os = 0
            for k in (t - c.windowDays + 1)...t {
                cs += challengeByDay[k] ?? 0
                os += otherByDay[k] ?? 0
            }
            let doseToday = max(0.5, dose(day))
            let normalWeek = doseToday + c.otherWorkoutWeight * max(0, c.expectedOtherPerWeek)
            let a = min(c.activityCap, (Double(cs) + c.otherWorkoutWeight * Double(os)) / normalWeek)
            let isBest = bestSet.contains(t)
            g = max(c.progressDecay * g, isBest ? 1 : 0)
            let x = a + c.progressWeight * g
            m = c.smoothing * x + (1 - c.smoothing) * m
            let next = nextMood(current: mood, m: m, daysInMood: daysInMood, c)
            if next != mood {
                mood = next
                daysInMood = 0
            }
            daysInMood += 1
            out.append(MomentumDay(date: day, challengeSessions: cs, otherWorkouts: os, dose: doseToday,
                                   a: a, g: g, m: m, mood: mood, newBest: isBest))
        }
        return MomentumResult(days: out, lastBestDate: lastBest)
    }

    /// Momentum for the app state at `now`. Starts on the first logged day (or today).
    static func compute(engine: YearEngine, config: MomentumConfig = .standard) -> MomentumResult {
        let cal = engine.rules.calendar
        let now = engine.now
        let dates = engine.state.workouts.map(\.date) + engine.state.entries.map(\.date)
        let start = dates.filter { $0 <= now }.min() ?? now
        let workouts = engine.state.workouts.filter { $0.date <= now }
        let bests = newBestDays(engine: engine).filter { $0 <= now }
        return run(workouts: workouts, bestDays: bests, dose: { engine.weeklyDose(on: $0) },
                   start: start, end: now, calendar: cal, config: config)
    }

    /// Mood shown on screen: a finished current month overrides momentum
    /// (target hit → pumped, under 50 points → tired).
    static func displayMood(momentum: MomentumResult, currentMonth: ResolvedSlot?) -> Mood {
        if let r = currentMonth, r.isFinal, let s = r.score {
            if s >= 100 { return .pumped }
            if s < 50 { return .tired }
        }
        return momentum.mood
    }

    /// One-line explanation for tapping the mascot: "3/3 sessions this week · new best 4 days ago".
    static func explanation(momentum: MomentumResult, now: Date, calendar: Calendar) -> String {
        guard let d = momentum.today else { return "No workouts logged yet" }
        var s = "\(d.challengeSessions)/\(Int(d.dose.rounded())) sessions this week"
        if d.otherWorkouts > 0 { s += " + \(d.otherWorkouts) other" }
        if let b = momentum.lastBestDate {
            let n = calendar.dayCount(from: b, to: now)
            s += n == 0 ? " · new best today" : " · new best \(n) day\(n == 1 ? "" : "s") ago"
        } else {
            s += " · no new best yet"
        }
        return s
    }

    /// Short status for the speech bubble.
    static func status(mood: Mood, momentum: MomentumResult) -> String {
        let d = momentum.today
        let c = d?.challengeSessions ?? 0
        let dose = Int((d?.dose ?? 3).rounded())
        switch mood {
        case .onfire: return "New best and \(c)/\(dose) this week. Unstoppable."
        case .pumped: return "\(c)/\(dose) sessions this week. Keep it going."
        case .steady: return "\(c)/\(dose) this week. One more gets me pumped."
        case .tired: return "Only \(c)/\(dose) this week. Get one in."
        case .slumped: return "Haven't seen the gym in days. Wake me up."
        }
    }
}
