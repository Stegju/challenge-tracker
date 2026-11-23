import Foundation
import SwiftUI

/// Sprites from Resources/mascot.json: 40 × 40 grids with a palette per mood.
struct MascotSprites: Decodable {
    struct Sprite: Decodable {
        var palette: [String: String]
        var rows: [String]
        var rotateDegrees: Double?
        var rotateAnchor: [Double]?
    }
    var moods: [String: Sprite]

    /// Pre-merged horizontal runs per mood for fast drawing.
    struct Run {
        var x: Int
        var y: Int
        var length: Int
        var color: Color
    }

    static let shared: MascotSprites? = {
        guard let url = ResourceLocator.url(named: "mascot", ext: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(MascotSprites.self, from: data)
    }()

    static let runs: [String: [Run]] = {
        guard let s = shared else { return [:] }
        var out: [String: [Run]] = [:]
        for (mood, sprite) in s.moods {
            var colors: [Character: Color] = [:]
            for (k, v) in sprite.palette {
                if let ch = k.first { colors[ch] = Color(hexString: v) }
            }
            var runs: [Run] = []
            for (y, row) in sprite.rows.enumerated() {
                let chars = Array(row)
                var x = 0
                while x < chars.count {
                    let c = chars[x]
                    if c == "." { x += 1; continue }
                    var len = 1
                    while x + len < chars.count && chars[x + len] == c { len += 1 }
                    if let color = colors[c] { runs.append(Run(x: x, y: y, length: len, color: color)) }
                    x += len
                }
            }
            out[mood] = runs
        }
        return out
    }()
}

/// Static pixel render of one mood, crisp edges.
struct MascotSprite: View {
    var mood: Mood

    var body: some View {
        Canvas { ctx, size in
            let s = min(size.width, size.height) / 40
            let sprite = MascotSprites.shared?.moods[mood.rawValue]
            if let deg = sprite?.rotateDegrees, deg != 0 {
                let a = sprite?.rotateAnchor ?? [20, 38]
                let ax = CGFloat(a.first ?? 20) * s, ay = CGFloat(a.count > 1 ? a[1] : 38) * s
                ctx.translateBy(x: ax, y: ay)
                ctx.rotate(by: .degrees(deg))
                ctx.translateBy(x: -ax, y: -ay)
            }
            // Small overlap hides hairline seams between cells.
            let o: CGFloat = 0.3
            for r in MascotSprites.runs[mood.rawValue] ?? [] {
                let rect = CGRect(x: CGFloat(r.x) * s, y: CGFloat(r.y) * s,
                                  width: CGFloat(r.length) * s + o, height: s + o)
                ctx.fill(Path(rect), with: .color(r.color))
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

/// Mascot with its idle motion: hop (pumped, on fire), bob (steady, tired), sway (slumped).
/// All motion stops under Reduce Motion.
struct MascotView: View {
    var mood: Mood
    var size: CGFloat
    var animated = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if animated && !reduceMotion {
                TimelineView(.periodic(from: .now, by: 0.1)) { tl in
                    let t = tl.date.timeIntervalSinceReferenceDate
                    let m = Self.motion(mood, t: t)
                    MascotSprite(mood: mood)
                        .rotationEffect(.degrees(m.rotation), anchor: .bottom)
                        .offset(y: m.dy)
                }
            } else {
                MascotSprite(mood: mood)
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement()
        .accessibilityLabel("Mascot, \(mood.label.lowercased())")
    }

    /// Stepped keyframes like the CSS (steps(n)).
    static func motion(_ mood: Mood, t: Double) -> (dy: CGFloat, rotation: Double) {
        func stepped(period: Double, steps: Int) -> Double {
            let p = t.truncatingRemainder(dividingBy: period) / period
            let tri = p < 0.5 ? p * 2 : (1 - p) * 2     // 0 → 1 → 0
            return (tri * Double(steps)).rounded(.down) / Double(steps)
        }
        switch mood {
        case .onfire, .pumped: return (-8 * stepped(period: 1.2, steps: 2), 0)
        case .steady, .tired: return (-3 * stepped(period: 2.8, steps: 1), 0)
        case .slumped: return (0, -3 * stepped(period: 4, steps: 1))
        }
    }
}
