import Foundation

/// A slot with everything derived from it at a given moment.
struct ResolvedSlot: Equatable, Sendable {
    var month: Int
    var slot: Slot
    var challenge: Challenge?
    var kind: SlotKind?
    var baseline: Double?
    var target: Double?
    var entries: [Entry]
    var best: Double?
    /// finalResult if final, else best so far.
    var result: Double?
    var isLocked: Bool
    var phase: MonthPhase
    var isFinal: Bool
    /// Baseline and target can still change (setup window open, not locked in, not final, not a redo).
    var setupOpen: Bool
    /// No challenge at the 1st, or no baseline/target when the setup window closed.
    var isForfeit: Bool
    /// Score with the current result (final or live). nil if it cannot be computed yet.
    var score: Int?

    var isRedo: Bool { kind == .redo }
    var isBoss: Bool { challenge?.fixedMonth == month && month == 12 }
    var isChosen: Bool { challenge != nil }
    var targetHit: Bool { (score ?? 0) >= 100 }
    /// Score that counts toward the total for this slot alone (final or forfeit).
    var settledScore: Int? {
        if isForfeit { return 0 }
        return isFinal ? score : nil
    }
}

struct PickOption: Equatable, Identifiable, Sendable {
    var id: String               // challenge id (new) or "redo-<month>"
    var challenge: Challenge
    var sourceMonth: Int?        // redo only
    var sourceScore: Int?        // redo only
    var disabled: Bool
    var subtitle: String
}

struct YearEngine {
    var state: YearState
    var catalogue: Catalogue
    var rules: LockRules
    var now: Date

    init(state: YearState, catalogue: Catalogue, rules: LockRules = LockRules(), now: Date) {
        self.state = state
        self.catalogue = catalogue
        self.rules = rules
        self.now = now
    }

    // MARK: Slots

    func resolve(_ month: Int) -> ResolvedSlot {
        let slot = state.slot(month)
        let locked = rules.isLocked(month, now: now)
        var challenge: Challenge? = nil
        if let id = slot.challengeId {
            challenge = locked ? (slot.snapshot ?? catalogue.challenge(id: id)) : (catalogue.challenge(id: id) ?? slot.snapshot)
        }
        var baseline = slot.baseline
        var target = slot.target
        if slot.kind == .redo, let src = slot.sourceMonth {
            let s = state.slot(src)
            baseline = s.baseline
            target = s.target
        }
        let entries = state.entries(for: month)
        let best = challenge.flatMap { ch in Scoring.best(entries.map(\.value), direction: ch.direction) }
        let result = slot.isFinal ? slot.finalResult : best
        let setupOpen = slot.kind != .redo && !slot.isFinal && slot.setupLockedAt == nil
            && rules.inSetupWindow(month, now: now)
        let forfeit = locked && (challenge == nil || (!setupOpen && (target == nil || baseline == nil)))
        var score: Int? = nil
        if forfeit {
            score = 0
        } else if let r = result, let b = baseline, let t = target {
            score = Scoring.score(result: r, baseline: b, target: t)
        } else if slot.isFinal {
            score = 0
        }
        return ResolvedSlot(month: month, slot: slot, challenge: challenge, kind: slot.kind,
                            baseline: baseline, target: target, entries: entries, best: best,
                            result: result, isLocked: locked, phase: rules.phase(month, now: now),
                            isFinal: slot.isFinal, setupOpen: setupOpen, isForfeit: forfeit, score: score)
    }

    var all: [ResolvedSlot] { (1...12).map(resolve) }

    // MARK: Totals

    /// Sum of settled scores, redo pairs counted once with the better score.
    var yearTotal: Int {
        let resolved = all
        var total = 0
        for r in resolved where r.kind != .redo {
            var best = r.settledScore ?? 0
            for redo in resolved where redo.kind == .redo && redo.slot.sourceMonth == r.month {
                best = max(best, redo.settledScore ?? 0)
            }
            total += best
        }
        return total
    }

    var finishedCount: Int { all.filter { $0.isFinal || $0.isForfeit }.count }

    func redosUsed(excluding month: Int? = nil) -> Int {
        state.slots.filter { $0.kind == .redo && $0.month != month }.count
    }

    // MARK: Picking

    /// Catalogue challenges used by a slot (other than `month`).
    func usedChallengeIds(excluding month: Int? = nil) -> Set<String> {
        Set(state.slots.filter { $0.month != month && $0.kind == .new }.compactMap(\.challengeId))
    }

    func canPick(_ month: Int) -> Bool {
        guard (1...12).contains(month), rules.canEditChoice(month, now: now) else { return false }
        if let id = state.slot(month).challengeId, catalogue.challenge(id: id)?.fixedMonth == month { return false }
        return catalogue.challenges.contains { $0.fixedMonth == month } == false
    }

    func newOptions(for month: Int) -> [PickOption] {
        let used = usedChallengeIds(excluding: month)
        return catalogue.challenges
            .filter { $0.fixedMonth == nil && !used.contains($0.id) }
            .map { ch in
                PickOption(id: ch.id, challenge: ch, sourceMonth: nil, sourceScore: nil, disabled: false,
                           subtitle: "\(ch.domain.rawValue.uppercased()) · \(ValueFormat.metricLabel(ch))")
            }
    }

    func redoOptions(for month: Int) -> [PickOption] {
        guard month != 1 else { return [] }
        let takenSources = Set(state.slots.filter { $0.kind == .redo && $0.month != month }.compactMap(\.sourceMonth))
        return (1..<month).compactMap { m -> PickOption? in
            let r = resolve(m)
            guard r.kind == .new, r.isFinal, let ch = r.challenge, ch.fixedMonth == nil,
                  !takenSources.contains(m) else { return nil }
            let s = r.score ?? 0
            var sub = YearConfig.short(m)
            if let b = r.baseline, let res = r.result {
                sub += " · \(ValueFormat.format(b, metric: ch.metric)) → \(ValueFormat.formatWithUnit(res, ch).uppercased())"
            }
            if s >= 120 { sub += " · MAXED" }
            return PickOption(id: "redo-\(m)", challenge: ch, sourceMonth: m, sourceScore: s,
                              disabled: s >= 120, subtitle: sub)
        }
    }

    func newLeft(excluding month: Int? = nil) -> Int { newOptions(for: month ?? 0).count }
    func redoLeft(excluding month: Int? = nil) -> Int { max(0, rules.config.redosPerYear - redosUsed(excluding: month)) }

    /// Months that are still open (unchosen and unlocked), excluding fixed months.
    func openMonths(now: Date) -> [Int] {
        (1...12).filter { m in
            !state.slot(m).isChosen && !rules.isLocked(m, now: now)
        }
    }

    /// "3 months left: 1 challenge + 2 redos" when the remaining open months equal the remaining picks.
    func remainingPicksMessage() -> String? {
        let open = openMonths(now: now).count
        let newL = newLeft()
        let redoL = redoLeft()
        guard open > 0, open == newL + redoL else { return nil }
        var parts: [String] = []
        if newL > 0 { parts.append("\(newL) challenge\(newL == 1 ? "" : "s")") }
        if redoL > 0 { parts.append("\(redoL) redo\(redoL == 1 ? "" : "s")") }
        return "\(open) month\(open == 1 ? "" : "s") left: " + parts.joined(separator: " + ")
    }

    // MARK: Status helpers

    /// Weekly dose for a given day: the challenge of the month that day falls in, else 3.
    func weeklyDose(on day: Date) -> Double {
        let comps = rules.calendar.dateComponents([.year, .month], from: day)
        if comps.year == rules.config.year, let m = comps.month, let ch = resolve(m).challenge, ch.weeklyDose.amount > 0 {
            return ch.weeklyDose.amount
        }
        return 3
    }

    /// Relative improvement from baseline to result (final or live), positive = better.
    /// 0.25 means 25 % better than the baseline.
    func improvement(_ r: ResolvedSlot) -> Double? {
        guard r.isLocked, !r.isForfeit, let ch = r.challenge, let b = r.baseline, b != 0, let res = r.result else { return nil }
        let raw = (res - b) / abs(b)
        return ch.direction == .higher ? raw : -raw
    }

    /// Average improvement per domain over every attempt with a result so far.
    func domainImprovement() -> [Domain: Double] {
        var sums: [Domain: (Double, Int)] = [:]
        for r in all {
            guard let ch = r.challenge, let v = improvement(r) else { continue }
            let cur = sums[ch.domain] ?? (0, 0)
            sums[ch.domain] = (cur.0 + v, cur.1 + 1)
        }
        return sums.mapValues { $0.0 / Double($0.1) }
    }

    /// Exercises whose sets feed this month's entries: the month's own choice, else (for a redo)
    /// the original month's choice, else the catalogue defaults plus any extras.
    func countedExercises(_ month: Int) -> [String] {
        let slot = state.slot(month)
        if let o = slot.countedOverride { return o }
        if slot.kind == .redo, let src = slot.sourceMonth, let o = state.slot(src).countedOverride { return o }
        return (resolve(month).challenge?.countedExercises ?? []) + slot.extraCountedExercises
    }

    /// Exercise names seen in saved workouts, most frequent first (one spelling per normalized name).
    var knownExercises: [String] {
        var counts: [String: (name: String, n: Int)] = [:]
        for w in state.workouts {
            for ex in w.exercises ?? [] {
                let key = MotraParser.normalize(ex.name)
                let cur = counts[key] ?? (ex.name, 0)
                counts[key] = (cur.name, cur.n + 1)
            }
        }
        return counts.values.sorted { $0.n != $1.n ? $0.n > $1.n : $0.name < $1.name }.map(\.name)
    }

    func canFinalize(_ month: Int) -> Bool {
        let r = resolve(month)
        return r.isLocked && !r.isFinal && !r.isForfeit && r.best != nil && r.baseline != nil && r.target != nil
    }
}

// MARK: - Mutations (pure, on YearState)

enum YearActions {
    enum ActionError: Error, Equatable {
        case locked
        case notAllowed
        case invalidTarget(Scoring.TargetProblem)
    }

    static func chooseNew(_ state: inout YearState, month: Int, challenge: Challenge, engine: YearEngine) throws {
        guard engine.canPick(month) else { throw ActionError.locked }
        guard engine.newOptions(for: month).contains(where: { $0.challenge.id == challenge.id }) else { throw ActionError.notAllowed }
        state.update(month) { s in
            if s.challengeId != challenge.id || s.kind != .new {
                s.baseline = nil
                s.target = nil
            }
            s.kind = .new
            s.challengeId = challenge.id
            s.snapshot = challenge
            s.sourceMonth = nil
            s.setupLockedAt = nil
        }
    }

    static func chooseRedo(_ state: inout YearState, month: Int, sourceMonth: Int, engine: YearEngine) throws {
        guard engine.canPick(month) else { throw ActionError.locked }
        guard engine.redoLeft(excluding: month) > 0,
              let opt = engine.redoOptions(for: month).first(where: { $0.sourceMonth == sourceMonth }),
              !opt.disabled else { throw ActionError.notAllowed }
        let src = state.slot(sourceMonth)
        state.update(month) { s in
            s.kind = .redo
            s.challengeId = src.challengeId
            s.snapshot = src.snapshot ?? opt.challenge
            s.sourceMonth = sourceMonth
            s.baseline = nil
            s.target = nil
        }
    }

    static func clearChoice(_ state: inout YearState, month: Int, engine: YearEngine) throws {
        guard engine.canPick(month) else { throw ActionError.locked }
        state.update(month) { s in
            s.kind = nil
            s.challengeId = nil
            s.snapshot = nil
            s.sourceMonth = nil
            s.baseline = nil
            s.target = nil
            s.setupLockedAt = nil
        }
    }

    static func setBaseline(_ state: inout YearState, month: Int, value: Double?, engine: YearEngine) throws {
        let s = state.slot(month)
        guard engine.resolve(month).setupOpen else { throw ActionError.locked }
        if let ch = engine.resolve(month).challenge,
           let p = Scoring.validate(baseline: value, target: s.target, direction: ch.direction) {
            throw ActionError.invalidTarget(p)
        }
        state.update(month) { $0.baseline = value }
    }

    static func setTarget(_ state: inout YearState, month: Int, value: Double?, engine: YearEngine) throws {
        let s = state.slot(month)
        guard engine.resolve(month).setupOpen else { throw ActionError.locked }
        if let ch = engine.resolve(month).challenge,
           let p = Scoring.validate(baseline: s.baseline, target: value, direction: ch.direction) {
            throw ActionError.invalidTarget(p)
        }
        state.update(month) { $0.target = value }
    }

    /// Freezes baseline and target before the setup window closes.
    static func lockInSetup(_ state: inout YearState, month: Int, engine: YearEngine) throws {
        let r = engine.resolve(month)
        guard r.setupOpen, r.isChosen else { throw ActionError.locked }
        guard r.baseline != nil, r.target != nil else { throw ActionError.notAllowed }
        if let ch = r.challenge, let p = Scoring.validate(baseline: r.baseline, target: r.target, direction: ch.direction) {
            throw ActionError.invalidTarget(p)
        }
        state.update(month) { $0.setupLockedAt = engine.now }
    }

    /// Saves an imported workout with at most one entry (its best set). Importing the same
    /// workout again (same source, start and name) replaces the earlier copy and its entry.
    static func importWorkout(_ state: inout YearState, workout: Workout, entry: Entry?, engine: YearEngine) throws {
        var w = workout
        if let old = state.workouts.first(where: { $0.source == w.source && $0.date == w.date && $0.title == w.title }) {
            w.id = old.id
            state.workouts.removeAll { $0.id == old.id }
            state.entries.removeAll { $0.workoutId == old.id && !engine.resolve($0.month).isFinal }
        }
        // The Watch records the same session: drop Health copies within 15 minutes for good.
        if w.source != .healthkit {
            let twins = state.workouts.filter { $0.source == .healthkit && abs($0.date.timeIntervalSince(w.date)) <= HealthImport.matchWindow }
            for t in twins {
                state.workouts.removeAll { $0.id == t.id }
                state.entries.removeAll { $0.workoutId == t.id && !engine.resolve($0.month).isFinal }
                if let hk = t.healthKitId, !state.ignoredHealthKitIds.contains(hk) { state.ignoredHealthKitIds.append(hk) }
            }
        }
        state.workouts.append(w)
        if var e = entry {
            e.workoutId = w.id
            let alreadyFinalCopy = state.entries.contains { $0.workoutId == w.id }
            if !alreadyFinalCopy { try addEntry(&state, e, engine: engine) }
        }
    }

    /// Saves a parsed Motra workout: one workout, plus one entry if an exercise counts for its month.
    /// Returns the entry that was added, if any.
    @discardableResult
    static func importParsed(_ state: inout YearState, parsed: ParsedWorkout, fallbackDate: Date,
                             engine: YearEngine) throws -> Entry? {
        let date = parsed.date ?? fallbackDate
        var month: Int? = nil
        if let m = engine.rules.currentMonth(now: date) {
            let r = engine.resolve(m)
            if r.isLocked && r.challenge != nil && !r.isFinal && !r.isForfeit { month = m }
        }
        let counted = month.map { engine.countedExercises($0) } ?? []
        let anyCounts = parsed.exercises.contains { MotraParser.counts($0.name, counted: counted) }
        let workout = Workout(date: date, kind: anyCounts ? .challenge : .other, source: .motra, title: parsed.name,
                              durationMinutes: parsed.durationMinutes, notes: nil, exercises: parsed.exercises)
        var entry: Entry? = nil
        if let m = month, let ch = engine.resolve(m).challenge,
           let sug = MotraParser.suggestedValue(workout: parsed, challenge: ch, counted: counted) {
            entry = Entry(month: m, date: date, value: sug.value, weightKg: sug.weightKg, reps: sug.reps, source: .motra)
        }
        try importWorkout(&state, workout: workout, entry: entry, engine: engine)
        return entry
    }

    /// Chooses which exercises count this month, then refills the entries that came from
    /// imported workouts so earlier imports pick up the new choice.
    static func setCounted(_ state: inout YearState, month: Int, names: [String], engine: YearEngine) throws {
        guard !engine.resolve(month).isFinal else { throw ActionError.locked }
        var seen = Set<String>()
        let clean = names.map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && seen.insert(MotraParser.normalize($0)).inserted }
        state.update(month) { s in
            s.countedOverride = clean
            s.extraCountedExercises = []
        }
        rebuildImportedEntries(&state, month: month, engine: engine)
    }

    /// Recomputes one entry per imported workout in the month from its best counted set.
    static func rebuildImportedEntries(_ state: inout YearState, month: Int, engine: YearEngine) {
        let e = YearEngine(state: state, catalogue: engine.catalogue, rules: engine.rules, now: engine.now)
        let r = e.resolve(month)
        guard r.isLocked, !r.isFinal, !r.isForfeit, let ch = r.challenge else { return }
        let counted = e.countedExercises(month)
        let start = e.rules.lockDate(month), end = e.rules.monthEnd(month)
        state.entries.removeAll { $0.month == month && $0.workoutId != nil }
        for i in state.workouts.indices {
            let w = state.workouts[i]
            guard let exercises = w.exercises, w.date >= start, w.date < end, w.date <= e.now else { continue }
            let parsed = ParsedWorkout(name: w.title ?? "", date: w.date, durationMinutes: w.durationMinutes,
                                       volumeKg: nil, kcal: nil, exercises: exercises)
            if let sug = MotraParser.suggestedValue(workout: parsed, challenge: ch, counted: counted) {
                state.entries.append(Entry(month: month, date: w.date, value: sug.value, weightKg: sug.weightKg,
                                           reps: sug.reps, source: w.source, workoutId: w.id))
                state.workouts[i].kind = .challenge
            }
        }
    }

    static func addEntry(_ state: inout YearState, _ entry: Entry, engine: YearEngine) throws {
        let r = engine.resolve(entry.month)
        guard r.isLocked, !r.isFinal, !r.isForfeit else { throw ActionError.locked }
        state.entries.append(entry)
    }

    static func deleteEntry(_ state: inout YearState, id: UUID, engine: YearEngine) throws {
        guard let e = state.entries.first(where: { $0.id == id }) else { return }
        guard !engine.resolve(e.month).isFinal else { throw ActionError.locked }
        state.entries.removeAll { $0.id == id }
    }

    static func finalize(_ state: inout YearState, month: Int, engine: YearEngine) throws {
        guard engine.canFinalize(month), let best = engine.resolve(month).best else { throw ActionError.notAllowed }
        state.update(month) { s in
            s.finalResult = best
            s.isFinal = true
        }
    }

    /// Until a slot locks its snapshot follows the catalogue; after that it is frozen.
    static func refreshSnapshots(_ state: inout YearState, catalogue: Catalogue, rules: LockRules, now: Date) {
        for i in state.slots.indices {
            let m = state.slots[i].month
            guard !rules.isLocked(m, now: now), let id = state.slots[i].challengeId,
                  let ch = catalogue.challenge(id: id) else { continue }
            if state.slots[i].snapshot != ch { state.slots[i].snapshot = ch }
        }
        // Fixed-month challenges are always assigned.
        for ch in catalogue.challenges {
            guard let m = ch.fixedMonth, (1...12).contains(m), !rules.isLocked(m, now: now) else { continue }
            if state.slot(m).challengeId == nil {
                state.update(m) { s in
                    s.kind = .new
                    s.challengeId = ch.id
                    s.snapshot = ch
                }
            }
        }
    }
}
