import Foundation

/// Parsing and formatting of challenge values. Time is stored in seconds,
/// e1RM in kg, numbers as typed.
enum ValueFormat {

    // MARK: Parsing

    /// Accepts "h:mm:ss", "mm:ss" or plain seconds. Returns nil if malformed.
    static func parseTime(_ text: String) -> Double? {
        let t = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard !t.isEmpty else { return nil }
        let parts = t.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 1, parts.count <= 3 else { return nil }
        var total = 0.0
        for (i, p) in parts.enumerated() {
            guard let v = Double(p), v >= 0 else { return nil }
            // Minutes and seconds after the first field must be below 60.
            if i > 0 && v >= 60 { return nil }
            total = total * 60 + v
        }
        return total
    }

    /// Accepts "12", "12.5", "12,5".
    static func parseNumber(_ text: String) -> Double? {
        let t = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard !t.isEmpty, let v = Double(t), v.isFinite else { return nil }
        return v
    }

    /// e1RM = w (1 + r / 30), rounded to 0.5 kg.
    static func e1rm(weightKg: Double, reps: Int) -> Double {
        let raw = weightKg * (1 + Double(reps) / 30)
        return (raw * 2).rounded() / 2
    }

    /// Parses a value for the metric. For e1rm, a plain number is taken as kg (used for baseline/target).
    static func parse(_ text: String, metric: Metric) -> Double? {
        switch metric {
        case .time: return parseTime(text)
        case .number, .e1rm: return parseNumber(text)
        }
    }

    // MARK: Formatting

    static func formatTime(_ seconds: Double) -> String {
        let s = Int(seconds.rounded())
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, sec) }
        return String(format: "%d:%02d", m, sec)
    }

    static func formatNumber(_ v: Double) -> String {
        if v == v.rounded() { return String(Int(v)) }
        let s = String(format: "%.2f", v)
        var trimmed = s
        while trimmed.hasSuffix("0") { trimmed.removeLast() }
        if trimmed.hasSuffix(".") { trimmed.removeLast() }
        return trimmed
    }

    /// Value only, no unit: "21:25", "102.5", "15".
    static func format(_ v: Double, metric: Metric) -> String {
        switch metric {
        case .time: return formatTime(v)
        case .number, .e1rm: return formatNumber(v)
        }
    }

    /// Short unit suffix for display after a number, or "" for time.
    static func unitSuffix(_ ch: Challenge) -> String {
        switch ch.metric {
        case .time: return ""
        case .e1rm: return "kg"
        case .number: return ch.unit
        }
    }

    /// "21:25", "102.5 kg", "15 reps".
    static func formatWithUnit(_ v: Double, _ ch: Challenge) -> String {
        let u = unitSuffix(ch)
        return u.isEmpty ? format(v, metric: ch.metric) : "\(format(v, metric: ch.metric)) \(u)"
    }

    /// "REPS · HIGHER WINS", "TIME · FASTER WINS".
    static func metricLabel(_ ch: Challenge) -> String {
        switch ch.metric {
        case .time: return ch.direction == .lower ? "TIME · FASTER WINS" : "TIME · LONGER WINS"
        case .e1rm: return "E1RM · KG"
        case .number:
            let u = ch.unit.uppercased()
            return ch.direction == .lower ? "\(u) · LOWER WINS" : u
        }
    }

    /// "Reps, higher", "Time, lower".
    static func metricShort(_ ch: Challenge) -> String {
        let what: String
        switch ch.metric {
        case .time: what = "Time"
        case .e1rm: what = "e1RM kg"
        case .number: what = ch.unit.prefix(1).uppercased() + ch.unit.dropFirst()
        }
        return "\(what), \(ch.direction.rawValue)"
    }

    /// Hint for the input field.
    static func inputHint(_ ch: Challenge) -> String {
        switch ch.metric {
        case .time: return ch.unit == "h:mm:ss" ? "h:mm:ss" : "mm:ss"
        case .e1rm: return "kg"
        case .number: return ch.unit.uppercased()
        }
    }
}
