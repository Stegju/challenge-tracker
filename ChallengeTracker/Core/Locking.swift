import Foundation

struct LockConfig: Sendable {
    /// Baseline can be entered on days 1...baselineGraceDays of the month.
    var baselineGraceDays = 3
    /// The next-month card on Home shows this many days before a lock.
    var nextMonthCardDays = 3
    var redosPerYear = 2
    var year = YearConfig.year

    static let standard = LockConfig()
}

enum MonthPhase: Equatable, Sendable {
    case upcoming   // before the 1st, 00:00
    case active     // during the month
    case ended      // after the last day
}

struct LockRules: Sendable {
    var config: LockConfig = .standard
    var calendar: Calendar = DateProvider.defaultCalendar

    /// 00:00 local on the 1st of the month.
    func lockDate(_ month: Int) -> Date {
        calendar.date(year: config.year, month: month, day: 1)
    }

    /// 00:00 on the 1st of the following month.
    func monthEnd(_ month: Int) -> Date {
        if month >= 12 { return calendar.date(year: config.year + 1, month: 1, day: 1) }
        return calendar.date(year: config.year, month: month + 1, day: 1)
    }

    /// End of the baseline window: 00:00 on day (grace + 1).
    func baselineClose(_ month: Int) -> Date {
        calendar.date(year: config.year, month: month, day: config.baselineGraceDays + 1)
    }

    func isLocked(_ month: Int, now: Date) -> Bool { now >= lockDate(month) }

    func phase(_ month: Int, now: Date) -> MonthPhase {
        if now < lockDate(month) { return .upcoming }
        if now < monthEnd(month) { return .active }
        return .ended
    }

    func canEditChoice(_ month: Int, now: Date) -> Bool { !isLocked(month, now: now) }
    func canEditTarget(_ month: Int, now: Date) -> Bool { !isLocked(month, now: now) }
    func canEditBaseline(_ month: Int, now: Date) -> Bool { now < baselineClose(month) }

    /// Entries are accepted from the lock until the month ends (and later, until finalized,
    /// so a result from the last day can still be typed in).
    func canAddEntry(_ month: Int, now: Date) -> Bool { isLocked(month, now: now) }

    /// The month we are in, or nil outside the challenge year.
    func currentMonth(now: Date) -> Int? {
        let c = calendar.dateComponents([.year, .month], from: now)
        guard c.year == config.year, let m = c.month else { return nil }
        return m
    }

    var yearStart: Date { lockDate(1) }
    var yearEnd: Date { monthEnd(12) }

    func isBeforeYear(_ now: Date) -> Bool { now < yearStart }
    func isAfterYear(_ now: Date) -> Bool { now >= yearEnd }

    /// The month whose lock comes next (1...12), or nil after December has locked.
    func nextLockMonth(now: Date) -> Int? {
        (1...12).first { lockDate($0) > now }
    }

    /// Whole days until the next lock of `month` (ceil, 0 when it locks today).
    func daysUntilLock(_ month: Int, now: Date) -> Int {
        let secs = lockDate(month).timeIntervalSince(now)
        if secs <= 0 { return 0 }
        return Int((secs / 86_400).rounded(.up))
    }

    /// Days left in the month including today.
    func daysLeft(_ month: Int, now: Date) -> Int {
        max(0, calendar.dayCount(from: now, to: monthEnd(month)))
    }
}
