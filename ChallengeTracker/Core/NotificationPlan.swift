import Foundation

struct NotificationToggles: Codable, Equatable, Sendable {
    var nextSlotEmpty = true
    var baselineBlank = true
    var noResult = true
    var notFinalized = true
    var moodDrop = false
}

struct PlannedNotification: Equatable, Sendable {
    var id: String
    var date: Date
    var title: String
    var body: String
}

/// Local notifications from spec section 7, computed from the state. Pure: the
/// scheduler in Data/ hands these to UNUserNotificationCenter.
enum NotificationPlanner {
    static let hour = 9

    static func plan(engine: YearEngine, toggles: NotificationToggles) -> [PlannedNotification] {
        let rules = engine.rules
        let cal = rules.calendar
        let now = engine.now
        var out: [PlannedNotification] = []

        func at(_ d: Date) -> Date {
            cal.date(bySettingHour: hour, minute: 0, second: 0, of: d) ?? d
        }
        func add(_ id: String, _ d: Date, _ title: String, _ body: String) {
            let when = at(d)
            if when > now { out.append(PlannedNotification(id: id, date: when, title: title, body: body)) }
        }

        for m in 1...12 {
            let r = engine.resolve(m)
            let name = YearConfig.name(m).capitalized
            let lock = rules.lockDate(m)

            if toggles.nextSlotEmpty && !r.isChosen {
                for days in [7, 2] {
                    add("empty-\(m)-\(days)", cal.addingDays(-days, to: lock),
                        "\(name) locks in \(days) days", "Nothing picked yet. Choose a challenge before the 1st.")
                }
            }
            if toggles.baselineBlank && r.isChosen && r.kind != .redo && (r.baseline == nil || r.target == nil) && r.slot.setupLockedAt == nil {
                let days = rules.config.setupDays
                add("baseline-\(m)-1", lock, "Baseline and target for \(name)",
                    "Test your starting point and set a target. Open until day \(days).")
                add("baseline-\(m)-\(days - 1)", cal.addingDays(days - 2, to: lock), "Baseline and target close tomorrow",
                    "\(name) scores 0 without both by the end of day \(days).")
            }
            let end = rules.monthEnd(m)
            if toggles.noResult && r.isChosen && r.entries.isEmpty && !r.isFinal {
                add("noresult-\(m)", cal.addingDays(-3, to: end), "3 days left in \(name)", "No result logged yet.")
            }
            if toggles.notFinalized && r.isChosen && !r.isFinal {
                add("finalize-\(m)", end, "Finalize \(name)", "Lock in your result to bank the points.")
            }
        }
        // iOS keeps at most 64 pending; keep the soonest.
        return Array(out.sorted { $0.date < $1.date }.prefix(60))
    }
}
