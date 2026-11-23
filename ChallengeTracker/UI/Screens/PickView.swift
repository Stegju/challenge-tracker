import Foundation
import SwiftUI
import UIKit

struct PickView: View {
    var month: Int
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(\.dismiss) private var dismiss
    @State private var tab: SlotKind = .new
    @State private var selected: String?

    var body: some View {
        let e = store.engine
        let newOpts = e.newOptions(for: month)
        let redoOpts = e.redoOptions(for: month)
        let redoLeft = e.redoLeft(excluding: month)
        let canPick = e.canPick(month)
        let items = tab == .new ? newOpts : redoOpts
        let picked = items.first { $0.id == selected }
        let monthName = YearConfig.name(month)
        var cta = "PICK ONE"
        if let p = picked {
            let prefix = p.sourceMonth != nil ? "REDO " : ""
            cta = "SET " + prefix + p.challenge.name.uppercased() + " FOR " + monthName
        }
        return ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 12) {
                        BackButton { dismiss() }
                        VStack(alignment: .leading, spacing: 4) {
                            Lbl("LOCKS \(Fmt.lockLabel(store.rules.lockDate(month), store.calendar)) 00:00")
                            Text("CHOOSE \(monthName)").font(.heading(20)).foregroundStyle(.white)
                        }
                    }
                    if !canPick {
                        Text("\(monthName.capitalized) is locked. Choices can't change after midnight on the 1st.")
                            .font(.vt(19)).foregroundStyle(Palette.alertText)
                    }
                    HStack(spacing: 4) {
                        tabButton("NEW · \(newOpts.count) LEFT", kind: .new, on: Palette.lime)
                        tabButton("REDO · \(redoLeft) LEFT", kind: .redo, on: Palette.redo)
                    }
                    .padding(4)
                    .panel()
                    if let msg = e.remainingPicksMessage() {
                        Text(msg).font(.vt(19)).foregroundStyle(Palette.plateYellow)
                    }
                    if tab == .redo {
                        Text(month == 1 ? "January can't be a redo."
                             : (redoLeft == 0 ? "Both redos are used."
                                : "Same baseline and target as last time. The better attempt counts."))
                            .font(.vt(19)).foregroundStyle(Palette.muted)
                        if redoOpts.isEmpty && month != 1 && redoLeft > 0 {
                            Text("Finish a challenge first. Finished months show up here.")
                                .font(.vt(19)).foregroundStyle(Palette.dim)
                        }
                    }
                    VStack(spacing: 4) {
                        ForEach(items) { opt in
                            optionRow(opt, isRedo: tab == .redo,
                                      disabled: opt.disabled || !canPick || (tab == .redo && redoLeft == 0))
                        }
                    }
                    if canPick, store.state.slot(month).isChosen {
                        Button("CLEAR \(monthName)") {
                            store.clearChoice(month: month)
                            selected = nil
                        }
                        .buttonStyle(SecondaryButtonStyle(edge: Palette.alert, textColor: Palette.alertText, height: 44))
                        .padding(.top, 6)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 18)
                .padding(.bottom, 100)
            }
            .scrollIndicators(.hidden)

            Button(cta) {
                guard let p = picked else { return }
                let ok: Bool
                if let src = p.sourceMonth {
                    ok = store.chooseRedo(month: month, sourceMonth: src)
                } else {
                    ok = store.chooseNew(month: month, challenge: p.challenge)
                }
                if ok { router.replaceTop(with: .challenge(month)) }
            }
            .buttonStyle(PrimaryButtonStyle(height: 54))
            .disabled(picked == nil || !canPick)
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
        .screen()
        .onAppear {
            if selected == nil, let id = store.state.slot(month).challengeId, store.state.slot(month).kind == .new {
                selected = id
            }
        }
    }

    private func tabButton(_ title: String, kind: SlotKind, on: Color) -> some View {
        let isOn = tab == kind
        return Button(title) {
            tab = kind
            selected = nil
        }
        .font(.heading(11))
        .tracking(1)
        .foregroundStyle(isOn ? Palette.onLime : Palette.muted)
        .frame(maxWidth: .infinity, minHeight: 44)
        .notched(fill: isOn ? on : Color.clear)
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private func optionRow(_ opt: PickOption, isRedo: Bool, disabled: Bool) -> some View {
        let on = selected == opt.id
        let bg: Color = on ? Palette.lime.opacity(0.1) : (disabled ? Color(hex: 0x0A0D12, opacity: 0.7) : Palette.panel)
        let edge: Color = on ? Palette.lime : Palette.panelEdge
        let fg: Color = disabled ? Palette.veryDim : Palette.text
        let sub: Color = disabled ? Palette.veryDim : (on ? Palette.lime : Palette.muted)
        let rightColor: Color = disabled ? Palette.veryDim : (on ? Palette.lime : (isRedo ? Palette.redo : Palette.veryDim))
        return Button {
            selected = on ? nil : opt.id
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(opt.challenge.name).font(.vt(22)).foregroundStyle(fg)
                    Text(opt.subtitle).font(.label(9)).tracking(1).foregroundStyle(sub)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                if isRedo {
                    Text("\(opt.sourceScore ?? 0)").font(.number(26)).foregroundStyle(rightColor)
                } else if on {
                    Lbl("PICKED", color: rightColor)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(minHeight: 54)
            .notched(fill: bg, edge: edge)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}
