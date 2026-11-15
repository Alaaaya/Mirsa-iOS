import Foundation
import Darwin

enum MirsaPosterCopy {
 static let provider = "com.apple.WallpaperKit.CollectionsPoster"
 static let store = "Library/Application Support/PRBPosterExtensionDataStore"
    /// Select only an existing numeric-version CollectionsPoster descriptors dir.
    /// Unlike the legacy layout() helper, never grant/list every provider.
    static func destination(lease: PosterBoardLease) throws -> String {
        let fm = FileManager.default
        guard lease.grant(store) else { throw PosterBoardStore.failure("Datastore grant failed.") }
        let root = lease.effectiveURL.appendingPathComponent(store)
        let versions = try fm.contentsOfDirectory(atPath: root.path).filter {
            !$0.isEmpty && $0.utf8.allSatisfy { $0 >= 48 && $0 <= 57 } && Int($0) != nil
        }.sorted { (Int($0) ?? 0) > (Int($1) ?? 0) }
        guard versions.count <= 8 else { throw PosterBoardStore.failure("Ambiguous datastore versions; nothing written.") }
        for version in versions {
            let parts = [store + "/" + version, store + "/" + version + "/Extensions",
                         store + "/" + version + "/Extensions/" + provider,
                         store + "/" + version + "/Extensions/" + provider + "/descriptors"]
            var valid = true
            for part in parts {
                let url = lease.effectiveURL.appendingPathComponent(part)
                guard lease.grant(part), lease.permits(url) else { valid = false; break }
                do {
                    guard try url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else { valid = false; break }
                } catch {
                    let e = error as NSError
                    if e.domain == NSCocoaErrorDomain &&
                        (e.code == NSFileNoSuchFileError || e.code == NSFileReadNoSuchFileError) {
                        valid = false; break
                    }
                    throw error
                }
            }
            if valid { return parts[3] }
        }
        throw PosterBoardStore.failure("No existing CollectionsPoster descriptors directory. Refusing to create/guess provider registration.")
    }

    static func relativePaths(_ root: URL) throws -> Set<String> {
        var error: Error?
        let canonicalRoot = root.resolvingSymlinksInPath().standardizedFileURL
        let prefix = canonicalRoot.path + "/"
        guard let entries = FileManager.default.enumerator(at: canonicalRoot, includingPropertiesForKeys: [.isSymbolicLinkKey, .isRegularFileKey, .isDirectoryKey],
            errorHandler: { _, failure in error = failure; return false }) else {
            throw PosterBoardStore.failure("Cannot enumerate owned tree.")
        }
        var paths = Set<String>()
        for case let url as URL in entries {
            let info = try url.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey, .isDirectoryKey])
            guard info.isSymbolicLink != true, info.isRegularFile == true || info.isDirectory == true else {
                throw PosterBoardStore.failure("Redirected owned tree.")
            }
            let entryPath = url.resolvingSymlinksInPath().standardizedFileURL.path
            guard entryPath.hasPrefix(prefix) else { throw PosterBoardStore.failure("Owned entry escaped canonical root. root=\(prefix) entry=\(entryPath) raw=\(url.path)") }
            paths.insert(String(entryPath.dropFirst(prefix.count)))
        }
        if let error { throw error }
        return paths
    }

    static func typedPaths(_ root: URL) throws -> [String] {
        try relativePaths(root).map { relative in
            let info = try root.appendingPathComponent(relative).resourceValues(forKeys: [.isDirectoryKey])
            return (info.isDirectory == true ? "D:" : "F:") + relative
        }.sorted()
    }

    /// Compare permission/date metadata only, not ownership, ACL or protection.
    static func verifyCopyAttributes(source: URL, target: URL) throws {
        let fm = FileManager.default
        let paths = try relativePaths(source).union([""])
        for path in paths {
            let a = try fm.attributesOfItem(atPath: source.appendingPathComponent(path).path)
            let b = try fm.attributesOfItem(atPath: target.appendingPathComponent(path).path)
            guard let am = a[.posixPermissions] as? NSNumber, let bm = b[.posixPermissions] as? NSNumber,
                  am == bm, let ad = a[.modificationDate] as? Date, let bd = b[.modificationDate] as? Date,
                  abs(ad.timeIntervalSince(bd)) <= 0.001 else {
                throw PosterBoardStore.failure("Whole-root permissions/mtime readback mismatch at \(path).")
            }
        }
    }

    /// Copy the WHOLE root through Foundation, including root metadata. Never
    /// replace an existing path. Failure during copy has uncertain ownership,
    /// so leave any partial tree for journal review instead of deleting it.
    static func copyExclusive(source: URL, target: URL, expected: [String: String], log: (String) -> Void) throws {
        let fm = FileManager.default
        _ = try PosterBoardStore.manifest(source) // reject symlinks before copying
        var existing = stat()
        guard lstat(target.path, &existing) != 0, errno == ENOENT else {
            throw PosterBoardStore.failure("Descriptor destination exists or is uncertain; preserved unchanged.")
        }
        do { try fm.copyItem(at: source, to: target) }
        catch {
            log("CLEANUP ERROR · whole-root copy failed; any partial destination retained, no ownership assumed")
            throw error
        }
        var owned = stat()
        guard lstat(target.path, &owned) == 0, (owned.st_mode & S_IFMT) == S_IFDIR else {
            throw PosterBoardStore.failure("Cannot prove copied directory ownership; retained for journal review.")
        }
        do {
            try verifyCopyAttributes(source: source, target: target)
            let readback = try PosterBoardStore.manifest(target)
            let sourcePaths = try relativePaths(source)
            let targetPaths = try relativePaths(target)
            guard sourcePaths == targetPaths else {
                throw PosterBoardStore.failure("Whole-root path readback mismatch.")
            }
            guard readback == expected else {
                throw PosterBoardStore.failure("Descriptor readback mismatch. expected=\(expected) actual=\(readback)")
            }
        } catch {
            var current = stat()
            let sameRoot = lstat(target.path, &current) == 0 &&
                current.st_dev == owned.st_dev && current.st_ino == owned.st_ino &&
                (current.st_mode & S_IFMT) == S_IFDIR
            // Only exact complete source files may be removed, never an unknown
            // partial write or files added by PosterBoard. Preserve on uncertainty.
            let actual = try? PosterBoardStore.manifest(target)
            let knownFiles = actual.map { found in found.allSatisfy { expected[$0.key] == $0.value } } ?? false
            let expectedPaths = try? relativePaths(source)
            let actualPaths = try? relativePaths(target)
            let knownPaths = expectedPaths.flatMap { wanted in actualPaths.map { $0.isSubset(of: wanted) } } ?? false
            let known = knownFiles && knownPaths
            if sameRoot && known {
                do { try fm.removeItem(at: target); log("INSTALL TEST ROLLBACK · only owned verified-copy directory removed") }
                catch { log("CLEANUP ERROR · retained owned descriptor for journal review") }
            } else {
                log("CLEANUP ERROR · rollback refused uncertain ownership/content; preserve pending journal and do not retry")
            }
            throw error
        }
    }
}
