import Foundation

/// A Concept2 result as shared from ErgData or the online logbook.
struct ErgResult: Equatable, Sendable {
    var meters: Double
    var seconds: Double
    /// "row", "ski" or "bike"
    var machine: String
    /// "c2:<result id>" from the share link, for de-duplication.
    var id: String?
    var link: URL?

    /// Health-style activity name, so the usual rules apply ("rowing" counts for the 2K row).
    var activity: String {
        switch machine {
        case "ski": return "skiing"
        case "bike": return "cycling"
        default: return "rowing"
        }
    }

    /// "2000m row · 8:05.4"
    var title: String {
        "\(ValueFormat.formatNumber(meters))m \(machine) · \(ErgParser.formatTenths(seconds))"
    }
}

/// Reads Concept2 share text, e.g.
/// "I did a 2000m Row workout in a time of 8:05.4 and wanted to share it with you.
///  See the details here: https://log.concept2.com/share/3121134/123417617"
/// and the time-based form "I did a 30:00 Row workout with a distance of 7250m".
enum ErgParser {

    static func parse(_ text: String) -> ErgResult? {
        let machine = #"(row|rowerg|ski|skierg|bike|bikeerg)"#
        let time = #"(\d+(?::\d{1,2}){1,2}(?:[.,]\d+)?)"#
        let meters = #"(\d[\d,.]*)\s*m"#
        // Distance first: "2000m Row workout in a time of 8:05.4"
        if let g = groups(#"\#(meters)\s+\#(machine)\b[^\n]*?time of\s+\#(time)"#, in: text),
           let m = number(g[0]), let s = ValueFormat.parseTime(g[2]) {
            return make(meters: m, seconds: s, machine: g[1], text: text)
        }
        // Time first: "30:00 Row workout with a distance of 7250m"
        if let g = groups(#"\#(time)\s+\#(machine)\b[^\n]*?distance of\s+\#(meters)"#, in: text),
           let s = ValueFormat.parseTime(g[0]), let m = number(g[2]) {
            return make(meters: m, seconds: s, machine: g[1], text: text)
        }
        return nil
    }

    private static func make(meters: Double, seconds: Double, machine raw: String, text: String) -> ErgResult? {
        guard meters > 0, seconds > 0 else { return nil }
        let lower = raw.lowercased()
        let machine = lower.hasPrefix("ski") ? "ski" : (lower.hasPrefix("bike") ? "bike" : "row")
        var id: String? = nil
        var link: URL? = nil
        if let r = text.range(of: #"https?://log\.concept2\.com/[^\s]+"#, options: [.regularExpression, .caseInsensitive]) {
            link = URL(string: String(text[r]))
            if let g = groups(#"/share/\d+/(\d+)"#, in: String(text[r])) { id = "c2:\(g[0])" }
        }
        return ErgResult(meters: meters, seconds: seconds, machine: machine, id: id, link: link)
    }

    /// "2,000" / "2.000" / "2000" → 2000 (Concept2 distances are whole metres).
    private static func number(_ s: String) -> Double? {
        Double(s.filter(\.isASCIIDigit))
    }

    private static func groups(_ pattern: String, in text: String) -> [String]? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let ns = text as NSString
        guard let m = re.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return (1..<m.numberOfRanges).map { i in
            let r = m.range(at: i)
            return r.location == NSNotFound ? "" : ns.substring(with: r)
        }
    }

    /// 485.4 → "8:05.4"
    static func formatTenths(_ seconds: Double) -> String {
        let tenths = Int((seconds * 10).rounded())
        let m = tenths / 600, s = (tenths % 600) / 10, t = tenths % 10
        if m >= 60 { return String(format: "%d:%02d:%02d.%d", m / 60, m % 60, s, t) }
        return String(format: "%d:%02d.%d", m, s, t)
    }

    static let monthNames = ["january", "february", "march", "april", "may", "june", "july",
                             "august", "september", "october", "november", "december"]

    /// Workout date on the logbook page, e.g. "November 27, 2026" (with an optional "6:40 pm"), if found.
    static func date(inPage text: String, calendar: Calendar) -> Date? {
        let pattern = #"(January|February|March|April|May|June|July|August|September|October|November|December|Jan|Feb|Mar|Apr|Jun|Jul|Aug|Sep|Sept|Oct|Nov|Dec)\.?\s+(\d{1,2}),?\s+(\d{4})(?:[^\d\n]{0,12}(\d{1,2}):(\d{2})\s*(am|pm)?)?"#
        guard let g = groups(pattern, in: text) else { return nil }
        let name = g[0].lowercased()
        guard let month = monthNames.firstIndex(where: { $0.hasPrefix(String(name.prefix(3))) }).map({ $0 + 1 }),
              let day = Int(g[1]), let year = Int(g[2]) else { return nil }
        var hour = Int(g[3]) ?? 12
        let minute = Int(g[4]) ?? 0
        if g[5].lowercased() == "pm" && hour < 12 { hour += 12 }
        if g[5].lowercased() == "am" && hour == 12 { hour = 0 }
        return calendar.date(year: year, month: month, day: day, hour: hour, minute: minute)
    }
}
