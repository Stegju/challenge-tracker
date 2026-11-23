import Foundation

/// Sample year for test mode, matching the artboards: January 5K run done (81),
/// February bench maxed (120), March pull-ups live (12 → 18, best 15).
enum DemoData {
    static let defaultTestDate: Date = DateProvider.defaultCalendar.date(year: YearConfig.year, month: 3, day: 14, hour: 18)

    static func make(catalogue: Catalogue, until end: Date, calendar: Calendar = DateProvider.defaultCalendar) -> YearState {
        var s = YearState.fresh(catalogue: catalogue)
        let y = YearConfig.year
        func d(_ m: Int, _ day: Int, _ h: Int = 7) -> Date { calendar.date(year: y, month: m, day: day, hour: h) }

        func set(_ m: Int, _ id: String, baseline: Double, target: Double) {
            guard let ch = catalogue.challenge(id: id) else { return }
            s.update(m) { slot in
                slot.kind = .new
                slot.challengeId = id
                slot.snapshot = ch
                slot.baseline = baseline
                slot.target = target
            }
        }

        set(1, "run-5k", baseline: 1390, target: 1260)
        set(2, "bench-e1rm", baseline: 90, target: 100)
        set(3, "pullups-max", baseline: 12, target: 18)

        var entries: [Entry] = [
            Entry(month: 1, date: d(1, 10), value: 1360),
            Entry(month: 1, date: d(1, 20), value: 1315),
            Entry(month: 1, date: d(1, 28), value: 1285),
            Entry(month: 2, date: d(2, 8), value: 95, weightKg: 85, reps: 3),
            Entry(month: 2, date: d(2, 16), value: 100, weightKg: 90, reps: 3),
            Entry(month: 2, date: d(2, 25), value: 102.5, weightKg: 95, reps: 2),
            Entry(month: 3, date: d(3, 2), value: 12),
            Entry(month: 3, date: d(3, 7), value: 13),
            Entry(month: 3, date: d(3, 11), value: 15, source: .motra)
        ]
        entries = entries.filter { $0.date <= end }
        s.entries = entries

        for (m, last) in [(1, 1285.0), (2, 102.5)] where calendar.date(year: y, month: m + 1, day: 1) <= end {
            s.update(m) { slot in
                slot.finalResult = last
                slot.isFinal = true
            }
        }

        // Training pattern: challenge sessions Mon/Wed/Fri, other workouts Tue/Sat.
        var workouts: [Workout] = []
        var day = calendar.date(year: y, month: 1, day: 1)
        let stop = min(end, calendar.date(year: y + 1, month: 1, day: 1))
        while day <= stop {
            let wd = calendar.component(.weekday, from: day) // 1 Sun ... 7 Sat
            switch wd {
            case 2, 4, 6:
                workouts.append(Workout(date: calendar.date(bySettingHour: 7, minute: 0, second: 0, of: day) ?? day,
                                        kind: .challenge, title: "Challenge session", durationMinutes: 45))
            case 3, 7:
                workouts.append(Workout(date: calendar.date(bySettingHour: 18, minute: 0, second: 0, of: day) ?? day,
                                        kind: .other, title: "Hypertrophy", durationMinutes: 60))
            default:
                break
            }
            day = calendar.addingDays(1, to: day)
        }
        s.workouts = workouts.filter { $0.date <= end }
        return s
    }
}
