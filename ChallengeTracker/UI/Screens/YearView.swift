import Foundation
import SwiftUI
import UIKit

struct YearView: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router

    var body: some View {
        let e = store.engine
        let rows = e.all
        let nextOpen = (1...12).first { m in !rows[m - 1].isChosen && e.canPick(m) }
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        Lbl("\(e.finishedCount) OF 12 DONE")
                        Text("YEAR 2027").font(.heading(22)).foregroundStyle(.white)
                    }
                    Spacer()
                    (Text("\(e.yearTotal)").font(.number(36)).foregroundColor(.white)
                     + Text(" pts").font(.number(18)).foregroundColor(Palette.dim))
                }
                if let msg = e.remainingPicksMessage() {
                    Text(msg).font(.vt(19)).foregroundStyle(Palette.plateYellow)
                }
                VStack(spacing: 4) {
                    ForEach(rows, id: \.month) { r in
                        row(r, isNext: r.month == nextOpen, engine: e)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 18)
            .padding(.bottom, 96)
        }
        .scrollIndicators(.hidden)
        .screen()
    }

    private func row(_ r: ResolvedSlot, isNext: Bool, engine: YearEngine) -> some View {
        var bg = Palette.panel
        var edge = Palette.panelEdge
        var monthColor = Palette.muted
        var nameColor = Palette.text
        var name = r.challenge?.name ?? "Not chosen"
        enum Right { case score(Int, Color), chip(String, Color, Color), empty }
        var right = Right.empty
        let current = store.currentMonth == r.month

        if r.isRedo, let ch = r.challenge { name = "Redo · \(ch.name)" }

        if r.isForfeit && r.isLocked {
            name = r.challenge?.name ?? "Nothing chosen"
            nameColor = Palette.muted
            right = .chip("FORFEIT · 0", Palette.onLime, Palette.alert)
        } else if r.isFinal {
            let s = r.score ?? 0
            right = .score(s, s >= 120 ? Palette.lime : (r.isRedo ? Palette.redo : .white))
        } else if r.isLocked {
            if current { edge = Palette.lime; monthColor = Palette.lime }
            right = .score(r.score ?? 0, Palette.dim)
        } else if r.isBoss {
            bg = Palette.alert.opacity(0.08); edge = Palette.alert; monthColor = Palette.alertText; nameColor = Palette.bossName
            right = .chip("BOSS", Palette.alertText, .clear)
        } else if r.isChosen {
            right = r.target == nil ? .chip("NO TARGET", Palette.onLime, Palette.plateYellow) : .chip("SET", Palette.soft, .clear)
            if r.isRedo { monthColor = Palette.redo }
        } else if isNext {
            name = "Next up"; nameColor = Palette.soft; monthColor = Palette.soft
            right = .chip("CHOOSE", Palette.onLime, Palette.lime)
        } else {
            bg = Color(hex: 0x0A0D12, opacity: 0.7); nameColor = Palette.veryDim; monthColor = Palette.veryDim
            right = .chip("OPEN", Palette.veryDim, .clear)
        }
        if r.month == 12 && !r.isFinal { edge = Palette.alert; monthColor = Palette.alertText; bg = Palette.alert.opacity(0.08) }

        return Button {
            if r.isChosen || r.isLocked { router.push(.challenge(r.month)) } else { router.push(.pick(r.month)) }
        } label: {
            HStack(spacing: 10) {
                Text(YearConfig.short(r.month))
                    .font(.heading(12))
                    .foregroundStyle(monthColor)
                    .frame(width: 44, alignment: .leading)
                Text(name)
                    .font(.vt(22))
                    .foregroundStyle(nameColor)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 4)
                switch right {
                case .score(let s, let c):
                    Text("\(s)").font(.number(26)).foregroundStyle(c)
                case .chip(let t, let fg, let bgc):
                    Text(t).font(.label(10)).tracking(1).foregroundStyle(fg)
                        .padding(.horizontal, 8).padding(.vertical, 5)
                        .background(bgc)
                case .empty:
                    EmptyView()
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 48)
            .notched(fill: bg, edge: edge)
        }
        .buttonStyle(.plain)
    }
}
