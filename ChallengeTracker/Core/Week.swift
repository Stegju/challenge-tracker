import Foundation

/// Data for the "This week" panel on Home: Monday to Sunday of the week containing `now`.
struct WeekSummary: Equatable, Sendable {
    enum Block: Equatable, Sendable {
        case challenge, other
    }
    struct Day: Equatable, Sendable {
        var date: Date
        var letter: String
        var blocks: [Block]
        var isToday: Bool
        var isFuture: Bool
    }

    var days: [Day]
    var challengeCount: Int
    var otherCount: Int
    var dose: Int

    /// "2/3 CHALLENGE · 4 OTHER"
    var label: String { "\(challengeCount)/\(dose) CHALLENGE · \(otherCount) OTHER" }

    init(workouts: [Workout], now: Date, dose: Double, calendar: Calendar) {
        var cal = calendar
        cal.firstWeekday = 2
        let today = cal.startOfDay(for: now)
        let weekday = cal.component(.weekday, from: today) // 1 = Sunday
        let offsetFromMonday = (weekday + 5) % 7
        let monday = cal.addingDays(-offsetFromMonday, to: today)
        let letters = ["M", "T", "W", "T", "F", "S", "S"]
        var days: [Day] = []
        var c = 0, o = 0
        for i in 0..<7 {
            let d = cal.addingDays(i, to: monday)
            let items = workouts.filter { cal.isDate($0.date, inSameDayAs: d) }.sorted { $0.date < $1.date }
            let blocks: [Block] = items.map { $0.kind == .challenge ? .challenge : .other }
            c += blocks.filter { $0 == .challenge }.count
            o += blocks.filter { $0 == .other }.count
            days.append(Day(date: d, letter: letters[i], blocks: blocks,
                            isToday: cal.isDate(d, inSameDayAs: today), isFuture: d > today))
        }
        self.days = days
        challengeCount = c
        otherCount = o
        self.dose = Int(dose.rounded())
    }
}
