import Foundation
import SwiftUI

/// Safe inline Markdown for chat bubbles: bold/italic/code and https links only. No HTML, no images.
enum ForgeChatMarkdown {
    /// Only http/https with a plausible host (letters, digits, dots, dashes, at least one dot) and no credentials.
    static func isSafeLink(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return false }
        guard url.user == nil, url.password == nil, let host = url.host?.lowercased(), host.contains("."), host.count <= 253 else { return false }
        let allowed = Set("abcdefghijklmnopqrstuvwxyz0123456789.-")
        guard host.allSatisfy({ allowed.contains($0) }), !host.hasPrefix("."), !host.hasPrefix("-"), !host.hasSuffix(".") else { return false }
        return true
    }

    /// Never throws: malformed Markdown falls back to the plain original text.
    static func attributed(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace, failurePolicy: .returnPartiallyParsedIfPossible)
        guard var out = try? AttributedString(markdown: text, options: options) else { return AttributedString(text) }
        for run in out.runs {
            if let link = run.link, !isSafeLink(link) { out[run.range].link = nil }
        }
        return out
    }

    /// Plain text of the rendered result (what the user sees), used by tests.
    static func visibleText(_ text: String) -> String { String(attributed(text).characters) }
    static func links(_ text: String) -> [URL] { attributed(text).runs.compactMap { $0.link } }
    static func hasBold(_ text: String) -> Bool {
        attributed(text).runs.contains { $0.inlinePresentationIntent?.contains(.stronglyEmphasized) == true }
    }
}
