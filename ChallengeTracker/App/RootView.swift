import Foundation
import Observation
import SwiftUI
import UIKit

enum AppTab: String, CaseIterable, Hashable {
    case home, year, stats, importTab, setup

    var title: String {
        switch self {
        case .home: return "HOME"
        case .year: return "YEAR"
        case .stats: return "STATS"
        case .importTab: return "IMPORT"
        case .setup: return "SETUP"
        }
    }

    var icon: PixelIcon.Kind {
        switch self {
        case .home: return .home
        case .year: return .year
        case .stats: return .stats
        case .importTab: return .importIcon
        case .setup: return .setup
        }
    }
}

enum Route: Hashable {
    case pick(Int)
    case challenge(Int)
    case exercises
    case debug
}

/// Navigation state per tab, shared through the environment.
@Observable
@MainActor
final class Router {
    var tab: AppTab = .home
    var paths: [AppTab: [Route]] = [:]

    func path(_ t: AppTab) -> [Route] { paths[t] ?? [] }

    func binding(_ t: AppTab) -> Binding<[Route]> {
        Binding(get: { self.paths[t] ?? [] }, set: { self.paths[t] = $0 })
    }

    func push(_ r: Route) {
        paths[tab, default: []].append(r)
    }

    /// Replace the top route (used after picking: Pick → Challenge detail).
    func replaceTop(with r: Route) {
        var p = paths[tab] ?? []
        if !p.isEmpty { p.removeLast() }
        p.append(r)
        paths[tab] = p
    }

    func pop() {
        if var p = paths[tab], !p.isEmpty {
            p.removeLast()
            paths[tab] = p
        }
    }

    func go(_ t: AppTab, _ r: Route? = nil) {
        tab = t
        paths[t] = r.map { [$0] } ?? []
    }

    var isPushed: Bool { !(paths[tab] ?? []).isEmpty }
}

/// Parsed import waiting to be saved (Import tab → Exercises screen).
@Observable
@MainActor
final class ImportDraft {
    var text: String = ""
    var workout: ParsedWorkout?
    var error: String?
}

struct RootView: View {
    @State private var store = AppStore()
    @State private var router = Router()
    @State private var draft = ImportDraft()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack(alignment: .bottom) {
            Atmosphere()
            tabContent
            if !router.isPushed {
                TabBar(selection: Binding(get: { router.tab }, set: { router.tab = $0 }))
                    .padding(.horizontal, 12)
                    .padding(.bottom, 4)
            }
            ToastView(message: Binding(get: { store.message }, set: { store.message = $0 }))
                .padding(.bottom, router.isPushed ? 90 : 84)
            ScanlineOverlay()
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if store.isTestMode { TestModeBanner() }
        }
        .environment(store)
        .environment(router)
        .environment(draft)
        .preferredColorScheme(.dark)
        .tint(Palette.lime)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { store.refresh() }
        }
        .onChange(of: store.unreadShare) { _, text in
            guard let text else { return }
            draft.text = text
            draft.workout = nil
            draft.error = "Got a share from Motra but couldn't read a workout in it. The text is below."
            router.go(.importTab)
            store.unreadShare = nil
        }
        .task {
            store.refresh()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                store.tick = Date()
            }
        }
    }

    @ViewBuilder private var tabContent: some View {
        switch router.tab {
        case .home: stack(.home) { HomeView() }
        case .year: stack(.year) { YearView() }
        case .stats: stack(.stats) { StatsView() }
        case .importTab: stack(.importTab) { ImportView() }
        case .setup: stack(.setup) { SettingsView() }
        }
    }

    private func stack<Content: View>(_ t: AppTab, @ViewBuilder _ content: () -> Content) -> some View {
        NavigationStack(path: router.binding(t)) {
            content()
                .navigationDestination(for: Route.self) { r in
                    switch r {
                    case .pick(let m): PickView(month: m)
                    case .challenge(let m): ChallengeDetailView(month: m)
                    case .exercises: ExercisesView()
                    case .debug: DebugView()
                    }
                }
        }
        .id(t)
    }
}

// MARK: - Screen chrome

extension View {
    /// Background, hidden navigation bar, standard padding for a screen.
    func screen() -> some View {
        self
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Atmosphere())
            .toolbar(.hidden, for: .navigationBar)
            .foregroundStyle(Palette.text)
            .font(.vt(20))
    }
}

struct TabBar: View {
    @Binding var selection: AppTab

    var body: some View {
        HStack(spacing: 4) {
            ForEach(AppTab.allCases, id: \.self) { t in
                let on = t == selection
                Button {
                    selection = t
                } label: {
                    VStack(spacing: 4) {
                        PixelIcon(t.icon).frame(width: 16, height: 16)
                        Text(t.title).font(.label(9)).tracking(1).lineLimit(1).minimumScaleFactor(0.7)
                    }
                    .foregroundStyle(on ? Palette.onLime : Palette.muted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .notched(fill: on ? Palette.lime : Color.clear)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(t.title.capitalized)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(6)
        .frame(height: 60)
        .notched(fill: Color(hex: 0x0A0D12, opacity: 0.96), edge: Palette.panelEdge)
    }
}

struct TestModeBanner: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        HStack(spacing: 8) {
            Lbl("TEST MODE", color: Palette.onLime)
            Text(Fmt.dayMonthYear(store.now, store.calendar))
                .font(.number(18))
                .foregroundStyle(Palette.onLime)
            Spacer()
            Button("EXIT") { store.exitTestMode() }
                .font(.heading(10))
                .foregroundStyle(Palette.onLime)
                .padding(.horizontal, 8)
                .frame(minHeight: 32)
                .innerBorder(Palette.onLime)
                .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .background(Palette.plateYellow)
    }
}

struct ToastView: View {
    @Binding var message: String?

    var body: some View {
        if let m = message {
            Text(m)
                .font(.vt(19))
                .foregroundStyle(Palette.text)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .notched(fill: Color(hex: 0x0A0D12, opacity: 0.97), edge: Palette.plateYellow)
                .padding(.horizontal, 24)
                .onTapGesture { message = nil }
                .task(id: m) {
                    try? await Task.sleep(nanoseconds: 2_800_000_000)
                    if message == m { message = nil }
                }
                .accessibilityAddTraits(.isStaticText)
        }
    }
}

// MARK: - Formatting helpers for the UI

enum Fmt {
    static func formatter(_ format: String, _ cal: Calendar) -> DateFormatter {
        let f = DateFormatter()
        f.calendar = cal
        f.timeZone = cal.timeZone
        f.locale = Locale(identifier: "en_GB")
        f.dateFormat = format
        return f
    }

    /// "SUN 14 MAR"
    static func dayLabel(_ d: Date, _ cal: Calendar) -> String { formatter("EEE d MMM", cal).string(from: d).uppercased() }
    /// "14 Mar"
    static func dayMonth(_ d: Date, _ cal: Calendar) -> String { formatter("d MMM", cal).string(from: d) }
    /// "02 Mar"
    static func dayMonth2(_ d: Date, _ cal: Calendar) -> String { formatter("dd MMM", cal).string(from: d) }
    /// "14 Mar 2027"
    static func dayMonthYear(_ d: Date, _ cal: Calendar) -> String { formatter("d MMM yyyy", cal).string(from: d) }
    /// "THU 11 MAR · 06:15"
    static func dayTime(_ d: Date, _ cal: Calendar) -> String { formatter("EEE d MMM · HH:mm", cal).string(from: d).uppercased() }
    /// "1 APR"
    static func lockLabel(_ d: Date, _ cal: Calendar) -> String { formatter("d MMM", cal).string(from: d).uppercased() }
}
