import Foundation
import SwiftUI

/// 12 × 12 pixel icons from the artboards, drawn even-odd so holes show.
struct PixelIcon: View {
    enum Kind {
        case home, year, stats, importIcon, setup, back, lock, chevron, check, plus

        var path: String {
            switch self {
            case .home: return "M5 1h2v1h-2zM4 2h4v1h-4zM3 3h6v1h-6zM2 4h8v1h-8zM3 5h6v6h-6zM5 8h2v3h-2z"
            case .year: return "M1 2h10v9h-10zM2 5h2v2h-2zM5 5h2v2h-2zM8 5h2v2h-2zM2 8h2v2h-2zM5 8h2v2h-2zM8 8h2v2h-2zM3 1h1v1h-1zM8 1h1v1h-1z"
            case .stats: return "M1 7h2v4h-2zM4 4h2v7h-2zM7 6h2v5h-2zM10 2h1v9h-1zM0 11h12v1h-12z"
            case .importIcon: return "M5 1h2v5h-2zM2 5h8v1h-8zM3 6h6v1h-6zM4 7h4v1h-4zM5 8h2v1h-2zM1 10h10v1h-10zM1 9h1v1h-1zM10 9h1v1h-1z"
            case .setup: return "M1 2h10v1h-10zM3 1h2v3h-2zM1 6h10v1h-10zM7 5h2v3h-2zM1 10h10v1h-10zM4 9h2v3h-2z"
            case .back: return "M3 5h8v2h-8zM4 3h2v2h-2zM2 4h2v4h-2zM4 7h2v2h-2zM6 2h1v1h-1zM6 9h1v1h-1z"
            case .lock: return "M4 1h4v1h-4zM3 2h1v3h-1zM8 2h1v3h-1zM2 5h8v6h-8zM5 7h2v2h-2z"
            case .chevron: return "M4 2h2v2h-2zM6 4h2v2h-2zM8 5h1v2h-1zM6 6h2v2h-2zM4 8h2v2h-2z"
            case .check: return "M9 3h2v2h-2zM8 5h2v1h-2zM7 6h2v1h-2zM6 7h2v1h-2zM5 8h2v1h-2zM2 6h2v1h-2zM3 7h2v1h-2zM4 8h1v1h-1z"
            case .plus: return "M5 2h2v8h-2zM2 5h8v2h-8z"
            }
        }
    }

    var kind: Kind
    init(_ kind: Kind) { self.kind = kind }

    var body: some View {
        PixelPathShape(rects: PixelPathShape.parse(kind.path), grid: 12)
            .fill(style: FillStyle(eoFill: true, antialiased: false))
            .aspectRatio(1, contentMode: .fit)
    }
}

/// Shape made of rectangles on a square grid.
struct PixelPathShape: Shape {
    var rects: [CGRect]
    var grid: CGFloat

    nonisolated func path(in r: CGRect) -> Path {
        let s = min(r.width, r.height) / grid
        var p = Path()
        for rc in rects {
            p.addRect(CGRect(x: r.minX + rc.minX * s, y: r.minY + rc.minY * s, width: rc.width * s, height: rc.height * s))
        }
        return p
    }

    /// Parses the artboards' "Mx yhWvHh-Wz" rectangle paths.
    static func parse(_ d: String) -> [CGRect] {
        var out: [CGRect] = []
        for part in d.split(separator: "M") {
            // e.g. "5 1h2v1h-2z"
            let s = part.replacingOccurrences(of: "z", with: "")
            let pieces = s.split(whereSeparator: { $0 == "h" || $0 == "v" }).map { String($0).trimmingCharacters(in: .whitespaces) }
            guard pieces.count >= 3 else { continue }
            let xy = pieces[0].split(separator: " ").compactMap { Double($0) }
            guard xy.count == 2, let w = Double(pieces[1]), let h = Double(pieces[2]) else { continue }
            out.append(CGRect(x: xy[0], y: xy[1], width: w, height: h))
        }
        return out
    }
}
