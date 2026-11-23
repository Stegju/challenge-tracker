import Foundation
import SwiftUI

/// Barbell with exact partial plate, drawn on the artboard's 440 × 160 canvas and scaled.
struct BarbellView: View {
    var points: Int

    var body: some View {
        let layout = BarbellLayout(points: points)
        Canvas { ctx, size in
            let s = size.width / 440
            func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
                CGRect(x: x * s, y: y * s, width: w * s, height: h * s)
            }
            func fill(_ r: CGRect, _ c: Color) { ctx.fill(Path(r), with: .color(c)) }

            // Bar: collars, sleeves, knurled centre.
            fill(rect(4, 72, 6, 16), Color(hex: 0x8B97A8))
            fill(rect(10, 74, 130, 12), Color(hex: 0xB8C2D0))
            fill(rect(10, 74, 130, 2), Color(hex: 0xE3E8EF))
            fill(rect(10, 84, 130, 2), Color(hex: 0x7E8A9B))
            fill(rect(140, 69, 10, 22), Color(hex: 0xC9D2DE))
            fill(rect(140, 88, 10, 3), Color(hex: 0x7E8A9B))
            var kx: CGFloat = 150
            var dark = false
            while kx < 290 {
                fill(rect(kx, 77, 2, 6), dark ? Color(hex: 0x6B7686) : Color(hex: 0xA3AEBD))
                kx += 2
                dark.toggle()
            }
            fill(rect(290, 69, 10, 22), Color(hex: 0xC9D2DE))
            fill(rect(290, 88, 10, 3), Color(hex: 0x7E8A9B))
            fill(rect(300, 74, 130, 12), Color(hex: 0xB8C2D0))
            fill(rect(300, 74, 130, 2), Color(hex: 0xE3E8EF))
            fill(rect(300, 84, 130, 2), Color(hex: 0x7E8A9B))
            fill(rect(430, 72, 6, 16), Color(hex: 0x8B97A8))

            func plate(x: CGFloat, w: CGFloat, top: CGFloat, h: CGFloat, color: Color, hub: Bool) {
                fill(rect(x, top, w, h), color)
                fill(rect(x, top, 2, h), Color.white.opacity(0.35))
                fill(rect(x + w - 2, top, 2, h), Color.black.opacity(0.35))
                if hub { fill(rect(x, 72, w, 16), Color.black.opacity(0.22)) }
            }
            func ghost(x: CGFloat, w: CGFloat, color: Color) {
                let r = rect(x, 20, w, 120).insetBy(dx: s, dy: s)
                ctx.stroke(Path(r), with: .color(color.opacity(0.3)),
                           style: StrokeStyle(lineWidth: 2 * s, dash: [4 * s, 3 * s]))
            }

            // Left side: plates grow leftward from the collar at x = 138 (row-reverse, gap 2).
            var left: CGFloat = 138
            var right: CGFloat = 302
            for p in layout.plates {
                let w = CGFloat(p.thickness)
                let color = Palette.plates[p.tier]
                plate(x: left - w, w: w, top: 20, h: 120, color: color, hub: true)
                plate(x: right, w: w, top: 20, h: 120, color: color, hub: true)
                left -= w + 2
                right += w + 2
            }
            if let g = layout.partial {
                let w = CGFloat(g.thickness)
                let color = Palette.plates[g.tier]
                ghost(x: left - w, w: w, color: color)
                ghost(x: right, w: w, color: color)
                if g.height > 0 {
                    let top = 20 + CGFloat(g.top)
                    plate(x: left - w, w: w, top: top, h: CGFloat(g.height), color: color, hub: false)
                    plate(x: right, w: w, top: top, h: CGFloat(g.height), color: color, hub: false)
                }
            }
        }
        .aspectRatio(440.0 / 160.0, contentMode: .fit)
        .accessibilityElement()
        .accessibilityLabel(String(format: "%.2f plates per side: %d full and a partial plate for the last %d points",
                                   layout.platesPerSide, layout.fullPlates, points % 100))
    }
}
