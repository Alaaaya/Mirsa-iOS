import Foundation

/// Client-side rules of the Mirsa 2.1 attachments contract (Foundation only, unit-testable).
/// The server re-checks everything; these only stop obviously invalid items before any upload.
enum ChatAttachmentRules {
    static let maxPerMessage = 3
    static let imageMaxSide = 1600
    static let imageMaxPixels = 2_560_000
    static let imageMaxBytes = 1_048_576
    static let textMaxBytes = 262_144
    static let urlMaxLength = 2048
    static let nameMax = 100
    /// Binary files (.zip / .deb / .dylib), behind MirsaFeatures.binaryAttachmentsEnabled: 5 MiB decoded each.
    static let binaryMaxBytes = 5_242_880
    /// Server-side active storage per device (informational on the client; the server answers 409 attachment_storage_limit).
    static let deviceStorageMaxBytes = 20 * 1_048_576
    static let binaryMimes: [String: String] = [
        "zip": "application/zip",
        "deb": "application/vnd.debian.binary-package",
        "dylib": "application/x-mach-binary",
    ]

    // MARK: Links

    enum LinkProblem: Error, Equatable { case empty, invalid, notHTTPS, tooLong, credentials, host, port, blockedFile }

    /// Executable, installer and archive extensions. A link whose path (decoded, any segment) ends in one is refused.
    static let blockedExtensions: Set<String> = [
        "ipa", "apk", "xapk", "apks", "apkm", "aab", "deb", "rpm", "udeb", "ipsw",
        "exe", "msi", "msix", "msixbundle", "appx", "appxbundle", "dmg", "pkg", "mpkg", "app", "com", "scr", "cpl",
        "bat", "cmd", "ps1", "vbs", "sh", "bash", "zsh", "command", "run", "bin", "elf", "out",
        "jar", "war", "ear", "dll", "so", "dylib", "framework", "kext",
        "zip", "zipx", "tar", "gz", "tgz", "bz2", "tbz", "tbz2", "xz", "txz", "lz", "lzma", "lz4", "zst", "z",
        "7z", "rar", "cab", "arj", "cpio", "ar", "iso", "img", "vhd", "vhdx", "vmdk", "sit", "sitx", "xar", "crx", "xpi"
    ]

    private static let localSuffixes = [".localhost", ".local", ".localdomain", ".internal", ".intranet", ".lan", ".home", ".home.arpa", ".arpa", ".corp", ".private"]

    static func validateLink(_ raw: String) -> Result<URL, LinkProblem> {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { return .failure(.empty) }
        if s.count > urlMaxLength || s.utf8.count > urlMaxLength { return .failure(.tooLong) }
        if s.unicodeScalars.contains(where: { $0.value < 0x21 || $0.value == 0x7F }) { return .failure(.invalid) }
        guard let c = URLComponents(string: s), let scheme = c.scheme else { return .failure(.invalid) }
        guard scheme.lowercased() == "https" else { return .failure(.notHTTPS) }
        if c.user != nil || c.password != nil || c.percentEncodedUser != nil { return .failure(.credentials) }
        guard var host = c.host?.lowercased(), !host.isEmpty else { return .failure(.host) }
        while host.hasSuffix(".") { host.removeLast() }
        if !isPublicHostName(host) { return .failure(.host) }
        if let p = c.port, p != 443 { return .failure(.port) }
        if hasBlockedPath(c.percentEncodedPath) { return .failure(.blockedFile) }
        guard let url = c.url else { return .failure(.invalid) }
        return .success(url)
    }

    /// Host names only: no IP literals (v4 in any notation, v6), no localhost, no single-label or private suffixes.
    static func isPublicHostName(_ host: String) -> Bool {
        if host.contains(":") || host.contains("[") || host.contains("%") || host.contains("@") { return false }
        if host == "localhost" || localSuffixes.contains(where: { host.hasSuffix($0) }) { return false }
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2, !labels.contains(where: { $0.isEmpty }) else { return false }
        // A numeric or hex last label means an IP literal in some notation (127.1, 0x7f.0.0.1, 2130706433.x).
        if let last = labels.last, last.allSatisfy({ $0.isNumber }) || last.lowercased().hasPrefix("0x") { return false }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-.")
        return host.unicodeScalars.allSatisfy { allowed.contains($0) || $0.value > 0x7F }
    }

    /// Decodes percent-encoding repeatedly (double-encoded "%252Eipa" too) and checks every path segment.
    static func hasBlockedPath(_ percentEncodedPath: String) -> Bool {
        var path = percentEncodedPath
        for _ in 0..<4 {
            guard let d = path.removingPercentEncoding, d != path else { break }
            path = d
        }
        for segment in path.lowercased().split(whereSeparator: { $0 == "/" || $0 == "\\" }) {
            var name = String(segment.split(separator: ";").first ?? "")
            while let last = name.last, last == "." || last == " " || last == "\t" || last == "\u{0}" { name.removeLast() }
            guard let dot = name.lastIndex(of: ".") else { continue }
            let ext = String(name[name.index(after: dot)...])
            if blockedExtensions.contains(ext) { return true }
        }
        return false
    }

    /// Display name for a link chip and the put "name" field.
    static func linkName(_ url: URL) -> String { safeName(url.host ?? url.absoluteString) }

    // MARK: Text files

    enum FileProblem: Error, Equatable { case type, size, utf8, control, json, binarySize, signature }

    /// Only .txt (text/plain) and .json (application/json), at most 256 KiB, strict UTF-8, no control bytes.
    static func validateTextFile(name: String, data: Data) -> Result<(name: String, mime: String), FileProblem> {
        let ext = (name as NSString).pathExtension.lowercased()
        let mime: String
        switch ext {
        case "txt": mime = "text/plain"
        case "json": mime = "application/json"
        default: return .failure(.type)
        }
        if data.isEmpty || data.count > textMaxBytes { return .failure(.size) }
        guard String(data: data, encoding: .utf8) != nil else { return .failure(.utf8) }
        if data.contains(where: { ($0 < 0x20 && $0 != 0x09 && $0 != 0x0A && $0 != 0x0D) || $0 == 0x7F }) { return .failure(.control) }
        if mime == "application/json", (try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])) == nil { return .failure(.json) }
        return .success((safeName(name), mime))
    }

    // MARK: Binary files (.zip / .deb / .dylib)

    /// MIME for a binary attachment by extension, or nil when the extension is not one of the three.
    static func binaryMime(forName name: String) -> String? { binaryMimes[(name as NSString).pathExtension.lowercased()] }

    /// Extension, size (1 byte … 5 MiB) and container family only (ZIP "PK", DEB "!<arch>\n", Mach-O / FAT magic).
    /// Nothing is extracted, loaded or executed; the server does the real checks.
    static func validateBinaryFile(name: String, data: Data) -> Result<(name: String, mime: String), FileProblem> {
        guard let mime = binaryMime(forName: name) else { return .failure(.type) }
        if data.isEmpty || data.count > binaryMaxBytes { return .failure(.binarySize) }
        let head = [UInt8](data.prefix(8))
        let ok: Bool
        switch mime {
        case "application/zip":
            ok = head.count >= 4 && head[0] == 0x50 && head[1] == 0x4B && ((head[2] == 0x03 && head[3] == 0x04) || (head[2] == 0x05 && head[3] == 0x06))
        case "application/vnd.debian.binary-package":
            ok = head == Array("!<arch>\n".utf8)
        default:
            let magics: [[UInt8]] = [[0xFE, 0xED, 0xFA, 0xCE], [0xCE, 0xFA, 0xED, 0xFE], [0xFE, 0xED, 0xFA, 0xCF], [0xCF, 0xFA, 0xED, 0xFE], [0xCA, 0xFE, 0xBA, 0xBE]]
            ok = head.count >= 4 && magics.contains(Array(head.prefix(4)))
        }
        return ok ? .success((safeName(name), mime)) : .failure(.signature)
    }

    /// The problem with a binary file, or nil when it is acceptable.
    static func binaryFileProblem(name: String, data: Data) -> FileProblem? {
        if case .failure(let p) = validateBinaryFile(name: name, data: data) { return p }
        return nil
    }

    /// The problem with a text file, or nil when it is acceptable.
    static func textFileProblem(name: String, data: Data) -> FileProblem? {
        if case .failure(let p) = validateTextFile(name: name, data: data) { return p }
        return nil
    }

    // MARK: Images

    /// Target pixel size for a photo: each side <= 1600 and width*height <= 2.56 MP, aspect kept, never upscaled.
    static func imageTargetSize(width: Int, height: Int) -> (width: Int, height: Int) {
        let w = Double(max(width, 1)), h = Double(max(height, 1))
        let scale = min(1, Double(imageMaxSide) / w, Double(imageMaxSide) / h, (Double(imageMaxPixels) / (w * h)).squareRoot())
        var tw = max(1, Int((w * scale).rounded(.down))), th = max(1, Int((h * scale).rounded(.down)))
        while tw * th > imageMaxPixels { if tw >= th { tw -= 1 } else { th -= 1 } }
        return (min(tw, imageMaxSide), min(th, imageMaxSide))
    }

    // MARK: Names and IDs

    /// Safe display basename, at most 100 characters, no path or control characters.
    static func safeName(_ raw: String) -> String {
        let base = raw.split(whereSeparator: { $0 == "/" || $0 == "\\" }).last.map(String.init) ?? raw
        let cleaned = String(String.UnicodeScalarView(base.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) && $0 != ":" }))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let name = String(cleaned.prefix(nameMax))
        return name.isEmpty ? "attachment" : name
    }

    /// attachmentIDs for chat-send: unique, in order, at most 3.
    static func sendIDs(_ ids: [UUID]) -> [UUID] {
        var seen = Set<UUID>()
        return Array(ids.filter { seen.insert($0).inserted }.prefix(maxPerMessage))
    }
}
