import Foundation
import Darwin

/// Descriptor-relative cleanup of disposable container storage, never persistent Library/Documents.
/// Unknown current-process files fail closed: only unchanged files from BEFORE this process are
/// eligible. This preserves legacy operations that have not migrated to managed workspaces yet.
enum MirsaContainerCleanup {
    static var processStart = Date()
    static func captureProcessStart() { processStart = Date() }

    enum Scope { case temporary, caches }
    struct Result { var bytes: Int64 = 0; var removed = 0 }
    private struct Identity: Equatable {
        let device: dev_t
        let inode: ino_t
        let mode: mode_t
        let size: off_t
        let modifiedSeconds: Int
        let modifiedNanos: Int
        let changedSeconds: Int
        let changedNanos: Int
        let bornSeconds: Int
        let bornNanos: Int
        init(_ s: stat) {
            device = s.st_dev; inode = s.st_ino; mode = s.st_mode; size = s.st_size
            modifiedSeconds = Int(s.st_mtimespec.tv_sec); modifiedNanos = Int(s.st_mtimespec.tv_nsec)
            changedSeconds = Int(s.st_ctimespec.tv_sec); changedNanos = Int(s.st_ctimespec.tv_nsec)
            bornSeconds = Int(s.st_birthtimespec.tv_sec); bornNanos = Int(s.st_birthtimespec.tv_nsec)
        }
        var born: TimeInterval { Double(bornSeconds) + Double(bornNanos) / 1_000_000_000 }
        var changed: TimeInterval { Double(changedSeconds) + Double(changedNanos) / 1_000_000_000 }
    }
    private struct Link { let parent: Int32; let name: String; let identity: Identity }

    // Saved imports/exports and system-owned stores are never disposable, even if a legacy
    // version happened to put one beneath tmp or Caches. Inbox can exist before cold launch.
    private static func protected(_ name: String) -> Bool {
        let n = name.lowercased()
        return n.hasSuffix("-inbox") || n == "inbox" || n.hasPrefix("com.apple.") ||
            n.hasPrefix("com.apple-") || n.hasPrefix(".com.apple") ||
            n.hasPrefix("cfnetworkdownload") || n.hasPrefix("nsurlsession") ||
            n.hasPrefix("nsird_") || n.hasPrefix(".nsird_") || n == "webkit" || n == "snapshots" ||
            n == "temporaryitems" || n.contains("document being saved") ||
            n.hasPrefix("cache.db") || n.hasSuffix(".db") || n.hasSuffix(".db-wal") ||
            n.hasSuffix(".db-shm") ||
            ["documents", "library", "application support", "projects", "mirsa-projects",
             "personalprojects", "mirsapersonalprojects", "savedipas", "saved-ipas", "savedipa",
             "downloads", "originals", "backups", "mirsasignedexports", "aircardapps",
             "mirsaforge", "ipatweaklibrary",
             "mirsa-tweak-library", "mirsatweaklibrary", "mirsabundlefiles", "personalappslibrary", "mirsapersonalapps", "download inbox"].contains(n)
    }

    // Only recognizable disposable root leftovers in Caches. URLCache/WebKit/system databases
    // are not guessed at or reset. tmp itself is entirely disposable except the denylist above.
    private static func disposableCache(_ name: String) -> Bool {
        let n = name.lowercased()
        return ["ipa", "zip", "tmp", "temp"].contains((n as NSString).pathExtension) ||
            ["mirsa-managed", "mirsa-screenshots", "mirsascreenshots", "unzip-", "extract-",
             "sign-", "signing-", "cert-install-", "personal-url-", "store-download-",
             "store-server-", "container-extract-", "forgeinj-", "mirsa-open-in-"].contains {
                n == $0 || n.hasPrefix($0)
            }
    }

    private static func info(_ parent: Int32, _ name: String) -> stat? {
        var s = stat()
        guard fstatat(parent, name, &s, AT_SYMLINK_NOFOLLOW) == 0 else { return nil }
        return s
    }
    private static func sameNode(_ a: stat, _ b: Identity) -> Bool {
        a.st_dev == b.device && a.st_ino == b.inode && (a.st_mode & S_IFMT) == (b.mode & S_IFMT)
    }
    private static func intact(_ chain: [Link]) -> Bool {
        chain.allSatisfy { link in
            guard let s = info(link.parent, link.name) else { return false }
            return sameNode(s, link.identity)
        }
    }

    /// Open EVERY path component without following links, not merely the last component.
    /// Resolve only Darwin's known /var and /tmp aliases. Arbitrary ancestor links fail closed.
    private static func openRoot(_ url: URL) -> (Int32, [Int32], [Link], String)? {
        guard url.isFileURL else { return nil }
        var parts = url.standardizedFileURL.pathComponents.dropFirst().map { $0 }
        if parts.first == "var" { parts.insert("private", at: 0) }
        else if parts.first == "tmp" { parts.insert("private", at: 0) }
        guard !parts.isEmpty else { return nil }
        let first = open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
        guard first >= 0 else { return nil }
        var descriptors = [first], chain: [Link] = []
        var parent = first
        for name in parts {
            guard name != ".", name != "..", !name.contains("/"),
                  let s = info(parent, name), (s.st_mode & S_IFMT) == S_IFDIR else {
                descriptors.forEach { close($0) }; return nil
            }
            let next = openat(parent, name, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
            var opened = stat()
            guard next >= 0 else { descriptors.forEach { close($0) }; return nil }
            guard fstat(next, &opened) == 0, sameNode(opened, Identity(s)) else {
                close(next); descriptors.forEach { close($0) }; return nil
            }
            chain.append(Link(parent: parent, name: name, identity: Identity(s)))
            descriptors.append(next); parent = next
        }
        return (parent, descriptors, chain, "/" + parts.joined(separator: "/"))
    }

    /// Caller serializes this with managed begin/end/leases. No recursive removeItem, no
    /// symlink traversal, no directory removals, no unregistered new-file deletion.
    /// beforeDelete is a deterministic race fixture hook; production always leaves it nil.
    static func scan(root: URL, scope: Scope, delete: Bool, cutoff: Date,
                     protectedPaths: Set<String>, now: Date = Date(),
                     beforeDelete: ((URL) -> Void)? = nil) -> Result {
        guard let (fd, descriptors, initialChain, canonical) = openRoot(root) else { return Result() }
        defer { descriptors.forEach { close($0) } }
        let blocked = protectedPaths.map { URL(fileURLWithPath: $0).resolvingSymlinksInPath().standardizedFileURL.path }
        var result = Result()
        var rootStat = stat()
        guard fstat(fd, &rootStat) == 0 else { return result }
        let rootDevice = rootStat.st_dev
        let limit = cutoff.timeIntervalSince1970
        let openNodes = delete ? openFileNodes() : Set<String>()

        func leased(_ path: String) -> Bool {
            blocked.contains { path == $0 || path.hasPrefix($0 + "/") || $0.hasPrefix(path + "/") }
        }
        func walk(_ directory: Int32, path: String, chain: [Link], depth: Int) {
            guard depth < 48, intact(chain) else { return }
            // dup shares directory offsets, but each descriptor is enumerated exactly once.
            let copy = dup(directory)
            guard copy >= 0 else { return }
            guard let stream = fdopendir(copy) else { close(copy); return }
            defer { closedir(stream) }
            while let entry = readdir(stream) {
                let name = withUnsafePointer(to: &entry.pointee.d_name) {
                    $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXNAMLEN) + 1) { String(cString: $0) }
                }
                guard name != ".", name != "..", !name.contains("/"), !protected(name),
                      !(depth == 0 && scope == .caches && !disposableCache(name)),
                      let s = info(directory, name), s.st_dev == rootDevice else { continue }
                let current = path + "/" + name
                let identity = Identity(s)
                let type = s.st_mode & S_IFMT
                if type == S_IFDIR {
                    let child = openat(directory, name, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
                    guard child >= 0 else { continue }
                    var opened = stat()
                    if fstat(child, &opened) == 0, sameNode(opened, identity) {
                        walk(child, path: current, chain: chain + [Link(parent: directory, name: name, identity: identity)], depth: depth + 1)
                    }
                    close(child)
                } else if type == S_IFREG {
                    result.bytes += max(0, Int64(s.st_size))
                    // ctime, NOT mtime: copied/unzipped files can preserve an ancient mtime.
                    // Also avoid unlinking a still-open URLSession/legacy file.
                    guard delete, let openNodes, now.timeIntervalSince1970 >= limit,
                          identity.changed < limit, identity.born < limit, !leased(current) else { continue }
                    let file = openat(directory, name, O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK)
                    guard file >= 0 else { continue }
                    var opened = stat()
                    let matches = fstat(file, &opened) == 0 && Identity(opened) == identity
                    close(file)
                    guard matches else { continue }
                    beforeDelete?(URL(fileURLWithPath: current))
                    guard intact(chain), let fresh = info(directory, name),
                          Identity(fresh) == identity, !leased(current),
                          !openNodes.contains(nodeKey(fresh)) else { continue }
                    if unlinkat(directory, name, 0) == 0 { result.removed += 1 }
                }
                // Symlinks and other special files are neither followed nor deleted.
            }
        }
        walk(fd, path: canonical, chain: initialChain, depth: 0)
        return result
    }

    private static func nodeKey(_ s: stat) -> String { "\(s.st_dev):\(s.st_ino)" }
    private static func openFileNodes() -> Set<String>? {
        var nodes = Set<String>()
        let maximum = getdtablesize()
        // An abnormal descriptor limit is not an excuse to scan partially and delete.
        guard maximum > 0, maximum <= 65536 else { return nil }
        for descriptor in 0..<maximum {
            var value = stat()
            if fstat(descriptor, &value) == 0 { nodes.insert(nodeKey(value)) }
        }
        return nodes
    }
}
