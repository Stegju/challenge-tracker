import Foundation
import SwiftUI
import UIKit

struct HomeView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        Group {
            if store.isBeforeYear {
                CountdownView()
            } else if let m = store.currentMonth {
                HomeMonthView(month: m)
            } else {
                YearDoneView()
            }
        }
        .screen()
    }
}

// MARK: - Home during 2027

struct HomeMonthView: View {
    var month: Int
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    @State private var showExplain = false
    @State private var showWorkout = false

    var body: some View {
        let engine = store.engine
        let r = engine.resolve(month)
        let mom = store.momentum
        let mood = MomentumEngine.displayMood(momentum: mom, currentMonth: r)
        ScrollView {
            VStack(spacing: 10) {
                TopRow(total: engine.yearTotal, redosUsed: engine.redosUsed())
                MonthStrip(engine: engine, current: month, todayLabel: Fmt.dayLabel(store.now, store.calendar))
                mascotRow(mood: mood, mom: mom)
                CurrentChallengeCard(r: r, daysLeft: store.rules.daysLeft(month, now: store.now))
                WeekPanel(mom: mom, onAdd: { showWorkout = true })
                nextMonthCard(engine: engine)
            }
            .padding(.horizontal, 16)
            .padding(.top, 18)
            .padding(.bottom, 96)
        }
        .scrollIndicators(.hidden)
        .sheet(isPresented: $showWorkout) { WorkoutSheet() }
    }

    private func mascotRow(mood: Mood, mom: MomentumResult) -> some View {
        HStack(spacing: 20) {
            Button {
                showExplain.toggle()
            } label: {
                VStack(spacing: 0) {
                    MascotView(mood: mood, size: 132)
                    Rectangle().fill(Color.black.opacity(0.4)).frame(width: 80, height: 6).offset(y: -4)
                }
            }
            .buttonStyle(.plain)
            .accessibilityHint("Shows why the mascot feels this way")
            SpeechBubble(mood: mood,
                         text: showExplain
                            ? MomentumEngine.explanation(momentum: mom, now: store.now, calendar: store.calendar)
                            : MomentumEngine.status(mood: mood, momentum: mom))
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 138)
        .padding(.top, 8)
    }

    @ViewBuilder
    private func nextMonthCard(engine: YearEngine) -> some View {
        if let next = store.rules.nextLockMonth(now: store.now), next != month,
           store.rules.daysUntilLock(next, now: store.now) <= store.rules.config.nextMonthCardDays {
            let r = engine.resolve(next)
            let days = store.rules.daysUntilLock(next, now: store.now)
            NextMonthCard(month: next, days: days, chosenName: r.challenge?.name, canPick: engine.canPick(next)) {
                if r.isChosen { router.push(.challenge(next)) } else { router.push(.pick(next)) }
            }
        }
    }
}

struct TopRow: View {
    var total: Int
    var redosUsed: Int

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Lbl("TOTAL")
                (Text("\(total)").font(.number(36)).foregroundColor(.white)
                 + Text("/1000").font(.number(18)).foregroundColor(Palette.dim))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            NeonSign()
            VStack(alignment: .trailing, spacing: 2) {
                Lbl("REDO")
                HStack(spacing: 6) {
                    HStack(spacing: 3) {
                        ForEach(0..<2, id: \.self) { i in
                            Rectangle()
                                .fill(i < redosUsed ? Palette.redo : Color.clear)
                                .frame(width: 10, height: 10)
                                .innerBorder(Palette.redo)
                        }
                    }
                    (Text("\(redosUsed)").font(.number(36)).foregroundColor(.white)
                     + Text("/2").font(.number(18)).foregroundColor(Palette.dim))
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .accessibilityElement(children: .combine)
        }
    }
}

struct MonthStrip: View {
    var engine: YearEngine
    var current: Int?
    var todayLabel: String
    @Environment(Router.self) private var router
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Lbl("MONTHS")
                Spacer()
                Lbl(todayLabel, color: Palette.soft)
            }
            TimelineView(.periodic(from: .now, by: 0.6)) { tl in
                let pulseOn = reduceMotion ? true : Int(tl.date.timeIntervalSinceReferenceDate / 0.6) % 2 == 0
                HStack(spacing: 3) {
                    ForEach(1...12, id: \.self) { m in
                        cell(m, pulseOn: pulseOn)
                    }
                }
            }
        }
    }

    private func cell(_ m: Int, pulseOn: Bool) -> some View {
        let r = engine.resolve(m)
        let letter = YearConfig.monthLetters[m - 1]
        var bg = Color.clear
        var fg = Palette.dim
        var edge = Palette.inputEdge
        var edgeWidth: CGFloat = 1
        var glow = false
        var opacity = 1.0
        if r.isFinal {
            bg = Palette.lime; fg = Palette.onLime; edge = .clear
        } else if r.isForfeit && r.phase == .ended {
            bg = Palette.alert; fg = Palette.onLime; edge = .clear
        } else if m == current {
            bg = Palette.onLime; fg = Palette.lime; edge = Palette.lime; edgeWidth = 2
            opacity = pulseOn ? 1 : 0.45
        } else if r.isBoss || m == 12 {
            bg = Palette.alert.opacity(0.12); fg = Palette.alertText; edge = Palette.alert; edgeWidth = 2; glow = true
        } else if r.phase == .ended {
            edge = Palette.lime.opacity(0.5); fg = Palette.soft
        } else if r.isChosen {
            edge = Palette.edge2; fg = Palette.soft
        }
        return Button {
            if r.isChosen || r.isLocked { router.push(.challenge(m)) } else { router.push(.pick(m)) }
        } label: {
            Text(letter)
                .font(.number(20))
                .foregroundStyle(fg)
                .frame(maxWidth: .infinity)
                .frame(height: 26)
                .background(bg)
                .innerBorder(edge, width: edgeWidth)
                .shadow(color: glow ? Palette.alert.opacity(0.35) : .clear, radius: 4)
                .opacity(opacity)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(YearConfig.name(m).capitalized)\(r.isFinal ? ", done" : "")")
    }
}

struct SpeechBubble: View {
    var mood: Mood
    var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Lbl(mood.label, color: Palette.moodText(mood))
            Text(text)
                .font(.vt(20))
                .lineSpacing(-2)
                .foregroundStyle(Palette.text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(width: 150, alignment: .leading)
        .notched(fill: Color(.sRGB, red: 18 / 255, green: 24 / 255, blue: 34 / 255, opacity: 0.94), edge: Palette.moodEdge(mood))
        .accessibilityElement(children: .combine)
    }
}

struct CurrentChallengeCard: View {
    var r: ResolvedSlot
    var daysLeft: Int
    @Environment(Router.self) private var router
    @Environment(AppStore.self) private var store

    var body: some View {
        let accent = r.isBoss ? Palette.alert : Palette.lime
        let accentText = r.isBoss ? Palette.alertText : Palette.lime
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Lbl("\(YearConfig.name(r.month)) · \(r.challenge?.domain.rawValue.uppercased() ?? (r.isForfeit ? "FORFEIT" : "OPEN"))\(r.isRedo ? " · REDO" : "")",
                    color: accentText)
                Spacer()
                Lbl(r.isFinal ? "FINAL" : "\(daysLeft) DAY\(daysLeft == 1 ? "" : "S") LEFT", color: Palette.soft)
            }
            if let ch = r.challenge, !r.isForfeit {
                Text(ch.name.uppercased())
                    .font(.heading(18))
                    .tracking(0.5)
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(alignment: .lastTextBaseline) {
                    (Text(r.result.map { ValueFormat.format($0, metric: ch.metric) } ?? "—")
                        .font(.number(52)).foregroundColor(accentText)
                     + Text(" / \(r.target.map { ValueFormat.formatWithUnit($0, ch) } ?? "—")")
                        .font(.number(24)).foregroundColor(Palette.dim))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Spacer(minLength: 8)
                    if let b = r.baseline {
                        Text("from \(ValueFormat.format(b, metric: ch.metric))")
                            .font(.vt(20))
                            .foregroundStyle(Palette.muted)
                            .padding(.bottom, 6)
                    }
                }
                if r.setupOpen && (r.baseline == nil || r.target == nil) {
                    Lbl("SET BASELINE + TARGET BY DAY \(store.rules.config.setupDays)", color: Palette.plateYellow)
                }
                VStack(spacing: 4) {
                    ScoreMeter(score: Double(r.score ?? 0))
                    HStack {
                        Lbl(r.isFinal ? "\(r.score ?? 0) PTS FINAL" : "\(r.score ?? 0) PTS NOW")
                        Spacer()
                        Lbl("100")
                    }
                }
                Button(r.isFinal ? "VIEW RESULT" : "MONTH OVERVIEW") { router.push(.challenge(r.month)) }
                    .buttonStyle(PrimaryButtonStyle(fill: accent))
            } else {
                Text(r.isForfeit ? "FORFEIT · 0 POINTS" : "NOTHING CHOSEN")
                    .font(.heading(18))
                    .foregroundStyle(.white)
                Text(r.isForfeit ? "No challenge on the 1st, or no baseline and target by day 7. This month scores 0."
                                 : "Choose a challenge for this month.")
                    .font(.vt(20))
                    .foregroundStyle(Palette.muted)
                Button("DETAILS") { router.push(.challenge(r.month)) }
                    .buttonStyle(SecondaryButtonStyle())
            }
        }
        .padding(16)
        .panel(edge: r.isBoss ? Palette.alert : Palette.panelEdge)
    }
}

struct WeekPanel: View {
    var mom: MomentumResult
    var onAdd: () -> Void
    @Environment(AppStore.self) private var store

    var body: some View {
        let dose = store.engine.weeklyDose(on: store.now)
        let week = WeekSummary(workouts: store.state.workouts, now: store.now, dose: dose, calendar: store.calendar)
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Lbl("THIS WEEK")
                Spacer()
                Lbl(week.label, color: Palette.soft)
            }
            HStack(alignment: .bottom, spacing: 16) {
                HStack(alignment: .bottom, spacing: 4) {
                    ForEach(Array(week.days.enumerated()), id: \.offset) { _, d in
                        VStack(spacing: 4) {
                            VStack(spacing: 2) {
                                if d.blocks.isEmpty {
                                    if d.isToday {
                                        Rectangle().fill(Color.clear).frame(height: 10).innerBorder(.white)
                                    } else {
                                        Rectangle().fill(Palette.panelEdge).frame(height: 2)
                                    }
                                } else {
                                    ForEach(Array(d.blocks.reversed().enumerated()), id: \.offset) { _, b in
                                        Rectangle().fill(b == .challenge ? Palette.lime : Palette.plateBlue).frame(height: 10)
                                    }
                                }
                            }
                            Text(d.letter)
                                .font(.number(16))
                                .foregroundStyle(d.isToday ? Palette.onLime : Palette.dim)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 1)
                                .background(d.isToday ? Color.white : Color.clear)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .accessibilityElement()
                .accessibilityLabel("This week: \(week.challengeCount) of \(week.dose) challenge sessions and \(week.otherCount) other workouts")
                VStack(alignment: .trailing, spacing: 0) {
                    Text(String(format: "%.2f", mom.m)).font(.number(30)).foregroundStyle(Palette.lime)
                    Lbl("MOMENTUM \(mom.trend.arrow)", size: 9)
                }
            }
            HStack(spacing: 14) {
                keyItem(Palette.lime, "CHALLENGE", filled: true)
                keyItem(Palette.plateBlue, "OTHER WORKOUT", filled: true)
                keyItem(.white, "TODAY", filled: false)
                Spacer(minLength: 0)
            }
            .padding(.top, 2)
            Button("+ LOG WORKOUT", action: onAdd)
                .buttonStyle(SecondaryButtonStyle(height: 44))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .panel()
    }

    private func keyItem(_ c: Color, _ label: String, filled: Bool) -> some View {
        HStack(spacing: 5) {
            Rectangle().fill(filled ? c : Color.clear).frame(width: 10, height: 8).innerBorder(filled ? Color.clear : c)
            Lbl(label, size: 9)
        }
    }
}

struct NextMonthCard: View {
    var month: Int
    var days: Int
    var chosenName: String?
    var canPick: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Lbl("\(YearConfig.name(month)) LOCKS IN \(days) DAY\(days == 1 ? "" : "S")", color: Palette.lime)
                    Text(chosenName ?? "Nothing picked yet").font(.vt(20)).foregroundStyle(Palette.text)
                }
                Spacer()
                Text(chosenName == nil ? "CHOOSE" : "EDIT")
                    .font(.label(10)).tracking(1)
                    .foregroundStyle(Palette.onLime)
                    .padding(.horizontal, 10).padding(.vertical, 8)
                    .background(Palette.lime)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .notched(fill: Palette.lime.opacity(0.08), edge: Palette.lime)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - After the year

struct YearDoneView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        let e = store.engine
        ScrollView {
            VStack(spacing: 16) {
                NeonSign(fontSize: 32).padding(.top, 30)
                Lbl("THE YEAR IS DONE", color: Palette.lime, size: 12)
                (Text("\(e.yearTotal)").font(.number(64)).foregroundColor(.white)
                 + Text(" / 1000").font(.number(28)).foregroundColor(Palette.dim))
                BarbellView(points: e.yearTotal).padding(14).panel()
                MascotView(mood: store.displayMood, size: 132)
            }
            .padding(16)
            .padding(.bottom, 96)
        }
    }
}

// MARK: - Workout logging

struct WorkoutSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var kind: WorkoutKind = .other
    @State private var date = Date()
    @State private var title = ""
    @State private var didSetDate = false

    var body: some View {
        let cal = store.calendar
        let recent = store.state.workouts
            .filter { $0.date <= store.now && cal.dayCount(from: $0.date, to: store.now) < 14 }
            .sorted { $0.date > $1.date }
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("LOG WORKOUT").font(.heading(20)).foregroundStyle(.white)
                    Spacer()
                    Button("CLOSE") { dismiss() }.buttonStyle(.plain).font(.label(11)).foregroundStyle(Palette.muted)
                }
                Lbl("KIND")
                HStack(spacing: 4) {
                    kindButton(.challenge, "CHALLENGE SESSION")
                    kindButton(.other, "OTHER WORKOUT")
                }
                .padding(4)
                .panel()
                Text(kind == .challenge ? "Training for this month's challenge. Counts fully toward momentum."
                                        : "Anything else: hypertrophy, sport, a walk. Counts half.")
                    .font(.vt(18)).foregroundStyle(Palette.muted)
                Lbl("WHEN")
                DatePicker("", selection: $date, in: ...store.now, displayedComponents: [.date, .hourAndMinute])
                    .labelsHidden()
                    .datePickerStyle(.compact)
                    .colorScheme(.dark)
                Lbl("NOTE (OPTIONAL)")
                PixelField(placeholder: "e.g. Push day", text: $title, keyboard: .default, fontSize: 22)
                Button("SAVE WORKOUT") {
                    store.addWorkout(Workout(date: date, kind: kind, title: title.isEmpty ? nil : title))
                    dismiss()
                }
                .buttonStyle(PrimaryButtonStyle())
                if !recent.isEmpty {
                    Lbl("LAST 14 DAYS · LONG-PRESS TO DELETE").padding(.top, 8)
                    VStack(spacing: 4) {
                        ForEach(recent) { w in
                            HStack {
                                Rectangle().fill(w.kind == .challenge ? Palette.lime : Palette.plateBlue).frame(width: 10, height: 10)
                                Text(Fmt.dayLabel(w.date, cal)).font(.number(18)).foregroundStyle(Palette.muted)
                                Text(w.title ?? (w.kind == .challenge ? "Challenge session" : "Other workout"))
                                    .font(.vt(19)).lineLimit(1)
                                Spacer()
                                Lbl(w.source.label, size: 9)
                            }
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(Palette.input)
                            .contextMenu {
                                Button("Delete workout", role: .destructive) { store.deleteWorkout(w.id) }
                            }
                        }
                    }
                }
            }
            .padding(16)
        }
        .foregroundStyle(Palette.text)
        .background(Palette.background.ignoresSafeArea())
        .presentationDetents([.large])
        .onAppear {
            if !didSetDate {
                date = store.now
                didSetDate = true
            }
        }
    }

    private func kindButton(_ k: WorkoutKind, _ label: String) -> some View {
        Button(label) { kind = k }
            .font(.heading(10))
            .tracking(1)
            .foregroundStyle(kind == k ? Palette.onLime : Palette.muted)
            .frame(maxWidth: .infinity, minHeight: 44)
            .notched(fill: kind == k ? (k == .challenge ? Palette.lime : Palette.plateBlue) : Color.clear)
            .buttonStyle(.plain)
    }
}
