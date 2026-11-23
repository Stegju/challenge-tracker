import Foundation
import SwiftUI
import UIKit

/// Home before 1 January 2027: countdown, January pick, test mode.
struct CountdownView: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    @State private var showWorkout = false

    var body: some View {
        let engine = store.engine
        let jan = engine.resolve(1)
        let dec = engine.resolve(12)
        let mood = store.displayMood
        ScrollView {
            VStack(spacing: 14) {
                VStack(spacing: 10) {
                    Lbl("TWELVE MONTHS · TWELVE CHALLENGES", color: Palette.muted)
                    NeonSign(fontSize: 44)
                        .padding(.vertical, 6)
                }
                .padding(.top, 14)

                CountdownClock(target: store.rules.yearStart, testNow: store.isTestMode ? store.now : nil)

                HStack(spacing: 20) {
                    VStack(spacing: 0) {
                        MascotView(mood: mood == .slumped || mood == .tired ? .steady : .pumped, size: 120)
                        Rectangle().fill(Color.black.opacity(0.4)).frame(width: 72, height: 6).offset(y: -4)
                    }
                    SpeechBubble(mood: .pumped, text: jan.isChosen
                                 ? (jan.target == nil ? "Set January's target before midnight on the 31st." : "January is set. See you on the 1st.")
                                 : "Pick January before midnight on the 31st.")
                }
                .padding(.vertical, 4)

                januaryCard(jan)

                bossCard(dec)

                Button("+ LOG WORKOUT") { showWorkout = true }
                    .buttonStyle(SecondaryButtonStyle(height: 44))

                testModeCard
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 96)
        }
        .scrollIndicators(.hidden)
        .sheet(isPresented: $showWorkout) { WorkoutSheet() }
    }

    private func januaryCard(_ jan: ResolvedSlot) -> some View {
        let days = store.rules.daysUntilLock(1, now: store.now)
        return Button {
            if jan.isChosen { router.push(.challenge(1)) } else { router.push(.pick(1)) }
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Lbl("JANUARY LOCKS IN \(days) DAY\(days == 1 ? "" : "S")", color: Palette.lime)
                    Spacer()
                    Lbl("1 JAN 00:00", color: Palette.soft)
                }
                if let ch = jan.challenge {
                    Text(ch.name.uppercased()).font(.heading(18)).foregroundStyle(.white)
                    HStack(spacing: 8) {
                        tile("BASELINE", jan.baseline.map { ValueFormat.format($0, metric: ch.metric) } ?? "—")
                        tile("TARGET", jan.target.map { ValueFormat.format($0, metric: ch.metric) } ?? "—")
                    }
                    if jan.target == nil {
                        Text("No target yet. Empty at lock scores 0.").font(.vt(18)).foregroundStyle(Palette.plateYellow)
                    }
                } else {
                    Text("Nothing picked yet").font(.vt(22)).foregroundStyle(Palette.text)
                }
                Text(jan.isChosen ? "EDIT JANUARY" : "CHOOSE JANUARY")
                    .font(.heading(12)).tracking(1)
                    .foregroundStyle(Palette.onLime)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .notched(fill: Palette.lime)
            }
            .padding(16)
            .notched(fill: Palette.lime.opacity(0.08), edge: Palette.lime)
        }
        .buttonStyle(.plain)
    }

    private func tile(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Lbl(label)
            Text(value).font(.number(30)).foregroundStyle(.white)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .notched(fill: Palette.input)
    }

    private func bossCard(_ dec: ResolvedSlot) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Lbl("DECEMBER · BOSS", color: Palette.alertText)
                Text(dec.challenge?.name ?? "Murph").font(.vt(22)).foregroundStyle(Palette.bossName)
            }
            Spacer()
            Lbl("BOSS", color: Palette.alertText)
                .padding(.horizontal, 8).padding(.vertical, 5)
                .innerBorder(Palette.alert)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .notched(fill: Palette.alert.opacity(0.08), edge: Palette.alert)
    }

    private var testModeCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Lbl("TEST MODE · SEE 2027 NOW", color: Palette.plateYellow)
            Text("Jump to 14 March 2027 with a demo year: January done, February maxed, March in progress. Your real data is untouched.")
                .font(.vt(18)).foregroundStyle(Palette.soft)
                .fixedSize(horizontal: false, vertical: true)
            Button("ENTER TEST MODE") { store.enterTestMode() }
                .buttonStyle(PrimaryButtonStyle(fill: Palette.plateYellow))
        }
        .padding(14)
        .notched(fill: Palette.plateYellow.opacity(0.06), edge: Palette.testEdge)
    }
}

/// DD : HH : MM : SS to the start of the year, ticking every second.
struct CountdownClock: View {
    var target: Date
    var testNow: Date?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { tl in
            let now = testNow ?? tl.date
            let secs = max(0, Int(target.timeIntervalSince(now)))
            let d = secs / 86_400, h = (secs % 86_400) / 3600, m = (secs % 3600) / 60, s = secs % 60
            HStack(alignment: .top, spacing: 4) {
                unit(d, "DAYS", pad: false)
                colon
                unit(h, "HRS", pad: true)
                colon
                unit(m, "MIN", pad: true)
                colon
                unit(s, "SEC", pad: true)
            }
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .panel()
            .accessibilityElement()
            .accessibilityLabel("\(d) days, \(h) hours, \(m) minutes until 2027")
        }
    }

    private var colon: some View {
        Text(":").font(.number(44)).foregroundStyle(Palette.dim)
    }

    private func unit(_ v: Int, _ label: String, pad: Bool) -> some View {
        VStack(spacing: 0) {
            Text(pad ? String(format: "%02d", v) : "\(v)")
                .font(.number(52))
                .foregroundStyle(Palette.lime)
                .shadow(color: Palette.lime.opacity(0.5), radius: 6)
                .monospacedDigit()
            Lbl(label, size: 9)
        }
        .frame(minWidth: 56)
    }
}
