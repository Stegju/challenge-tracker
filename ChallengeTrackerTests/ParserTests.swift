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
