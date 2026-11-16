import Foundation
import Darwin

/// One serialized access owner, shared by discovery, copy, delete and cleanup.
/// Journals are app-private and bind exact UUID, canonical container and root inode.
enum MirsaWallpaperJournal {
    static let lock = NSRecursiveLock()
    static func exclusive<T>(_ body: () throws -> T) throws -> T {
        // Recursive callers on this thread remain valid; competing operations
        // still fail immediately; installation explicitly uses bounded queued access.
        guard lock.try() else {
            throw PosterBoardStore.failure("Another wallpaper operation is already running. Wait for its log to finish, then retry.")
        }
        defer { lock.unlock() }
        return try body()
    }
    /// Installation waits off-main behind discovery/listing without weakening the
    /// same recursive mutation lock. Cancellation is honored BEFORE the body;
    /// once acquired, the existing journaled transaction runs to completion.
    static func exclusiveWaiting<T>(timeout: TimeInterval = 120,
                                    isCancelled: () -> Bool = { false },
                                    onWait: () -> Void = {},
                                    _ body: () throws -> T) throws -> T {
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        guard timeout.isFinite, timeout >= 0 else {
            throw PosterBoardStore.failure("Invalid wallpaper wait timeout.")
        }
        if isCancelled() { throw CancellationError() }
        var acquired = lock.try()
        var reportedWait = false
        while !acquired {
            if isCancelled() { throw CancellationError() }
            let remaining = deadline - ProcessInfo.processInfo.systemUptime
            guard remaining > 0 else {
                throw PosterBoardStore.failure("Wallpaper operation wait timed out. No installation started; retry after the current operation finishes.")
            }
            if !reportedWait { reportedWait = true; onWait() }
            acquired = lock.lock(before: Date(timeIntervalSinceNow: min(0.05, remaining)))
        }
        defer { lock.unlock() }
        if isCancelled() { throw CancellationError() }
        return try body()
    }
    private final class PendingCancellation: @unchecked Sendable {
        private let guardLock = NSLock()
        private var value = false
        func cancel() { guardLock.lock(); defer { guardLock.unlock() }; value = true }
        var isCancelled: Bool { guardLock.lock(); defer { guardLock.unlock() }; return value }
    }
    static func queued<T>(onWait: @escaping () -> Void = {}, _ body: @escaping () throws -> T) async throws -> T {
        try await queued(timeout: 120, onWait: onWait) { _ in try body() }
    }
    static func queued<T>(timeout: TimeInterval, onWait: @escaping () -> Void = {}, _ body: @escaping (@escaping () -> Bool) throws -> T) async throws -> T {
        let pending = PendingCancellation()
        return try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        let result = try exclusiveWaiting(timeout: timeout, isCancelled: { pending.isCancelled }, onWait: onWait) {
                            try body({ pending.isCancelled })
                        }
                        continuation.resume(returning: result)
                    } catch { continuation.resume(throwing: error) }
                }
            }
        }, onCancel: { pending.cancel() })
    }
    struct Record: Codable, Identifiable {
        var id: String
        var title: String
        var container: String
        var relative: String
        var expected: [String: String]
        var device: UInt64?
        var inode: UInt64?
        var copied: Bool = false
        var paths: [String]? = nil
    }
    static var root: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MirsaWallpaperJournals", isDirectory: true)
    }
    static var work: URL { root.appendingPathComponent("Extraction", isDirectory: true) }
    static func safeLocal(_ url: URL) throws {
        guard PosterBoardStore.unredirected(url) else { throw PosterBoardStore.failure("Redirected Mirsa journal path.") }
    }
    static func save(_ record: Record) throws {
        try safeLocal(root)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent(record.id + ".json")
        try safeLocal(url)
        try JSONEncoder().encode(record).write(to: url, options: .atomic)
    }
    static func records() throws -> [Record] {
        try safeLocal(root)
        guard FileManager.default.fileExists(atPath: root.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }.map { url in
                try safeLocal(url)
                guard UUID(uuidString: url.deletingPathExtension().lastPathComponent) != nil else {
                    throw PosterBoardStore.failure("Unknown journal filename; preserved.")
                }
                let record = try JSONDecoder().decode(Record.self, from: Data(contentsOf: url))
                guard record.id == url.deletingPathExtension().lastPathComponent else {
                    throw PosterBoardStore.failure("Journal filename mismatch.")
                }
                try validatePath(record)
                return record
            }
    }
    static func validatePath(_ record: Record) throws {
        let components = record.relative.split(separator: "/").map(String.init)
        guard record.relative == components.joined(separator: "/"), components.count == 8, components[0] == "Library", components[1] == "Application Support",
              components[2] == "PRBPosterExtensionDataStore",
              !components[3].isEmpty, components[3].utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }),
              Int(components[3]).map({ $0 > 0 }) == true,
              components[4] == "Extensions", components[5] == MirsaPosterCopy.provider,
              components[6] == "descriptors", components[7] == record.id,
              UUID(uuidString: record.id) != nil,
              try PosterBoardStore.canonicalContainer(record.container) == record.container,
              !record.expected.isEmpty,
              record.expected.keys.allSatisfy({ !$0.isEmpty && !$0.hasPrefix("/") && !$0.contains("\\") && !$0.contains("\0") && !$0.split(separator: "/", omittingEmptySubsequences: false).contains(where: { $0.isEmpty || $0 == "." || $0 == ".." }) }) else {
            throw PosterBoardStore.failure("Invalid exact owned descriptor path.")
        }
    }
    static func grantExact(_ record: Record, lease: PosterBoardLease) throws -> URL {
        try validatePath(record)
        guard lease.targetURL.path == record.container else { throw PosterBoardStore.failure("Journal container changed.") }
        var relative = ""
        for part in record.relative.split(separator: "/") {
            relative += (relative.isEmpty ? "" : "/") + part
            guard lease.grant(relative), lease.permits(lease.effectiveURL.appendingPathComponent(relative)) else {
                throw PosterBoardStore.failure("Owned descriptor access denied.")
            }
        }
        return lease.effectiveURL.appendingPathComponent(record.relative)
    }
    static func grantTree(_ record: Record, lease: PosterBoardLease) throws -> URL {
        let target = try grantExact(record, lease: lease)
        for file in record.expected.keys {
            var path = record.relative
            for part in file.split(separator: "/") {
                path += "/" + part
                guard lease.grant(path), lease.permits(lease.effectiveURL.appendingPathComponent(path)) else {
                    throw PosterBoardStore.failure("Owned file access denied.")
                }
            }
        }
        return target
    }
    /// Only genuine ENOENT is absence. ENOTDIR, denied and unknown reads fail closed.
    static func absenceResult(_ result: Int32, error: Int32) throws -> Bool {
        if result == 0 { return false } // includes symlinks and special nodes
        guard result == -1, error == ENOENT else {
            throw PosterBoardStore.failure("Absence is not proven; journal retained.")
        }
        return true
    }
    static func sameParent(_ before: stat, _ after: stat) -> Bool {
        (before.st_mode & S_IFMT) == S_IFDIR && (after.st_mode & S_IFMT) == S_IFDIR &&
        before.st_dev == after.st_dev && before.st_ino == after.st_ino
    }
    static func absent(_ target: URL) throws -> Bool {
        var info = stat()
        let result = lstat(target.path, &info)
        let error = errno
        guard try absenceResult(result, error: error) else { return false }
        // Pin a readable real parent. A missing ancestor or linked parent is not proof.
        let parent = target.deletingLastPathComponent()
        var before = stat()
        guard lstat(parent.path, &before) == 0, (before.st_mode & S_IFMT) == S_IFDIR else {
            throw PosterBoardStore.failure("Descriptor parent unavailable.")
        }
        let fd = open(parent.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard fd >= 0 else { throw PosterBoardStore.failure("Descriptor parent unreadable; journal retained.") }
        defer { Darwin.close(fd) }
        var pinned = stat(), after = stat()
        guard fstat(fd, &pinned) == 0, pinned.st_dev == before.st_dev, pinned.st_ino == before.st_ino else {
            throw PosterBoardStore.failure("Descriptor parent changed; journal retained.")
        }
        var child = stat()
        let childResult = fstatat(fd, target.lastPathComponent, &child, AT_SYMLINK_NOFOLLOW)
        let childError = errno
        let missing = try absenceResult(childResult, error: childError)
        guard lstat(parent.path, &after) == 0, (after.st_mode & S_IFMT) == S_IFDIR,
              after.st_dev == pinned.st_dev, after.st_ino == pinned.st_ino else {
            throw PosterBoardStore.failure("Descriptor parent changed; journal retained.")
        }
        return missing
    }
    static func removeJournal(_ record: Record) throws {
        let url = root.appendingPathComponent(record.id + ".json")
        try safeLocal(url)
        let current = try JSONDecoder().decode(Record.self, from: Data(contentsOf: url))
        guard current.id == record.id, current.relative == record.relative,
              current.container == record.container, current.expected == record.expected,
              current.device == record.device, current.inode == record.inode,
              current.copied == record.copied, current.paths == record.paths else { throw PosterBoardStore.failure("Journal changed.") }
        try FileManager.default.removeItem(at: url)
    }
    enum JournalState { case absent, present }
    static func sameRecord(_ lhs: Record, _ rhs: Record) -> Bool {
        lhs.id == rhs.id && lhs.title == rhs.title && lhs.container == rhs.container &&
        lhs.relative == rhs.relative && lhs.expected == rhs.expected &&
        lhs.device == rhs.device && lhs.inode == rhs.inode &&
        lhs.copied == rhs.copied && lhs.paths == rhs.paths
    }
    private static func current(_ requested: Record) throws -> Record {
        guard let record = try records().first(where: { $0.id == requested.id }),
              sameRecord(record, requested) else { throw PosterBoardStore.failure("Journal changed; refresh before continuing.") }
        return record
    }
    /// Fresh exact path check only. Never traverses payload files.
    static func inspect(_ requested: Record, log: @escaping (String) -> Void) throws -> JournalState {
        try exclusive {
            let record = try current(requested)
            let lease = try PosterBoardLease(path: record.container, log: log)
            defer { try? lease.close() }
            try PosterBoardStore.validateIdentity(lease.effectiveURL, lease: lease)
            let target = try grantExact(record, lease: lease)
            let missing = try absent(target)
            try lease.close()
            log("JOURNAL INSPECT " + record.id + (missing ? " exact path absent; lease closed." : " present; journal retained; lease closed."))
            return missing ? .absent : .present
        }
    }
    /// Confirmation action. Rechecks absence independently of any prior inspect.
    /// Closing scoped access must succeed BEFORE any local journal is archived.
    static func archive(_ requested: Record, log: @escaping (String) -> Void) throws {
        try exclusive {
            let record = try current(requested)
            let lease = try PosterBoardLease(path: record.container, log: log)
            defer { try? lease.close() }
            try PosterBoardStore.validateIdentity(lease.effectiveURL, lease: lease)
            let target = try grantExact(record, lease: lease)
            guard try absent(target) else {
                throw PosterBoardStore.failure("This exact wallpaper is still present. Journal retained; use its separate confirmed delete action.")
            }
            try lease.close()
            _ = try current(record)
            try archiveLocal(record, at: root, revalidate: {})
            log("JOURNAL ARCHIVED " + record.id + " fresh exact absence; lease closed; no PosterBoard files modified.")
        }
    }
    /// Move ONLY app-private evidence. Revalidate immediately before and after
    /// the move; a racing target appearance restores the original journal.
    static func archiveLocal(_ record: Record, at journalRoot: URL,
                             revalidate: () throws -> Void) throws {
        let source = journalRoot.appendingPathComponent(record.id + ".json")
        let history = journalRoot.appendingPathComponent("Archived", isDirectory: true)
        try safeLocal(journalRoot)
        try safeLocal(history)
        try FileManager.default.createDirectory(at: history, withIntermediateDirectories: true)
        let destination = history.appendingPathComponent(record.id + "-" + UUID().uuidString + ".json")
        try safeLocal(source)
        try safeLocal(destination)
        let stored = try JSONDecoder().decode(Record.self, from: Data(contentsOf: source))
        guard sameRecord(stored, record) else { throw PosterBoardStore.failure("Journal changed; retained.") }
        try revalidate()
        try FileManager.default.moveItem(at: source, to: destination)
        do { try revalidate() }
        catch {
            // No overwrite and no system mutation, even when restoration fails.
            // In that case original evidence remains in Archived and install stops.
            try FileManager.default.moveItem(at: destination, to: source)
            throw error
        }
    }
    /// Called inside the install's exclusive operation using its SAME active lease.
    /// A prior list/inspect result is deliberately never used as absence evidence.
    static func archiveAbsentForReinstall(_ requested: Record, lease: PosterBoardLease,
                                         log: @escaping (String) -> Void) throws {
        try exclusive {
            let record = try current(requested)
            try PosterBoardStore.validateIdentity(lease.effectiveURL, lease: lease)
            let target = try grantExact(record, lease: lease)
            let parent = target.deletingLastPathComponent()
            var originalParent = stat()
            guard lstat(parent.path, &originalParent) == 0, (originalParent.st_mode & S_IFMT) == S_IFDIR else {
                throw PosterBoardStore.failure("Descriptor parent unavailable; journal retained.")
            }
            func revalidate() throws {
                var currentParent = stat()
                guard lstat(parent.path, &currentParent) == 0, sameParent(originalParent, currentParent),
                      lease.targetURL.path == record.container,
                      lease.permits(parent), lease.permits(target), try absent(target) else {
                    throw PosterBoardStore.failure("Exact wallpaper is present or uncertain; journal retained.")
                }
            }
            try revalidate()
            try archiveLocal(record, at: root, revalidate: revalidate)
            log("JOURNAL REINSTALL ARCHIVED " + record.id + " fresh exact ENOENT under install lease; no PosterBoard files modified.")
        }
    }
    /// Called only from the per-item destructive confirmation, never on launch.
    static func delete(_ requested: Record, log: @escaping (String) -> Void) throws {
        try exclusive {
            guard let record = try records().first(where: { $0.id == requested.id }),
                  record.container == requested.container, record.relative == requested.relative,
                  record.copied, record.device != nil, record.inode != nil, record.paths != nil else {
                throw PosterBoardStore.failure("No completed owned installation journal.")
            }
            let lease = try PosterBoardLease(path: record.container, log: log)
            do {
                try PosterBoardStore.validateIdentity(lease.effectiveURL, lease: lease)
                let target = try grantTree(record, lease: lease)
                var info = stat()
                guard lstat(target.path, &info) == 0, (info.st_mode & S_IFMT) == S_IFDIR,
                      UInt64(info.st_dev) == record.device, UInt64(info.st_ino) == record.inode else {
                    throw PosterBoardStore.failure("Owned descriptor root changed or absent; nothing deleted.")
                }
                // Content/hash gate dropped: PosterBoard legitimately writes files after respring.
                // Ownership is the exact journal UUID + canonical path + root inode verified above.
                var final = stat()
                guard lstat(target.path, &final) == 0, final.st_dev == info.st_dev, final.st_ino == info.st_ino,
                      lease.permits(target) else { throw PosterBoardStore.failure("Owned descriptor changed before delete.") }
                try FileManager.default.removeItem(at: target)
                guard try absent(target) else { throw PosterBoardStore.failure("Deletion readback failed.") }
                try lease.close()
                try removeJournal(record)
                log("DELETE VERIFIED exact Mirsa descriptor UUID " + record.id + "; lease closed; gallery refresh pending.")
            } catch { try? lease.close(); throw error }
        }
    }
    /// No system deletion here. Only absent-entry journals and our extraction root.
    static func cleanup(log: @escaping (String) -> Void) throws {
        try exclusive {
            for record in try records() {
                let lease = try PosterBoardLease(path: record.container, log: log)
                do {
                    try PosterBoardStore.validateIdentity(lease.effectiveURL, lease: lease)
                    let target = try grantExact(record, lease: lease)
                    let missing = try absent(target)
                    try lease.close()
                    if missing { try removeJournal(record); log("Removed absent owned journal " + record.id) }
                } catch { try? lease.close(); throw error }
            }
            try safeLocal(work)
            if FileManager.default.fileExists(atPath: work.path) {
                for url in try FileManager.default.contentsOfDirectory(at: work, includingPropertiesForKeys: nil) {
                    guard UUID(uuidString: url.lastPathComponent) != nil else { continue }
                    try safeLocal(url)
                    _ = try MirsaPosterCopy.relativePaths(url) // reject nested redirects
                    try FileManager.default.removeItem(at: url)
                }
            }
            log("CLEANUP COMPLETE Mirsa-only extraction files and proven-absent journals; no system descriptors removed.")
        }
    }
}

/// Bounded app-private evidence, independent of the transient on-screen log.
/// Never read on-disk history as instructions or as deletion/ownership authority.
enum MirsaWallpaperEvidence {
    static let lock = NSLock()
    static let maxEvents = 256, maxLine = 2048, maxBytes = 2 * 1024 * 1024
    static let session = UUID().uuidString
    static var file: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MirsaWallpaperEvidence", isDirectory: true)
            .appendingPathComponent("history.json")
    }
    static func read(at url: URL) throws -> [String] {
        try MirsaWallpaperJournal.safeLocal(url)
        var node = stat()
        let result = lstat(url.path, &node), error = errno
        if result == -1 && error == ENOENT { return [] }
        guard result == 0, (node.st_mode & S_IFMT) == S_IFREG, node.st_nlink == 1,
              node.st_size <= Int64(maxBytes) else {
            throw PosterBoardStore.failure("Wallpaper evidence is unavailable or unsafe.")
        }
        return Array(try JSONDecoder().decode([String].self, from: Data(contentsOf: url)).suffix(maxEvents))
            .map { String($0.prefix(maxLine)) }
    }
    static func append(_ line: String, at url: URL) throws {
        lock.lock(); defer { lock.unlock() }
        try MirsaWallpaperJournal.safeLocal(url.deletingLastPathComponent())
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var events = try read(at: url)
        events.append(String(line.prefix(maxLine)))
        events = Array(events.suffix(maxEvents))
        try JSONEncoder().encode(events).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
    @discardableResult static func record(_ line: String) -> Bool {
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
        let stamp = ISO8601DateFormatter().string(from: Date())
        let text = stamp + " uptime=" + String(ProcessInfo.processInfo.systemUptime) +
            " build=" + build + " session=" + session + " " + line
        do { try append(text, at: file); return true } catch { return false }
    }
    static func restored() -> [String] {
        lock.lock(); defer { lock.unlock() }
        do { return try read(at: file).map { "HISTORY " + $0 } }
        catch { return ["HISTORY UNAVAILABLE " + error.localizedDescription] }
    }
    static func captureVisible(_ lines: [String]) {
        for line in lines where ["REFRESH", "DELETE", "CLEANUP", "CUSTOM LIST", "Removed absent", "❌ Error:"]
            .contains(where: { line.hasPrefix($0) }) {
            record(line)
        }
    }
    /// Exact root metadata only, using access already granted by the caller.
    /// ENOENT is logged verbatim; no purge/copy-success conclusion is inferred.
    static func observe(_ target: URL, context: String, log: (String) -> Void) {
        var node = stat()
        let result = lstat(target.path, &node), error = result == 0 ? 0 : errno
        let line = "OBSERVE " + context + " path=" + MirsaWallpaperDiagnostics.quoted(target.path) +
            " rc=" + String(result) + " errno=" + String(error) +
            " mode=" + String(node.st_mode) + " device=" + String(node.st_dev) +
            " inode=" + String(node.st_ino) + " mtime=" + String(node.st_mtimespec.tv_sec)
        record(line)
        log(line)
    }
}
