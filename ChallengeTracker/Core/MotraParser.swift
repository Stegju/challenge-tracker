import Foundation

struct ParsedWorkout: Equatable, Sendable {
    var name: String
    var date: Date?
    var durationMinutes: Double?
    var volumeKg: Double?
    var kcal: Double?
    var exercises: [ParsedExercise]

    var setCount: Int { exercises.reduce(0) { $0 + $1.sets.count } }
}

/// Best set of an exercise, ignoring warm-ups and drop sets.
struct ExerciseBest: Equatable, Sendable {
    var reps: Int
    var weightKg: Double?
    var e1rm: Double?
    /// e1RM above 10 reps is flagged unreliable.
    var unreliable: Bool
}

/// Lenient parser for workout text shared from Motra (spec section 8).
/// Real export shape (see ParserTests.realExport):
///
///     My workout:
///
///     Monday upper
///     23 Nov 2026 at 6:10
///
///     Duration: 46m
///     Volume: 6,7K kg
///     Calories: 307 cal
///     Exercises: 6
///
///     Pull-Up
///     Warm Up: 7 reps x BW
///     1: 8 reps x BW
///     Drop Set: 7 reps x 40 kg
///
///     Tracked with Motra.
///     https://motra.com/share/workout/...
enum MotraParser {

    static func parse(_ text: String, calendar: Calendar = DateProvider.defaultCalendar) -> ParsedWorkout? {
        let lines = text.replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard !lines.isEmpty else { return nil }

        var name: String? = nil
        var date: Date? = nil
        var duration: Double? = nil
        var volume: Double? = nil
        var kcal: Double? = nil
        var exercises: [ParsedExercise] = []
        var pendingType: SetType = .normal
        var lastNonSetLine: String? = nil

        for line in lines {
            let lower = line.lowercased()
            if lower.hasPrefix("http") || lower.contains("://") { continue }
            // "Tracked with Motra." ends the workout; anything after it (a second copy) is ignored.
            if lower.hasPrefix("tracked with") { break }
            if lower.contains("motra") && !lower.contains(":") && !exercises.isEmpty { continue }
            // Header labels like "My workout:".
            if line.hasSuffix(":") && !line.contains(where: { $0.isNumber }) && exercises.isEmpty { continue }

            if date == nil, let d = parseDate(line, calendar: calendar) {
                date = d
                continue
            }
            if let set = parseSet(line, type: pendingType) {
                if exercises.last == nil || lastNonSetLine != nil {
                    let exName = lastNonSetLine ?? "Exercise"
                    exercises.append(ParsedExercise(name: exName, sets: []))
                    lastNonSetLine = nil
                }
                exercises[exercises.count - 1].sets.append(set)
                pendingType = .normal
                continue
            }
            if let t = setTypeLabel(lower) {
                pendingType = t
                continue
            }
            if exercises.isEmpty {
                if duration == nil, let d = parseDuration(lower) { duration = d; continue }
                if volume == nil, let v = parseVolume(lower) { volume = v; continue }
                if kcal == nil, let k = parseKcal(lower) { kcal = k; continue }
                if lower.range(of: #"^\d+\s+exercises?$"#, options: .regularExpression) != nil { continue }
                if lower.range(of: #"^exercises?\s*:\s*\d+$"#, options: .regularExpression) != nil { continue }
            }
            if name == nil {
                name = line
                continue
            }
            lastNonSetLine = line
        }

        // A trailing name line with no sets (a footer) is dropped.
        exercises = exercises.filter { !$0.sets.isEmpty }
        guard name != nil || !exercises.isEmpty else { return nil }
        return ParsedWorkout(name: name ?? "Workout", date: date, durationMinutes: duration,
                             volumeKg: volume, kcal: kcal, exercises: exercises)
    }

    // MARK: Pieces

    static func normalize(_ exercise: String) -> String {
        let lowered = exercise.lowercased()
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
        var s = ""
        for scalar in lowered.unicodeScalars where CharacterSet.alphanumerics.contains(scalar) || scalar == " " {
            s.unicodeScalars.append(scalar)
        }
        let words = s.split(separator: " ").map(String.init)
        // "pull ups" → "pull up", "push-ups" → "push up"
        var out = words
        if let lastWord = out.last, lastWord.count >= 3, lastWord.hasSuffix("s"), !lastWord.hasSuffix("ss") {
            out[out.count - 1] = String(lastWord.dropLast())
        }
        return out.joined(separator: " ")
    }

    static func setTypeLabel(_ lower: String) -> SetType? {
        let l = lower.replacingOccurrences(of: "-", with: " ")
        if l == "warm up" || l == "warmup" || l == "warm up set" { return .warmup }
        if l == "drop set" || l == "dropset" { return .drop }
        return nil
    }

    /// "1: 9 reps x 80 kg", "2: 15 reps x BW", "Warm Up: 15 reps x 40 kg", "Drop Set: 7 reps x 40 kg",
    /// "3. 8 x 72,5 kg". A warm-up or drop label may also sit on the line before.
    /// Labelled sets get index 0.
    static func parseSet(_ line: String, type: SetType) -> ParsedSet? {
        let pattern = #"^(warm[\s-]*up|drop[\s-]*set|\d+)\s*[:.)]\s*(\d+)\s*(?:reps?)?\s*(?:[x×*]\s*([0-9]+(?:[.,][0-9]+)?\s*(?:kg)?|bw|bodyweight))?\s*(.*)$"#
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let ns = line as NSString
        guard let m = re.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) else { return nil }
        func g(_ i: Int) -> String? {
            let r = m.range(at: i)
            return r.location == NSNotFound ? nil : ns.substring(with: r)
        }
        guard let head = g(1)?.lowercased(), let reps = g(2).flatMap({ Int($0) }) else { return nil }
        var t = type
        var idx = 0
        if head.hasPrefix("warm") {
            t = .warmup
        } else if head.hasPrefix("drop") {
            t = .drop
        } else {
            idx = Int(head) ?? 0
        }
        var weight: Double? = nil
        if let w = g(3)?.lowercased(), !w.hasPrefix("b") {
            let num = w.replacingOccurrences(of: "kg", with: "").trimmingCharacters(in: .whitespaces)
            weight = ValueFormat.parseNumber(num)
        }
        if let tail = g(4)?.lowercased() {
            if tail.contains("warm") { t = .warmup }
            if tail.contains("drop") { t = .drop }
        }
        return ParsedSet(index: idx, setType: t, reps: reps, weightKg: weight)
    }

    static let monthMap: [String: Int] = ["jan": 1, "feb": 2, "mar": 3, "apr": 4, "may": 5, "jun": 6,
                                          "jul": 7, "aug": 8, "sep": 9, "oct": 10, "nov": 11, "dec": 12]

    /// "16 Nov 2026 at 6:15" or "16 Nov 2026, 06:15" or "16 Nov 2026".
    static func parseDate(_ line: String, calendar: Calendar) -> Date? {
        let pattern = #"(\d{1,2})\s+([A-Za-z]{3})[A-Za-z]*\.?\s+(\d{4})(?:\s*(?:at|,)?\s*(\d{1,2})[:.](\d{2}))?"#
        guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = line as NSString
        guard let m = re.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) else { return nil }
        func g(_ i: Int) -> String? {
            let r = m.range(at: i)
            return r.location == NSNotFound ? nil : ns.substring(with: r)
        }
        guard let d = g(1).flatMap({ Int($0) }), let mon = g(2).flatMap({ monthMap[$0.lowercased()] }),
              let y = g(3).flatMap({ Int($0) }) else { return nil }
        let h = g(4).flatMap { Int($0) } ?? 12
        let mi = g(5).flatMap { Int($0) } ?? 0
        return calendar.date(year: y, month: mon, day: d, hour: h, minute: mi)
    }

    /// "Duration: 46m", "58 min", "1h 5m", "58:12".
    static func parseDuration(_ lower: String) -> Double? {
        let looksLikeDuration = lower.contains("duration") || lower.contains("time")
            || lower.range(of: #"^\d+\s*(h|m|min)\b"#, options: .regularExpression) != nil
        guard looksLikeDuration else { return nil }
        var minutes = 0.0
        var found = false
        if let r = lower.range(of: #"(\d+)\s*h"#, options: .regularExpression) {
            minutes += (Double(lower[r].filter(\.isNumber)) ?? 0) * 60
            found = true
        }
        if let r = lower.range(of: #"(\d+)\s*m(?:in)?\b"#, options: .regularExpression) {
            minutes += Double(lower[r].filter(\.isNumber)) ?? 0
            found = true
        }
        if !found, let r = lower.range(of: #"\d+:\d{2}(:\d{2})?"#, options: .regularExpression),
           let secs = ValueFormat.parseTime(String(lower[r])) {
            minutes = secs / 60
            found = true
        }
        return found ? minutes : nil
    }

    /// "Volume: 6,3K kg", "6300 kg".
    static func parseVolume(_ lower: String) -> Double? {
        guard lower.contains("kg"), !lower.contains("rep") else { return nil }
        guard let r = lower.range(of: #"(\d+(?:[.,]\d+)?)\s*(k)?\s*kg"#, options: .regularExpression) else { return nil }
        let part = String(lower[r])
        let isK = part.replacingOccurrences(of: "kg", with: "").contains("k")
        let num = part.replacingOccurrences(of: "kg", with: "").replacingOccurrences(of: "k", with: "")
        guard let v = ValueFormat.parseNumber(num) else { return nil }
        return isK ? v * 1000 : v
    }

    /// "Calories: 412 kcal", "412 cal".
    static func parseKcal(_ lower: String) -> Double? {
        guard lower.contains("cal") else { return nil }
        guard let r = lower.range(of: #"\d+(?:[.,]\d+)?"#, options: .regularExpression) else { return nil }
        return ValueFormat.parseNumber(String(lower[r]))
    }

    // MARK: Bests

    static func best(_ ex: ParsedExercise) -> ExerciseBest? {
        let normal = ex.sets.filter { $0.setType == .normal }
        guard !normal.isEmpty else { return nil }
        let weighted = normal.filter { $0.weightKg != nil }
        if weighted.isEmpty {
            let r = normal.map(\.reps).max() ?? 0
            return ExerciseBest(reps: r, weightKg: nil, e1rm: nil, unreliable: false)
        }
        var bestSet = weighted[0]
        var bestE = ValueFormat.e1rm(weightKg: bestSet.weightKg ?? 0, reps: bestSet.reps)
        for s in weighted.dropFirst() {
            let e = ValueFormat.e1rm(weightKg: s.weightKg ?? 0, reps: s.reps)
            if e > bestE { bestE = e; bestSet = s }
        }
        return ExerciseBest(reps: bestSet.reps, weightKg: bestSet.weightKg, e1rm: bestE, unreliable: bestSet.reps > 10)
    }

    /// Does this exercise count for the challenge (catalogue list plus per-slot extras)?
    static func counts(_ exercise: String, counted: [String]) -> Bool {
        let n = normalize(exercise)
        return counted.contains { normalize($0) == n }
    }

    /// Suggested entry value for a challenge from the counted exercises, or nil.
    static func suggestedValue(workout: ParsedWorkout, challenge: Challenge, counted: [String]) -> (value: Double, weightKg: Double?, reps: Int?)? {
        let matching = workout.exercises.filter { counts($0.name, counted: counted) }
        guard !matching.isEmpty else { return nil }
        switch challenge.metric {
        case .e1rm:
            var best: ExerciseBest? = nil
            for ex in matching {
                if let b = self.best(ex), let e = b.e1rm, e > (best?.e1rm ?? 0) { best = b }
            }
            guard let b = best, let e = b.e1rm else { return nil }
            return (e, b.weightKg, b.reps)
        case .number:
            // Reps challenges: best normal set's reps.
            let reps = matching.flatMap { $0.sets.filter { $0.setType == .normal }.map(\.reps) }.max()
            guard let r = reps, challenge.unit.lowercased().contains("rep") else { return nil }
            return (Double(r), nil, r)
        case .time:
            return nil
        }
    }
}
