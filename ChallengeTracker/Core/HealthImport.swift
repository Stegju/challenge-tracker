import Foundation

/// A workout read from Apple Health, reduced to what the app needs.
struct HealthWorkout: Equatable, Sendable {
    var id: String              // HKWorkout UUID
    var start: Date
    var durationSeconds: Double
    /// Normalized activity: "running", "cycling", "rowing", "walking", "strength training", ...
    var activity: String
    var distanceKm: Double?

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

    /// Entry value a Health workout gives a challenge, or nil.
    /// - distance challenges (km): the workout's distance
    /// - timed distance challenges (5K, 2K): time scaled to the distance, if the workout was 99 to 110 % of it
    static func entryValue(_ hw: HealthWorkout, challenge ch: Challenge, counted: [String]) -> Double? {
        guard MotraParser.counts(hw.activity, counted: counted) else { return nil }
        switch ch.metric {
        case .number where ch.unit.lowercased() == "km":
            guard let d = hw.distanceKm, d > 0 else { return nil }
            return (d * 100).rounded() / 100
        case .time:
            guard let target = targetDistanceKm(ch), let d = hw.distanceKm, d >= target * 0.99, d <= target * 1.10,
                  hw.durationSeconds > 0 else { return nil }
            return (hw.durationSeconds * target / d).rounded()
        default:
            return nil
        }
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
                counts = MotraParser.counts(hw.activity, counted: counted)
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
