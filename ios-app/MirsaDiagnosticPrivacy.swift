import Foundation

/// One diagnostic-only boundary. Never use this on paths, credentials or journal records
/// used to perform an operation. Normalize BEFORE filtering and bound AFTER filtering,
/// including for old persisted evidence and all presentation/clipboard/share payloads.
enum MirsaDiagnosticPrivacy {
    static let maximumLine = 2048
    private static let patterns: [(NSRegularExpression, String)] = {
        let rules: [(String, String)] = [
            (#"(?is)-----BEGIN [^-]*(?:PRIVATE KEY|CERTIFICATE)[^-]*-----.*?(?:-----END [^-]+-----|$)"#, "[private material]"),
            (#"(?im)\b(?:authorization|proxy-authorization|cookie|set-cookie)\s*[:=][^\r\n]*"#, "[credential header]"),
            (#"(?i)\b(?:Bearer|Basic)\s+[^\s,;]+"#, "[credential]"),
            (#"(?im)\b(?:authorization|proxy-authorization|cookie|set-cookie|password|passwd|passphrase|secret|client[_ -]?secret|api[_ -]?key|access[_ -]?token|refresh[_ -]?token|device[_ -]?token|token|pairing(?:data|record)?|private[_ -]?key|apple[_ -]?id|account(?:[_ -]?(?:id|name))?|user[_ -]?(?:id|name)|email|udid|ecid|serial(?:number)?|dsid|adsid|team[_ -]?id|device(?:[_ -]?(?:id|name))?|identifier|session|uuid|bundle[_ -]?id|path|relative|container|inode|mtime)\b["']?\s*[:=]\s*(?:"[^"\r\n]*"|'[^'\r\n]*'|[^,;\r\n]*?)(?=\s+[A-Za-z_][A-Za-z0-9_-]*\s*[:=]|[,;\r\n]|$)"#, "[private field]"),
            (#"(?i)\b[a-z][a-z0-9+.-]*://[^\s<>"']+"#, "[url]"),
            (#"(?i)["']/(?:[^"'\r\n]*)["']"#, "[path]"),
            (#"(?i)(?:[a-z]:\\|/(?:private/)?(?:var|Users|home|tmp|run|mnt|data|storage|Applications|Library|System|usr|opt|root|files|containers)(?:/|\b))[^\s<>"']*"#, "[path]"),
            (#"(?i)\b(?:Library|Documents|AppData|Containers|Application Support|AirCardApps)/(?:[^\s<>"']+)"#, "[path]"),
            (#"(?i)\b[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}\b"#, "[email]"),
            (#"(?i)\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b"#, "[id]"),
            (#"(?i)\b(?:eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+|(?:sk|pk|ghp|github_pat|AIza|sb_secret)[_-]?[A-Za-z0-9_-]{8,})\b"#, "[credential]"),
            (#"(?i)\b[0-9a-f]{8,}\b"#, "[id]"),
            (#"\b[A-Za-z0-9_+/=\-]{24,}\b"#, "[opaque]"),
            (#"\b[0-9]{7,}\b"#, "[id]"),
            (#"\b(?:[0-9]{1,3}\.){3}[0-9]{1,3}\b"#, "[address]"),
            (#"(?i)\b(?:[0-9a-f]{2}:){5}[0-9a-f]{2}\b"#, "[address]")
        ]
        // A programmer typo must fail closed, not silently disable one filter.
        return rules.map { (try! NSRegularExpression(pattern: $0.0), $0.1) }
    }()

    private static let unicodeRegex = try! NSRegularExpression(pattern: #"\\u([0-9a-fA-F]{4})"#)
    private static let oscRegex = try! NSRegularExpression(pattern: "\u{1B}\\][^\u{07}\u{1B}]*(\u{07}|\u{1B}\\\\)")
    /// Keeps already-sanitized prefix, sanitizes only appended lines (avoids O(n^2) on main thread).
    static func appending(old: [String], new: [String]) -> [String] {
        if new.count >= old.count, Array(new.prefix(old.count)) == old { return old + lines(Array(new.dropFirst(old.count))) }
        return lines(new)
    }
    static func line(_ input: String) -> String {
        // Oversized untrusted messages are not partially retained: a cut could split a credential.
        guard input.utf8.count <= 64 * 1024 else { return "[oversized diagnostic omitted]" }
        var text = input.replacingOccurrences(of: #"\/"#, with: "/")
        for _ in 0..<2 {
            let decoded = text.removingPercentEncoding ?? text
            if decoded == text { break }; text = decoded
        }
        // Normalize JSON unicode escapes too, without interpreting log text as code.
        let unicode = unicodeRegex
        for match in unicode.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
            if let digits = Range(match.range(at: 1), in: text),
               let value = UInt32(text[digits], radix: 16), let scalar = UnicodeScalar(value),
               let range = Range(match.range, in: text) { text.replaceSubrange(range, with: String(scalar)) }
        }
        text = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        // Remove terminal escape content before controls, preventing control-separated secret labels.
        text = text.replacingOccurrences(of: "\u{1B}\\][^\u{07}\u{1B}]*(\u{07}|\u{1B}\\\\)", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "\u{1B}\\[[0-9;?]*[ -/]*[@-~]", with: "", options: .regularExpression)
        text = String(text.unicodeScalars.filter { $0 == "\n" || $0 == "\t" || $0.value >= 32 && $0.value != 127 && !CharacterSet.controlCharacters.contains($0) && !CharacterSet(charactersIn: "\u{200B}\u{200C}\u{200D}\u{FEFF}").contains($0) })
        // Keep boundary markers across appends so split PEM payloads never become history.
        let begins = text.contains("-----BEGIN ") || text == "[private material begin]"
        let ends = text.contains("-----END ") || text == "[private material end]"
        if begins && !ends { return "[private material begin]" }
        if ends && !begins { return "[private material end]" }
        for (regex, replacement) in patterns {
            text = regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: replacement)
        }
        return String(text.prefix(maximumLine))
    }

    static func lines(_ input: [String]) -> [String] {
        var privateBlock = false
        return input.map { item in
            let safe = line(item)
            // Retain harmless boundary markers, not PEM material, across incremental arrays.
            if safe == "[private material begin]" { privateBlock = true; return safe }
            if safe == "[private material end]" { privateBlock = false; return safe }
            if privateBlock { return "[private material]" }
            return safe
        }
    }
    /// One instance per producer. A split private-key payload is suppressed before persistence.
    final class Stream: @unchecked Sendable {
        private let lock = NSLock()
        private var privateBlock = false
        func line(_ input: String) -> String {
            lock.lock(); defer { lock.unlock() }
            let safe = MirsaDiagnosticPrivacy.line(input)
            if safe == "[private material begin]" { privateBlock = true; return safe }
            if safe == "[private material end]" { privateBlock = false; return safe }
            return privateBlock ? "[private material]" : safe
        }
    }
    /// All display/copy/export use the same final formatting, including historical input.
    static func formatted(_ input: [String]) -> String { lines(input).joined(separator: "\n") }

    static func copy(_ input: [String], write: (String) -> Void) { write(formatted(input)) }
    static func export(_ input: [String]) -> Data { Data(formatted(input).utf8) }

    static func migrateInstallBreadcrumbs(_ defaults: UserDefaults) -> [String] {
        let keys = ["mirsa.install.stage", "mirsa.install.lastLog"]
        let history = keys.compactMap { defaults.string(forKey: $0) }
        // Remove raw historical storage regardless of entitlement or UI visibility.
        keys.forEach { defaults.removeObject(forKey: $0) }
        return lines(history)
    }
}
