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
    /// Before the year starts: the moment 2027 begins (widget shows a countdown).
    var countdownTo: Date?
    /// Before the year starts: January's challenge, nil if not chosen yet.
    var januaryName: String?
    /// Before the year starts: January has both baseline and target.
    var januaryReady: Bool?

    static let fileName = "widget.json"
    static let appGroup = "group.jpsdigitalventures.challengetracker"
}
