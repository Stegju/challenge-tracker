import Foundation
import Testing
@testable import ChallengeTracker

@MainActor
struct HealthImportTests {
    func hw(_ id: String, _ day: Int, month: Int = 3, activity: String = "running", km: Double?, minutes: Double) -> HealthWorkout {
        HealthWorkout(id: id, start: T.d(month, day, 7), durationSeconds: minutes * 60, activity: activity, distanceKm: km)
    }

    @Test func targetDistanceFromName() throws {
        let c = T.catalogue
        #expect(HealthImport.targetDistanceKm(try #require(c.challenge(id: "run-5k"))) == 5)
        #expect(HealthImport.targetDistanceKm(try #require(c.challenge(id: "row-2k"))) == 2)
        #expect(HealthImport.targetDistanceKm(try #require(c.challenge(id: "murph"))) == nil)
    }

    @Test func fiveKRunGivesScaledTime() throws {
        let ch = try #require(T.catalogue.challenge(id: "run-5k"))
        // 5.05 km in 22:13 → 5 km in 22:00
        let v = HealthImport.entryValue(hw("a", 5, km: 5.05, minutes: 22 + 13.0 / 60), challenge: ch, counted: ch.countedExercises)
        #expect(v == 1320)
        // A 10K doesn't count as a 5K attempt, and a ride doesn't count at all.
        #expect(HealthImport.entryValue(hw("b", 6, km: 10, minutes: 48), challenge: ch, counted: ch.countedExercises) == nil)
        #expect(HealthImport.entryValue(hw("c", 7, activity: "cycling", km: 5, minutes: 10), challenge: ch, counted: ch.countedExercises) == nil)
    }

    @Test func longRunUsesDistance() throws {
        let ch = try #require(T.catalogue.challenge(id: "run-long"))
        #expect(HealthImport.entryValue(hw("a", 5, km: 18.437, minutes: 100), challenge: ch, counted: ch.countedExercises) == 18.44)
    }

    @Test func mergeAddsWorkoutsAndEntriesOnce() {
        var s = T.fresh()
        T.put(&s, 3, "run-long", b: 15, t: 21)
        let list = [hw("a", 5, km: 16, minutes: 90), hw("b", 6, activity: "strength training", km: nil, minutes: 60)]
        let n = HealthImport.merge(&s, workouts: list, catalogue: T.catalogue, rules: LockRules(), now: T.d(3, 10))
        #expect(n == 2)
        #expect(s.workouts.count == 2)
        #expect(s.workouts.first { $0.healthKitId == "a" }?.kind == .challenge)
        #expect(s.workouts.first { $0.healthKitId == "b" }?.kind == .other)
        #expect(s.entries.map(\.value) == [16])
        #expect(s.entries.first?.source == .healthkit)
        // Second sync adds nothing.
        #expect(HealthImport.merge(&s, workouts: list, catalogue: T.catalogue, rules: LockRules(), now: T.d(3, 10)) == 0)
        #expect(s.workouts.count == 2)
    }

    @Test func watchCopyOfMotraSessionIsSkipped() throws {
        var s = T.fresh()
        // Motra session at 07:00, Watch strength workout at 07:05: same session.
        let motra = Workout(date: T.d(3, 5, 7), kind: .other, source: .motra, title: "Push")
        let e1 = T.engine(s, T.d(3, 6))
        try YearActions.importWorkout(&s, workout: motra, entry: nil, engine: e1)
        var watch = hw("w", 5, activity: "strength training", km: nil, minutes: 50)
        watch.start = T.d(3, 5, 7).addingTimeInterval(5 * 60)
        HealthImport.merge(&s, workouts: [watch], catalogue: T.catalogue, rules: LockRules(), now: T.d(3, 6))
        #expect(s.workouts.count == 1)
        #expect(s.ignoredHealthKitIds == ["w"])
    }

    @Test func motraImportReplacesEarlierWatchCopy() throws {
        var s = T.fresh()
        var watch = hw("w", 5, activity: "strength training", km: nil, minutes: 50)
        watch.start = T.d(3, 5, 7).addingTimeInterval(5 * 60)
        HealthImport.merge(&s, workouts: [watch], catalogue: T.catalogue, rules: LockRules(), now: T.d(3, 6))
        #expect(s.workouts.count == 1)
        let motra = Workout(date: T.d(3, 5, 7), kind: .other, source: .motra, title: "Push")
        let e = T.engine(s, T.d(3, 6))
        try YearActions.importWorkout(&s, workout: motra, entry: nil, engine: e)
        #expect(s.workouts.map(\.source) == [.motra])
        #expect(s.ignoredHealthKitIds == ["w"])
        // A later sync doesn't bring the Watch copy back.
        #expect(HealthImport.merge(&s, workouts: [watch], catalogue: T.catalogue, rules: LockRules(), now: T.d(3, 6)) == 0)
    }
}

@MainActor
struct HealthRulesTests {
    func hw(_ activity: String, km: Double? = nil, indoor: Bool = false, minutes: Double = 60) -> HealthWorkout {
        HealthWorkout(id: UUID().uuidString, start: T.d(3, 5, 7), durationSeconds: minutes * 60,
                      activity: activity, distanceKm: km, indoor: indoor)
    }

    @Test func longRunAndRideAreOutdoorOnly() throws {
        let run = try #require(T.catalogue.challenge(id: "run-long"))
        #expect(HealthImport.entryValue(hw("running", km: 12, indoor: true), challenge: run, counted: run.countedExercises) == nil)
        #expect(HealthImport.entryValue(hw("running", km: 12), challenge: run, counted: run.countedExercises) == 12)
        let bike = try #require(T.catalogue.challenge(id: "bike-long"))
        #expect(HealthImport.entryValue(hw("cycling", km: 40, indoor: true), challenge: bike, counted: bike.countedExercises) == nil)
    }

    @Test func fastestStretchFindsTheQuickPart() {
        // 10 km: first 5 km at 5:00/km, last 5 km at 4:00/km, a point every 100 m.
        var pts: [(t: Double, d: Double)] = [(0, 0)]
        var t = 0.0
        for i in 1...100 {
            t += i <= 50 ? 30 : 24
            pts.append((t, Double(i) * 100))
        }
        let best = HealthImport.fastestStretch(pts, meters: 5000)
        #expect(best == 1200)
        #expect(HealthImport.fastestStretch(Array(pts.prefix(20)), meters: 5000) == nil)
    }

    @Test func fiveKUsesFastestStretchOfALongerRun() throws {
        let ch = try #require(T.catalogue.challenge(id: "run-5k"))
        var long = hw("running", km: 10, minutes: 45)
        long.fastestStretches = [5: 1250]
        #expect(HealthImport.entryValue(long, challenge: ch, counted: ch.countedExercises) == 1250)
        #expect(HealthImport.stretchDistances(T.catalogue) == [5])
    }

    @Test func hyroxSessionsAreEverythingButStrengthAndBoxing() throws {
        let ch = try #require(T.catalogue.challenge(id: "hyrox-race"))
        #expect(HealthImport.isSession(activity: "running", challenge: ch, counted: ch.countedExercises))
        #expect(HealthImport.isSession(activity: "rowing", challenge: ch, counted: ch.countedExercises))
        #expect(HealthImport.isSession(activity: "functional strength training", challenge: ch, counted: ch.countedExercises))
        #expect(!HealthImport.isSession(activity: "strength training", challenge: ch, counted: ch.countedExercises))
        #expect(!HealthImport.isSession(activity: "boxing", challenge: ch, counted: ch.countedExercises))
        // No automatic entry: the race time is typed in.
        #expect(HealthImport.entryValue(hw("running", km: 8), challenge: ch, counted: ch.countedExercises) == nil)
    }

    @Test func murphSessionsAreRunsStrengthAndHiit() throws {
        let ch = try #require(T.catalogue.challenge(id: "murph"))
        #expect(HealthImport.isSession(activity: "running", challenge: ch, counted: ch.countedExercises))
        #expect(HealthImport.isSession(activity: "strength training", challenge: ch, counted: ch.countedExercises))
        #expect(HealthImport.isSession(activity: "hiit", challenge: ch, counted: ch.countedExercises))
        #expect(!HealthImport.isSession(activity: "cycling", challenge: ch, counted: ch.countedExercises))
    }

    @Test func hyroxMonthMergeMarksSessions() {
        var s = T.fresh()
        T.put(&s, 3, "hyrox-race", b: 5400, t: 5100)
        let list = [hw("running", km: 8), hw("strength training")]
        HealthImport.merge(&s, workouts: list, catalogue: T.catalogue, rules: LockRules(), now: T.d(3, 10))
        #expect(s.workouts.first { $0.title == "Running" }?.kind == .challenge)
        #expect(s.workouts.first { $0.title == "Strength training" }?.kind == .other)
        #expect(s.entries.isEmpty)
    }
}
