import Foundation
import SwiftUI

/// Background behind every screen: ceiling lights, perspective floor grid,
/// plate trees, drifting chalk dust. Scanlines go on top via `ScanlineOverlay`.
struct Atmosphere: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                Palette.background
                // Ceiling lights
                let spacing = geo.size.width / 390
                ForEach(0..<3, id: \.self) { i in
                    Rectangle()
                        .fill(Color(hex: 0xD7ECFF))
                        .frame(width: 92 * spacing, height: 3)
                        .opacity(0.4)
                        .shadow(color: Color(.sRGB, red: 140 / 255, green: 190 / 255, blue: 1, opacity: 0.3), radius: 12)
                        .offset(x: (36 + CGFloat(i) * 113) * spacing, y: 0)
                }
                FloorGrid()
                    .frame(height: 300)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .opacity(0.6)
                PlateTree()
                    .frame(width: 36, height: 72)
                    .opacity(0.18)
                    .position(x: 2 + 18, y: geo.size.height - 100 - 36)
                PlateTree()
                    .frame(width: 36, height: 72)
                    .scaleEffect(x: -1, y: 1)
                    .opacity(0.18)
                    .position(x: geo.size.width - 2 - 18, y: geo.size.height - 100 - 36)
                if !reduceMotion {
                    ChalkDust(size: geo.size)
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Rubber floor grid in perspective: 2 pt lines #18202D, 40 pt cells.
struct FloorGrid: View {
    var body: some View {
        Canvas { ctx, size in
            let color = GraphicsContext.Shading.color(Color(hex: 0x18202D))
            let w = size.width, h = size.height
            let vanishY = -h * 0.9
            let cx = w / 2
            // Vertical lines converge towards a vanishing point above the top edge.
            let cell: CGFloat = 40
            var i: CGFloat = -12
            while i <= 12 {
                let xBottom = cx + i * cell * 1.6
                var p = Path()
                p.move(to: CGPoint(x: xBottom, y: h))
                let t = (0 - h) / (vanishY - h)
                p.addLine(to: CGPoint(x: xBottom + (cx - xBottom) * t, y: 0))
                ctx.stroke(p, with: color, lineWidth: 2)
                i += 1
            }
            // Horizontal lines get closer together towards the top.
            var y = h
            var gap: CGFloat = 46
            while y > 0 {
                ctx.fill(Path(CGRect(x: 0, y: y - 2, width: w, height: 2)), with: color)
                y -= gap
                gap *= 0.72
                if gap < 3 { break }
            }
        }
    }
}

/// Plate tree pixel art (16 × 32 grid) from the artboards.
struct PlateTree: View {
    private static let layers: [(String, Color)] = [
        ("M7 3h2v26h-2zM2 29h12v2h-12z", Color(hex: 0x2A3344)),
        ("M3 6h3v9h-3z", Palette.plateBlue),
        ("M10 8h3v7h-3z", Palette.plateGreen),
        ("M3 17h3v8h-3z", Palette.plateYellow),
        ("M10 16h3v10h-3z", Palette.plateRed),
        ("M6 10h1v1h-1zM9 11h1v1h-1zM6 21h1v1h-1zM9 21h1v1h-1z", Color(hex: 0x4A5568))
    ]

    var body: some View {
        Canvas { ctx, size in
            let s = min(size.width / 16, size.height / 32)
            for (d, c) in Self.layers {
                for r in PixelPathShape.parse(d) {
                    ctx.fill(Path(CGRect(x: r.minX * s, y: r.minY * s, width: r.width * s, height: r.height * s)), with: .color(c))
                }
            }
        }
    }
}

/// A few chalk specks drifting up (10 s loop, staggered).
struct ChalkDust: View {
    var size: CGSize
    private let specks: [(CGFloat, CGFloat, Double)] = [(60, 640, 0), (220, 700, 3.5), (320, 600, 6.5), (140, 540, 8)]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { tl in
            Canvas { ctx, sz in
                let t = tl.date.timeIntervalSinceReferenceDate
                let sx = sz.width / 390, sy = sz.height / 844
                for (x, y, delay) in specks {
                    let phase = ((t - delay).truncatingRemainder(dividingBy: 10) + 10).truncatingRemainder(dividingBy: 10) / 10
                    let opacity = phase < 0.2 ? phase / 0.2 * 0.45 : 0.45 * (1 - (phase - 0.2) / 0.8)
                    let px = x * sx + 16 * phase
                    let py = y * sy - 140 * phase
                    ctx.fill(Path(CGRect(x: px, y: py, width: 3, height: 3)), with: .color(Color(hex: 0xE8EDF3).opacity(opacity)))
                }
            }
        }
    }
}

/// Faint scanlines over everything: 1 pt dark line every 3 pt at 10%.
struct ScanlineOverlay: View {
    var body: some View {
        Canvas { ctx, size in
            var y: CGFloat = 0
            var p = Path()
            while y < size.height {
                p.addRect(CGRect(x: 0, y: y, width: size.width, height: 1))
                y += 3
            }
            ctx.fill(p, with: .color(.black.opacity(0.1)))
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Flickering neon "2027" sign (flickers every ~7 s; static under Reduce Motion).
struct NeonSign: View {
    var text = "2027"
    var fontSize: CGFloat = 20
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if reduceMotion {
            sign(opacity: 1)
        } else {
            TimelineView(.periodic(from: .now, by: 0.07)) { tl in
                let p = tl.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 7) / 7
                sign(opacity: Self.flicker(p))
            }
        }
    }

    static func flicker(_ p: Double) -> Double {
        switch p {
        case 0.91..<0.92: return 0.3
        case 0.94..<0.95: return 0.55
        default: return 1
        }
    }

    private func sign(opacity: Double) -> some View {
        Text(text)
            .font(.heading(fontSize))
            .foregroundStyle(Palette.limeSoft)
            .shadow(color: Palette.lime, radius: 2)
            .shadow(color: Palette.lime.opacity(0.8), radius: 7)
            .padding(.vertical, 4)
            .padding(.horizontal, 12)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Palette.lime, lineWidth: 2)
                    .shadow(color: Palette.lime.opacity(0.4), radius: 5)
            )
            .opacity(opacity)
            .accessibilityLabel(text)
    }
}
