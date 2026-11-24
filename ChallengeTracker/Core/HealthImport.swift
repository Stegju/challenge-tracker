import Foundation

/// A workout read from Apple Health, reduced to what the app needs.
struct HealthWorkout: Equatable, Sendable {
    var id: String              // HKWorkout UUID
    var start: Date
    var durationSeconds: Double
    /// Normalized activity: "running", "cycling", "rowing", "walking", "strength training", ...
    var activity: String
    var distanceKm: Double?
    /// Treadmill, indoor cycle, etc. (Health's indoor workout flag).
    var indoor: Bool = false
    /// Fastest stretch in seconds per distance in km, e.g. [5: 1290] (from the workout's distance samples).
    var fastestStretches: [Double: Double] = [:]

    var title: String { activity.prefix(1).uppercased() + activity.dropFirst() }
}

/// Turns Health workouts into workouts and entries (spec section 8). Never finalizes.
enum HealthImport {
    /// A Health workout within this many seconds of a Motra workout is the same session.
    static let matchWindow: TimeInterval = 15 * 60

    /// Distance in km a timed challenge is about, read from its name ("5K run" → 5, "2K row" → 2).
    static func targetDistanceKm(_ ch: Challenge) -> Double? {
        guard let r = ch.name.range(of: #"(\d+(?:[.,]\d+)?)\s*[kK]\b"#, options: .regularExpression) else { return nil }
        let num = ch.name[r].filter { $0.isNumber || $0 == "." || $0 == "," }
        return ValueFormat.parseNumber(String(num))
    }

    /// Does a workout of this activity count as a session for the challenge?
    /// The month's counted exercises always count; `sessionActivities` widens it ("*" = all).
    static func isSession(activity: String, challenge ch: Challenge?, counted: [String]) -> Bool {
        if MotraParser.counts(activity, counted: counted) { return true }
        guard let ch, let list = ch.sessionActivities else { return false }
        if MotraParser.counts(activity, counted: ch.sessionActivitiesExcluded ?? []) { return false }
        return list.contains("*") || MotraParser.counts(activity, counted: list)
    }

    /// Entry value a Health workout gives a challenge, or nil.
    /// - distance challenges (km): the distance of an outdoor workout
    /// - timed distance challenges (5K, 2K): the fastest stretch of that distance inside the workout,
    ///   else the whole workout's time scaled, if it was 99 to 110 % of the distance
    static func entryValue(_ hw: HealthWorkout, challenge ch: Challenge, counted: [String]) -> Double? {
        guard MotraParser.counts(hw.activity, counted: counted) else { return nil }
        switch ch.metric {
        case .number where ch.unit.lowercased() == "km":
            guard !hw.indoor, let d = hw.distanceKm, d > 0 else { return nil }
            return (d * 100).rounded() / 100
        case .time:
            guard let target = targetDistanceKm(ch) else { return nil }
            if let fastest = hw.fastestStretches[target] { return fastest.rounded() }
            guard let d = hw.distanceKm, d >= target * 0.99, d <= target * 1.10, hw.durationSeconds > 0 else { return nil }
            return (hw.durationSeconds * target / d).rounded()
        default:
            return nil
        }
    }

    /// Fastest time to cover `meters` inside a workout, from cumulative (time, distance) points.
    /// Each window is the shortest run of samples covering the distance, time scaled to it exactly.
    static func fastestStretch(_ points: [(t: Double, d: Double)], meters: Double) -> Double? {
        guard meters > 0, let last = points.last, let first = points.first, last.d - first.d >= meters * 0.999 else { return nil }
        var best: Double? = nil
        var i = 0
        for j in points.indices {
            while i + 1 < j && points[j].d - points[i + 1].d >= meters { i += 1 }
            let dd = points[j].d - points[i].d
            guard dd >= meters * 0.999, dd > 0 else { continue }
            let t = (points[j].t - points[i].t) * meters / dd
            if t > 0 { best = min(best ?? t, t) }
        }
        return best
    }

    /// Distances (km) worth computing a fastest stretch for in runs: timed running challenges ("5K run" → 5).
    static func stretchDistances(_ catalogue: Catalogue, activity: String = "running") -> [Double] {
        let timed = catalogue.challenges.filter { $0.metric == .time && MotraParser.counts(activity, counted: $0.countedExercises) }
        return Array(Set(timed.compactMap { targetDistanceKm($0) })).sorted()
    }

    /// Adds Health workouts that aren't in the state yet. Skips ones that duplicate a Motra
    /// import (same session within 15 minutes). Returns how many were added.
    @discardableResult
    static func merge(_ state: inout YearState, workouts: [HealthWorkout], catalogue: Catalogue,
                      rules: LockRules, now: Date) -> Int {
        var added = 0
        for hw in workouts.sorted(by: { $0.start < $1.start }) where hw.start <= now {
            if state.ignoredHealthKitIds.contains(hw.id) || state.workouts.contains(where: { $0.healthKitId == hw.id }) {
                continue
            }
            if state.workouts.contains(where: { $0.source != .healthkit && abs($0.date.timeIntervalSince(hw.start)) <= matchWindow }) {
                state.ignoredHealthKitIds.append(hw.id)
                continue
            }
            let e = YearEngine(state: state, catalogue: catalogue, rules: rules, now: now)
            var value: Double? = nil
            var month: Int? = nil
            var counts = false
            if let m = rules.currentMonth(now: hw.start) {
                let r = e.resolve(m)
                let counted = e.countedExercises(m)
                counts = isSession(activity: hw.activity, challenge: r.challenge, counted: counted)
                if r.isLocked, !r.isFinal, !r.isForfeit, let ch = r.challenge {
                    value = entryValue(hw, challenge: ch, counted: counted)
                    month = m
                }
            }
            let w = Workout(date: hw.start, kind: counts ? .challenge : .other, source: .healthkit, title: hw.title,
                            durationMinutes: hw.durationSeconds / 60, notes: hw.distanceKm.map { String(format: "%.2f km", $0) },
                            healthKitId: hw.id)
            state.workouts.append(w)
            if let v = value, let m = month {
                state.entries.append(Entry(month: m, date: hw.start, value: v, source: .healthkit, workoutId: w.id))
            }
            added += 1
        }
        return added
    }
}
