import Foundation
import SwiftUI
import UIKit

struct ChallengeDetailView: View {
    var month: Int
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(\.dismiss) private var dismiss

    @State private var editing: EditField?
    @State private var editText = ""
    @State private var entryText = ""
    @State private var weightText = ""
    @State private var repsText = ""
    @State private var entryDate = Date()
    @State private var finalizeStage = 0
    @State private var didInit = false

    enum EditField { case baseline, target }

    var body: some View {
        let e = store.engine
        let r = e.resolve(month)
        let rules = store.rules
        let now = store.now
        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header(r)
                if let ch = r.challenge {
                    challengeCard(r, ch, rules: rules, now: now)
                    if r.isLocked && !r.isForfeit {
                        entriesCard(r, ch, now: now)
                        resultCard(r, ch, engine: e)
                    } else if r.isForfeit {
                        forfeitNote
                    } else {
                        Text("Entries open on \(Fmt.dayMonth(rules.lockDate(month), store.calendar)) when the month locks.")
                            .font(.vt(19)).foregroundStyle(Palette.muted)
                    }
                } else {
                    emptyCard(r, engine: e)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 18)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .screen()
        .onAppear {
            if !didInit {
                entryDate = min(store.now, rules.monthEnd(month).addingTimeInterval(-60))
                didInit = true
            }
        }
    }

    // MARK: Header

    private func header(_ r: ResolvedSlot) -> some View {
        HStack(spacing: 12) {
            BackButton { dismiss() }
            VStack(alignment: .leading, spacing: 4) {
                Lbl("SLOT \(month) OF 12")
                Text(YearConfig.name(month)).font(.heading(20)).foregroundStyle(.white)
            }
            Spacer()
            statusChip(r)
        }
    }

    @ViewBuilder
    private func statusChip(_ r: ResolvedSlot) -> some View {
        if r.isForfeit {
            chip("FORFEIT · 0", fg: Palette.onLime, bg: Palette.alert, edge: nil, icon: false)
        } else if r.isFinal {
            chip("FINAL", fg: Palette.onLime, bg: Palette.lime, edge: nil, icon: false)
        } else if r.isLocked {
            chip("LOCKED", fg: Palette.lime, bg: .clear, edge: Palette.lime, icon: true)
        } else if r.isBoss {
            chip("BOSS", fg: Palette.alertText, bg: .clear, edge: Palette.alert, icon: false)
        } else if r.isRedo {
            chip("REDO", fg: Palette.onLime, bg: Palette.redo, edge: nil, icon: false)
        } else {
            chip("OPEN", fg: Palette.muted, bg: .clear, edge: Palette.inputEdge, icon: false)
        }
    }

    private func chip(_ t: String, fg: Color, bg: Color, edge: Color?, icon: Bool) -> some View {
        HStack(spacing: 6) {
            if icon { PixelIcon(.lock).frame(width: 12, height: 12) }
            Text(t).font(.label(10)).tracking(1)
        }
        .foregroundStyle(fg)
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(bg)
        .innerBorder(edge ?? .clear)
    }

    // MARK: Challenge card

    private func challengeCard(_ r: ResolvedSlot, _ ch: Challenge, rules: LockRules, now: Date) -> some View {
        let canBaseline = r.kind != .redo && rules.canEditBaseline(month, now: now) && !r.isFinal
        let canTarget = r.kind != .redo && rules.canEditTarget(month, now: now)
        return VStack(alignment: .leading, spacing: 12) {
            Text(ch.name.uppercased()).font(.heading(18)).foregroundStyle(r.isBoss ? Palette.bossName : .white)
            HStack(alignment: .top, spacing: 8) {
                info("DOMAIN", ch.domain.title)
                info("METRIC", ValueFormat.metricShort(ch))
                info("WEEKLY", "\(ValueFormat.formatNumber(ch.weeklyDose.amount)) \(ch.weeklyDose.unit)")
            }
            if let notes = ch.notes {
                Text(notes).font(.vt(18)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
            }
            Rectangle().fill(Palette.panelEdge).frame(height: 2)
            HStack(spacing: 8) {
                valueTile("BASELINE", r.baseline, ch, field: .baseline, editable: canBaseline)
                valueTile("TARGET", r.target, ch, field: .target, editable: canTarget)
            }
            if let field = editing {
                editRow(field, ch)
            }
            Text(lockLine(r, rules: rules, now: now))
                .font(.vt(18)).foregroundStyle(Palette.muted)
                .fixedSize(horizontal: false, vertical: true)
            if !r.isLocked && store.engine.canPick(month) {
                Button("CHANGE CHALLENGE") { router.push(.pick(month)) }
                    .buttonStyle(SecondaryButtonStyle(height: 44))
            }
        }
        .padding(16)
        .panel(edge: r.isBoss ? Palette.alert : Palette.panelEdge)
    }

    private func info(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Lbl(label)
            Text(value).font(.vt(21)).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func valueTile(_ label: String, _ value: Double?, _ ch: Challenge, field: EditField, editable: Bool) -> some View {
        Button {
            guard editable else { return }
            if editing == field {
                editing = nil
            } else {
                editing = field
                editText = value.map { ValueFormat.format($0, metric: ch.metric) } ?? ""
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Lbl(label)
                    Spacer()
                    if editable { Lbl(editing == field ? "EDITING" : "EDIT", color: Palette.lime, size: 9) }
                }
                Text(value.map { ValueFormat.format($0, metric: ch.metric) } ?? "—")
                    .font(.number(34))
                    .foregroundStyle(value == nil ? Palette.veryDim : Palette.text)
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .notched(fill: Palette.input, edge: editing == field ? Palette.lime : nil)
        }
        .buttonStyle(.plain)
        .disabled(!editable)
        .accessibilityLabel("\(label.capitalized) \(value.map { ValueFormat.formatWithUnit($0, ch) } ?? "not set")")
    }

    private func editRow(_ field: EditField, _ ch: Challenge) -> some View {
        HStack(alignment: .bottom, spacing: 6) {
            VStack(alignment: .leading, spacing: 4) {
                Lbl("\(field == .baseline ? "BASELINE" : "TARGET") · \(ValueFormat.inputHint(ch))", size: 9)
                PixelField(placeholder: ValueFormat.inputHint(ch), text: $editText,
                           keyboard: ch.metric == .time ? .numbersAndPunctuation : .decimalPad)
            }
            Button("SAVE") {
                let trimmed = editText.trimmingCharacters(in: .whitespaces)
                let value: Double? = trimmed.isEmpty ? nil : ValueFormat.parse(trimmed, metric: ch.metric)
                if !trimmed.isEmpty && value == nil {
                    store.message = "Couldn't read that. Use \(ValueFormat.inputHint(ch))."
                    return
                }
                let ok = field == .baseline ? store.setBaseline(month: month, value: value)
                                            : store.setTarget(month: month, value: value)
                if ok { editing = nil }
            }
            .buttonStyle(PrimaryButtonStyle())
            .frame(width: 88)
        }
    }

    private func lockLine(_ r: ResolvedSlot, rules: LockRules, now: Date) -> String {
        let cal = store.calendar
        let lock = Fmt.dayMonth(rules.lockDate(month), cal)
        let baseClose = Fmt.dayMonth(rules.addingDaysBeforeClose(month), cal)
        if r.isRedo, let src = r.slot.sourceMonth {
            return "Redo of \(YearConfig.name(src).capitalized): same baseline and target. The better attempt counts."
        }
        if !r.isLocked {
            return "Locks \(lock) 00:00. Baseline can still be entered until \(baseClose)."
        }
        if rules.canEditBaseline(month, now: now) {
            return "Target locked \(lock). Baseline open until the end of \(baseClose)."
        }
        return "Target locked \(lock). Baseline closed \(baseClose)." + (r.baseline == nil ? " No baseline was entered, so this month can't score." : "")
    }

    // MARK: Entries

    private func entriesCard(_ r: ResolvedSlot, _ ch: Challenge, now: Date) -> some View {
        let cal = store.calendar
        let canAdd = !r.isFinal
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Lbl("ENTRIES")
                Spacer()
                Lbl("BEST COUNTS")
            }
            if r.entries.isEmpty {
                Text("No entries yet.").font(.vt(19)).foregroundStyle(Palette.dim)
            }
            VStack(spacing: 4) {
                ForEach(r.entries) { entry in
                    let top = entry.value == r.best
                    HStack(spacing: 8) {
                        Text(Fmt.dayMonth2(entry.date, cal)).font(.vt(20)).foregroundStyle(Palette.muted)
                            .frame(width: 72, alignment: .leading)
                        Text(entryText(entry, ch)).font(.number(24)).foregroundStyle(top ? Palette.lime : Palette.text)
                        Spacer()
                        Lbl(entry.source.label, size: 9)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(top ? Palette.lime.opacity(0.08) : Palette.input)
                    .innerBorder(top ? Palette.lime : .clear)
                    .contextMenu {
                        if canAdd {
                            Button("Delete entry", role: .destructive) { store.deleteEntry(entry.id) }
                        }
                    }
                }
            }
            if canAdd {
                addEntryRow(ch, now: now)
                Text("Long-press an entry to delete it. Logging an entry also counts as a challenge session that day.")
                    .font(.vt(16)).foregroundStyle(Palette.dim)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .panel()
    }

    private func entryText(_ e: Entry, _ ch: Challenge) -> String {
        var s = ValueFormat.formatWithUnit(e.value, ch)
        if ch.metric == .e1rm, let w = e.weightKg, let reps = e.reps {
            s += "  (\(reps) × \(ValueFormat.formatNumber(w)))"
        }
        return s
    }

    private func addEntryRow(_ ch: Challenge, now: Date) -> some View {
        let rules = store.rules
        let lower = rules.lockDate(month)
        let upper = max(lower, min(now, rules.monthEnd(month).addingTimeInterval(-60)))
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .bottom, spacing: 6) {
                VStack(alignment: .leading, spacing: 4) {
                    Lbl("DATE", size: 9)
                    DatePicker("", selection: $entryDate, in: lower...upper, displayedComponents: .date)
                        .labelsHidden()
                        .datePickerStyle(.compact)
                        .colorScheme(.dark)
                        .frame(height: 48)
                }
                if ch.metric == .e1rm {
                    VStack(alignment: .leading, spacing: 4) {
                        Lbl("KG", size: 9)
                        PixelField(placeholder: "0", text: $weightText)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Lbl("REPS", size: 9)
                        PixelField(placeholder: "0", text: $repsText, keyboard: .numberPad)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        Lbl(ValueFormat.inputHint(ch), size: 9)
                        PixelField(placeholder: ch.metric == .time ? "mm:ss" : "0", text: $entryText,
                                   keyboard: ch.metric == .time ? .numbersAndPunctuation : .decimalPad)
                    }
                }
            }
            Button("ADD ENTRY") { addEntry(ch) }
                .buttonStyle(PrimaryButtonStyle())
        }
    }

    private func addEntry(_ ch: Challenge) {
        var value: Double?
        var w: Double? = nil
        var reps: Int? = nil
        if ch.metric == .e1rm {
            w = ValueFormat.parseNumber(weightText)
            reps = Int(repsText.trimmingCharacters(in: .whitespaces))
            if let w, let reps, reps > 0, w > 0 { value = ValueFormat.e1rm(weightKg: w, reps: reps) }
        } else {
            value = ValueFormat.parse(entryText, metric: ch.metric)
        }
        guard let v = value else {
            store.message = "Couldn't read that value."
            return
        }
        let entry = Entry(month: month, date: entryDate, value: v, weightKg: w, reps: reps, source: .manual)
        if store.addEntry(entry, alsoLogSession: true) {
            entryText = ""; weightText = ""; repsText = ""
            if let reps, reps > 10 { store.message = "Saved. Over 10 reps makes the e1RM shaky." }
        }
    }

    // MARK: Result

    private func resultCard(_ r: ResolvedSlot, _ ch: Challenge, engine: YearEngine) -> some View {
        let accent = r.isBoss ? Palette.alertText : Palette.lime
        let canFinal = engine.canFinalize(month)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    Lbl("RESULT")
                    (Text(r.result.map { ValueFormat.format($0, metric: ch.metric) } ?? "—")
                        .font(.number(44)).foregroundColor(accent)
                     + Text(ValueFormat.unitSuffix(ch).isEmpty ? "" : " \(ValueFormat.unitSuffix(ch))")
                        .font(.number(20)).foregroundColor(Palette.dim))
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Lbl("SCORE")
                    Text(r.score.map { "\($0)" } ?? "—").font(.number(44)).foregroundStyle(.white)
                }
            }
            ScoreMeter(score: Double(r.score ?? 0))
            if r.isFinal {
                Text("FINAL · \(r.score ?? 0) PTS")
                    .font(.heading(12)).tracking(1)
                    .foregroundStyle(Palette.onLime)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .notched(fill: Palette.lime)
            } else if finalizeStage == 0 {
                Button("FINALIZE RESULT") { finalizeStage = 1 }
                    .buttonStyle(SecondaryButtonStyle(edge: Palette.lime, textColor: Palette.lime))
                    .disabled(!canFinal)
                    .opacity(canFinal ? 1 : 0.4)
                if !canFinal {
                    Text(r.baseline == nil ? "Needs a baseline before it can be finalized." : "Log an entry first.")
                        .font(.vt(17)).foregroundStyle(Palette.dim)
                }
            } else {
                HStack(spacing: 6) {
                    PulsingButton(title: "TAP AGAIN TO LOCK") {
                        store.finalize(month: month)
                        finalizeStage = 0
                    }
                    Button("CANCEL") { finalizeStage = 0 }
                        .buttonStyle(SecondaryButtonStyle())
                        .frame(width: 96)
                }
            }
        }
        .padding(16)
        .panel(edge: r.isBoss ? Palette.alert : Palette.panelEdge)
    }

    private var forfeitNote: some View {
        VStack(alignment: .leading, spacing: 6) {
            Lbl("FORFEIT", color: Palette.alertText)
            Text("No challenge or no target was set at midnight on the 1st, so this month scores 0.")
                .font(.vt(19)).foregroundStyle(Palette.soft)
        }
        .padding(16)
        .panel(edge: Palette.alert)
    }

    private func emptyCard(_ r: ResolvedSlot, engine: YearEngine) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(r.isForfeit ? "NOTHING CHOSEN" : "NOT CHOSEN YET").font(.heading(18)).foregroundStyle(.white)
            if r.isForfeit {
                Text("This month locked empty and scores 0.").font(.vt(19)).foregroundStyle(Palette.alertText)
            } else if engine.canPick(month) {
                Button("CHOOSE \(YearConfig.name(month))") { router.push(.pick(month)) }
                    .buttonStyle(PrimaryButtonStyle())
            }
        }
        .padding(16)
        .panel()
    }
}

extension LockRules {
    /// Last day the baseline can be entered (day `baselineGraceDays`).
    func addingDaysBeforeClose(_ month: Int) -> Date {
        calendar.addingDays(-1, to: baselineClose(month))
    }
}

/// Yellow "tap again" button that pulses (static under Reduce Motion).
struct PulsingButton: View {
    var title: String
    var action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.6)) { tl in
            let on = reduceMotion || Int(tl.date.timeIntervalSinceReferenceDate / 0.6) % 2 == 0
            Button(title, action: action)
                .buttonStyle(PrimaryButtonStyle(fill: Palette.plateYellow))
                .opacity(on ? 1 : 0.6)
        }
    }
}
