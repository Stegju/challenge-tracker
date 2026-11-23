import Foundation
import SwiftUI

/// Score meter: 0 to 120, plate-colour bands every 20 points (red from 80 up),
/// dark 1 pt dividers every 6 pt, white tick at 100.
struct ScoreMeter: View {
    var score: Double
    var height: CGFloat = 16
    var dividerEvery: CGFloat = 6
    var tickOverhang: CGFloat = 4

    var body: some View {
        Canvas { ctx, size in
            let w = size.width
            let h = height
            let top = tickOverhang
            let track = CGRect(x: 0, y: top, width: w, height: h)
            ctx.fill(Path(track), with: .color(Palette.input))
            ctx.stroke(Path(track.insetBy(dx: 1, dy: 1)), with: .color(Palette.panelEdge), lineWidth: 2)

            let inner = track.insetBy(dx: 2, dy: 2)
            let frac = max(0, min(1, score / 120))
            let fillW = inner.width * frac
            if fillW > 0 {
                let bandW = inner.width / 6
                for i in 0..<6 {
                    let x0 = inner.minX + CGFloat(i) * bandW
                    let x1 = min(inner.minX + fillW, x0 + bandW)
                    guard x1 > x0 else { break }
                    let color = Palette.plates[min(i, 4)]
                    ctx.fill(Path(CGRect(x: x0, y: inner.minY, width: x1 - x0, height: inner.height)), with: .color(color))
                }
                var x = inner.minX + dividerEvery - 1
                while x < inner.minX + fillW {
                    ctx.fill(Path(CGRect(x: x, y: inner.minY, width: 1, height: inner.height)), with: .color(.black.opacity(0.35)))
                    x += dividerEvery
                }
            }
            let tickX = w * (100.0 / 120.0)
            ctx.fill(Path(CGRect(x: tickX, y: 0, width: 2, height: h + 2 * tickOverhang)), with: .color(.white))
        }
        .frame(height: height + 2 * tickOverhang)
        .accessibilityElement()
        .accessibilityLabel("Score \(Int(score.rounded())), target 100, bonus to 120")
    }
}
