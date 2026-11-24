import UIKit
import UniformTypeIdentifiers

/// Receives a workout shared from Motra (text and/or link), drops it in the App Group
/// inbox and closes. The app reads the inbox the next time it opens.
final class ShareViewController: UIViewController {
    private let titleLabel = UILabel()
    private let bodyLabel = UILabel()

    static let appGroup = "group.jpsdigitalventures.challengetracker"

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 13 / 255, green: 17 / 255, blue: 24 / 255, alpha: 0.96)

        titleLabel.font = UIFont.monospacedSystemFont(ofSize: 16, weight: .bold)
        titleLabel.textColor = UIColor(red: 198 / 255, green: 1, blue: 61 / 255, alpha: 1)
        titleLabel.text = "2027 CHALLENGE"
        bodyLabel.font = UIFont.monospacedSystemFont(ofSize: 15, weight: .regular)
        bodyLabel.textColor = UIColor(red: 230 / 255, green: 237 / 255, blue: 243 / 255, alpha: 1)
        bodyLabel.numberOfLines = 0
        bodyLabel.textAlignment = .center
        bodyLabel.text = "Reading workout…"

        let stack = UIStackView(arrangedSubviews: [titleLabel, bodyLabel])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24)
        ])

        Task { await handleShare() }
    }

    private func handleShare() async {
        var parts: [String] = []
        var types: [String] = []
        var images: [Data] = []
        let items = (extensionContext?.inputItems as? [NSExtensionItem]) ?? []
        for item in items {
            if let t = item.attributedContentText?.string, !t.isEmpty { parts.append(t) }
            for provider in item.attachments ?? [] {
                types.append(provider.registeredTypeIdentifiers.joined(separator: ","))
                for type in provider.registeredTypeIdentifiers {
                    guard let ut = UTType(type) else { continue }
                    if ut.conforms(to: .image) {
                        if let d = await loadImageData(provider, type: type) { images.append(d) }
                        break
                    }
                    if ut.conforms(to: .text) || ut.conforms(to: .url) {
                        if let s = await loadString(provider, type: type) { parts.append(s) }
                        break
                    }
                }
            }
        }
        // Drop exact repeats (Motra may send the text both as content and as an attachment).
        var seen = Set<String>()
        let unique = parts.filter { seen.insert($0.trimmingCharacters(in: .whitespacesAndNewlines)).inserted }
        // First line records what Motra sent, for the debug log.
        let header = "#motrashare types=\(types.joined(separator: " | ")) images=\(images.count)"
        let text = ([header] + unique).joined(separator: "\n\n")

        let saved = save(text, images: images)
        bodyLabel.text = saved ? "Saved. Open 2027 Challenge and it's added automatically." : "Couldn't save that share."
        try? await Task.sleep(nanoseconds: 1_400_000_000)
        extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
    }

    private func loadImageData(_ provider: NSItemProvider, type: String) async -> Data? {
        guard let item = try? await provider.loadItem(forTypeIdentifier: type, options: nil) else { return nil }
        var image: UIImage? = nil
        if let d = item as? Data { image = UIImage(data: d) }
        if let u = item as? URL, let d = try? Data(contentsOf: u) { image = UIImage(data: d) }
        if let i = item as? UIImage { image = i }
        return image?.jpegData(compressionQuality: 0.9)
    }

    private func loadString(_ provider: NSItemProvider, type: String) async -> String? {
        guard let item = try? await provider.loadItem(forTypeIdentifier: type, options: nil) else { return nil }
        if let s = item as? String { return s }
        if let u = item as? URL { return u.isFileURL ? (try? String(contentsOf: u, encoding: .utf8)) : u.absoluteString }
        if let d = item as? Data { return String(data: d, encoding: .utf8) }
        if let a = item as? NSAttributedString { return a.string }
        return nil
    }

    private func save(_ text: String, images: [Data]) -> Bool {
        guard let dir = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Self.appGroup)?
            .appendingPathComponent("Inbox", isDirectory: true) else { return false }
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let stem = "\(Int(Date().timeIntervalSince1970 * 1000))"
            for (i, d) in images.prefix(4).enumerated() {
                try d.write(to: dir.appendingPathComponent("\(stem)-\(i).jpg"))
            }
            // The text file is written last: the app treats it as "this share is complete".
            try text.write(to: dir.appendingPathComponent("\(stem).txt"), atomically: true, encoding: .utf8)
            return true
        } catch {
            return false
        }
    }
}
