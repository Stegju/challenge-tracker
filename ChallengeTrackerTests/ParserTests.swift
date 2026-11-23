import Foundation
import Testing
@testable import ChallengeTracker

@MainActor
struct ParserTests {
    let sample = """
    Pull Day
    11 Mar 2027 at 6:15
    Duration: 58 min
    Volume: 6,3K kg
    Calories: 412 kcal
    3 exercises

    Pull Up
    Warm Up
    1: 5 reps x BW
    2: 15 reps x BW
    3: 11 reps x BW
    Lat Pulldown
    1: 10 reps x 65 kg
    2: 9 reps x 72,5 kg
    Seated Cable Row
    1: 12 reps x 60 kg
    Drop Set
    2: 10 reps x 45 kg

    Tracked with Motra
    https://motra.app/w/abc
    """

    /// A real Motra share (23 Nov 2026), pasted twice to check the second copy is ignored.
    static let realExport = """
    My workout:

    Monday upper
    23 Nov 2026 at 6:10

    Duration: 46m
    Volume: 6,7K kg
    Calories: 307 cal
    Exercises: 6

    Machine Incline Bench Press
    Warm Up: 15 reps x 40 kg
    1: 8 reps x 80 kg
    2: 5 reps x 80 kg
    Drop Set: 7 reps x 40 kg

    Pull-Up
    Warm Up: 7 reps x BW
    1: 8 reps x BW
    2: 5 reps x BW

    Machine Shoulder Press
    Warm Up: 10 reps x 25 kg
    1: 8 reps x 32,5 kg
    Drop Set: 2 reps x 25 kg
    3: 7 reps x 32,5 kg
    Drop Set: 3 reps x 25 kg

    Dumbbell Bicep Curl
    Warm Up: 12 reps x 14 kg
    1: 5 reps x 20 kg
    2: 4 reps x 20 kg
    Drop Set: 6 reps x 14 kg

    Machine Row
    Warm Up: 14 reps x 80 kg
    1: 7 reps x 120 kg
    2: 5 reps x 120 kg

    Cable Bar Overhead Tricep Extension High
    1: 5 reps x 32,5 kg
    2: 6 reps x 32,5 kg
    Drop Set: 4 reps x 25 kg

    Tracked with Motra.

    My workout:

    Monday upper
    23 Nov 2026 at 6:10

    Duration: 46m
    Machine Row
    1: 7 reps x 120 kg

    Tracked with Motra.
    https://motra.com/share/workout/cb7f4d9b87
    """

    @Test func realExportHeader() throws {
        let w = try #require(MotraParser.parse(Self.realExport, calendar: T.cal))
        #expect(w.name == "Monday upper")
        #expect(w.date == T.cal.date(year: 2026, month: 11, day: 23, hour: 6, minute: 10))
        #expect(w.durationMinutes == 46)
        #expect(w.volumeKg == 6700)
        #expect(w.kcal == 307)
    }

    @Test func realExportExercises() throws {
        let w = try #require(MotraParser.parse(Self.realExport, calendar: T.cal))
        #expect(w.exercises.map(\.name) == ["Machine Incline Bench Press", "Pull-Up", "Machine Shoulder Press",
                                            "Dumbbell Bicep Curl", "Machine Row", "Cable Bar Overhead Tricep Extension High"])
        #expect(w.exercises[1].sets.map(\.setType) == [.warmup, .normal, .normal])
        #expect(w.exercises[2].sets.map(\.setType) == [.warmup, .normal, .drop, .normal, .drop])
        #expect(w.exercises[2].sets[1].weightKg == 32.5)
        #expect(w.exercises[0].sets[0].weightKg == 40)
        #expect(w.setCount == 22)
    }

    @Test func realExportBests() throws {
        let w = try #require(MotraParser.parse(Self.realExport, calendar: T.cal))
        #expect(MotraParser.best(w.exercises[1])?.reps == 8)               // pull-ups, bodyweight
        #expect(MotraParser.best(w.exercises[0])?.e1rm == 101.5)           // 8 × 80 kg
        #expect(MotraParser.best(w.exercises[4])?.e1rm == 148)             // 7 × 120 kg
        let ch = try #require(T.catalogue.challenge(id: "pullups-max"))
        let s = try #require(MotraParser.suggestedValue(workout: w, challenge: ch, counted: ch.countedExercises))
        #expect(s.value == 8)
    }

    @Test func parsesHeaderAndSummary() throws {
        let w = try #require(MotraParser.parse(sample, calendar: T.cal))
        #expect(w.name == "Pull Day")
        #expect(w.date == T.cal.date(year: 2027, month: 3, day: 11, hour: 6, minute: 15))
        #expect(w.durationMinutes == 58)
        #expect(w.volumeKg == 6300)
        #expect(w.kcal == 412)
    }

    @Test func parsesExercisesAndSetTypes() throws {
        let w = try #require(MotraParser.parse(sample, calendar: T.cal))
        #expect(w.exercises.map(\.name) == ["Pull Up", "Lat Pulldown", "Seated Cable Row"])
        #expect(w.exercises[0].sets.map(\.setType) == [.warmup, .normal, .normal])
        #expect(w.exercises[0].sets[1].weightKg == nil)
        #expect(w.exercises[1].sets[1].weightKg == 72.5)
        #expect(w.exercises[2].sets[1].setType == .drop)
    }

    @Test func bestIgnoresWarmupAndDrop() throws {
        let w = try #require(MotraParser.parse(sample, calendar: T.cal))
        let pull = try #require(MotraParser.best(w.exercises[0]))
        #expect(pull.reps == 15)
        #expect(pull.weightKg == nil)
        let row = try #require(MotraParser.best(w.exercises[2]))
        #expect(row.reps == 12)
        #expect(row.unreliable)
    }

    @Test func suggestsEntryForCountedExercise() throws {
        let w = try #require(MotraParser.parse(sample, calendar: T.cal))
        let ch = try #require(T.catalogue.challenge(id: "pullups-max"))
        let s = try #require(MotraParser.suggestedValue(workout: w, challenge: ch, counted: ch.countedExercises))
        #expect(s.value == 15)
    }

    @Test func normalizesNames() {
        #expect(MotraParser.normalize("Pull-Ups") == "pull up")
        #expect(MotraParser.normalize("Bench Press") == "bench press")
        #expect(MotraParser.counts("Push Ups", counted: ["push up"]))
    }

    @Test func rejectsEmptyText() {
        #expect(MotraParser.parse("   \n  ") == nil)
    }
}

@MainActor
struct NotificationTests {
    @Test func remindsBeforeEmptyLock() {
        let s = T.fresh()
        let e = T.engine(s, T.d(3, 14))
        let plan = NotificationPlanner.plan(engine: e, toggles: NotificationToggles())
        #expect(plan.contains { $0.id == "empty-4-7" })
        #expect(plan.contains { $0.id == "empty-4-2" })
        #expect(!plan.contains { $0.id.hasPrefix("empty-3") })
        #expect(plan.allSatisfy { $0.date > e.now })
    }

    @Test func respectsToggles() {
        let s = T.fresh()
        let e = T.engine(s, T.d(3, 14))
        var t = NotificationToggles()
        t.nextSlotEmpty = false
        #expect(!NotificationPlanner.plan(engine: e, toggles: t).contains { $0.id.hasPrefix("empty") })
    }
}

@MainActor
struct InputFormatTests {
    @Test func timeFillsFromTheRight() {
        #expect(InputFormat.formatTime("2125", hours: false) == "21:25")
        #expect(InputFormat.formatTime("212", hours: false) == "2:12")
        #expect(InputFormat.formatTime("21", hours: false) == "21")
        #expect(InputFormat.formatTime("12000", hours: true) == "1:20:00")
        #expect(InputFormat.formatTime("1:20:00", hours: true) == "1:20:00")
        #expect(InputFormat.formatTime("1h20abc00", hours: true) == "1:20:00")
        #expect(InputFormat.formatTime("123456", hours: true) == "1:23:45")   // capped at 5 digits
        #expect(InputFormat.formatTime("05:30", hours: false) == "5:30")
    }

    @Test func timeProblems() {
        #expect(InputFormat.problem("1:75:00", kind: .time(hours: true)) != nil)
        #expect(InputFormat.problem("21:25", kind: .time(hours: false)) == nil)
        #expect(InputFormat.problem("", kind: .time(hours: false)) == nil)
    }

    @Test func decimalsAndIntegers() {
        #expect(InputFormat.formatDecimal("12,55", maxDecimals: 1) == "12.5")
        #expect(InputFormat.formatDecimal("1.2.3", maxDecimals: 2) == "1.23")
        #expect(InputFormat.formatDecimal("abc", maxDecimals: 2) == "")
        #expect(InputFormat.formatDecimal(",5", maxDecimals: 2) == "0.5")
        #expect(InputFormat.format("1a8", kind: .integer) == "18")
    }

    @Test func kindPerChallenge() throws {
        let c = T.catalogue
        #expect(InputFormat.kind(for: try #require(c.challenge(id: "hyrox-race"))) == .time(hours: true))
        #expect(InputFormat.kind(for: try #require(c.challenge(id: "run-5k"))) == .time(hours: false))
        #expect(InputFormat.kind(for: try #require(c.challenge(id: "pullups-max"))) == .integer)
        #expect(InputFormat.kind(for: try #require(c.challenge(id: "the-cut"))) == .decimal(maxDecimals: 2))
    }
}
