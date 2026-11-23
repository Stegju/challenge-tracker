import Foundation

/// Barbell layout, mirroring the script in docs/design/artboards/Barbell.dc.html.
struct BarbellLayout: Equatable, Sendable {
    struct Plate: Equatable, Sendable {
        var tier: Int        // 0 white, 1 green, 2 yellow, 3 blue, 4 red
        var thickness: Int
    }
    struct Partial: Equatable, Sendable {
        var tier: Int
        var thickness: Int
        /// Height in plate units (full plate = 120). 0 when there is no remainder.
        var height: Int
        var top: Int
    }

    /// Full plates on one side, heaviest (highest tier) first, i.e. closest to the centre.
    var plates: [Plate]
    /// The next plate: dashed outline plus the partial fill. nil once the bar is full (10 plates).
    var partial: Partial?
    var points: Int

    var platesPerSide: Double { Double(points) / 100 }
    var fullPlates: Int { plates.count }
    /// Points still needed for the next full plate (nil at 10 plates).
    var pointsToNextPlate: Int? { partial == nil ? nil : 100 - (points % 100) }

    static let plateHeight = 120
    static let thicknesses = [7, 9, 11, 13, 15]
    static let maxPlates = 10

    init(points rawPoints: Int) {
        let pts = max(0, rawPoints)
        points = pts
        let n = min(Self.maxPlates, pts / 100)
        let tiers = (0..<n).map { $0 / 2 }.sorted(by: >)
        plates = tiers.map { Plate(tier: $0, thickness: Self.thicknesses[$0]) }
        if n < Self.maxPlates {
            let gt = n / 2
            let frac = Double(pts % 100) / 100
            let h = frac > 0 ? max(4, Int((Double(Self.plateHeight) * frac).rounded())) : 0
            let top = Int((Double(Self.plateHeight - h) / 2).rounded())
            partial = Partial(tier: gt, thickness: Self.thicknesses[gt], height: h, top: top)
        } else {
            partial = nil
        }
    }
}
