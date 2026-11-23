import Foundation
import Observation
import SwiftUI
import UserNotifications
import WidgetKit

/// The single source of truth for the UI. Holds the real year and the test-mode
/// sandbox, applies rule-checked mutations and saves after each change.
@Observable
@MainActor
final class AppStore {
    let catalogue: Catalogue
    let rules = LockRules()

    private(set) var real: YearState
    private(set) var sandbox: YearState?
    var settings: AppSettings {
        didSet {
            if settings != oldValue {
                Persistence.save(settings, to: Persistence.settingsURL)
                if settings.notifications != oldValue.notifications { scheduleNotifications() }
            }
        }
    }
    /// Bumped periodically so derived values that depend on "now" refresh.
    var tick = Date()
    /// Last rule violation, shown as a toast.
    var message: String?

    init() {
        let cat = Catalogue.bundled()
        catalogue = cat
        settings = Persistence.load(AppSettings.self, from: Persistence.settingsURL) ?? AppSettings()
        var year = Persistence.load(YearState.self, from: Persistence.yearURL) ?? YearState.fresh(catalogue: cat)
        if year.slots.count != 12 { year = YearState.fresh(catalogue: cat) }
        YearActions.refreshSnapshots(&year, catalogue: cat, rules: LockRules(), now: Date())
        real = year
        sandbox = Persistence.load(YearState.self, from: Persistence.sandboxURL)
        if settings.testMode && sandbox == nil {
            sandbox = DemoData.make(catalogue: cat, until: settings.testDate)
        }
        AppLog.add("Launch. Test mode \(settings.testMode ? "on" : "off").")
    }

    // MARK: Derived

    var isTestMode: Bool { settings.testMode }
    var state: YearState { isTestMode ? (sandbox ?? real) : real }
    var dates: DateProvider { DateProvider(testDate: isTestMode ? settings.testDate : nil) }
    var now: Date {
        _ = tick
        return dates.now()
    }
    var calendar: Calendar { rules.calendar }
    var engine: YearEngine { YearEngine(state: state, catalogue: catalogue, rules: rules, now: now) }
    var momentum: MomentumResult { MomentumEngine.compute(engine: engine) }

    var currentMonth: Int? { rules.currentMonth(now: now) }
    var isBeforeYear: Bool { rules.isBeforeYear(now) }

    var displayMood: Mood {
        let e = engine
        return MomentumEngine.displayMood(momentum: momentum, currentMonth: currentMonth.map { e.resolve($0) })
    }

    // MARK: Mutations

    /// Runs a rule-checked change on the visible state and saves it.
    @discardableResult
    func mutate(_ what: String, _ change: (inout YearState, YearEngine) throws -> Void) -> Bool {
        var s = state
        let e = engine
        do {
            try change(&s, e)
        } catch let err as YearActions.ActionError {
            message = Self.describe(err)
            AppLog.add("\(what) refused: \(err)")
            return false
        } catch {
            message = "Something went wrong."
            AppLog.add("\(what) failed: \(error)")
            return false
        }
        commit(s)
        AppLog.add(what)
        return true
    }

    private func commit(_ s: YearState) {
        if isTestMode {
            sandbox = s
            Persistence.save(s, to: Persistence.sandboxURL)
        } else {
            real = s
            Persistence.save(s, to: Persistence.yearURL)
            afterRealChange()
        }
    }

    static func describe(_ e: YearActions.ActionError) -> String {
        switch e {
        case .locked: return "Locked. That can't change any more."
        case .notAllowed: return "Not allowed right now."
        case .invalidTarget(.equalsBaseline): return "Target can't equal the baseline."
        case .invalidTarget(.wrongSide): return "Target is on the wrong side of the baseline."
        }
    }

    func chooseNew(month: Int, challenge: Challenge) -> Bool {
        mutate("Chose \(challenge.id) for \(month)") { s, e in try YearActions.chooseNew(&s, month: month, challenge: challenge, engine: e) }
    }

    func chooseRedo(month: Int, sourceMonth: Int) -> Bool {
        mutate("Chose redo of \(sourceMonth) for \(month)") { s, e in try YearActions.chooseRedo(&s, month: month, sourceMonth: sourceMonth, engine: e) }
    }

    func clearChoice(month: Int) {
        mutate("Cleared \(month)") { s, e in try YearActions.clearChoice(&s, month: month, engine: e) }
    }

    @discardableResult
    func setBaseline(month: Int, value: Double?) -> Bool {
        mutate("Baseline \(month)") { s, e in try YearActions.setBaseline(&s, month: month, value: value, engine: e) }
    }

    @discardableResult
    func setTarget(month: Int, value: Double?) -> Bool {
        mutate("Target \(month)") { s, e in try YearActions.setTarget(&s, month: month, value: value, engine: e) }
    }

    /// Adds an entry; optionally logs a challenge session that day if none exists yet.
    @discardableResult
    func addEntry(_ entry: Entry, alsoLogSession: Bool) -> Bool {
        mutate("Entry \(entry.month)") { s, e in
            try YearActions.addEntry(&s, entry, engine: e)
            if alsoLogSession {
                let cal = e.rules.calendar
                let has = s.workouts.contains { $0.kind == .challenge && cal.isDate($0.date, inSameDayAs: entry.date) }
                if !has { s.workouts.append(Workout(date: entry.date, kind: .challenge, source: entry.source)) }
            }
        }
    }

    func deleteEntry(_ id: UUID) {
        mutate("Deleted entry") { s, e in try YearActions.deleteEntry(&s, id: id, engine: e) }
    }

    func finalize(month: Int) {
        mutate("Finalized \(month)") { s, e in try YearActions.finalize(&s, month: month, engine: e) }
    }

    func addWorkout(_ w: Workout) {
        mutate("Workout \(w.kind.rawValue)") { s, _ in s.workouts.append(w) }
    }

    func deleteWorkout(_ id: UUID) {
        mutate("Deleted workout") { s, _ in s.workouts.removeAll { $0.id == id } }
    }

    func toggleCounted(exercise: String, month: Int) {
        mutate("Toggled counted \(exercise)") { s, _ in
            s.update(month) { slot in
                let n = MotraParser.normalize(exercise)
                if let i = slot.extraCountedExercises.firstIndex(where: { MotraParser.normalize($0) == n }) {
                    slot.extraCountedExercises.remove(at: i)
                } else {
                    slot.extraCountedExercises.append(exercise)
                }
            }
        }
    }

    /// Catalogue counted exercises plus the month's extras.
    func countedExercises(month: Int) -> [String] {
        let r = engine.resolve(month)
        return (r.challenge?.countedExercises ?? []) + r.slot.extraCountedExercises
    }

    func resetYear() {
        let fresh = YearState.fresh(catalogue: catalogue)
        commit(fresh)
        AppLog.add("Reset year (\(isTestMode ? "sandbox" : "real"))")
    }

    // MARK: Test mode

    func enterTestMode(at date: Date? = nil) {
        if let date { settings.testDate = date }
        if sandbox == nil {
            let demo = DemoData.make(catalogue: catalogue, until: settings.testDate)
            sandbox = demo
            Persistence.save(demo, to: Persistence.sandboxURL)
        }
        settings.testMode = true
        AppLog.add("Entered test mode at \(settings.testDate)")
    }

    func exitTestMode() {
        settings.testMode = false
        tick = Date()
        AppLog.add("Exited test mode")
    }

    func resetDemo() {
        let demo = DemoData.make(catalogue: catalogue, until: settings.testDate)
        sandbox = demo
        Persistence.save(demo, to: Persistence.sandboxURL)
        AppLog.add("Demo data refilled")
    }

    // MARK: Backup

    func exportData() -> Data? {
        try? Persistence.encoder.encode(state)
    }

    func exportFileURL() -> URL? {
        guard let data = exportData() else { return nil }
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        let name = "challenge-tracker-\(isTestMode ? "test-" : "")\(f.string(from: Date())).json"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        do {
            try data.write(to: url, options: .atomic)
            settings.lastExport = Date()
            return url
        } catch {
            AppLog.add("Export failed: \(error)")
            return nil
        }
    }

    func restore(from url: URL) -> Bool {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url),
              let s = try? Persistence.decoder.decode(YearState.self, from: data),
              s.slots.count == 12 else {
            message = "That file isn't a valid backup."
            return false
        }
        commit(s)
        AppLog.add("Restored backup (\(s.entries.count) entries, \(s.workouts.count) workouts)")
        message = "Backup restored."
        return true
    }

    // MARK: Side effects (real data only)

    private func afterRealChange() {
        writeWidgetSnapshot()
        scheduleNotifications()
    }

    func writeWidgetSnapshot() {
        let e = YearEngine(state: real, catalogue: catalogue, rules: rules, now: Date())
        let snap = WidgetSnapshotBuilder.make(engine: e)
        Persistence.save(snap, to: Persistence.widgetURL)
        WidgetCenter.shared.reloadAllTimelines()
    }

    func scheduleNotifications() {
        let e = YearEngine(state: real, catalogue: catalogue, rules: rules, now: Date())
        let plan = NotificationPlanner.plan(engine: e, toggles: settings.notifications)
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        for p in plan {
            let content = UNMutableNotificationContent()
            content.title = p.title
            content.body = p.body
            content.sound = .default
            let comps = rules.calendar.dateComponents([.year, .month, .day, .hour, .minute], from: p.date)
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            center.add(UNNotificationRequest(identifier: p.id, content: content, trigger: trigger)) { _ in }
        }
    }

    func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            Task { @MainActor in
                AppLog.add("Notifications \(granted ? "allowed" : "denied")")
            }
        }
    }

    /// Called when the app becomes active.
    func refresh() {
        tick = Date()
        var s = real
        YearActions.refreshSnapshots(&s, catalogue: catalogue, rules: rules, now: Date())
        if s != real {
            real = s
            Persistence.save(s, to: Persistence.yearURL)
        }
        afterRealChange()
    }
}

enum WidgetSnapshotBuilder {
    static func make(engine e: YearEngine) -> WidgetSnapshot {
        let mom = MomentumEngine.compute(engine: e)
        let month = e.rules.currentMonth(now: e.now)
        let r = month.map { e.resolve($0) }
        let mood = MomentumEngine.displayMood(momentum: mom, currentMonth: r)
        var title = "2027 · STARTS SOON"
        var best = "—"
        var target = "—"
        var score = 0
        var daysLabel = ""
        if let r, let m = month {
            let name = r.challenge.map { WidgetSnapshotBuilder.shortName($0) } ?? "NOT CHOSEN"
            title = "\(YearConfig.short(m)) · \(name)"
            if let ch = r.challenge {
                best = r.best.map { ValueFormat.format($0, metric: ch.metric) } ?? "—"
                target = r.target.map { ValueFormat.format($0, metric: ch.metric) } ?? "—"
            }
            score = r.score ?? 0
            daysLabel = "\(e.rules.daysLeft(m, now: e.now))D LEFT"
        } else if e.rules.isBeforeYear(e.now) {
            daysLabel = "\(e.rules.daysUntilLock(1, now: e.now))D TO GO"
        }
        return WidgetSnapshot(mood: mood.rawValue, moodLabel: mood.label, title: title, best: best, target: target,
                              score: score, daysLeftLabel: daysLabel, points: e.yearTotal,
                              isBoss: r?.isBoss ?? false, updated: Date())
    }

    /// "PULL-UPS" from "Max pull-ups"; uppercase name otherwise.
    static func shortName(_ ch: Challenge) -> String {
        var n = ch.name
        for prefix in ["Max ", "Long "] where n.hasPrefix(prefix) && ch.id != "run-long" && ch.id != "bike-long" {
            n = String(n.dropFirst(prefix.count))
        }
        return n.uppercased()
    }
}
