import Foundation

/// File-manager operations (new folder/file, copy, move, zip, unzip, search, binary patch) for the
/// staged bundle overlay. Everything is staged as ordinary overlay ops (directories are staged as
/// directory blobs), so the original bundle is never touched and apply() stays all-or-nothing.
enum FileToolsLimits {
    static let maxTreeBytes = 64 * 1024 * 1024
    static let maxTreeEntries = 20_000
    static let maxHexBytes = 8 * 1024 * 1024
    static let maxSearchEntries = 20_000
    static let maxSearchResults = 300
    static let maxDepth = 64
}

final class TreeBudget {
    var bytes = 0, entries = 0
    func add(bytes b: Int) throws {
        bytes += b; entries += 1
        if bytes > FileToolsLimits.maxTreeBytes { throw BundleFileError.importTooLarge(bytes) }
        if entries > FileToolsLimits.maxTreeEntries { throw BundleFileError.tooLarge(entries) }
    }
}

struct BundleSearchHit: Identifiable, Equatable {
    let path: String
    let line: Int?        // nil = name match
    let snippet: String
    var id: String { path + "#" + String(line ?? 0) }
}

extension BundleFileManager {
    /// Shared copy/cut clipboard (path inside the bundle's effective tree).
    final class Clipboard { static var path: String?; static var isCut = false }

    // MARK: helpers
    private func snapshotAndRun(_ work: () throws -> Void, cleanup: [URL] = []) throws {
        let saved = overlay
        do { try work() } catch {
            overlay = saved
            for u in cleanup { try? FileManager.default.removeItem(at: u) }
            throw error
        }
    }
    private func requireDirectory(_ dir: String) throws {
        if dir.isEmpty { return }
        guard exists(dir), try entry(dir).kind == .directory else { throw BundleFileError.notFound(dir) }
    }
    private func checkDestination(_ dir: String, _ name: String) throws -> String {
        try BundlePath.validName(name)
        try requireDirectory(dir)
        let dest = BundlePath.join(dir, name)
        guard !exists(dest) else { throw BundleFileError.alreadyExists(dest) }
        if let r = guardrails.destinationReason(dest) { throw BundleFileError.protectedPath(dest, r) }
        return dest
    }
    private func newBlobURL() -> (String, URL) {
        let b = "blob-\(UUID().uuidString)"
        return (b, stagingDirectory.appendingPathComponent(b))
    }
    /// Copies the EFFECTIVE item (original or staged) into dest (file or whole tree). Symlinks are never followed.
    func materialize(_ path: String, to dest: URL, budget: TreeBudget, depth: Int = 0) throws {
        guard depth <= FileToolsLimits.maxDepth else { throw BundleFileError.tooLarge(depth) }
        let e = try entry(path)
        let fm = FileManager.default
        if e.kind == .directory {
            try fm.createDirectory(at: dest, withIntermediateDirectories: false)
            try budget.add(bytes: 0)
            for c in try list(path) { try materialize(c.path, to: dest.appendingPathComponent(c.name), budget: budget, depth: depth + 1) }
        } else {
            let src = try fileURL(of: path)
            try budget.add(bytes: e.size)
            guard fm.createFile(atPath: dest.path, contents: nil) else { throw BundleFileError.conflict("cannot create file") }
            let i = try FileHandle(forReadingFrom: src); defer { try? i.close() }
            let o = try FileHandle(forWritingTo: dest); defer { try? o.close() }
            var total = 0
            while let chunk = try i.read(upToCount: 1 << 20), !chunk.isEmpty {
                total += chunk.count
                guard total <= e.size + (1 << 20) else { throw BundleFileError.importTooLarge(total) }
                try o.write(contentsOf: chunk)
            }
        }
    }
    private func stageBlob(_ blob: String, dir: String, name: String) {
        overlay.ops.append(.importFile(directory: dir, name: name, blob: blob))
    }

    // MARK: create
    func stageMakeDirectory(in dir: String, name: String) throws {
        _ = try checkDestination(dir, name)
        let (b, u) = newBlobURL()
        try snapshotAndRun({
            try FileManager.default.createDirectory(at: u, withIntermediateDirectories: false)
            stageBlob(b, dir: dir, name: name)
        }, cleanup: [u])
    }
    func stageNewFile(in dir: String, name: String, text: String = "") throws {
        _ = try checkDestination(dir, name)
        let (b, u) = newBlobURL()
        try snapshotAndRun({
            try Data(text.utf8).write(to: u, options: .atomic)
            stageBlob(b, dir: dir, name: name)
        }, cleanup: [u])
    }

    // MARK: copy / move
    @discardableResult
    func stageCopy(_ path: String, toDirectory dir: String, name: String? = nil) throws -> String {
        _ = try BundlePath.components(path)
        guard exists(path), !path.isEmpty else { throw BundleFileError.notFound(path) }
        let n = name ?? BundlePath.lastComponent(path)
        let dest = try checkDestination(dir, n)
        if dest == path || dest.hasPrefix(path + "/") { throw BundleFileError.conflict("cannot copy a folder into itself") }
        let (b, u) = newBlobURL()
        try snapshotAndRun({
            try materialize(path, to: u, budget: TreeBudget())
            try verifyTreeDestinations(u, base: dest)
            stageBlob(b, dir: dir, name: n)
        }, cleanup: [u])
        return dest
    }
    func stageMove(_ path: String, toDirectory dir: String, name: String? = nil) throws {
        if let r = protectedReason(path) { throw BundleFileError.protectedPath(path, r) }
        let n = name ?? BundlePath.lastComponent(path)
        if BundlePath.parent(path) == dir && n == BundlePath.lastComponent(path) { return }
        let saved = overlay
        try stageCopy(path, toDirectory: dir, name: n)
        do { try stageDelete(path) } catch {
            if case let .importFile(_, _, blob)? = overlay.ops.last { try? FileManager.default.removeItem(at: stagingDirectory.appendingPathComponent(blob)) }
            overlay = saved
            throw error
        }
    }
    /// Every item inside a staged tree must also pass the destination guards (case aliases etc.).
    private func verifyTreeDestinations(_ tree: URL, base: String) throws {
        guard let en = FileManager.default.enumerator(atPath: tree.path) else { return }
        for case let rel as String in en {
            if let r = guardrails.destinationReason(base + "/" + rel) { throw BundleFileError.protectedPath(base + "/" + rel, r) }
        }
    }

    // MARK: binary / raw write (Hex editor)
    func readData(_ path: String, limit: Int = FileToolsLimits.maxHexBytes) throws -> Data {
        let e = try entry(path)
        guard e.kind != .directory else { throw BundleFileError.notFound(path) }
        return try Self.readLimited(try fileURL(of: path), limit)
    }
    /// Stages replacement bytes of an existing regular file. Info.plist has its own validated editor.
    func stageWriteRaw(_ path: String, data: Data) throws {
        guard exists(path) else { throw BundleFileError.notFound(path) }
        let e = try entry(path)
        guard e.kind != .directory else { throw BundleFileError.notFound(path) }
        guard path != "Info.plist" else { throw BundleFileError.protectedPath(path, "Use the plist editor for Info.plist.") }
        guard data.count <= FileToolsLimits.maxHexBytes else { throw BundleFileError.tooLarge(data.count) }
        let (b, u) = newBlobURL()
        try data.write(to: u, options: .atomic)
        overlay.ops.append(.writeFile(path: path, blob: b))
    }

    // MARK: zip / unzip
    @discardableResult
    func stageZip(_ path: String, intoDirectory dir: String, name: String? = nil) throws -> String {
        guard exists(path) else { throw BundleFileError.notFound(path) }
        let n = name ?? (BundlePath.lastComponent(path) + ".zip")
        _ = try checkDestination(dir, n)
        let tmp = stagingDirectory.appendingPathComponent("tmp-\(UUID().uuidString)")
        let (b, u) = newBlobURL()
        defer { try? FileManager.default.removeItem(at: tmp) }
        try snapshotAndRun({
            try materialize(path, to: tmp, budget: TreeBudget())
            try BundleZipWriter.write(tree: tmp, rootName: BundlePath.lastComponent(path), to: u)
            stageBlob(b, dir: dir, name: n)
        }, cleanup: [u])
        return BundlePath.join(dir, n)
    }

    /// Extracts into a NEW folder; archive entries are validated (no traversal, absolute paths, symlinks,
    /// duplicates/case collisions, bombs) and every extracted path passes the bundle destination guards.
    @discardableResult
    func stageUnzip(_ path: String, intoDirectory dir: String, folderName: String? = nil) throws -> String {
        guard exists(path), try entry(path).kind != .directory else { throw BundleFileError.notFound(path) }
        var stem = BundlePath.lastComponent(path)
        if stem.lowercased().hasSuffix(".zip") || stem.lowercased().hasSuffix(".ipa") { stem = String(stem.dropLast(4)) }
        let n = folderName ?? (stem.isEmpty ? "extracted" : stem)
        let dest = try checkDestination(dir, n)
        let (b, u) = newBlobURL()
        try snapshotAndRun({
            let archive = try fileURL(of: path)
            try BundleZipExtractor.extract(archive: archive, to: u)
            try verifyTreeDestinations(u, base: dest)
            stageBlob(b, dir: dir, name: n)
        }, cleanup: [u])
        return dest
    }

    // MARK: search
    func search(_ query: String, in directory: String = "", content: Bool, isCancelled: () -> Bool = { false }) -> [BundleSearchHit] {
        let q = query.lowercased()
        guard !q.isEmpty else { return [] }
        var hits: [BundleSearchHit] = []
        var visited = 0
        func walk(_ dir: String, _ depth: Int) {
            guard depth <= FileToolsLimits.maxDepth, let kids = try? list(dir) else { return }
            for e in kids {
                if isCancelled() || hits.count >= FileToolsLimits.maxSearchResults || visited >= FileToolsLimits.maxSearchEntries { return }
                visited += 1
                if e.name.lowercased().contains(q) { hits.append(BundleSearchHit(path: e.path, line: nil, snippet: e.name)) }
                if e.kind == .directory { walk(e.path, depth + 1) }
                else if content, e.kind == .text || e.kind == .plist, e.size <= BundleLimits.maxTextBytes,
                        let url = try? fileURL(of: e.path), let d = try? Self.readLimited(url, BundleLimits.maxTextBytes),
                        let s = String(data: d, encoding: .utf8) {
                    var ln = 0
                    for line in s.split(separator: "\n", omittingEmptySubsequences: false) {
                        ln += 1
                        if line.lowercased().contains(q) {
                            hits.append(BundleSearchHit(path: e.path, line: ln, snippet: String(line.prefix(160)).trimmingCharacters(in: .whitespaces)))
                            if hits.count >= FileToolsLimits.maxSearchResults { return }
                        }
                    }
                }
            }
        }
        walk(directory, 0)
        return hits
    }
}
