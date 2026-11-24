import Foundation

// Plain value types for the whole year. Stored as one JSON document
// (see Data/Persistence.swift). Scores, totals, plates, momentum and mood
// are derived from these and never stored.

enum Domain: String, Codable, CaseIterable, Sendable {
    case strength, speed, endurance, physique, hybrid

    var title: String { rawValue.capitalized }
}

enum Metric: String, Codable, Sendable {
    case number, time, e1rm
}

enum Direction: String, Codable, Sendable {
    case higher, lower
}

struct WeeklyDose: Codable, Equatable, Sendable {
    var unit: String
    var amount: Double
}

struct Challenge: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var name: String
    var domain: Domain
    var metric: Metric
    var unit: String
    var direction: Direction
    var weeklyDose: WeeklyDose
    var countedExercises: [String]
    var fixedMonth: Int?
    var notes: String?
    /// Workout activities (Health names, e.g. "running") that count as sessions; "*" = all.
    var sessionActivities: [String]?
    var sessionActivitiesExcluded: [String]?
}

struct Catalogue: Codable, Equatable, Sendable {
    var version: Int
    var challenges: [Challenge]

    func challenge(id: String) -> Challenge? {
        challenges.first { $0.id == id }
    }

    static func decode(_ data: Data) throws -> Catalogue {
        try JSONDecoder().decode(Catalogue.self, from: data)
    }

    /// Loads `challenges.json` from the app bundle. Returns an empty catalogue if missing.
    static func bundled(_ bundle: Bundle = .main) -> Catalogue {
        guard let url = ResourceLocator.url(named: "challenges", ext: "json", bundle: bundle),
              let data = try? Data(contentsOf: url),
              let cat = try? decode(data) else {
            return Catalogue(version: 0, challenges: [])
        }
        return cat
    }
}

enum ResourceLocator {
    static func url(named name: String, ext: String, bundle: Bundle = .main) -> URL? {
        if let u = bundle.url(forResource: name, withExtension: ext) { return u }
        if let u = bundle.url(forResource: name, withExtension: ext, subdirectory: "Resources") { return u }
        return nil
    }
}

enum SlotKind: String, Codable, Sendable {
    case new, redo
}

enum EntrySource: String, Codable, Sendable {
    case manual, healthkit, motra

    var label: String { rawValue.uppercased() }
}

enum WorkoutKind: String, Codable, Sendable {
    case challenge, other
}

struct Slot: Codable, Equatable, Identifiable, Sendable {
    var month: Int
    var kind: SlotKind?
    var challengeId: String?
    /// Copy of the catalogue entry; refreshed until the slot locks, then frozen.
    var snapshot: Challenge?
    /// For a redo: the month of the original attempt.
    var sourceMonth: Int?
    var baseline: Double?
    var target: Double?
    var finalResult: Double?
    var isFinal: Bool = false
    /// Extra exercise names that count for this month (toggled on the Exercises screen).
    var extraCountedExercises: [String] = []
    /// Set when baseline and target were locked in by hand before the window closed.
    var setupLockedAt: Date?
    /// Exercises that count this month, chosen by hand. nil = catalogue defaults (+ extras).
    var countedOverride: [String]?

    var id: Int { month }

    init(month: Int) {
        self.month = month
    }

    var isChosen: Bool { challengeId != nil }

    // Tolerant decoding so older backups keep loading when fields are added.
    enum CodingKeys: String, CodingKey {
        case month, kind, challengeId, snapshot, sourceMonth, baseline, target, finalResult, isFinal, extraCountedExercises, setupLockedAt, countedOverride
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        month = try c.decode(Int.self, forKey: .month)
        kind = try c.decodeIfPresent(SlotKind.self, forKey: .kind)
        challengeId = try c.decodeIfPresent(String.self, forKey: .challengeId)
        snapshot = try c.decodeIfPresent(Challenge.self, forKey: .snapshot)
        sourceMonth = try c.decodeIfPresent(Int.self, forKey: .sourceMonth)
        baseline = try c.decodeIfPresent(Double.self, forKey: .baseline)
        target = try c.decodeIfPresent(Double.self, forKey: .target)
        finalResult = try c.decodeIfPresent(Double.self, forKey: .finalResult)
        isFinal = try c.decodeIfPresent(Bool.self, forKey: .isFinal) ?? false
        extraCountedExercises = try c.decodeIfPresent([String].self, forKey: .extraCountedExercises) ?? []
        setupLockedAt = try c.decodeIfPresent(Date.self, forKey: .setupLockedAt)
        countedOverride = try c.decodeIfPresent([String].self, forKey: .countedOverride)
    }
}

struct Entry: Codable, Equatable, Identifiable, Sendable {
    var id: UUID = UUID()
    var month: Int
    var date: Date
    /// Seconds for time, kg (e1RM) for e1rm, raw number otherwise.
    var value: Double
    var weightKg: Double?
    var reps: Int?
    var source: EntrySource = .manual
    /// The workout this entry came from (imports, HealthKit). One entry per workout.
    var workoutId: UUID?
}

enum SetType: String, Codable, Sendable {
    case normal, warmup, drop
}

struct ParsedSet: Codable, Equatable, Sendable {
    var index: Int
    var setType: SetType
    var reps: Int
    /// nil = bodyweight
    var weightKg: Double?
}

struct ParsedExercise: Codable, Equatable, Sendable {
    var name: String
    var sets: [ParsedSet]
}

struct Workout: Codable, Equatable, Identifiable, Sendable {
    var id: UUID = UUID()
    var date: Date
    var kind: WorkoutKind
    var source: EntrySource = .manual
    var title: String?
    var durationMinutes: Double?
    var notes: String?
    var exercises: [ParsedExercise]?
    /// Apple Health workout UUID, for workouts that came from HealthKit.
    var healthKitId: String?
}

struct YearState: Codable, Equatable, Sendable {
    var schemaVersion: Int = 1
    var year: Int = YearConfig.year
    var slots: [Slot]
    var entries: [Entry] = []
    var workouts: [Workout] = []
    /// Health workouts that duplicated a Motra import and must not be added again.
    var ignoredHealthKitIds: [String] = []

    /// Twelve empty slots with Murph (or any fixed-month challenge) pre-assigned.
    static func fresh(catalogue: Catalogue) -> YearState {
        var slots = (1...12).map { Slot(month: $0) }
        for ch in catalogue.challenges {
            if let m = ch.fixedMonth, (1...12).contains(m) {
                slots[m - 1].kind = .new
                slots[m - 1].challengeId = ch.id
                slots[m - 1].snapshot = ch
            }
        }
        return YearState(slots: slots)
    }

    func slot(_ month: Int) -> Slot {
        slots.first { $0.month == month } ?? Slot(month: month)
    }

    mutating func update(_ month: Int, _ change: (inout Slot) -> Void) {
        if let i = slots.firstIndex(where: { $0.month == month }) {
            change(&slots[i])
        }
    }

    func entries(for month: Int) -> [Entry] {
        entries.filter { $0.month == month }.sorted { $0.date < $1.date }
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion, year, slots, entries, workouts, ignoredHealthKitIds
    }

    init(slots: [Slot]) {
        self.slots = slots
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        year = try c.decodeIfPresent(Int.self, forKey: .year) ?? YearConfig.year
        slots = try c.decode([Slot].self, forKey: .slots)
        entries = try c.decodeIfPresent([Entry].self, forKey: .entries) ?? []
        workouts = try c.decodeIfPresent([Workout].self, forKey: .workouts) ?? []
        ignoredHealthKitIds = try c.decodeIfPresent([String].self, forKey: .ignoredHealthKitIds) ?? []
    }
}

enum YearConfig {
    static let year = 2027
    static let monthNames = ["JANUARY", "FEBRUARY", "MARCH", "APRIL", "MAY", "JUNE",
                             "JULY", "AUGUST", "SEPTEMBER", "OCTOBER", "NOVEMBER", "DECEMBER"]
    static let monthShort = ["JAN", "FEB", "MAR", "APR", "MAY", "JUN",
                             "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"]
    static let monthLetters = ["J", "F", "M", "A", "M", "J", "J", "A", "S", "O", "N", "D"]

    static func name(_ month: Int) -> String { monthNames[max(1, min(12, month)) - 1] }
    static func short(_ month: Int) -> String { monthShort[max(1, min(12, month)) - 1] }
}
