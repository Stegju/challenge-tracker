import Foundation
import SwiftUI
import UIKit
import CoreText

extension Color {
    /// 0xRRGGBB
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }

    /// "#RRGGBB"
    init(hexString: String) {
        let s = hexString.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        self.init(hex: UInt32(s, radix: 16) ?? 0)
    }
}

/// Design tokens from docs/design/README.md.
enum Palette {
    static let background = Color(hex: 0x0D1118)
    static let deepBackground = Color(hex: 0x07090D)
    static let panel = Color(.sRGB, red: 18 / 255, green: 24 / 255, blue: 34 / 255, opacity: 0.92)
    static let panelEdge = Color(hex: 0x232C3B)
    static let input = Color(hex: 0x0A0D12)
    static let inputEdge = Color(hex: 0x2C3749)
    static let edge2 = Color(hex: 0x3A4659)
    static let divider = Color(hex: 0x1F2838)

    static let text = Color(hex: 0xE6EDF3)
    static let strong = Color.white
    static let soft = Color(hex: 0xC9D2DE)
    static let muted = Color(hex: 0x8794A6)
    static let dim = Color(hex: 0x6F7C8E)
    static let veryDim = Color(hex: 0x4D5869)

    static let lime = Color(hex: 0xC6FF3D)
    static let onLime = Color(hex: 0x0B0E13)
    static let limeSoft = Color(hex: 0xE9FFB0)

    static let plateWhite = Color(hex: 0xF2F2F2)
    static let plateGreen = Color(hex: 0x3ECF6A)
    static let plateYellow = Color(hex: 0xF5D33B)
    static let plateBlue = Color(hex: 0x3D8BFF)
    static let plateRed = Color(hex: 0xFF4D4D)
    static let plates = [plateWhite, plateGreen, plateYellow, plateBlue, plateRed]

    static let alert = Color(hex: 0xFF4D4D)
    static let alertText = Color(hex: 0xFF8A8A)
    static let bossName = Color(hex: 0xFFB3B3)
    static let redo = Color(hex: 0xF5D33B)
    static let info = Color(hex: 0x3D8BFF)
    static let infoText = Color(hex: 0x7FB2FF)
    static let testEdge = Color(hex: 0x5C5220)

    static func moodText(_ m: Mood) -> Color {
        switch m {
        case .onfire: return alertText
        case .pumped: return lime
        case .steady: return infoText
        case .tired: return plateYellow
        case .slumped: return Color(hex: 0xB4BDC9)
        }
    }

    static func moodEdge(_ m: Mood) -> Color {
        switch m {
        case .onfire: return plateRed
        case .pumped: return lime
        case .steady: return plateBlue
        case .tired: return plateYellow
        case .slumped: return Color(hex: 0x7B8594)
        }
    }
}

// MARK: - Fonts

enum PixelFont {
    static let silkscreen = "Silkscreen-Regular"
    static let silkscreenBold = "Silkscreen-Bold"
    static let vt323 = "VT323-Regular"

    /// Registers the bundled fonts in case Info.plist registration is missing. Safe to call twice.
    static func registerIfNeeded() {
        for name in ["Silkscreen-Regular", "Silkscreen-Bold", "VT323-Regular"] {
            let url = Bundle.main.url(forResource: name, withExtension: "ttf")
                ?? Bundle.main.url(forResource: name, withExtension: "ttf", subdirectory: "Fonts")
                ?? Bundle.main.url(forResource: name, withExtension: "ttf", subdirectory: "Resources/Fonts")
            if let url {
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            }
        }
    }
}

extension Font {
    /// Silkscreen label, fixed size (labels are tiny and layout-critical).
    static func label(_ size: CGFloat = 10) -> Font { .custom(PixelFont.silkscreen, fixedSize: size) }
    static func heading(_ size: CGFloat = 18) -> Font { .custom(PixelFont.silkscreenBold, fixedSize: size) }
    /// VT323 body text, scales with Dynamic Type.
    static func vt(_ size: CGFloat = 20) -> Font { .custom(PixelFont.vt323, size: size, relativeTo: .body) }
    /// VT323 numbers, fixed size.
    static func number(_ size: CGFloat) -> Font { .custom(PixelFont.vt323, fixedSize: size) }
}

/// Small uppercase Silkscreen label with 1 pt letter spacing.
struct Lbl: View {
    var text: String
    var color: Color = Palette.muted
    var size: CGFloat = 10

    init(_ text: String, color: Color = Palette.muted, size: CGFloat = 10) {
        self.text = text
        self.color = color
        self.size = size
    }

    var body: some View {
        Text(text)
            .font(.label(size))
            .tracking(1)
            .foregroundStyle(color)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }
}

// MARK: - Shapes

/// Stepped pixel corners: a 2 × 2 pt step cut at 6 pt from each corner (the `.nt` clip-path).
struct NotchedRect: Shape {
    var notch: CGFloat = 6
    var step: CGFloat = 2

    nonisolated func path(in r: CGRect) -> Path {
        let n = min(notch, r.width / 2, r.height / 2)
        let s = min(step, n)
        var p = Path()
        let x0 = r.minX, y0 = r.minY, x1 = r.maxX, y1 = r.maxY
        p.move(to: CGPoint(x: x0, y: y0 + n))
        p.addLine(to: CGPoint(x: x0 + s, y: y0 + n))
        p.addLine(to: CGPoint(x: x0 + s, y: y0 + s))
        p.addLine(to: CGPoint(x: x0 + n, y: y0 + s))
        p.addLine(to: CGPoint(x: x0 + n, y: y0))
        p.addLine(to: CGPoint(x: x1 - n, y: y0))
        p.addLine(to: CGPoint(x: x1 - n, y: y0 + s))
        p.addLine(to: CGPoint(x: x1 - s, y: y0 + s))
        p.addLine(to: CGPoint(x: x1 - s, y: y0 + n))
        p.addLine(to: CGPoint(x: x1, y: y0 + n))
        p.addLine(to: CGPoint(x: x1, y: y1 - n))
        p.addLine(to: CGPoint(x: x1 - s, y: y1 - n))
        p.addLine(to: CGPoint(x: x1 - s, y: y1 - s))
        p.addLine(to: CGPoint(x: x1 - n, y: y1 - s))
        p.addLine(to: CGPoint(x: x1 - n, y: y1))
        p.addLine(to: CGPoint(x: x0 + n, y: y1))
        p.addLine(to: CGPoint(x: x0 + n, y: y1 - s))
        p.addLine(to: CGPoint(x: x0 + s, y: y1 - s))
        p.addLine(to: CGPoint(x: x0 + s, y: y1 - n))
        p.addLine(to: CGPoint(x: x0, y: y1 - n))
        p.closeSubpath()
        return p
    }
}

extension View {
    /// Notched background with a 2 pt inner border.
    func notched(fill: Color, edge: Color? = nil, lineWidth: CGFloat = 2) -> some View {
        self
            .background(NotchedRect().fill(fill))
            .overlay {
                if let edge {
                    NotchedRect().stroke(edge, lineWidth: lineWidth * 2).clipShape(NotchedRect())
                        .allowsHitTesting(false)
                }
            }
            .clipShape(NotchedRect())
    }

    /// Standard panel: rgba(18,24,34,0.92) with a 2 pt #232C3B inner border.
    func panel(edge: Color = Palette.panelEdge, fill: Color = Palette.panel) -> some View {
        notched(fill: fill, edge: edge)
    }

    /// Plain rectangle with an inner border (inset box-shadow).
    func innerBorder(_ color: Color, width: CGFloat = 2) -> some View {
        overlay(Rectangle().strokeBorder(color, lineWidth: width).allowsHitTesting(false))
    }
}

// MARK: - Buttons

struct PrimaryButtonStyle: ButtonStyle {
    var fill: Color = Palette.lime
    var textColor: Color = Palette.onLime
    var height: CGFloat = 48
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.heading(12))
            .tracking(1)
            .foregroundStyle(isEnabled ? textColor : Palette.veryDim)
            .frame(maxWidth: .infinity, minHeight: height)
            .notched(fill: isEnabled ? fill : Color(hex: 0x0A0D12, opacity: 0.94), edge: isEnabled ? nil : Palette.panelEdge)
            .opacity(configuration.isPressed ? 0.8 : 1)
            .contentShape(NotchedRect())
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    var edge: Color = Palette.edge2
    var textColor: Color = Palette.soft
    var height: CGFloat = 48
    var bold = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(bold ? .heading(12) : .label(12))
            .tracking(1)
            .foregroundStyle(textColor)
            .frame(maxWidth: .infinity, minHeight: height)
            .notched(fill: Color.clear, edge: edge)
            .opacity(configuration.isPressed ? 0.7 : 1)
            .contentShape(NotchedRect())
    }
}

/// Square pixel switch from the Setup artboard.
struct PixelSwitch: View {
    @Binding var isOn: Bool
    var onColor: Color = Palette.lime
    var label: String

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            HStack {
                if isOn { Spacer(minLength: 0) }
                Rectangle()
                    .fill(isOn ? Palette.onLime : Palette.dim)
                    .frame(width: 22, height: 22)
                if !isOn { Spacer(minLength: 0) }
            }
            .padding(3)
            .frame(width: 52, height: 28)
            .background(isOn ? onColor : Palette.onLime)
            .innerBorder(isOn ? onColor : Palette.edge2)
        }
        .buttonStyle(.plain)
        .frame(minWidth: 52, minHeight: 44)
        .accessibilityLabel(label)
        .accessibilityValue(isOn ? "On" : "Off")
        .accessibilityAddTraits(.isToggle)
    }
}

/// Back button (44 × 44 notched panel with the pixel arrow).
struct BackButton: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            PixelIcon(.back)
                .foregroundStyle(Palette.lime)
                .frame(width: 16, height: 16)
                .frame(width: 44, height: 44)
                .panel()
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Back")
    }
}

/// Text field styled like `.inp`.
struct PixelField: View {
    var placeholder: String
    @Binding var text: String
    var keyboard: UIKeyboardType = .decimalPad
    var height: CGFloat = 48
    var fontSize: CGFloat = 24

    var body: some View {
        TextField("", text: $text, prompt: Text(placeholder).foregroundStyle(Palette.veryDim))
            .font(.number(fontSize))
            .foregroundStyle(Color.white)
            .keyboardType(keyboard)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .padding(.horizontal, 12)
            .frame(height: height)
            .background(Palette.input)
            .innerBorder(Palette.inputEdge)
            .tint(Palette.lime)
    }
}

/// Value input that only accepts well-formed values for its kind (time fills colons as you type).
struct ValueField: View {
    var kind: InputKind
    @Binding var text: String
    var placeholder: String?

    var body: some View {
        PixelField(placeholder: placeholder ?? kind.placeholder, text: $text, keyboard: keyboard)
            .onChange(of: text) { _, new in
                let f = InputFormat.format(new, kind: kind)
                if f != new { text = f }
            }
    }

    private var keyboard: UIKeyboardType {
        switch kind {
        case .time, .integer: return .numberPad
        case .decimal: return .decimalPad
        }
    }
}
