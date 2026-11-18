import Foundation
import Darwin
import CryptoKit

/// Evidence only. No classifier, system mutation, permission bypass or delete authority.
enum MirsaWallpaperDiagnostics {
    final class Budget {
        var nodes = 0, bytes = 0, grants = 0
        var granted = Set<String>()
        let maxNodes: Int, maxBytes: Int, maxGrants: Int, deadline: TimeInterval
        init(nodes: Int = 128, bytes: Int = 512 * 1024, grants: Int = 128, seconds: Double = 5) {
            maxNodes = nodes; maxBytes = bytes; maxGrants = grants
            deadline = ProcessInfo.processInfo.systemUptime + seconds
        }
        func check() throws {
            guard nodes < maxNodes, bytes <= maxBytes, grants < maxGrants,
                  ProcessInfo.processInfo.systemUptime < deadline else {
                throw NSError(domain: "MirsaWallpaperDiagnosticBudget", code: Int(E2BIG))
            }
        }
    }
    struct Node {
        let kind: String
        let hash: String?
        let error: Int32
    }
    struct Inventory {
        var nodes: [String: Node] = [:]
        var complete = true
        var error: Int32 = 0
    }
    static func quoted(_ s: String) -> String {
        // JSON escaping keeps file names and values on a single unambiguous line.
        let bounded = String(s.prefix(1024))
        let data = try? JSONEncoder().encode(bounded)
        return data.flatMap { String(data: $0, encoding: .utf8) } ?? "\"\""
    }
    static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
    private static func failure(_ code: Int32) -> NSError {
        NSError(domain: NSPOSIXErrorDomain, code: Int(code))
    }
    private static func stable(_ a: stat, _ b: stat) -> Bool {
        a.st_dev == b.st_dev && a.st_ino == b.st_ino && a.st_mode == b.st_mode &&
        a.st_size == b.st_size && a.st_nlink == b.st_nlink &&
        a.st_mtimespec.tv_sec == b.st_mtimespec.tv_sec && a.st_mtimespec.tv_nsec == b.st_mtimespec.tv_nsec &&
        a.st_ctimespec.tv_sec == b.st_ctimespec.tv_sec && a.st_ctimespec.tv_nsec == b.st_ctimespec.tv_nsec
    }
    static func kind(_ s: stat) -> String {
        switch s.st_mode & S_IFMT {
        case S_IFREG: return "file"
        case S_IFDIR: return "directory"
        case S_IFLNK: return "symlink"
        default: return "special"
        }
    }
    /// All descendants opened relative to pinned no-follow directory descriptors.
    final class Reader {
        let root: URL, fd: Int32, original: stat, budget: Budget
        let access: (String) throws -> Void
        init(root: URL, budget: Budget, access: @escaping (String) throws -> Void = { _ in }) throws {
            self.root = root; self.budget = budget; self.access = access
            var before = stat()
            guard lstat(root.path, &before) == 0 else { throw MirsaWallpaperDiagnostics.failure(errno) }
            guard MirsaWallpaperDiagnostics.kind(before) == "directory" else { throw MirsaWallpaperDiagnostics.failure(EINVAL) }
            let opened = open(root.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
            guard opened >= 0 else { throw MirsaWallpaperDiagnostics.failure(errno) }
            var pinned = stat()
            guard fstat(opened, &pinned) == 0, MirsaWallpaperDiagnostics.stable(before, pinned) else {
                Darwin.close(opened); throw MirsaWallpaperDiagnostics.failure(ESTALE)
            }
            fd = opened; original = pinned
        }
        deinit { Darwin.close(fd) }
        func verify() throws {
            var final = stat()
            guard lstat(root.path, &final) == 0, MirsaWallpaperDiagnostics.stable(original, final) else { throw MirsaWallpaperDiagnostics.failure(ESTALE) }
        }
        func withParent<T>(_ relative: String, _ body: (Int32, String) throws -> T) throws -> T {
            guard MirsaCustomWallpapers.validRelative(relative) else { throw MirsaWallpaperDiagnostics.failure(EINVAL) }
            try budget.check(); budget.nodes += 1
            let parts = relative.split(separator: "/").map(String.init)
            var parent = dup(fd)
            guard parent >= 0 else { throw MirsaWallpaperDiagnostics.failure(errno) }
            defer { Darwin.close(parent) }
            var prefix = ""
            for part in parts.dropLast() {
                prefix += (prefix.isEmpty ? "" : "/") + part
                try access(prefix)
                let next = openat(parent, part, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
                guard next >= 0 else { throw MirsaWallpaperDiagnostics.failure(errno) }
                Darwin.close(parent); parent = next
            }
            try access(relative)
            return try body(parent, parts.last!)
        }
        func node(_ relative: String) throws -> stat {
            try withParent(relative) { parent, name in
                var s = stat()
                guard fstatat(parent, name, &s, AT_SYMLINK_NOFOLLOW) == 0 else { throw MirsaWallpaperDiagnostics.failure(errno) }
                return s
            }
        }
        func names(_ relative: String?, limit: Int) throws -> [String] {
            try budget.check()
            let opened: Int32
            if let relative {
                opened = try withParent(relative) { parent, name in
                    let result = openat(parent, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
                    guard result >= 0 else { throw MirsaWallpaperDiagnostics.failure(errno) }
                    return result
                }
            } else { opened = dup(fd) }
            guard opened >= 0 else { throw MirsaWallpaperDiagnostics.failure(errno) }
            var before = stat()
            guard fstat(opened, &before) == 0 else { let e = errno; Darwin.close(opened); throw MirsaWallpaperDiagnostics.failure(e) }
            guard let directory = fdopendir(opened) else { let e = errno; Darwin.close(opened); throw MirsaWallpaperDiagnostics.failure(e) }
            defer { closedir(directory) }
            var names: [String] = []
            while true {
                try budget.check()
                errno = 0
                guard let entry = readdir(directory) else {
                    if errno != 0 { throw MirsaWallpaperDiagnostics.failure(errno) }; break
                }
                let name = withUnsafePointer(to: &entry.pointee.d_name) {
                    $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXNAMLEN) + 1) { String(cString: $0) }
                }
                if name == "." || name == ".." { continue }
                guard MirsaCustomWallpapers.validRelative(name), names.count < limit else { throw MirsaWallpaperDiagnostics.failure(E2BIG) }
                names.append(name)
            }
            var after = stat()
            guard fstat(dirfd(directory), &after) == 0, MirsaWallpaperDiagnostics.stable(before, after) else {
                throw MirsaWallpaperDiagnostics.failure(ESTALE)
            }
            return names.sorted()
        }
        func read(_ relative: String, limit: Int) throws -> Data {
            try withParent(relative) { parent, name in
                var before = stat()
                guard fstatat(parent, name, &before, AT_SYMLINK_NOFOLLOW) == 0 else { throw MirsaWallpaperDiagnostics.failure(errno) }
                guard MirsaWallpaperDiagnostics.kind(before) == "file", before.st_nlink == 1, before.st_size >= 0,
                      before.st_size <= Int64(limit),
                      before.st_size <= Int64(budget.maxBytes - budget.bytes) else { throw MirsaWallpaperDiagnostics.failure(EFBIG) }
                let opened = openat(parent, name, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
                guard opened >= 0 else { throw MirsaWallpaperDiagnostics.failure(errno) }
                defer { Darwin.close(opened) }
                var pinned = stat()
                guard fstat(opened, &pinned) == 0, MirsaWallpaperDiagnostics.stable(before, pinned) else { throw MirsaWallpaperDiagnostics.failure(ESTALE) }
                var data = Data(), buffer = [UInt8](repeating: 0, count: 32 * 1024)
                while true {
                    try budget.check()
                    let count = buffer.withUnsafeMutableBytes { Darwin.read(opened, $0.baseAddress!, $0.count) }
                    guard count >= 0 else { throw MirsaWallpaperDiagnostics.failure(errno) }
                    if count == 0 { break }
                    guard count <= limit - data.count, count <= budget.maxBytes - budget.bytes else { throw MirsaWallpaperDiagnostics.failure(EFBIG) }
                    data.append(contentsOf: buffer.prefix(count)); budget.bytes += count
                }
                var after = stat(), final = stat()
                guard fstat(opened, &after) == 0, fstatat(parent, name, &final, AT_SYMLINK_NOFOLLOW) == 0,
                      MirsaWallpaperDiagnostics.stable(pinned, after), MirsaWallpaperDiagnostics.stable(after, final), data.count == Int(final.st_size) else { throw MirsaWallpaperDiagnostics.failure(ESTALE) }
                return data
            }
        }
    }
    static func whitelist(_ dictionary: [String: Any], keys: [String]) -> [String: String] {
        var out: [String: String] = [:]
        for key in keys {
            if let value = dictionary[key] as? String { out[key] = String(value.prefix(160)) }
            else if let value = dictionary[key] as? NSNumber { out[key] = value.stringValue }
        }
        return out
    }
    static func shallow(_ reader: Reader, log: (String) -> Void) {
        func emit(_ path: String, keys: [String]?, limit: Int) {
            do {
                let node = try reader.node(path)
                log("DIAG NODE path=" + quoted(path) + " type=" + kind(node) + " device=" + String(node.st_dev) + " inode=" + String(node.st_ino) + " errno=0")
                let data = try reader.read(path, limit: limit)
                log("DIAG HASH path=" + quoted(path) + " actual=" + digest(data))
                if let keys {
                    guard let dict = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else { return }
                    for (key, value) in whitelist(dict, keys: keys).sorted(by: { $0.key < $1.key }) {
                        log("DIAG FIELD path=" + quoted(path) + " key=" + quoted(key) + " value=" + quoted(value))
                    }
                    // Only explicitly approved asset dictionary fields, never arbitrary metadata.
                    if path.hasSuffix("/Wallpaper.plist"),
                       let assets = dict["assets"] as? [String: Any],
                       let group = assets["lockAndHome"] as? [String: Any],
                       let item = group["default"] as? [String: Any] {
                        for (key, value) in whitelist(item, keys: ["type", "identifier", "name", "backgroundAnimationFileName", "floatingAnimationFileNameKey", "foregroundAnimationFileName"]).sorted(by: { $0.key < $1.key }) {
                            log("DIAG ASSET key=" + quoted(key) + " value=" + quoted(value))
                        }
                    }
                } else if let text = String(data: data, encoding: .utf8) {
                    let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    let valid = path == MirsaPosterNormalize.rawName ?
                        (!value.isEmpty && value.utf8.count <= 32 && value.utf8.allSatisfy { $0 >= 48 && $0 <= 57 }) :
                        (!value.isEmpty && value.utf8.count <= 80 && value.utf8.allSatisfy {
                            ($0 >= 65 && $0 <= 90) || ($0 >= 97 && $0 <= 122) || ($0 >= 48 && $0 <= 57) || $0 == 46 || $0 == 95 || $0 == 45
                        })
                    log("DIAG VALUE path=" + quoted(path) + " value=" + quoted(valid ? value : "<non-identity value redacted>"))
                }
            } catch { log("DIAG UNREAD path=" + quoted(path) + " errno=" + String((error as NSError).code)) }
        }
        emit("com.apple.posterkit.role.identifier", keys: nil, limit: 256)
        emit(MirsaPosterNormalize.rawName, keys: nil, limit: 256)
        do {
            let versions = try reader.names("versions", limit: 8)
            log("DIAG VERSIONS " + versions.map(quoted).joined(separator: ","))
            let numeric = versions.filter { !$0.isEmpty && $0.utf8.allSatisfy { $0 >= 48 && $0 <= 57 } }
            for version in numeric.suffix(2) {
                let contents = "versions/" + version + "/contents"
                let names = try reader.names(contents, limit: 16)
                log("DIAG CONTENTS path=" + quoted(contents) + " names=" + names.map(quoted).joined(separator: ","))
                emit(contents + "/" + MirsaPosterNormalize.userInfoName,
                     keys: ["wallpaperRepresentingIdentifier", "wallpaperRepresentingFileName"], limit: 16 * 1024)
                for package in names.filter({ $0.hasSuffix(".wallpaper") }).prefix(2) {
                    emit(contents + "/" + package + "/Wallpaper.plist",
                         keys: ["name", "identifier", "family", "logicalScreenClass", "version"], limit: 64 * 1024)
                }
            }
            try reader.budget.check()
            try reader.verify()
        } catch { log("DIAG PARTIAL errno=" + String((error as NSError).code) + " no provenance inferred") }
    }
    /// Selected journal only. Bounded full path/hash inventory is necessary to detect
    /// additions as well as changed original files. Never run this walk on list refresh.
    static func inventory(_ reader: Reader) -> Inventory {
        var result = Inventory()
        func walk(_ directory: String?, depth: Int) throws {
            guard depth <= 16 else { throw failure(E2BIG) }
            for name in try reader.names(directory, limit: 128) {
                let path = directory.map { $0 + "/" + name } ?? name
                do {
                    let node = try reader.node(path), type = kind(node)
                    result.nodes[path] = Node(kind: type, hash: nil, error: 0)
                    if type == "directory" {
                        try walk(path, depth: depth + 1)
                        guard stable(node, try reader.node(path)) else { throw failure(ESTALE) }
                    }
                    else if type == "file" {
                        result.nodes[path] = Node(kind: type, hash: digest(try reader.read(path, limit: 16 * 1024 * 1024)), error: 0)
                    } else { result.complete = false }
                } catch {
                    result.complete = false
                    let prior = result.nodes[path]
                    result.nodes[path] = Node(kind: prior?.kind ?? "unreadable", hash: nil, error: Int32((error as NSError).code))
                    // Budget exhaustion stops this selected inventory; never implies removal.
                    if reader.budget.nodes >= reader.budget.maxNodes || reader.budget.bytes >= reader.budget.maxBytes ||
                        ProcessInfo.processInfo.systemUptime >= reader.budget.deadline { throw error }
                }
            }
        }
        do { try walk(nil, depth: 0); try reader.verify() }
        catch { result.complete = false; result.error = Int32((error as NSError).code) }
        return result
    }
    static func diff(expected: [String: String], paths: [String], actual: Inventory) -> [String] {
        let originals = Dictionary(paths.prefix(512).compactMap { typed -> (String, String)? in
            guard typed.hasPrefix("F:") || typed.hasPrefix("D:") else { return nil }
            return (String(typed.dropFirst(2)), typed.hasPrefix("F:") ? "file" : "directory")
        }, uniquingKeysWith: { first, _ in first })
        let all = Set(originals.keys).union(expected.keys.sorted().prefix(512)).union(actual.nodes.keys)
        var lines = ["DIAG DIFF journalTruncated=" + String(paths.count > 512 || expected.count > 512) + " complete=" + String(actual.complete) + " errno=" + String(actual.error) + " (hash/path evidence only; no deletion rules changed)"]
        for path in all.sorted() {
            let oldType = originals[path] ?? (expected[path] != nil ? "file" : "absent")
            let oldHash = expected[path] ?? "-"
            let node = actual.nodes[path]
            let type = node?.kind ?? (actual.complete ? "absent" : "unobserved")
            let hash = node?.hash ?? "-"
            let status: String
            if oldType == "absent" { status = "added" }
            else if node == nil { status = actual.complete ? "removed" : "unobserved" }
            else if node?.error != 0 { status = "unreadable" }
            else if oldType != type || (oldType == "file" && oldHash != hash) { status = "modified" }
            else { status = "unchanged" }
            lines.append("DIAG DIFF status=" + status + " path=" + quoted(path) + " expectedType=" + oldType +
                         " actualType=" + type + " expectedHash=" + oldHash + " actualHash=" + hash +
                         " errno=" + String(node?.error ?? (actual.complete ? ENOENT : EAGAIN)))
        }
        return lines
    }
    static func reader(relative: String, lease: PosterBoardLease, budget: Budget) throws -> Reader {
        guard MirsaCustomWallpapers.validRelative(relative) else { throw failure(EINVAL) }
        func grant(_ path: String) throws {
            try budget.check()
            var prefix = ""
            for part in path.split(separator: "/") {
                prefix += (prefix.isEmpty ? "" : "/") + part
                if budget.granted.contains(prefix) { continue }
                try budget.check(); budget.grants += 1
                guard lease.grant(prefix), lease.permits(lease.effectiveURL.appendingPathComponent(prefix)) else { throw failure(EACCES) }
                budget.granted.insert(prefix)
            }
        }
        // Charge only actual distinct relative grant requests, not cached ancestors.
        var granted = Set<String>()
        func access(_ path: String) throws {
            if granted.contains(path) { return }
            try grant(path); granted.insert(path)
        }
        try access(relative)
        return try Reader(root: lease.effectiveURL.appendingPathComponent(relative), budget: budget) { subpath in
            try access(relative + "/" + subpath)
        }
    }
    static func catalogProbe(log: (String) -> Void) {
        let root = URL(fileURLWithPath: "/Library/Wallpaper/Collections")
        // No lease grants here, no alternate path, no traversal on failure.
        var s = stat()
        guard lstat(root.path, &s) == 0 else { log("DIAG CATALOG errno=" + String(errno) + " stopped"); return }
        guard PosterBoardStore.unredirected(root) else { log("DIAG CATALOG redirected or inaccessible; stopped"); return }
        guard kind(s) == "directory" else { log("DIAG CATALOG wrong node; stopped"); return }
        let fd = open(root.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard fd >= 0 else { log("DIAG CATALOG errno=" + String(errno) + " stopped"); return }
        defer { Darwin.close(fd) }
        var catalog = statfs(), system = statfs(), pinned = stat()
        guard fstat(fd, &pinned) == 0, stable(s, pinned),
              fstatfs(fd, &catalog) == 0, statfs("/System/Library", &system) == 0 else {
            log("DIAG CATALOG mount verification failed errno=" + String(errno) + " stopped"); return
        }
        let readonly = (UInt32(catalog.f_flags) & UInt32(MNT_RDONLY)) != 0
        let same = catalog.f_fsid.val.0 == system.f_fsid.val.0 && catalog.f_fsid.val.1 == system.f_fsid.val.1
        log("DIAG CATALOG readable=true readonly=" + String(readonly) + " sameSystemFS=" + String(same) + " inventoryNotRead=true; no classification")
    }
    /// Called off-main by management. Wait for list/thumbnail access to finish
    /// under the SAME recursive lock; never open a second lease while it is busy.
    /// This seam also exercises waiting/cancellation without device access.
    static func withInspectionAccess<T>(timeout: TimeInterval = 120,
                                         isCancelled: () -> Bool = { false },
                                         onWait: () -> Void = {},
                                         _ body: () throws -> T) throws -> T {
        try MirsaWallpaperJournal.exclusiveWaiting(timeout: timeout, isCancelled: isCancelled,
                                                    onWait: onWait, body)
    }
    static func inspect(_ item: MirsaCustomWallpapers.Item, log: @escaping (String) -> Void) throws {
        try withInspectionAccess(onWait: { log("DIAG WAIT current wallpaper access; no diagnostic lease opened yet") }) {
            let lease = try PosterBoardLease(path: item.container, log: { _ in })
            defer { try? lease.close() }
            try PosterBoardStore.validateIdentity(lease.effectiveURL, lease: lease)
            let budget = Budget(nodes: 512, bytes: 64 * 1024 * 1024, grants: 512, seconds: 12)
            let source = try reader(relative: item.relative, lease: lease, budget: budget)
            log("DIAG SELECTED uuid=" + item.id + " relative=" + quoted(item.relative) + " device=" + String(source.original.st_dev) + " inode=" + String(source.original.st_ino) + " evidence only")
            let records = try MirsaWallpaperJournal.records()
            if let record = records.first(where: { $0.id == item.id && $0.container == item.container && $0.relative == item.relative }) {
                log("DIAG JOURNAL rootMatches=" + String(UInt64(source.original.st_dev) == record.device && UInt64(source.original.st_ino) == record.inode))
                for line in diff(expected: record.expected, paths: record.paths ?? [], actual: inventory(source)) { log(line) }
            } else { shallow(source, log: log) }
            try lease.close()
            log("DIAG DONE read-only; copy Flash Log. Unknown is not custom; no delete rules relaxed.")
        }
    }
}
