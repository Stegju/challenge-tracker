import Foundation
import UIKit
import Vision

/// Turns what the MotraShare extension saved into text the Motra parser can read:
/// the shared text itself, text recognized in shared images, or the shared web page.
enum ShareReader {

    /// On-device text recognition, lines top to bottom.
    static func recognizeText(in data: Data) async -> String {
        await Task.detached(priority: .userInitiated) { () -> String in
            guard let image = UIImage(data: data), let cg = image.cgImage else { return "" }
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false
            let handler = VNImageRequestHandler(cgImage: cg, options: [:])
            do {
                try handler.perform([request])
            } catch {
                return ""
            }
            let observations = (request.results ?? []).sorted { $0.boundingBox.minY > $1.boundingBox.minY }
            return observations.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
        }.value
    }

    /// First Motra web link in the text, if any.
    static func motraLink(in text: String) -> URL? {
        guard let r = text.range(of: #"https?://[^\s]*motra[^\s]*"#, options: [.regularExpression, .caseInsensitive]) else { return nil }
        return URL(string: String(text[r]))
    }

    /// Visible text of a web page (tags stripped, block ends become new lines).
    static func pageText(_ url: URL) async -> String? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let html = String(data: data, encoding: .utf8) else { return nil }
        var s = html
        for pattern in [#"<script[\s\S]*?</script>"#, #"<style[\s\S]*?</style>"#] {
            s = s.replacingOccurrences(of: pattern, with: "", options: [.regularExpression, .caseInsensitive])
        }
        s = s.replacingOccurrences(of: #"<(br|/p|/div|/li|/h[1-6]|/tr)[^>]*>"#, with: "\n", options: [.regularExpression, .caseInsensitive])
        s = s.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
        for (k, v) in ["&amp;": "&", "&nbsp;": " ", "&#39;": "'", "&quot;": "\"", "&lt;": "<", "&gt;": ">", "&times;": "×"] {
            s = s.replacingOccurrences(of: k, with: v)
        }
        return s
    }
}
