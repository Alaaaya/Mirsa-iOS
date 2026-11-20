import Foundation
import CryptoKit

/// Content identity is independent of download UUIDs and root ordering, but
/// includes framework resources/relative paths so different versions stay distinct.
enum IPATweakIdentity {
    static func cleanName(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let leaf = raw.replacingOccurrences(of: "\\", with: "/").split(separator: "/").last.map(String.init) ?? ""
        let ext = (leaf as NSString).pathExtension.lowercased()
        let stem = ["dylib", "deb", "zip", "framework"].contains(ext) ? (leaf as NSString).deletingPathExtension : leaf
        let name = stem.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name != ".", name != "..", UUID(uuidString: name) == nil,
              !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { return nil }
        return String(name.prefix(120))
    }

    static func fingerprint(_ roots: [URL]) throws -> String {
        let fm = FileManager.default
        var components: [String] = []
        for root in roots {
            let directory = try root.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true
            var files = [root]
            if directory {
                guard let e = fm.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey]) else { throw CocoaError(.fileReadCorruptFile) }
                files = e.allObjects.compactMap { $0 as? URL }.sorted { $0.path < $1.path }
            }
            var digest = SHA256()
            digest.update(data: Data((directory ? "framework\0" : "dylib\0").utf8))
            for file in files {
                let v = try file.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey])
                guard v.isSymbolicLink != true else { throw CocoaError(.fileReadCorruptFile) }
                if directory {
                    let relative = String(file.path.dropFirst(root.path.count + 1))
                    digest.update(data: Data((relative + "\0").utf8))
                }
                if v.isDirectory == true { continue }
                guard v.isRegularFile == true else { throw CocoaError(.fileReadCorruptFile) }
                let input = try FileHandle(forReadingFrom: file)
                defer { try? input.close() }
                while let chunk = try input.read(upToCount: 65_536), !chunk.isEmpty { digest.update(data: chunk) }
            }
            components.append(digest.finalize().map { String(format: "%02x", $0) }.joined())
        }
        return SHA256.hash(data: Data(components.sorted().joined(separator: "\n").utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// Read bounded Mach-O metadata only; never load or execute imported code.
    static func metadataName(_ root: URL) -> String? {
        if root.pathExtension.lowercased() == "framework",
           let info = NSDictionary(contentsOf: root.appendingPathComponent("Info.plist")) {
            for key in ["CFBundleDisplayName", "CFBundleName", "CFBundleExecutable"] {
                if let name = cleanName(info[key] as? String) { return name }
            }
        }
        guard let input = try? FileHandle(forReadingFrom: root) else { return nil }
        defer { try? input.close() }
        guard let prefix = try? input.read(upToCount: 4096), prefix.count >= 32 else { return nil }
        func uint(_ bytes: Data, _ at: Int, _ count: Int, big: Bool) -> UInt64 {
            guard at >= 0, at + count <= bytes.count else { return 0 }
            return (0..<count).reduce(UInt64(0)) { value, i in
                value | UInt64(bytes[at+i]) << ((big ? count-1-i : i)*8)
            }
        }
        var base: UInt64 = 0
        let magic = uint(prefix, 0, 4, big: true)
        if [0xcafebabe, 0xcafebabf, 0xbebafeca, 0xbfbafeca].contains(magic) {
            let big = magic == 0xcafebabe || magic == 0xcafebabf
            let wide = magic == 0xcafebabf || magic == 0xbfbafeca
            let count = uint(prefix, 4, 4, big: big)
            let stride = wide ? 32 : 20
            guard count > 0, count <= 64, 8 + Int(count)*stride <= prefix.count else { return nil }
            var selected: UInt64?
            for i in 0..<Int(count) {
                let at = 8 + i*stride
                if uint(prefix, at, 4, big: big) == 0x0100000c {
                    selected = uint(prefix, at+8, wide ? 8 : 4, big: big)
                    break
                }
            }
            guard let selected else { return nil }
            base = selected
        }
        guard (try? input.seek(toOffset: base)) != nil,
              let data = try? input.read(upToCount: 1_048_576), data.count >= 32 else { return nil }
        func word(_ offset: Int) -> UInt32 { UInt32(uint(data, offset, 4, big: false)) }
        guard word(0) == 0xfeedfacf, word(16) <= 65_536,
              word(20) <= data.count - 32 else { return nil }
        let end = 32 + Int(word(20))
        var offset = 32
        for _ in 0..<Int(word(16)) {
            guard offset + 8 <= end else { return nil }
            let size = Int(word(offset + 4))
            guard size >= 8, size <= end - offset else { return nil }
            if word(offset) == 0xd, size >= 24 {
                let start = Int(word(offset + 8))
                guard start >= 24, start < size else { return nil }
                let bytes = data[(offset + start)..<(offset + size)].prefix { $0 != 0 }
                return cleanName(String(data: Data(bytes), encoding: .utf8))
            }
            offset += size
        }
        return nil
    }

    static func deduplicated<T>(_ items: [T], identity: (T) -> String?) -> [T] {
        var seen = Set<String>()
        return items.filter { item in
            guard let key = identity(item) else { return true }
            return seen.insert(key).inserted
        }
    }

    static func name(preferred: String?, roots: [URL], fingerprint: String) -> String {
        if let name = cleanName(preferred) { return name }
        for root in roots {
            if let name = metadataName(root) ?? cleanName(root.lastPathComponent) { return name }
        }
        return "Tweak " + String(fingerprint.prefix(8))
    }
}
