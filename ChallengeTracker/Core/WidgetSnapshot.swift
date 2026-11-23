import Foundation

/// What the widget shows. The app writes this as JSON into the App Group
/// container; the widget target has an identical copy of this struct.
/// Keep both files in sync (ChallengeWidget/WidgetSnapshot.swift).
struct WidgetSnapshot: Codable, Equatable, Sendable {
    var mood: String          // Mood raw value
    var moodLabel: String     // "PUMPED"
    var title: String         // "MAR · PULL-UPS"
    var best: String          // "15" or "—"
    var target: String        // "18"
    var score: Int            // 0...120
    var daysLeftLabel: String // "17D LEFT"
    var points: Int           // year total
    var isBoss: Bool
    var updated: Date

    static let fileName = "widget.json"
    static let appGroup = "group.jpsdigitalventures.challengetracker"
}
