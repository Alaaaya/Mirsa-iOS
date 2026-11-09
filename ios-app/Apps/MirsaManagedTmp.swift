import Foundation

/// Owned temporary workspace. Every operation (download, unzip, sign, OTA upload) gets its own directory
/// under tmp/mirsa-managed, registered while active and deleted when it ends (success, failure or cancel).
/// Only items directly inside that canonical root are ever deleted. Never Projects, library, archived IPAs or user files.
enum MirsaManagedTmp {
    static let rootName = "mirsa-managed"
    static var root: URL { FileManager.default.temporaryDirectory.appendingPathComponent(rootName, isDirectory: true) }
    private static let lock = NSLock()
    private static var active = Set<String>()
    private static var served: [String: Date] = [:]

    private static func canonicalRoot(_ r: URL) -> String { r.resolvingSymlinksInPath().standardizedFileURL.path }

    /// Creates and registers a fresh directory for one operation.
    @discardableResult
    static func begin(_ label: String, root r: URL? = nil) -> URL {
        let base = r ?? root
        let safe = String(label.filter { $0.isLetter || $0.isNumber || $0 == "-" }.prefix(24))
        let dir = base.appendingPathComponent(safe + "-" + UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        lock.lock(); active.insert(dir.lastPathComponent); lock.unlock()
        return dir
    }

    /// Unregisters and deletes the operation directory. Safe to call twice.
    static func end(_ dir: URL, root r: URL? = nil) {
        lock.lock(); active.remove(dir.lastPathComponent); served[dir.lastPathComponent] = nil; lock.unlock()
        guard isOwned(dir, root: r) else { return }
        try? FileManager.default.removeItem(at: dir)
    }

    /// Keeps a directory (for example an OTA payload) safe from sweeps until it expires.
    static func markServed(_ dir: URL, until: Date) { lock.lock(); served[dir.lastPathComponent] = until; lock.unlock() }

    static func isActive(_ name: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        if active.contains(name) { return true }
        if let u = served[name] { if u > Date() { return true }; served[name] = nil }
        return false
    }

    /// True only for a real directory (not a symlink) sitting directly inside the canonical managed root.
    static func isOwned(_ url: URL, root r: URL? = nil) -> Bool {
        let base = r ?? root
        let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey])
        if values?.isSymbolicLink == true { return false }
        let parent = url.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL.path
        return parent == canonicalRoot(base) && url.lastPathComponent != ".." && url.lastPathComponent != "."
    }

    /// Removes stale items (older than maxAge) that are not active or served. Returns how many were removed.
    @discardableResult
    static func sweep(maxAge: TimeInterval = 3600, now: Date = Date(), root r: URL? = nil) -> Int {
        let fm = FileManager.default
        let base = r ?? root
        guard let items = try? fm.contentsOfDirectory(at: base, includingPropertiesForKeys: [.contentModificationDateKey, .isSymbolicLinkKey], options: []) else { return 0 }
        var removed = 0
        for item in items {
            let name = item.lastPathComponent
            if isActive(name) { continue }
            let v = try? item.resourceValues(forKeys: [.contentModificationDateKey, .isSymbolicLinkKey])
            let age = now.timeIntervalSince(v?.contentModificationDate ?? now)
            guard age > maxAge else { continue }
            if v?.isSymbolicLink == true { try? fm.removeItem(at: item); removed += 1; continue } // removes only the link, never its target
            guard isOwned(item, root: base) else { continue }
            if (try? fm.removeItem(at: item)) != nil { removed += 1 }
        }
        return removed
    }

    /// Total bytes in the managed root (symlinks are not followed).
    static func size(root r: URL? = nil) -> Int64 {
        let base = r ?? root
        guard let e = FileManager.default.enumerator(at: base, includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .isRegularFileKey], options: []) else { return 0 }
        var total: Int64 = 0
        for case let u as URL in e {
            let v = try? u.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .isRegularFileKey])
            if v?.isRegularFile == true { total += Int64(v?.totalFileAllocatedSize ?? 0) }
        }
        return total
    }

    static var sizeText: String { ByteCountFormatter.string(fromByteCount: size(), countStyle: .file) }

    /// Removes everything that is not active right now (manual cleaning button).
    @discardableResult
    static func cleanNow() -> Int { sweep(maxAge: -1) }
}
