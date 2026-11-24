import Foundation
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    @State private var exportFile: ExportFile?
    @State private var showImporter = false
    @State private var resetArmed = false
    @State private var demoArmed = false

    var body: some View {
        @Bindable var store = store
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Lbl("HOUSEKEEPING")
                    Text("SETUP").font(.heading(22)).foregroundStyle(.white)
                        .onLongPressGesture(minimumDuration: 1.2) { router.push(.debug) }
                        .accessibilityHint("Long-press for the debug screen")
                }
                rules
                notifications($store.settings.notifications)
                health
                trainingWeek
                testDate
                backup
                resetButton
                Text("Build \(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?") · catalogue v\(store.catalogue.version)")
                    .font(.vt(16)).foregroundStyle(Palette.veryDim)
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 16)
            .padding(.top, 18)
            .padding(.bottom, 96)
        }
        .scrollIndicators(.hidden)
        .screen()
        .sheet(item: $exportFile) { file in
            ShareSheet(items: [file.url])
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in
            if case .success(let url) = result { _ = store.restore(from: url) }
        }
    }

    private func section<C: View>(_ title: String, color: Color = Palette.muted, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Lbl(title, color: color)
            content()
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panel()
    }

    private var rules: some View {
        section("RULES") {
            VStack(alignment: .leading, spacing: 3) {
                ForEach(Array(["12 slots. Exactly 2 are redo months.",
                               "Change the challenge until midnight on the 1st, then it locks.",
                               "Baseline and target: change them until day 7, or lock them in sooner.",
                               "No challenge on the 1st, or no baseline and target by day 7, scores 0.",
                               "Score 0–120. Redo keeps the better attempt.",
                               "One plate per side per 100 points."].enumerated()), id: \.offset) { i, line in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(i + 1).").foregroundStyle(Palette.muted).frame(width: 18, alignment: .trailing)
                        Text(line).foregroundStyle(Palette.soft).fixedSize(horizontal: false, vertical: true)
                    }
                    .font(.vt(18))
                }
            }
        }
    }

    private func notifications(_ t: Binding<NotificationToggles>) -> some View {
        section("NOTIFICATIONS") {
            VStack(spacing: 2) {
                toggleRow("Next slot empty, 7 and 2 days before lock", t.nextSlotEmpty)
                toggleRow("Baseline blank on day 1 and day 3", t.baselineBlank)
                toggleRow("No result 3 days before month end", t.noResult)
                toggleRow("Result not finalized, day after", t.notFinalized)
                toggleRow("Mascot drops to tired or slumped", t.moodDrop)
            }
        }
        .onAppear { store.requestNotificationPermission() }
    }

    private func toggleRow(_ label: String, _ on: Binding<Bool>) -> some View {
        HStack(spacing: 10) {
            Text(label).font(.vt(19)).fixedSize(horizontal: false, vertical: true)
            Spacer()
            PixelSwitch(isOn: on, label: label)
        }
        .frame(minHeight: 44)
    }

    private var health: some View {
        section("APPLE HEALTH · READ ONLY", color: Palette.infoText) {
            Text("Watch workouts count toward momentum. Runs, rides and rows fill in entries for distance and timed challenges (5K, 2K, long run, long ride). Nothing is finalized for you.")
                .font(.vt(18)).foregroundStyle(Palette.soft)
                .fixedSize(horizontal: false, vertical: true)
            if store.settings.healthConnected {
                HStack(spacing: 8) {
                    Lbl("CONNECTED", color: Palette.lime)
                    Spacer()
                    Lbl(store.settings.lastHealthSync.map { "SYNCED \(Fmt.dayLabel($0, store.calendar))" } ?? "NOT SYNCED YET")
                }
                Button("SYNC NOW") { Task { await store.syncHealth(); store.message = "Health synced." } }
                    .buttonStyle(SecondaryButtonStyle(edge: Palette.info, textColor: Palette.infoText, height: 44))
                Text("To change access: Settings app › Health › Data Access & Devices › 2027 Challenge.")
                    .font(.vt(16)).foregroundStyle(Palette.dim)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Button("CONNECT APPLE HEALTH") { Task { await store.connectHealth() } }
                    .buttonStyle(PrimaryButtonStyle(fill: Palette.info, textColor: .white, height: 44))
            }
        }
    }

    private var trainingWeek: some View {
        section("NORMAL WEEK · MOMENTUM") {
            HStack(spacing: 10) {
                Text("Other workouts in a normal week (on top of the challenge sessions)")
                    .font(.vt(19)).fixedSize(horizontal: false, vertical: true)
                Spacer()
                stepButton("-") { store.settings.otherWorkoutsPerWeek = max(0, store.settings.otherWorkoutsPerWeek - 1) }
                Text("\(store.settings.otherWorkoutsPerWeek)").font(.number(30)).foregroundStyle(Palette.lime).frame(minWidth: 28)
                stepButton("+") { store.settings.otherWorkoutsPerWeek = min(14, store.settings.otherWorkoutsPerWeek + 1) }
            }
            Text("A normal week keeps the mascot pumped. On fire needs a new best on top.")
                .font(.vt(17)).foregroundStyle(Palette.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func stepButton(_ t: String, action: @escaping () -> Void) -> some View {
        Button(t, action: action)
            .font(.heading(16))
            .foregroundStyle(Palette.lime)
            .frame(width: 44, height: 44)
            .notched(fill: .clear, edge: Palette.edge2)
            .buttonStyle(.plain)
    }

    private var testDate: some View {
        @Bindable var store = store
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Lbl("TEST MODE · DEMO YEAR", color: Palette.plateYellow)
                Spacer()
                PixelSwitch(isOn: Binding(get: { store.isTestMode },
                                          set: { $0 ? store.enterTestMode() : store.exitTestMode() }),
                            onColor: Palette.plateYellow, label: "Test mode")
            }
            Text("Pretend it is").font(.vt(18)).foregroundStyle(Palette.soft)
            DatePicker("", selection: $store.settings.testDate, displayedComponents: [.date, .hourAndMinute])
                .labelsHidden()
                .datePickerStyle(.compact)
                .colorScheme(.dark)
            Text("Uses a separate demo year so you can tap, log and finalize freely. Real data is never changed.")
                .font(.vt(18)).foregroundStyle(Palette.muted)
                .fixedSize(horizontal: false, vertical: true)
            Button(demoArmed ? "TAP AGAIN TO REFILL" : "REFILL DEMO DATA") {
                if demoArmed {
                    store.resetDemo()
                    demoArmed = false
                } else {
                    demoArmed = true
                }
            }
            .buttonStyle(SecondaryButtonStyle(edge: Palette.plateYellow, textColor: Palette.plateYellow, height: 44))
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .notched(fill: Palette.plateYellow.opacity(0.06), edge: Palette.testEdge)
    }

    private var backup: some View {
        section("BACKUP · JSON\(store.isTestMode ? " · DEMO YEAR" : "")") {
            HStack(spacing: 8) {
                Button("EXPORT") { exportFile = store.exportFileURL().map { ExportFile(url: $0) } }
                    .buttonStyle(PrimaryButtonStyle(height: 44))
                Button("RESTORE") { showImporter = true }
                    .buttonStyle(SecondaryButtonStyle(edge: Palette.lime, textColor: Palette.lime, height: 44))
            }
            Text(store.settings.lastExport.map { "Last export: \(Fmt.dayMonthYear($0, store.calendar))" } ?? "Not exported yet")
                .font(.vt(18)).foregroundStyle(Palette.muted)
        }
    }

    private var resetButton: some View {
        HStack(spacing: 6) {
            Button(resetArmed ? "TAP AGAIN TO RESET \(store.isTestMode ? "DEMO" : "2027")" : "RESET YEAR") {
                if resetArmed {
                    store.resetYear()
                    resetArmed = false
                } else {
                    resetArmed = true
                }
            }
            .buttonStyle(SecondaryButtonStyle(edge: Palette.alert, textColor: Palette.alertText))
            if resetArmed {
                Button("CANCEL") { resetArmed = false }
                    .buttonStyle(SecondaryButtonStyle())
                    .frame(width: 96)
            }
        }
    }
}

struct ExportFile: Identifiable {
    let id = UUID()
    let url: URL
}

/// UIActivityViewController wrapper for exporting the backup file.
struct ShareSheet: UIViewControllerRepresentable {
    var items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

struct DebugView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let mom = store.momentum
        let cal = store.calendar
        let json = (try? Persistence.encoder.encode(store.state)).flatMap { String(data: $0, encoding: .utf8) } ?? "?"
        return ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    BackButton { dismiss() }
                    Text("DEBUG").font(.heading(20)).foregroundStyle(.white)
                }
                section("NOW") {
                    Text("\(store.now.formatted()) · test \(store.isTestMode ? "on" : "off")")
                    Text("Store: \(Persistence.directory.lastPathComponent)")
                }
                section("MOMENTUM · LAST 14 DAYS") {
                    ForEach(Array(mom.days.suffix(14).enumerated()), id: \.offset) { _, d in
                        Text("\(Fmt.dayMonth2(d.date, cal))  a \(f(d.a))  g \(f(d.g))  m \(f(d.m))  \(d.mood.rawValue)\(d.newBest ? " ★" : "")  \(d.challengeSessions)c \(d.otherWorkouts)o")
                    }
                }
                section("LOG") {
                    ForEach(Array(AppLog.lines.suffix(60).reversed().enumerated()), id: \.offset) { _, line in
                        Text(line)
                    }
                }
                section("STATE") {
                    Text(json).textSelection(.enabled)
                }
            }
            .font(.number(15))
            .foregroundStyle(Palette.soft)
            .padding(16)
        }
        .screen()
    }

    private func f(_ v: Double) -> String { String(format: "%.2f", v) }

    private func section<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Lbl(title)
            content()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panel()
    }
}
