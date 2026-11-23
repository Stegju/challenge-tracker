import Foundation
import SwiftUI
import WidgetKit

// Medium widget (Widget.dc.html): mascot + mood on the left, this month's challenge on the right.
// Reads the snapshot the app writes into the App Group container.

struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

enum SnapshotStore {
    static func load() -> WidgetSnapshot {
        if let dir = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: WidgetSnapshot.appGroup) {
            let url = dir.appendingPathComponent(WidgetSnapshot.fileName)
            let d = JSONDecoder()
            d.dateDecodingStrategy = .iso8601
            if let data = try? Data(contentsOf: url), let s = try? d.decode(WidgetSnapshot.self, from: data) {
                return s
            }
        }
        return placeholder
    }

    static let placeholder = WidgetSnapshot(mood: "steady", moodLabel: "STEADY", title: "2027 · OPEN THE APP",
                                            best: "—", target: "—", score: 0, daysLeftLabel: "",
                                            points: 0, isBoss: false, updated: Date())

    static let sample = WidgetSnapshot(mood: "pumped", moodLabel: "PUMPED", title: "MAR · PULL-UPS",
                                       best: "15", target: "18", score: 50, daysLeftLabel: "17D LEFT",
                                       points: 201, isBoss: false, updated: Date())
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: Date(), snapshot: SnapshotStore.sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        let s = context.isPreview ? SnapshotStore.sample : SnapshotStore.load()
        completion(SnapshotEntry(date: Date(), snapshot: s))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let entry = SnapshotEntry(date: Date(), snapshot: SnapshotStore.load())
        // The app reloads the timeline on every save; refresh after midnight for the day count.
        var cal = Calendar.current
        cal.timeZone = TimeZone.current
        let tomorrow = cal.startOfDay(for: Date().addingTimeInterval(86_400)).addingTimeInterval(60)
        completion(Timeline(entries: [entry], policy: .after(tomorrow)))
    }
}

enum WPalette {
    static let background = Color(red: 13 / 255, green: 17 / 255, blue: 24 / 255)
    static let lime = Color(red: 198 / 255, green: 1, blue: 61 / 255)
    static let soft = Color(red: 201 / 255, green: 210 / 255, blue: 222 / 255)
    static let muted = Color(red: 135 / 255, green: 148 / 255, blue: 166 / 255)
    static let dim = Color(red: 111 / 255, green: 124 / 255, blue: 142 / 255)
    static let track = Color(red: 10 / 255, green: 13 / 255, blue: 18 / 255)
    static let edge = Color(red: 35 / 255, green: 44 / 255, blue: 59 / 255)
    static let red = Color(red: 1, green: 77 / 255, blue: 77 / 255)
    static let redText = Color(red: 1, green: 138 / 255, blue: 138 / 255)
    static let plates: [Color] = [
        Color(red: 242 / 255, green: 242 / 255, blue: 242 / 255),
        Color(red: 62 / 255, green: 207 / 255, blue: 106 / 255),
        Color(red: 245 / 255, green: 211 / 255, blue: 59 / 255),
        Color(red: 61 / 255, green: 139 / 255, blue: 1),
        Color(red: 1, green: 77 / 255, blue: 77 / 255)
    ]

    static func mood(_ m: String) -> Color {
        switch m {
        case "onfire": return redText
        case "pumped": return lime
        case "steady": return Color(red: 127 / 255, green: 178 / 255, blue: 1)
        case "tired": return Color(red: 245 / 255, green: 211 / 255, blue: 59 / 255)
        default: return Color(red: 180 / 255, green: 189 / 255, blue: 201 / 255)
        }
    }
}

struct WidgetMascot: View {
    var mood: String

    struct Sprites: Decodable {
        struct Sprite: Decodable {
            var palette: [String: String]
            var rows: [String]
            var rotateDegrees: Double?
        }
        var moods: [String: Sprite]
    }

    static func load() -> Sprites? {
        guard let url = Bundle.main.url(forResource: "mascot", withExtension: "json")
                ?? Bundle.main.url(forResource: "mascot", withExtension: "json", subdirectory: "Resources"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Sprites.self, from: data)
    }

    static func color(_ hex: String) -> Color {
        let v = UInt32(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0
        return Color(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }

    var body: some View {
        let sprite = Self.load()?.moods[mood]
        Canvas { ctx, size in
            guard let sprite else { return }
            let s = min(size.width, size.height) / 40
            if let deg = sprite.rotateDegrees, deg != 0 {
                ctx.translateBy(x: 20 * s, y: 38 * s)
                ctx.rotate(by: .degrees(deg))
                ctx.translateBy(x: -20 * s, y: -38 * s)
            }
            var colors: [Character: Color] = [:]
            for (k, v) in sprite.palette { if let c = k.first { colors[c] = Self.color(v) } }
            for (y, row) in sprite.rows.enumerated() {
                let chars = Array(row)
                var x = 0
                while x < chars.count {
                    let c = chars[x]
                    if c == "." { x += 1; continue }
                    var len = 1
                    while x + len < chars.count && chars[x + len] == c { len += 1 }
                    if let col = colors[c] {
                        ctx.fill(Path(CGRect(x: CGFloat(x) * s, y: CGFloat(y) * s, width: CGFloat(len) * s + 0.3, height: s + 0.3)),
                                 with: .color(col))
                    }
                    x += len
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

struct WidgetMeter: View {
    var score: Int

    var body: some View {
        Canvas { ctx, size in
            let h: CGFloat = 12, over: CGFloat = 3
            let track = CGRect(x: 0, y: over, width: size.width, height: h)
            ctx.fill(Path(track), with: .color(WPalette.track))
            ctx.stroke(Path(track.insetBy(dx: 1, dy: 1)), with: .color(WPalette.edge), lineWidth: 2)
            let inner = track.insetBy(dx: 2, dy: 2)
            let fillW = inner.width * CGFloat(max(0, min(120, score))) / 120
            let bandW = inner.width / 6
            for i in 0..<6 {
                let x0 = inner.minX + CGFloat(i) * bandW
                let x1 = min(inner.minX + fillW, x0 + bandW)
                if x1 <= x0 { break }
                ctx.fill(Path(CGRect(x: x0, y: inner.minY, width: x1 - x0, height: inner.height)), with: .color(WPalette.plates[min(i, 4)]))
            }
            var x = inner.minX + 4
            while x < inner.minX + fillW {
                ctx.fill(Path(CGRect(x: x, y: inner.minY, width: 1, height: inner.height)), with: .color(.black.opacity(0.35)))
                x += 5
            }
            ctx.fill(Path(CGRect(x: size.width * 100 / 120, y: 0, width: 2, height: h + 2 * over)), with: .color(.white))
        }
        .frame(height: 18)
    }
}

struct ChallengeWidgetEntryView: View {
    var entry: Provider.Entry

    private func label(_ t: String, _ c: Color) -> some View {
        Text(t).font(.custom("Silkscreen-Regular", fixedSize: 10)).tracking(1).foregroundStyle(c).lineLimit(1).minimumScaleFactor(0.7)
    }

    var body: some View {
        let s = entry.snapshot
        let accent = s.isBoss ? WPalette.redText : WPalette.lime
        HStack(spacing: 16) {
            VStack(spacing: 4) {
                WidgetMascot(mood: s.mood).frame(width: 96, height: 96)
                label(s.moodLabel, WPalette.mood(s.mood))
            }
            .frame(width: 104)
            VStack(alignment: .leading, spacing: 8) {
                label(s.title, WPalette.soft)
                HStack(alignment: .lastTextBaseline, spacing: 0) {
                    Text(s.best).font(.custom("VT323-Regular", fixedSize: 46)).foregroundStyle(accent)
                    Text(" / \(s.target)").font(.custom("VT323-Regular", fixedSize: 22)).foregroundStyle(WPalette.dim)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                WidgetMeter(score: s.score)
                HStack {
                    label(s.daysLeftLabel, WPalette.muted)
                    Spacer()
                    label("\(s.points) PTS", WPalette.soft)
                }
            }
        }
        .foregroundStyle(Color(red: 230 / 255, green: 237 / 255, blue: 243 / 255))
    }
}

struct ChallengeWidget: Widget {
    let kind: String = "ChallengeWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            ChallengeWidgetEntryView(entry: entry)
                .containerBackground(WPalette.background, for: .widget)
        }
        .configurationDisplayName("This month")
        .description("Your current challenge, score and mascot.")
        .supportedFamilies([.systemMedium])
    }
}

#Preview(as: .systemMedium) {
    ChallengeWidget()
} timeline: {
    SnapshotEntry(date: .now, snapshot: SnapshotStore.sample)
}
