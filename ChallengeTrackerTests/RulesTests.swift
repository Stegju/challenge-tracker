import Foundation
import Testing
@testable import ChallengeTracker

@MainActor
struct LockingTests {
    let rules = LockRules()

    @Test func locksAtMidnightOnTheFirst() {
        let before = T.cal.date(year: 2027, month: 3, day: 31, hour: 23, minute: 59)
        let at = T.cal.date(year: 2027, month: 4, day: 1)
        #expect(!rules.isLocked(4, now: before))
        #expect(rules.isLocked(4, now: at))
    }

    @Test func baselineWindowIsDaysOneToThree() {
        #expect(rules.canEditBaseline(3, now: T.d(3, 3, 23)))
        #expect(!rules.canEditBaseline(3, now: T.d(3, 4, 0)))
        #expect(rules.canEditBaseline(3, now: T.d(2, 20)))
        #expect(!rules.canEditTarget(3, now: T.d(3, 2)))
    }

    @Test func yearBoundary() {
        // December ends at 00:00 on 1 Jan 2028; January locks at 00:00 on 1 Jan 2027.
        #expect(rules.monthEnd(12) == T.cal.date(year: 2028, month: 1, day: 1))
        #expect(rules.phase(12, now: T.d(12, 31, 23)) == .active)
        #expect(rules.phase(12, now: T.cal.date(year: 2028, month: 1, day: 1, hour: 1)) == .ended)
        #expect(rules.phase(1, now: T.cal.date(year: 2026, month: 12, day: 31, hour: 23)) == .upcoming)
        #expect(rules.isBeforeYear(T.cal.date(year: 2026, month: 12, day: 31, hour: 23)))
        #expect(rules.currentMonth(now: T.cal.date(year: 2026, month: 12, day: 31)) == nil)
        #expect(rules.currentMonth(now: T.d(1, 1, 0)) == 1)
    }

    @Test func monthBoundaryPhases() {
        #expect(rules.phase(2, now: T.d(2, 28, 23)) == .active)
        #expect(rules.phase(2, now: T.d(3, 1, 0)) == .ended)
        #expect(rules.nextLockMonth(now: T.d(3, 14)) == 4)
        #expect(rules.nextLockMonth(now: T.d(12, 14)) == nil)
    }

    @Test func daysUntilLockAndDaysLeft() {
        #expect(rules.daysUntilLock(4, now: T.d(3, 29, 12)) == 3)
        #expect(rules.daysLeft(3, now: T.d(3, 14, 12)) == 18)
        #expect(rules.daysLeft(3, now: T.d(3, 31, 12)) == 1)
    }
}

@MainActor
struct EngineTests {

    @Test func catalogueLoads() {
        let c = T.catalogue
        #expect(c.challenges.count == 10)
        #expect(c.challenge(id: "murph")?.fixedMonth == 12)
    }

    @Test func freshYearAssignsMurphToDecember() {
        let s = T.fresh()
        #expect(s.slots.count == 12)
        #expect(s.slot(12).challengeId == "murph")
        #expect(s.slot(1).challengeId == nil)
    }

    @Test func forfeitWhenEmptyAtLock() {
        var s = T.fresh()
        T.put(&s, 2, "pushups-max", b: 30, t: nil)
        let e = T.engine(s, T.d(3, 2))
        #expect(e.resolve(1).isForfeit)
        #expect(e.resolve(1).score == 0)
        #expect(e.resolve(2).isForfeit)
        #expect(!e.resolve(4).isForfeit)   // April has not locked yet
    }

    @Test func liveScoreIsNotInTotalUntilFinal() {
        var s = T.fresh()
        T.put(&s, 3, "pullups-max", b: 12, t: 18)
        s.entries.append(Entry(month: 3, date: T.d(3, 11), value: 15))
        let e = T.engine(s, T.d(3, 14))
        #expect(e.resolve(3).score == 50)
        #expect(e.yearTotal == 0)
    }

    @Test func redoCountsBetterAttemptOnce() {
        var s = T.fresh()
        T.put(&s, 1, "run-5k", b: 1390, t: 1260)
        T.finalize(&s, 1, 1285)                 // 81
        s.update(4) { slot in
            slot.kind = .redo
            slot.challengeId = "run-5k"
            slot.sourceMonth = 1
        }
        T.finalize(&s, 4, 1250)                 // 108 with January's baseline and target
        let e = T.engine(s, T.d(5, 10))
        #expect(e.resolve(4).score == 108)
        #expect(e.yearTotal == 108)

        // A worse redo keeps the original.
        var s2 = s
        s2.update(4) { $0.finalResult = 1350 }
        #expect(T.engine(s2, T.d(5, 10)).yearTotal == 81)
    }

    @Test func pickerNewExcludesUsedAndFixed() {
        var s = T.fresh()
        T.put(&s, 1, "run-5k", b: nil, t: nil)
        let e = T.engine(s, T.d(1, 15, year: 2026))
        let ids = e.newOptions(for: 2).map(\.challenge.id)
        #expect(!ids.contains("run-5k"))
        #expect(!ids.contains("murph"))
        #expect(ids.count == 8)
        // The month's own pick stays available to itself.
        #expect(e.newOptions(for: 1).map(\.challenge.id).contains("run-5k"))
    }

    @Test func redoOptionsOnlyFinishedAndNotInJanuary() {
        var s = T.fresh()
        T.put(&s, 1, "run-5k", b: 1390, t: 1260)
        T.finalize(&s, 1, 1285)
        T.put(&s, 2, "bench-e1rm", b: 90, t: 100)
        T.finalize(&s, 2, 102.5)
        T.put(&s, 3, "pullups-max", b: 12, t: 18)
        let e = T.engine(s, T.d(3, 14))
        #expect(e.redoOptions(for: 1).isEmpty)
        let opts = e.redoOptions(for: 4)
        #expect(opts.map(\.sourceMonth) == [1, 2])
        #expect(opts[0].disabled == false)
        #expect(opts[1].disabled == true)   // already 120
    }

    @Test func onlyTwoRedos() throws {
        var s = T.fresh()
        T.put(&s, 1, "run-5k", b: 1390, t: 1260); T.finalize(&s, 1, 1300)
        T.put(&s, 2, "row-2k", b: 480, t: 450); T.finalize(&s, 2, 470)
        T.put(&s, 3, "pushups-max", b: 30, t: 50); T.finalize(&s, 3, 40)
        let now = T.d(3, 20)
        let e3450 = T.engine(s, now)
        try YearActions.chooseRedo(&s, month: 4, sourceMonth: 1, engine: e3450)
        let e7537 = T.engine(s, now)
        try YearActions.chooseRedo(&s, month: 5, sourceMonth: 2, engine: e7537)
        #expect(throws: YearActions.ActionError.self) {
            let e6215 = T.engine(s, now)
            try YearActions.chooseRedo(&s, month: 6, sourceMonth: 3, engine: e6215)
        }
        #expect(T.engine(s, now).redosUsed() == 2)
    }

    @Test func cannotChooseAfterLock() {
        var s = T.fresh()
        let ch = T.catalogue.challenge(id: "run-5k")!
        #expect(throws: YearActions.ActionError.self) {
            let e5979 = T.engine(s, T.d(3, 1, 0))
            try YearActions.chooseNew(&s, month: 3, challenge: ch, engine: e5979)
        }
        #expect(throws: YearActions.ActionError.self) {
            let e6840 = T.engine(s, T.d(3, 1))
            try YearActions.chooseNew(&s, month: 12, challenge: ch, engine: e6840)
        }
    }

    @Test func chooseThenSetTargetAndRejectWrongSide() throws {
        var s = T.fresh()
        let now = T.d(12, 20, year: 2026)
        let ch = T.catalogue.challenge(id: "pullups-max")!
        let e911 = T.engine(s, now)
        try YearActions.chooseNew(&s, month: 1, challenge: ch, engine: e911)
        let e131 = T.engine(s, now)
        try YearActions.setBaseline(&s, month: 1, value: 12, engine: e131)
        #expect(throws: YearActions.ActionError.self) {
            let e5311 = T.engine(s, now)
            try YearActions.setTarget(&s, month: 1, value: 10, engine: e5311)
        }
        let e3192 = T.engine(s, now)
        try YearActions.setTarget(&s, month: 1, value: 18, engine: e3192)
        #expect(s.slot(1).target == 18)
        // Target frozen after lock, baseline still editable on day 2.
        #expect(throws: YearActions.ActionError.self) {
            let e562 = T.engine(s, T.d(1, 2))
            try YearActions.setTarget(&s, month: 1, value: 20, engine: e562)
        }
        let e4892 = T.engine(s, T.d(1, 2))
        try YearActions.setBaseline(&s, month: 1, value: 11, engine: e4892)
        #expect(s.slot(1).baseline == 11)
    }

    @Test func finalizeUsesBestEntry() throws {
        var s = T.fresh()
        T.put(&s, 3, "pullups-max", b: 12, t: 18)
        for (day, v) in [(2, 12.0), (7, 16.0), (11, 15.0)] {
            s.entries.append(Entry(month: 3, date: T.d(3, day), value: v))
        }
        let now = T.d(3, 31)
        let e3000 = T.engine(s, now)
        try YearActions.finalize(&s, month: 3, engine: e3000)
        #expect(s.slot(3).finalResult == 16)
        #expect(T.engine(s, now).yearTotal == 67)
        #expect(throws: YearActions.ActionError.self) {
            let e9907 = T.engine(s, now)
            try YearActions.addEntry(&s, Entry(month: 3, date: now, value: 20), engine: e9907)
        }
    }

    @Test func redoUsesSourceBaselineAndTarget() {
        var s = T.fresh()
        T.put(&s, 2, "bench-e1rm", b: 90, t: 100); T.finalize(&s, 2, 95)
        s.update(5) { slot in
            slot.kind = .redo
            slot.challengeId = "bench-e1rm"
            slot.sourceMonth = 2
        }
        let r = T.engine(s, T.d(5, 3)).resolve(5)
        #expect(r.baseline == 90)
        #expect(r.target == 100)
    }

    @Test func remainingPicksMessage() {
        var s = T.fresh()
        // Fill months 1...8 with new challenges (8 of 9 non-Murph), leaving 9, 10, 11 open.
        let ids = ["hyrox-race", "pushups-max", "bench-e1rm", "row-2k", "the-cut", "run-5k", "bike-long", "run-long"]
        for (i, id) in ids.enumerated() {
            T.put(&s, i + 1, id, b: 1, t: 2)
            T.finalize(&s, i + 1, 2)
        }
        let e = T.engine(s, T.d(8, 20))
        #expect(e.remainingPicksMessage() == "3 months left: 1 challenge + 2 redos")
    }

    @Test func demoDataMatchesArtboard() {
        let s = DemoData.make(catalogue: T.catalogue, until: DemoData.defaultTestDate)
        let e = T.engine(s, DemoData.defaultTestDate)
        #expect(e.yearTotal == 201)
        #expect(e.resolve(3).score == 50)
        #expect(e.resolve(1).score == 81)
        #expect(e.resolve(2).score == 120)
    }

    @Test func snapshotsFreezeAtLock() {
        var s = T.fresh()
        T.put(&s, 1, "run-5k", b: 1390, t: 1260)
        T.put(&s, 4, "row-2k", b: 480, t: 450)
        var cat = T.catalogue
        if let i = cat.challenges.firstIndex(where: { $0.id == "run-5k" }) { cat.challenges[i].name = "5K (renamed)" }
        if let i = cat.challenges.firstIndex(where: { $0.id == "row-2k" }) { cat.challenges[i].name = "2K (renamed)" }
        YearActions.refreshSnapshots(&s, catalogue: cat, rules: LockRules(), now: T.d(2, 1))
        #expect(s.slot(1).snapshot?.name == "5K run")
        #expect(s.slot(4).snapshot?.name == "2K (renamed)")
    }
}
