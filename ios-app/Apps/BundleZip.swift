import Foundation
#if canImport(Compression)
import Compression
#endif

enum CRC32 {
    static let table: [UInt32] = (0..<256).map { i -> UInt32 in
        var c = UInt32(i)
        for _ in 0..<8 { c = (c & 1) != 0 ? (0xEDB88320 ^ (c >> 1)) : (c >> 1) }
        return c
    }
    static func update(_ crc: UInt32, _ data: Data) -> UInt32 {
        var c = ~crc
        for b in data { c = table[Int((c ^ UInt32(b)) & 0xFF)] ^ (c >> 8) }
        return ~c
    }
}

/// Minimal zip writer (store or deflate), no zip64, symlinks never followed. Used for "Compress".
enum BundleZipWriter {
    static func write(tree: URL, rootName: String, to dest: URL) throws {
        let fm = FileManager.default
        guard fm.createFile(atPath: dest.path, contents: nil) else { throw BundleFileError.conflict("cannot create archive") }
        let out = try FileHandle(forWritingTo: dest); defer { try? out.close() }
        var central = Data(), offset: UInt64 = 0, count = 0
        func le16(_ v: UInt16) -> Data { Data([UInt8(v & 0xFF), UInt8(v >> 8)]) }
        func le32(_ v: UInt32) -> Data { Data([UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF), UInt8((v >> 16) & 0xFF), UInt8(v >> 24)]) }
        func add(name: String, fileURL: URL?, isDir: Bool) throws {
            guard count < 0xFFFE, offset < 0xF000_0000 else { throw BundleFileError.tooLarge(count) }
            let nameData = Data((isDir ? name + "/" : name).utf8)
            var raw = Data()
            if let u = fileURL { raw = try BundleFileManager.readLimited(u, FileToolsLimits.maxTreeBytes) }
            let crc = CRC32.update(0, raw)
            var method: UInt16 = 0, payload = raw
            #if canImport(Compression)
            if raw.count > 64 {
                let cap = raw.count + raw.count / 8 + 1024
                var buf = [UInt8](repeating: 0, count: cap)
                let n = raw.withUnsafeBytes { s in compression_encode_buffer(&buf, cap, s.bindMemory(to: UInt8.self).baseAddress!, raw.count, nil, COMPRESSION_ZLIB) }
                if n > 0 && n < raw.count { method = 8; payload = Data(buf[0..<n]) }
            }
            #endif
            var local = Data()
            local += le32(0x04034b50) + le16(20) + le16(0x0800) + le16(method) + le16(0) + le16(0x21) + le32(crc)
            local += le32(UInt32(payload.count)) + le32(UInt32(raw.count)) + le16(UInt16(nameData.count)) + le16(0) + nameData
            try out.write(contentsOf: local); try out.write(contentsOf: payload)
            central += le32(0x02014b50) + le16(20) + le16(20) + le16(0x0800) + le16(method) + le16(0) + le16(0x21) + le32(crc)
            central += le32(UInt32(payload.count)) + le32(UInt32(raw.count)) + le16(UInt16(nameData.count)) + le16(0) + le16(0) + le16(0) + le16(0)
            central += le32(isDir ? 0x41ED0000 : 0x81A40000) + le32(UInt32(offset)) + nameData
            offset += UInt64(local.count + payload.count); count += 1
        }
        let isDirRoot = (try? tree.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        if !isDirRoot { try add(name: rootName, fileURL: tree, isDir: false) }
        else {
            try add(name: rootName, fileURL: nil, isDir: true)
            guard let en = fm.enumerator(at: tree, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey]) else { return }
            var rels: [(String, Bool, URL)] = []
            for case let u as URL in en {
                let v = try u.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                if v.isSymbolicLink == true { continue }
                let rel = String(u.standardizedFileURL.path.dropFirst(tree.standardizedFileURL.path.count + 1))
                rels.append((rel, v.isDirectory == true, u))
            }
            for (rel, d, u) in rels.sorted(by: { $0.0 < $1.0 }) { try add(name: rootName + "/" + rel, fileURL: d ? nil : u, isDir: d) }
        }
        let cdOffset = offset
        try out.write(contentsOf: central)
        var end = Data()
        end += le32(0x06054b50) + le16(0) + le16(0) + le16(UInt16(count)) + le16(UInt16(count))
        end += le32(UInt32(central.count)) + le32(UInt32(cdOffset)) + le16(0)
        try out.write(contentsOf: end)
    }
}

/// Safe extraction on top of ZipReader (no zip64, bounded sizes, no symlinks, no traversal).
enum BundleZipExtractor {
    static func extract(archive: URL, to dest: URL) throws {
        let fm = FileManager.default
        var limits = IPALimits()
        limits.maxEntries = FileToolsLimits.maxTreeEntries
        limits.maxTotalUncompressed = UInt64(FileToolsLimits.maxTreeBytes)
        limits.maxFileSize = UInt64(FileToolsLimits.maxTreeBytes)
        limits.maxPathDepth = FileToolsLimits.maxDepth
        limits.rejectSymlinks = true
        let data: Data
        do { data = try Data(contentsOf: archive, options: .mappedIfSafe) } catch { throw BundleFileError.notFound(archive.lastPathComponent) }
        let zip: ZipReader
        do { zip = try ZipReader(data: data, limits: limits) } catch { throw BundleFileError.applyFailed(String(describing: error)) }
        try fm.createDirectory(at: dest, withIntermediateDirectories: false)
        var seen = Set<String>(), dirs = Set<String>()
        for e in zip.entries {
            let isDir = e.name.hasSuffix("/")
            let clean = isDir ? String(e.name.dropLast()) : e.name
            if clean.isEmpty { continue }
            let parts = try BundlePath.components(clean)           // rejects ., .., empty, backslash
            if parts.first == "__MACOSX" || parts.last == ".DS_Store" { continue }
            let key = clean.lowercased()
            guard seen.insert(key).inserted else { throw BundleFileError.conflict("duplicate entry " + clean) }
            for i in 1..<max(parts.count, 1) { dirs.insert(parts[0..<i].joined(separator: "/").lowercased()) }
            if isDir { dirs.insert(key) }
            let target = try BundlePath.resolve(clean, in: dest, mustExist: false)
            if isDir { try fm.createDirectory(at: target, withIntermediateDirectories: true); continue }
            guard !dirs.contains(key) else { throw BundleFileError.conflict("file/folder clash " + clean) }
            try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            // re-check after creating parents: no symlink anywhere on the path
            _ = try BundlePath.resolve(BundlePath.parent(clean), in: dest, mustExist: false)
            guard fm.createFile(atPath: target.path, contents: nil) else { throw BundleFileError.conflict(clean) }
            let h = try FileHandle(forWritingTo: target); defer { try? h.close() }
            var off: UInt64 = 0
            let step: UInt64 = 4 << 20
            while off < e.uncompressedSize {
                let chunk: Data
                do { chunk = try zip.read(e, offset: off, length: step, limits: limits) } catch { throw BundleFileError.applyFailed(String(describing: error)) }
                if chunk.isEmpty { break }
                try h.write(contentsOf: chunk); off += UInt64(chunk.count)
            }
            guard off == e.uncompressedSize else { throw BundleFileError.applyFailed("corrupt entry " + clean) }
        }
    }
}
