import Foundation

/// Everything that reads "now" goes through this, so test mode works everywhere.
struct DateProvider: Sendable {
    var testDate: Date?
    var calendar: Calendar

    init(testDate: Date? = nil, calendar: Calendar = DateProvider.defaultCalendar) {
        self.testDate = testDate
        self.calendar = calendar
    }

    func now() -> Date { testDate ?? Date() }

    var isTest: Bool { testDate != nil }

    static var defaultCalendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone.current
        c.locale = Locale(identifier: "en_GB")
        c.firstWeekday = 2 // Monday
        return c
    }
}

extension Calendar {
    func date(year: Int, month: Int, day: Int, hour: Int = 0, minute: Int = 0) -> Date {
        var dc = DateComponents()
        dc.year = year
        dc.month = month
        dc.day = day
        dc.hour = hour
        dc.minute = minute
        return self.date(from: dc) ?? Date(timeIntervalSince1970: 0)
    }

    func addingDays(_ n: Int, to d: Date) -> Date {
        date(byAdding: .day, value: n, to: d) ?? d
    }

    /// Whole calendar days from a to b (b - a), based on start of day.
    func dayCount(from a: Date, to b: Date) -> Int {
        dateComponents([.day], from: startOfDay(for: a), to: startOfDay(for: b)).day ?? 0
    }
}
