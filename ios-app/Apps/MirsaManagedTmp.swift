import Foundation

/// Managed workspaces have explicit live leases. Container-wide legacy cleanup additionally
/// handles stale tmp/cache leftovers without touching current-process or persistent files.
enum MirsaManagedTmp {
    static let rootName = "mirsa-managed"
    static var root: URL { FileManager.default.temporaryDirectory.appendingPathComponent(rootName, isDirectory: true) }
    private static let lock = NSLock()
    private static var active = Set<String>()
    private static var served: [String: Date] = [:]
    // Foundation can expose the same iOS workspace through /var or /private/var.
    // Every registry lookup, including directory enumeration, needs the same key.
    private static func key(_ path: String) -> String {
        MirsaContainerCleanup.canonicalDarwinPath(URL(fileURLWithPath: path).resolvingSymlinksInPath())
    }

    // Reject symlinks at every caller-controlled component, including the root itself.
    // Darwin's system /var and /tmp aliases are permitted, not arbitrary parent links.
    private static func safeRoot(_ r: URL) -> URL? {
        let u = r.standardizedFileURL
        guard u.isFileURL, u.path != "/" else { return nil }
        var cursor = URL(fileURLWithPath: "/", isDirectory: true)
        for component in u.pathComponents.dropFirst() {
            cursor.appendPathComponent(component)
            if (try? cursor.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
                guard cursor.path != u.path, cursor.path == "/var" || cursor.path == "/tmp" else { return nil }
            }
        }
        return u.resolvingSymlinksInPath().standardizedFileURL
    }

    private static func owned(_ dir: URL, base: URL) -> Bool {
        guard let checked = safeRoot(dir), checked.deletingLastPathComponent().path == base.path,
              (try? checked.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { return false }
        return true
    }

    @discardableResult
    static func begin(_ label: String, root r: URL? = nil) throws -> URL {
        lock.lock(); defer { lock.unlock() }
        guard let base = safeRoot(r ?? root) else { throw CocoaError(.fileWriteInvalidFileName) }
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        guard safeRoot(base)?.path == base.path else { throw CocoaError(.fileWriteInvalidFileName) }
        let safe = String(label.filter { $0.isLetter || $0.isNumber || $0 == "-" }.prefix(24))
        let dir = base.appendingPathComponent(safe + "-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: false)
        active.insert(key(dir.path))
        return dir
    }

    static func end(_ dir: URL, root r: URL? = nil) {
        lock.lock()
        defer {
            lock.unlock()
            // Every completed sign/install workspace also sweeps stale legacy files.
            // Keep the pre-process cutoff for unregistered in-flight producers.
            if r == nil { _ = sweep(maxAge: 0) }
        }
        guard let base = safeRoot(r ?? root), owned(dir, base: base),
              let checked = safeRoot(dir) else { return }
        active.remove(key(checked.path)); served[key(checked.path)] = nil
        try? FileManager.default.removeItem(at: checked)
    }

    /// Transfers active ownership to a bounded consumer lease. Expiry is separate from active work.
    static func markServed(_ dir: URL, until: Date, root r: URL? = nil) {
        lock.lock(); defer { lock.unlock() }
        guard let base = safeRoot(r ?? root), owned(dir, base: base), let checked = safeRoot(dir) else { return }
        active.remove(key(checked.path))
        served[key(checked.path)] = until
    }

    /// Successful producer hands ownership to its caller; caller must end after copying/consuming.
    /// This stays active, so even manual cleaning cannot remove an in-flight consumer.
    static func isActive(_ path: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return active.contains(key(path)) || (served[key(path)].map { $0 > Date() } ?? false)
    }

    static func isOwned(_ dir: URL, root r: URL? = nil) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard let base = safeRoot(r ?? root) else { return false }
        return owned(dir, base: base)
    }

    @discardableResult
    static func sweep(maxAge: TimeInterval = 3600, now: Date = Date(), root r: URL? = nil) -> Int {
        lock.lock(); defer { lock.unlock() }
        guard let base = safeRoot(r ?? root),
              let items = try? FileManager.default.contentsOfDirectory(at: base, includingPropertiesForKeys: [.contentModificationDateKey]) else {
            return r == nil ? containerScan(delete: true, maxAge: maxAge, now: now).removed : 0
        }
        var removed = 0
        for item in items {
            guard owned(item, base: base), !active.contains(key(item.path)) else { continue }
            if let until = served[key(item.path)], until > now { continue }
            served[key(item.path)] = nil
            let modified = (try? item.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? now
            guard now.timeIntervalSince(modified) > maxAge else { continue }
            do { try FileManager.default.removeItem(at: item); removed += 1 } catch {}
        }
        if r == nil {
            removed += containerScan(delete: true, maxAge: maxAge, now: now).removed
        }
        return removed
    }

    // Runs under the registry lock shared with begin/end/markServed. A lease protects
    // its ancestors and descendants; unknown new legacy files fail closed by ctime.
    private static func containerScan(delete: Bool, maxAge: TimeInterval, now: Date) -> MirsaContainerCleanup.Result {
        let fm = FileManager.default
        let blocked = active.union(served.filter { $0.value > now }.map { $0.key })
        let cutoff = min(MirsaContainerCleanup.processStart.addingTimeInterval(-2),
                         now.addingTimeInterval(-max(0, maxAge)))
        var total = MirsaContainerCleanup.scan(root: fm.temporaryDirectory, scope: .temporary,
            delete: delete, cutoff: cutoff, protectedPaths: blocked, now: now)
        if let caches = fm.urls(for: .cachesDirectory, in: .userDomainMask).first {
            let cache = MirsaContainerCleanup.scan(root: caches, scope: .caches,
                delete: delete, cutoff: cutoff, protectedPaths: blocked, now: now)
            total.bytes += cache.bytes; total.removed += cache.removed
        }
        return total
    }

    static func size(root r: URL? = nil) -> Int64 {
        lock.lock(); defer { lock.unlock() }
        if r == nil { return containerScan(delete: false, maxAge: 0, now: Date()).bytes }
        guard let base = safeRoot(r ?? root) else { return 0 }
        // Walk each directory explicitly so skipping a link never prunes siblings.
        // Only real directories are enqueued; user-linked targets are never visited.
        let keys: Set<URLResourceKey> = [.isSymbolicLinkKey, .isDirectoryKey, .fileSizeKey, .isRegularFileKey]
        var pending = [base]
        var bytes: Int64 = 0
        while let directory = pending.popLast() {
            guard safeRoot(directory)?.path == directory.path,
                  let children = try? FileManager.default.contentsOfDirectory(
                    at: directory, includingPropertiesForKeys: Array(keys)) else { continue }
            for child in children {
                guard let values = try? child.resourceValues(forKeys: keys),
                      values.isSymbolicLink == false else { continue }
                if values.isDirectory == true { pending.append(child) }
                else if values.isRegularFile == true { bytes += Int64(values.fileSize ?? 0) }
            }
        }
        return bytes
    }

    static var sizeText: String { ByteCountFormatter.string(fromByteCount: size(), countStyle: .file) }
    @discardableResult
    static func cleanNow() -> Int { sweep(maxAge: -1) }
}
