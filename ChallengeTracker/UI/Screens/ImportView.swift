import Foundation
import SwiftUI
import UIKit

struct ImportView: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(ImportDraft.self) private var draft
    @State private var showEditor = false

    var body: some View {
        let cal = store.calendar
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        Lbl("MOTRA · PASTE")
                        Text("IMPORT").font(.heading(22)).foregroundStyle(.white)
                    }
                    Spacer()
                }
                VStack(spacing: 6) {
                    Button("PASTE FROM CLIPBOARD") { paste() }
                        .buttonStyle(PrimaryButtonStyle())
                    Text("In Motra: share the workout, copy the text, then paste it here.")
                        .font(.vt(18)).foregroundStyle(Palette.muted)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                    Button(showEditor ? "HIDE TEXT" : "TYPE OR EDIT TEXT") { showEditor.toggle() }
                        .buttonStyle(SecondaryButtonStyle(height: 40))
                }
                if showEditor { editor }
                if let err = draft.error {
                    Text(err).font(.vt(19)).foregroundStyle(Palette.alertText)
                }
                if let w = draft.workout {
                    workoutCard(w, cal)
                    exercisesRow(w)
                    suggestion(w)
                } else if draft.error == nil {
                    emptyHint
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 18)
            .padding(.bottom, 96)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .screen()
    }

    private var editor: some View {
        @Bindable var d = draft
        return VStack(spacing: 6) {
            TextEditor(text: $d.text)
                .font(.number(18))
                .foregroundStyle(Color.white)
                .scrollContentBackground(.hidden)
                .padding(8)
                .frame(minHeight: 160)
                .background(Palette.input)
                .innerBorder(Palette.inputEdge)
            Button("READ TEXT") { parse(draft.text) }
                .buttonStyle(SecondaryButtonStyle(edge: Palette.lime, textColor: Palette.lime, height: 44))
        }
    }

    private var emptyHint: some View {
        VStack(alignment: .leading, spacing: 6) {
            Lbl("HOW IT WORKS")
            Text("Paste a workout and the app reads the exercises and sets. If an exercise counts for this month's challenge, its best set becomes an entry automatically. Every import also logs a workout for the This week panel.")
                .font(.vt(19)).foregroundStyle(Palette.soft)
                .fixedSize(horizontal: false, vertical: true)
            Text("HealthKit and sharing straight from Motra come next.")
                .font(.vt(17)).foregroundStyle(Palette.infoText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .panel()
    }

    private func workoutCard(_ w: ParsedWorkout, _ cal: Calendar) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(w.name.uppercased()).font(.heading(16)).foregroundStyle(.white).lineLimit(2)
                Spacer()
                Lbl(w.date.map { Fmt.dayTime($0, cal) } ?? "NO DATE · USES TODAY")
            }
            HStack(alignment: .top, spacing: 8) {
                stat("TIME", w.durationMinutes.map { "\(Int($0.rounded())) min" } ?? "—")
                stat("VOLUME", w.volumeKg.map { $0 >= 1000 ? String(format: "%.1fK kg", $0 / 1000) : "\(Int($0)) kg" } ?? "—")
                stat("KCAL", w.kcal.map { "\(Int($0))" } ?? "—")
            }
        }
        .padding(16)
        .panel()
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Lbl(label)
            Text(value).font(.number(26))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func targetMonth(_ w: ParsedWorkout) -> Int? {
        let d = w.date ?? store.now
        guard let m = store.rules.currentMonth(now: d) else { return nil }
        let r = store.engine.resolve(m)
        return (r.isLocked && r.challenge != nil && !r.isFinal && !r.isForfeit) ? m : nil
    }

    private func exercisesRow(_ w: ParsedWorkout) -> some View {
        let month = targetMonth(w)
        let counted = month.map { store.countedExercises(month: $0) } ?? []
        let n = w.exercises.filter { MotraParser.counts($0.name, counted: counted) }.count
        return Button {
            router.push(.exercises)
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Lbl("EXERCISES FOUND")
                    (Text("\(w.exercises.count) exercise\(w.exercises.count == 1 ? "" : "s")").foregroundColor(.white)
                     + Text(month != nil ? " · \(n) count\(n == 1 ? "s" : "") for \(YearConfig.name(month!).capitalized)" : "")
                        .foregroundColor(Palette.lime))
                        .font(.number(22))
                }
                Spacer()
                PixelIcon(.chevron).frame(width: 16, height: 16).foregroundStyle(Palette.lime)
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
            .panel()
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func suggestion(_ w: ParsedWorkout) -> some View {
        let month = targetMonth(w)
        let ch = month.flatMap { store.engine.resolve($0).challenge }
        let sug: (value: Double, weightKg: Double?, reps: Int?)? = {
            guard let m = month, let ch else { return nil }
            return MotraParser.suggestedValue(workout: w, challenge: ch, counted: store.countedExercises(month: m))
        }()
        if let m = month, let ch, let s = sug {
            VStack(alignment: .leading, spacing: 4) {
                Lbl("ENTRY ADDED AUTOMATICALLY", color: Palette.lime)
                (Text("\(ch.name): ") + Text(ValueFormat.formatWithUnit(s.value, ch)).foregroundColor(Palette.lime)
                 + Text(" on \(Fmt.dayMonth(w.date ?? store.now, store.calendar))"))
                    .font(.vt(22))
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .notched(fill: Palette.lime.opacity(0.08), edge: Palette.lime)
            Button("SAVE WORKOUT + ENTRY") { save(w, month: m, entryValue: s) }
                .buttonStyle(PrimaryButtonStyle())
        } else {
            Text(month == nil ? "No locked challenge for this date, so it saves as a workout only."
                              : "Nothing here counts for this month's challenge. Toggle exercises to count them, or save the sets.")
                .font(.vt(18)).foregroundStyle(Palette.muted)
                .fixedSize(horizontal: false, vertical: true)
            Button("SAVE WORKOUT") { save(w, month: month, entryValue: nil) }
                .buttonStyle(PrimaryButtonStyle())
        }
    }

    // MARK: Actions

    private func paste() {
        let text = UIPasteboard.general.string ?? ""
        draft.text = text
        parse(text)
    }

    private func parse(_ text: String) {
        if let w = MotraParser.parse(text, calendar: store.calendar), !w.exercises.isEmpty || w.durationMinutes != nil {
            draft.workout = w
            draft.error = nil
        } else {
            draft.workout = nil
            draft.error = text.isEmpty ? "The clipboard is empty." : "Couldn't read a workout from that text."
        }
    }

    private func save(_ w: ParsedWorkout, month: Int?, entryValue: (value: Double, weightKg: Double?, reps: Int?)?) {
        let date = w.date ?? store.now
        let counted = month.map { store.countedExercises(month: $0) } ?? []
        let anyCounts = w.exercises.contains { MotraParser.counts($0.name, counted: counted) }
        let workout = Workout(date: date, kind: anyCounts ? .challenge : .other, source: .motra, title: w.name,
                              durationMinutes: w.durationMinutes, notes: nil, exercises: w.exercises)
        store.addWorkout(workout)
        if let m = month, let v = entryValue {
            let entry = Entry(month: m, date: date, value: v.value, weightKg: v.weightKg, reps: v.reps, source: .motra)
            if store.addEntry(entry, alsoLogSession: false) {
                store.message = "Workout and entry saved."
            }
        } else {
            store.message = "Workout saved."
        }
        draft.workout = nil
        draft.text = ""
        draft.error = nil
    }
}

struct ExercisesView: View {
    @Environment(AppStore.self) private var store
    @Environment(ImportDraft.self) private var draft
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let cal = store.calendar
        let w = draft.workout
        let date = w?.date ?? store.now
        let month = store.rules.currentMonth(now: date)
        let canToggle = month.map { store.engine.resolve($0).challenge != nil && !store.engine.resolve($0).isFinal } ?? false
        let counted = month.map { store.countedExercises(month: $0) } ?? []
        let monthShort = month.map { YearConfig.short($0) } ?? ""
        let n = (w?.exercises ?? []).filter { MotraParser.counts($0.name, counted: counted) }.count
        return ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 12) {
                        BackButton { dismiss() }
                        VStack(alignment: .leading, spacing: 4) {
                            Lbl("\((w?.name ?? "WORKOUT").uppercased()) · \(Fmt.dayMonth(date, cal).uppercased())")
                            Text("\(w?.exercises.count ?? 0) EXERCISES").font(.heading(20)).foregroundStyle(.white)
                        }
                    }
                    Text("Warm-ups and drop sets are kept but never count as a best set.")
                        .font(.vt(18)).foregroundStyle(Palette.muted)
                    ForEach(Array((w?.exercises ?? []).enumerated()), id: \.offset) { _, ex in
                        exerciseCard(ex, counts: MotraParser.counts(ex.name, counted: counted),
                                     month: month, monthShort: monthShort, canToggle: canToggle)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 18)
                .padding(.bottom, 90)
            }
            .scrollIndicators(.hidden)
            Button("DONE · \(n) COUNTED") { dismiss() }
                .buttonStyle(PrimaryButtonStyle(height: 54))
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
        }
        .screen()
    }

    private func bestLine(_ ex: ParsedExercise) -> String {
        guard let b = MotraParser.best(ex) else { return "NO WORKING SETS" }
        if let e = b.e1rm {
            return "E1RM \(ValueFormat.formatNumber(e)) KG" + (b.unreliable ? " · SHAKY, \(b.reps) REPS" : "")
        }
        return "BEST \(b.reps) REPS · BODYWEIGHT"
    }

    private func exerciseCard(_ ex: ParsedExercise, counts: Bool, month: Int?, monthShort: String, canToggle: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(ex.name).font(.vt(22)).foregroundStyle(.white)
                    Lbl(bestLine(ex), color: counts ? Palette.lime : Palette.muted, size: 9)
                }
                Spacer()
                Button(counts ? "COUNTS · \(monthShort)" : "+ COUNT") {
                    if let m = month { store.toggleCounted(exercise: ex.name, month: m) }
                }
                .font(.label(9)).tracking(1)
                .foregroundStyle(counts ? Palette.onLime : Palette.muted)
                .padding(.horizontal, 8)
                .frame(height: 32)
                .notched(fill: counts ? Palette.lime : Color.clear, edge: counts ? Palette.lime : Palette.edge2)
                .buttonStyle(.plain)
                .disabled(!canToggle)
                .opacity(canToggle ? 1 : 0.4)
            }
            VStack(spacing: 2) {
                ForEach(Array(ex.sets.enumerated()), id: \.offset) { _, s in
                    let dim = s.setType != .normal
                    HStack(spacing: 8) {
                        Text(s.index == 0 ? (s.setType == .warmup ? "W" : "D") : "\(s.index)").frame(width: 20, alignment: .leading)
                        Text("\(s.reps) × \(s.weightKg.map { "\(ValueFormat.formatNumber($0)) kg" } ?? "BW")")
                        Spacer()
                        if dim { Lbl(s.setType == .warmup ? "WARM-UP" : "DROP SET", size: 9) }
                    }
                    .font(.number(19))
                    .foregroundStyle(dim ? Palette.veryDim : Palette.soft)
                }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .notched(fill: counts ? Palette.lime.opacity(0.07) : Palette.panel, edge: counts ? Palette.lime : Palette.panelEdge)
    }
}
