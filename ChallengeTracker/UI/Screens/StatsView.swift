import Foundation
import SwiftUI
import UIKit

struct StatsView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        let e = store.engine
        let total = e.yearTotal
        let rows = e.all
        ScrollView {
            VStack(spacing: 12) {
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 2) {
                        Lbl("LOOKING BACK")
                        Text("STATS").font(.heading(22)).foregroundStyle(.white)
                    }
                    Spacer()
                    (Text("\(total)").font(.number(34)).foregroundColor(.white)
                     + Text("/1000").font(.number(18)).foregroundColor(Palette.muted))
                }
                barbellPanel(total)
                radarPanel(rows)
                monthBars(rows)
                startEndTable(rows)
            }
            .padding(.horizontal, 16)
            .padding(.top, 18)
            .padding(.bottom, 96)
        }
        .scrollIndicators(.hidden)
        .screen()
    }

    // MARK: Barbell

    private func barbellPanel(_ total: Int) -> some View {
        let layout = BarbellLayout(points: total)
        let nextTier = layout.partial?.tier ?? 4
        let tierColor = Palette.plates[nextTier]
        let toGo = layout.pointsToNextPlate
        let into = total % 100
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Lbl("THE BAR")
                Spacer()
                Lbl(String(format: "%.2f PLATES / SIDE", min(10, layout.platesPerSide)), color: .white)
            }
            BarbellView(points: total)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Lbl("NEXT PLATE")
                    Spacer()
                    if let toGo {
                        (Text("\(toGo)").foregroundColor(tierColor) + Text(" pts to go").foregroundColor(Palette.text))
                            .font(.number(22))
                    } else {
                        Text("Full bar").font(.number(22)).foregroundStyle(Palette.lime)
                    }
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Rectangle().fill(Palette.onLime).innerBorder(Palette.panelEdge)
                        Rectangle().fill(tierColor)
                            .frame(width: max(0, (geo.size.width - 4) * CGFloat(toGo == nil ? 100 : into) / 100))
                            .padding(2)
                    }
                }
                .frame(height: 10)
                Text(toGo == nil ? "Ten plates a side. Anything more is bonus."
                     : "The small plate is exact: \(into) of 100 toward plate \(layout.fullPlates + 1).")
                    .font(.vt(18)).foregroundStyle(Palette.muted)
            }
        }
        .padding(14)
        .panel()
    }

    // MARK: Radar

    private func radarPanel(_ rows: [ResolvedSlot]) -> some View {
        var best: [Domain: Int] = [:]
        for r in rows {
            guard let ch = r.challenge, let s = r.settledScore, !r.isForfeit else { continue }
            best[ch.domain] = max(best[ch.domain] ?? 0, s)
        }
        let order: [Domain] = [.strength, .speed, .endurance, .physique, .hybrid]
        let values = order.map { Double(best[$0] ?? 0) }
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Lbl("BY DOMAIN · BEST SCORE")
                Spacer()
                HStack(spacing: 4) {
                    DashedLine().stroke(Color.white, style: StrokeStyle(lineWidth: 2, dash: [2, 2])).frame(width: 10, height: 2)
                    Lbl("100")
                }
            }
            RadarChart(values: values, labels: order.map { $0.rawValue.uppercased() })
                .frame(maxWidth: 330)
                .aspectRatio(220.0 / 180.0, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .accessibilityElement()
                .accessibilityLabel("Radar: " + zip(order, values).map { "\($0.0.rawValue) \(Int($0.1))" }.joined(separator: ", "))
        }
        .padding(14)
        .panel()
    }

    // MARK: Month bars

    private func monthBars(_ rows: [ResolvedSlot]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Lbl("SCORE PER MONTH")
            ZStack(alignment: .top) {
                DashedLine().stroke(Color.white.opacity(0.6), style: StrokeStyle(lineWidth: 2, dash: [4, 3]))
                    .frame(height: 2)
                    .offset(y: 16)
                HStack(alignment: .bottom, spacing: 4) {
                    ForEach(rows, id: \.month) { r in bar(r) }
                }
                .frame(height: 96, alignment: .bottom)
            }
            .frame(height: 96)
            HStack(spacing: 4) {
                ForEach(rows, id: \.month) { r in
                    Text(barLabel(r).0)
                        .font(.number(17))
                        .foregroundStyle(barLabel(r).1)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .frame(maxWidth: .infinity)
                }
            }
            if rows.contains(where: { $0.isLocked && !$0.isFinal && !$0.isForfeit && $0.score != nil }) {
                Text("* live, not final").font(.vt(17)).foregroundStyle(Palette.muted)
            }
        }
        .padding(14)
        .panel()
    }

    @ViewBuilder
    private func bar(_ r: ResolvedSlot) -> some View {
        let h = CGFloat(r.score ?? 0) / 120 * 96
        if r.isFinal {
            Rectangle().fill(r.isRedo ? Palette.redo : Palette.lime).frame(height: max(2, h)).frame(maxWidth: .infinity)
        } else if r.isLocked && !r.isForfeit && r.score != nil {
            Rectangle().strokeBorder(Palette.lime, style: StrokeStyle(lineWidth: 2, dash: [4, 3]))
                .frame(height: max(4, h)).frame(maxWidth: .infinity)
        } else {
            Rectangle().fill(r.month == 12 || r.isForfeit ? Palette.alert : Palette.inputEdge)
                .frame(height: 2).frame(maxWidth: .infinity)
        }
    }

    private func barLabel(_ r: ResolvedSlot) -> (String, Color) {
        if r.isFinal, let s = r.score { return ("\(s)", s >= 120 ? Palette.lime : Palette.text) }
        if r.isLocked && !r.isForfeit, let s = r.score { return ("\(s)*", Palette.muted) }
        return (YearConfig.monthLetters[r.month - 1], Palette.muted)
    }

    // MARK: Start → end

    private func startEndTable(_ rows: [ResolvedSlot]) -> some View {
        let items = rows.filter { $0.challenge != nil && $0.isLocked && !$0.isForfeit && $0.baseline != nil }
        return VStack(alignment: .leading, spacing: 6) {
            Lbl("START → END")
            Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 0) {
                GridRow {
                    Lbl("CHALLENGE", size: 9)
                    Lbl("START", size: 9)
                    Lbl("END", size: 9)
                    Lbl("PTS", size: 9).gridColumnAlignment(.trailing)
                }
                .padding(.vertical, 4)
                ForEach(items, id: \.month) { r in
                    let ch = r.challenge!
                    let live = !r.isFinal
                    Rectangle().fill(Palette.divider).frame(height: 2).gridCellColumns(4)
                    GridRow {
                        Text((r.isRedo ? "↻ " : "") + ch.name).lineLimit(1).minimumScaleFactor(0.7)
                        Text(r.baseline.map { ValueFormat.formatWithUnit($0, ch) } ?? "—").foregroundStyle(Palette.muted)
                        Text((r.result.map { ValueFormat.formatWithUnit($0, ch) } ?? "—") + (live && r.result != nil ? "*" : ""))
                        Text("\(r.score ?? 0)\(live ? "*" : "")")
                            .foregroundStyle(live ? Palette.muted : ((r.score ?? 0) >= 120 ? Palette.lime : Palette.text))
                            .gridColumnAlignment(.trailing)
                    }
                    .font(.number(20))
                    .padding(.vertical, 6)
                }
            }
            if items.isEmpty {
                Text("Nothing locked yet.").font(.vt(18)).foregroundStyle(Palette.dim)
            }
        }
        .padding(14)
        .panel()
    }
}

struct DashedLine: Shape {
    nonisolated func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.midY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.midY))
        return p
    }
}

/// Pentagon radar on the artboard's 220 × 180 canvas: outer ring 120, dashed ring at 100.
struct RadarChart: View {
    var values: [Double]   // 0...120, five domains
    var labels: [String]

    var body: some View {
        Canvas { ctx, size in
            let s = size.width / 220
            let c = CGPoint(x: 110 * s, y: 96 * s)
            let R = 70 * s
            func pt(_ i: Int, _ v: Double) -> CGPoint {
                let a = -Double.pi / 2 + Double(i) * 2 * Double.pi / 5
                let r = R * CGFloat(v / 120)
                return CGPoint(x: c.x + r * CGFloat(cos(a)), y: c.y + r * CGFloat(sin(a)))
            }
            func ring(_ v: Double) -> Path {
                var p = Path()
                for i in 0..<5 {
                    if i == 0 { p.move(to: pt(i, v)) } else { p.addLine(to: pt(i, v)) }
                }
                p.closeSubpath()
                return p
            }
            ctx.stroke(ring(40), with: .color(Palette.divider), lineWidth: 1)
            ctx.stroke(ring(80), with: .color(Palette.divider), lineWidth: 1)
            ctx.stroke(ring(120), with: .color(Palette.inputEdge), lineWidth: 1.5)
            for i in 0..<5 {
                var p = Path()
                p.move(to: c)
                p.addLine(to: pt(i, 120))
                ctx.stroke(p, with: .color(Palette.divider), lineWidth: 1)
            }
            ctx.stroke(ring(100), with: .color(Color.white.opacity(0.7)), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))

            var data = Path()
            for i in 0..<5 {
                let v = i < values.count ? values[i] : 0
                if i == 0 { data.move(to: pt(i, max(v, 2))) } else { data.addLine(to: pt(i, max(v, 2))) }
            }
            data.closeSubpath()
            ctx.fill(data, with: .color(Palette.lime.opacity(0.22)))
            ctx.stroke(data, with: .color(Palette.lime), style: StrokeStyle(lineWidth: 2, lineJoin: .miter))
            for i in 0..<5 where i < values.count && values[i] > 0 {
                let p = pt(i, values[i])
                ctx.fill(Path(CGRect(x: p.x - 3 * s, y: p.y - 3 * s, width: 6 * s, height: 6 * s)), with: .color(Palette.lime))
            }

            let positions: [CGPoint] = [CGPoint(x: 110, y: 10), CGPoint(x: 190, y: 62), CGPoint(x: 160, y: 168),
                                        CGPoint(x: 60, y: 168), CGPoint(x: 28, y: 64)]
            for i in 0..<min(5, labels.count) {
                let v = i < values.count ? Int(values[i]) : 0
                let text = v > 0 ? "\(labels[i]) \(v)" : labels[i]
                let t = Text(text).font(.label(8 * s)).foregroundColor(Palette.soft)
                ctx.draw(t, at: CGPoint(x: positions[i].x * s, y: positions[i].y * s), anchor: .center)
            }
        }
    }
}
