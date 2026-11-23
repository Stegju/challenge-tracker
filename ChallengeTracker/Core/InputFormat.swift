import Foundation

/// What a value field accepts. Typing is filtered and formatted as you go,
/// so only well-formed values can be entered.
enum InputKind: Equatable, Sendable {
    /// Digits fill from the right: "12345" → "1:23:45" (hours) or "2125" → "21:25".
    case time(hours: Bool)
    case decimal(maxDecimals: Int)
    case integer

    var placeholder: String {
        switch self {
        case .time(let h): return h ? "h:mm:ss" : "mm:ss"
        case .decimal: return "0.0"
        case .integer: return "0"
        }
    }
}

enum InputFormat {

    static func kind(for ch: Challenge) -> InputKind {
        switch ch.metric {
        case .time: return .time(hours: ch.unit.lowercased().hasPrefix("h"))
        case .e1rm: return .decimal(maxDecimals: 2)
        case .number: return ch.unit.lowercased().contains("rep") ? .integer : .decimal(maxDecimals: 2)
        }
    }

    static func format(_ text: String, kind: InputKind) -> String {
        switch kind {
        case .time(let hours): return formatTime(text, hours: hours)
        case .decimal(let maxDecimals): return formatDecimal(text, maxDecimals: maxDecimals)
        case .integer: return String(text.filter(\.isASCIIDigit).prefix(4))
        }
    }

    /// Keeps digits only and inserts colons from the right.
    static func formatTime(_ text: String, hours: Bool) -> String {
        var digits = String(text.filter(\.isASCIIDigit))
        // Drop leading zeros beyond what is needed, so "0:21:25" re-formats cleanly.
        while digits.count > 1 && digits.hasPrefix("0") && digits.count > 3 { digits.removeFirst() }
        let maxDigits = hours ? 5 : 4
        if digits.count > maxDigits { digits = String(digits.prefix(maxDigits)) }
        let chars = Array(digits)
        switch chars.count {
        case 0...2: return digits
        case 3, 4:
            return String(chars[0..<(chars.count - 2)]) + ":" + String(chars[(chars.count - 2)...])
        default:
            let h = String(chars[0..<(chars.count - 4)])
            let m = String(chars[(chars.count - 4)..<(chars.count - 2)])
            let s = String(chars[(chars.count - 2)...])
            return h + ":" + m + ":" + s
        }
    }

    /// Digits with one decimal separator ("," becomes "."), at most `maxDecimals` after it.
    static func formatDecimal(_ text: String, maxDecimals: Int) -> String {
        var out = ""
        var seenSep = false
        var decimals = 0
        var intDigits = 0
        for c in text {
            if c.isASCIIDigit {
                if seenSep {
                    guard decimals < maxDecimals else { continue }
                    decimals += 1
                } else {
                    guard intDigits < 5 else { continue }
                    intDigits += 1
                }
                out.append(c)
            } else if (c == "." || c == ",") && !seenSep && maxDecimals > 0 {
                seenSep = true
                out.append(out.isEmpty ? "0." : ".")
            }
        }
        return out
    }

    /// A readable problem with a finished value, or nil if it is fine.
    static func problem(_ text: String, kind: InputKind) -> String? {
        let t = text.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return nil }
        switch kind {
        case .time(let hours):
            guard ValueFormat.parseTime(t) != nil else {
                return "Minutes and seconds must be under 60 (\(hours ? "h:mm:ss" : "mm:ss"))."
            }
            return nil
        case .decimal, .integer:
            return ValueFormat.parseNumber(t) == nil ? "That isn't a number." : nil
        }
    }
}

extension Character {
    var isASCIIDigit: Bool { ("0"..."9").contains(self) }
}
