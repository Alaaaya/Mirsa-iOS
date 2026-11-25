import Foundation
import CryptoKit

enum RuntimeTranslationScanError: Error, Equatable {
    case encrypted, malformed, tooLarge, invalidApp
}

/// Reads untrusted executable data only. Never loads code or modifies the app.
enum RuntimeTranslationScanner {
    struct Scan {
        let revision: String
        let items: [ArabicIPALocalizer.Item]
    }

    /// Binary extraction uses this CJK-only predicate. Latin text is accepted only
    /// from explicit localization resources, never arbitrary executable bytes.
    static func eligible(_ text: String) -> Bool {
        safe(text) && text.unicodeScalars.contains {
            (0x3400...0x9FFF).contains($0.value) || (0xF900...0xFAFF).contains($0.value) ||
            (0x3040...0x30FF).contains($0.value) || (0xAC00...0xD7AF).contains($0.value)
        }
    }

    // Mirrors runtime-translate safeText plus its per-item 256 UTF-16-unit contract.
    // Additional path/control rejection is intentionally stricter than the server.
    static func safeText(_ text: String) -> Bool {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              text.utf16.count <= 256 else { return false }
        let patterns = [
            #"[\x{0000}-\x{0008}\x{000B}\x{000C}\x{000E}-\x{001F}\x{007F}\x{202A}-\x{202E}\x{2066}-\x{2069}]"#,
            #"(?i)(?:https?:|www\.|mailto:|[\w.+-]+@[\w.-]+|\b[a-z0-9-]+\.(?:com|net|org|de|io|app)\b|(?:\d[\s().+-]*){7}|(?:bearer|password|passwd|secret|api[_ -]?key|token|address|phone|email|iban|ssn|姓名|身份证|手机号|密码|邮箱|住址)\s*[:=：]|(?:sk-|eyJ)[a-zA-Z0-9_-]{12}|[a-zA-Z0-9_+/=-]{40,}|(?:/Users/|/home/|file://))"#,
            #"(?:[/\\][\w.~%-]+)|^[~/\\]|[a-zA-Z][a-zA-Z0-9+.-]*://"#
        ]
        return !patterns.contains { text.range(of: $0, options: .regularExpression) != nil }
    }

    private static func safe(_ text: String) -> Bool {
        safeText(text) && text == text.trimmingCharacters(in: .whitespacesAndNewlines) &&
            ArabicIPALocalizer.worthTranslating(text)
    }

    static func scan(app: URL) throws -> Scan {
        let fm = FileManager.default
        // Permit only Darwin's system aliases, never an app-controlled symlink.
        let input = app.standardizedFileURL
        guard input.isFileURL, input.path != "/" else { throw RuntimeTranslationScanError.invalidApp }
        var cursor = URL(fileURLWithPath: "/", isDirectory: true)
        for component in input.pathComponents.dropFirst() {
            cursor.appendPathComponent(component)
            if (try? cursor.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
                guard cursor.path != input.path, cursor.path == "/var" || cursor.path == "/tmp" else {
                    throw RuntimeTranslationScanError.invalidApp
                }
            }
        }
        let root = input.resolvingSymlinksInPath().standardizedFileURL
        guard (try root.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])).isDirectory == true else {
            throw RuntimeTranslationScanError.invalidApp
        }
        func regular(_ url: URL) throws -> Bool {
            guard url.standardizedFileURL.path.hasPrefix(root.path + "/"),
                  url.resolvingSymlinksInPath().path == url.standardizedFileURL.path else { return false }
            let v = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            return v.isRegularFile == true && v.isSymbolicLink != true
        }
        func executable(_ bundle: URL) throws -> URL {
            let info = bundle.appendingPathComponent("Info.plist")
            guard try regular(info),
                  ((try info.resourceValues(forKeys: [.fileSizeKey])).fileSize ?? Int.max) <= 1_048_576,
                  let dict = try PropertyListSerialization.propertyList(from: Data(contentsOf: info), options: [], format: nil) as? [String: Any],
                  let name = dict["CFBundleExecutable"] as? String,
                  !name.isEmpty, !name.contains("/"), !name.contains("\\"), name != ".", name != ".." else {
                throw RuntimeTranslationScanError.invalidApp
            }
            let result = bundle.appendingPathComponent(name)
            guard try regular(result) else { throw RuntimeTranslationScanError.invalidApp }
            return result
        }
        var binaries = [try executable(root)]
        guard let entries = fm.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey]) else {
            throw RuntimeTranslationScanError.invalidApp
        }
        var count = 0
        for case let url as URL in entries {
            count += 1
            guard count <= 200_000 else { throw RuntimeTranslationScanError.tooLarge }
            let v = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            if v.isSymbolicLink == true { entries.skipDescendants(); continue }
            if v.isDirectory == true && ["framework", "app", "appex", "xpc"].contains(url.pathExtension) {
                // Include extension/App Clip executables in the encryption gate and revision.
                binaries.append(try executable(url))
            } else if v.isDirectory != true, try regular(url) {
                // Catch dylibs and Mach-O files outside conventional bundle locations.
                let handle = try FileHandle(forReadingFrom: url)
                let prefix: Data
                do { prefix = try handle.read(upToCount: 4) ?? Data(); try handle.close() }
                catch { try? handle.close(); throw error }
                let signatures: Set<Data> = [
                    Data([0xCF,0xFA,0xED,0xFE]), Data([0xFE,0xED,0xFA,0xCF]),
                    Data([0xCE,0xFA,0xED,0xFE]), Data([0xFE,0xED,0xFA,0xCE]),
                    Data([0xCA,0xFE,0xBA,0xBE]), Data([0xBE,0xBA,0xFE,0xCA]),
                    Data([0xCA,0xFE,0xBA,0xBF]), Data([0xBF,0xBA,0xFE,0xCA])
                ]
                if signatures.contains(prefix) { binaries.append(url) }
            }
            binaries = Array(Set(binaries))
            guard binaries.count <= 64 else { throw RuntimeTranslationScanError.tooLarge }
        }
        binaries = Array(Set(binaries)).sorted { $0.path < $1.path }
        var totalBytes = 0, texts = Set<String>(), hasher = SHA256()
        for binary in binaries {
            let size = try binary.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max
            guard size <= 200 * 1_048_576, size <= 256 * 1_048_576 - totalBytes else { throw RuntimeTranslationScanError.tooLarge }
            totalBytes += size
            let data = try Data(contentsOf: binary)
            guard data.count == size else { throw RuntimeTranslationScanError.malformed }
            let relative = String(binary.path.dropFirst(root.path.count))
            hasher.update(data: Data(relative.utf8)); hasher.update(data: Data([0]))
            hasher.update(data: Data(String(size).utf8)); hasher.update(data: Data([0]))
            hasher.update(data: data)
            try parse(data, texts: &texts)
        }
        let local = try ArabicIPALocalizer.scan(app: root)
        if !local.hasArabic {
            for item in local.items where safe(item.text) { texts.insert(item.text) }
        }
        var items: [ArabicIPALocalizer.Item] = [], chars = 0
        for text in texts.sorted() {
            guard items.count < 1500, chars + text.count <= 120_000 else { break }
            chars += text.count
            items.append(.init(id: digest(Data(text.utf8)), text: text))
        }
        return Scan(revision: hasher.finalize().map { String(format: "%02x", $0) }.joined(), items: items)
    }

    private static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private struct Reader {
        let data: Data
        let start: Int
        let size: Int
        let little: Bool
        func valid(_ offset: Int, _ length: Int) -> Bool {
            offset >= 0 && length >= 0 && offset <= size && length <= size - offset
        }
        func uint(_ offset: Int, _ bytes: Int) throws -> UInt64 {
            guard valid(offset, bytes) else { throw RuntimeTranslationScanError.malformed }
            var value: UInt64 = 0
            for i in 0..<bytes {
                let shift = (little ? i : bytes - i - 1) * 8
                value |= UInt64(data[start + offset + i]) << shift
            }
            return value
        }
        func int(_ offset: Int, _ bytes: Int) throws -> Int {
            let v = try uint(offset, bytes)
            guard v <= UInt64(Int.max) else { throw RuntimeTranslationScanError.malformed }
            return Int(v)
        }
        func name(_ offset: Int) throws -> String {
            guard valid(offset, 16) else { throw RuntimeTranslationScanError.malformed }
            return String(decoding: data[(start + offset)..<(start + offset + 16)].prefix { $0 != 0 }, as: UTF8.self)
        }
    }

    private static func parse(_ data: Data, texts: inout Set<String>) throws {
        let outer = Reader(data: data, start: 0, size: data.count, little: false)
        let magic = try outer.uint(0, 4)
        if [0xCAFEBABE, 0xBEBAFECA, 0xCAFEBABF, 0xBFBAFECA].contains(magic) {
            let fat = Reader(data: data, start: 0, size: data.count, little: magic == 0xBEBAFECA || magic == 0xBFBAFECA)
            let wide = magic == 0xCAFEBABF || magic == 0xBFBAFECA
            let count = try fat.int(4, 4), stride = wide ? 32 : 20
            guard count > 0, count <= 64, fat.valid(8, count * stride) else { throw RuntimeTranslationScanError.malformed }
            var ranges: [Range<Int>] = []
            for i in 0..<count {
                let p = 8 + i * stride
                let offset = try fat.int(p + 8, wide ? 8 : 4)
                let size = try fat.int(p + (wide ? 16 : 12), wide ? 8 : 4)
                guard offset >= 8 + count * stride, size > 0, fat.valid(offset, size),
                      !ranges.contains(where: { $0.overlaps(offset..<(offset + size)) }) else { throw RuntimeTranslationScanError.malformed }
                ranges.append(offset..<(offset + size))
                try thin(data, start: offset, size: size, texts: &texts)
            }
        } else {
            try thin(data, start: 0, size: data.count, texts: &texts)
        }
    }

    private static func thin(_ data: Data, start: Int, size: Int, texts: inout Set<String>) throws {
        let head = Reader(data: data, start: start, size: size, little: false)
        let magic = try head.uint(0, 4)
        guard [0xCFFAEDFE, 0xFEEDFACF, 0xCEFAEDFE, 0xFEEDFACE].contains(magic) else { throw RuntimeTranslationScanError.malformed }
        let wide = magic == 0xCFFAEDFE || magic == 0xFEEDFACF
        let r = Reader(data: data, start: start, size: size, little: magic == 0xCFFAEDFE || magic == 0xCEFAEDFE)
        let header = wide ? 32 : 28
        let count = try r.int(16, 4), commandBytes = try r.int(20, 4)
        guard count <= 65536, r.valid(header, commandBytes) else { throw RuntimeTranslationScanError.malformed }
        let end = header + commandBytes
        var p = header, sections: [(String, Int, Int)] = []
        let arm64 = try r.uint(4, 4) == 0x0100000C
        for _ in 0..<count {
            guard p <= end, end - p >= 8 else { throw RuntimeTranslationScanError.malformed }
            let cmd = try r.uint(p, 4), length = try r.int(p + 4, 4)
            guard length >= 8, length <= end - p else { throw RuntimeTranslationScanError.malformed }
            if cmd == 0x21 || cmd == 0x2C {
                guard length >= (cmd == 0x2C ? 24 : 20) else { throw RuntimeTranslationScanError.malformed }
                if try r.uint(p + 16, 4) != 0 { throw RuntimeTranslationScanError.encrypted }
            }
            if cmd == 0x19 && wide {
                guard length >= 72 else { throw RuntimeTranslationScanError.malformed }
                let n = try r.int(p + 64, 4)
                guard n <= (length - 72) / 80 else { throw RuntimeTranslationScanError.malformed }
                for i in 0..<n {
                    let s = p + 72 + i * 80
                    let name = try r.name(s)
                    if name == "__cstring" || name == "__ustring" {
                        let bytes = try r.int(s + 40, 8), offset = try r.int(s + 48, 4)
                        guard r.valid(offset, bytes), offset >= end else { throw RuntimeTranslationScanError.malformed }
                        if arm64 { sections.append((name, offset, bytes)) }
                    }
                }
            }
            p += length
        }
        guard p == end else { throw RuntimeTranslationScanError.malformed }
        // Extraction is deferred until every encryption command has been checked.
        for (name, offset, bytes) in sections {
            let unit = name == "__ustring" ? 2 : 1
            guard bytes % unit == 0 else { throw RuntimeTranslationScanError.malformed }
            var begin = offset, cursor = offset
            while cursor < offset + bytes {
                if try r.uint(cursor, unit) == 0 {
                    if cursor > begin, cursor - begin <= 2048 {
                        let chunk = data.subdata(in: (start + begin)..<(start + cursor))
                        let encoding: String.Encoding = unit == 1 ? .utf8 : (r.little ? .utf16LittleEndian : .utf16BigEndian)
                        if let text = String(data: chunk, encoding: encoding), eligible(text) {
                            // Bound memory even when a malicious section has millions of strings.
                            if texts.count < 6000 { texts.insert(text) }
                        }
                    }
                    begin = cursor + unit
                }
                cursor += unit
            }
        }
    }
}
