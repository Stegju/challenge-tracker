import Foundation

struct AppSettings: Codable, Equatable {
    var notifications = NotificationToggles()
    var testMode = false
    var testDate: Date = DemoData.defaultTestDate
    var lastExport: Date?

    enum CodingKeys: String, CodingKey { case notifications, testMode, testDate, lastExport }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        notifications = try c.decodeIfPresent(NotificationToggles.self, forKey: .notifications) ?? NotificationToggles()
        testMode = try c.decodeIfPresent(Bool.self, forKey: .testMode) ?? false
        testDate = try c.decodeIfPresent(Date.self, forKey: .testDate) ?? DemoData.defaultTestDate
        lastExport = try c.decodeIfPresent(Date.self, forKey: .lastExport)
    }
}

/// JSON files in the App Group container (falls back to Application Support).
enum Persistence {
    static var directory: URL {
        if let group = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: WidgetSnapshot.appGroup) {
            return group
        }
        let fm = FileManager.default
        let base = (try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? fm.temporaryDirectory
        return base
    }

    static var yearURL: URL { directory.appendingPathComponent("year2027.json") }
    static var sandboxURL: URL { directory.appendingPathComponent("sandbox2027.json") }
    static var settingsURL: URL { directory.appendingPathComponent("settings.json") }
    static var widgetURL: URL { directory.appendingPathComponent(WidgetSnapshot.fileName) }
    static var logURL: URL { directory.appendingPathComponent("log.txt") }

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    static func load<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        do {
            return try decoder.decode(type, from: data)
        } catch {
            AppLog.add("Could not read \(url.lastPathComponent): \(error)")
            return nil
        }
    }

    @discardableResult
    static func save<T: Encodable>(_ value: T, to url: URL) -> Bool {
        do {
            let data = try encoder.encode(value)
            try data.write(to: url, options: [.atomic])
            return true
        } catch {
            AppLog.add("Could not write \(url.lastPathComponent): \(error)")
            return false
        }
    }
}

/// Small log for the debug screen, kept in memory and appended to a file.
enum AppLog {
    private(set) static var lines: [String] = []

    static func add(_ message: String) {
        let stamp = ISO8601DateFormatter().string(from: Date())
        let line = "\(stamp) \(message)"
        lines.append(line)
        if lines.count > 300 { lines.removeFirst(lines.count - 300) }
        if let data = (line + "\n").data(using: .utf8) {
            let url = Persistence.logURL
            if let h = try? FileHandle(forWritingTo: url) {
                h.seekToEndOfFile()
                h.write(data)
                try? h.close()
            } else {
                try? data.write(to: url)
            }
        }
    }

    static func fileContents() -> String {
        (try? String(contentsOf: Persistence.logURL, encoding: .utf8)) ?? lines.joined(separator: "\n")
    }
}
