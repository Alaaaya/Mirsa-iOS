import Foundation
import CryptoKit

@_silgen_name("mirsa_pb_access_acquire")
private func acquirePosterBoardAccess(_ path: UnsafePointer<CChar>, _ error: UnsafeMutablePointer<Int64>,
                                     _ log: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>) -> UnsafeMutableRawPointer?
@_silgen_name("mirsa_pb_access_copy_path")
private func copyPosterBoardAccessPath(_ handle: UnsafeMutableRawPointer) -> UnsafeMutablePointer<CChar>?
@_silgen_name("mirsa_pb_access_release")
private func releasePosterBoardAccess(_ handle: UnsafeMutableRawPointer) -> UnsafeMutablePointer<CChar>?
@_silgen_name("mirsa_pb_access_free_string")
private func freePosterBoardAccessString(_ value: UnsafeMutablePointer<CChar>)

/// A scoped lease owns the effective access alias and restores its own signed
/// group's original Caches on close. No guessed/foreign group entitlement.
final class PosterBoardLease {
    private var handle: UnsafeMutableRawPointer?
    let targetURL: URL
    let effectiveURL: URL
    private let log: (String) -> Void
    init(path: String, log: @escaping (String) -> Void = { _ in }) throws {
        self.log = log
        targetURL = URL(fileURLWithPath: path)
        var code: Int64 = 0
        var diagnostic: UnsafeMutablePointer<CChar>?
        let acquired = path.withCString { acquirePosterBoardAccess($0, &code, &diagnostic) }
        let detail = diagnostic.map { String(cString: $0) } ?? ""
        if let diagnostic { freePosterBoardAccessString(diagnostic) }
        if !detail.isEmpty { log(detail) }
        guard let acquired else {
            throw PosterBoardStore.failure("Scoped PosterBoard access unavailable (lease \(code)). No wallpaper was applied.\n\(detail)")
        }
        guard let pointer = copyPosterBoardAccessPath(acquired) else {
            if let cleanup = releasePosterBoardAccess(acquired) { freePosterBoardAccessString(cleanup) }
            throw PosterBoardStore.failure("PosterBoard access returned no verified path.")
        }
        effectiveURL = URL(fileURLWithPath: String(cString: pointer))
        freePosterBoardAccessString(pointer)
        handle = acquired
    }
    /// Only the lease's exact alias may resolve to the corresponding target.
    /// Any additional symlink within Library, providers or descriptors is rejected.
    func permits(_ url: URL) -> Bool {
        guard handle != nil else { return false }
        let base = effectiveURL.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        guard path == base || path.hasPrefix(base + "/") else { return false }
        let suffix = String(path.dropFirst(base.count))
        return PosterBoardStore.normalizedPath(url.resolvingSymlinksInPath().path) ==
            PosterBoardStore.normalizedPath(targetURL.path + suffix)
    }
    func close() throws {
        guard let current = handle else { return }
        handle = nil
        guard let pointer = releasePosterBoardAccess(current) else { return }
        let detail = String(cString: pointer)
        freePosterBoardAccessString(pointer)
        if !detail.isEmpty {
            log(detail)
            throw PosterBoardStore.failure("PosterBoard access cleanup needs attention. Original Caches backup was retained.\n\(detail)")
        }
    }
    deinit { try? close() }
}

enum PosterBoardStore {
    static let roots = ["Application", "InternalDaemon", "PluginKitPlugin"].map {
        "/var/mobile/Containers/Data/" + $0
    }
    static func failure(_ message: String) -> NSError {
        NSError(domain: "MirsaPosterBoard", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
    static func canonicalContainer(_ raw: String) throws -> String {
        var path = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if path.hasPrefix("/private/var/") { path.removeFirst(8) }
        while path.hasSuffix("/") { path.removeLast() }
        let url = URL(fileURLWithPath: path)
        guard url.standardizedFileURL.path == path,
              roots.contains(url.deletingLastPathComponent().path),
              UUID(uuidString: url.lastPathComponent) != nil else {
            throw failure("Invalid PosterBoard container path.")
        }
        return path
    }
    static func normalizedPath(_ path: String) -> String {
        path.hasPrefix("/private/var/") ? String(path.dropFirst(8)) : path
    }
    /// Ignore only iOS's /var alias, plus the exact alias of an active lease.
    static func unredirected(_ url: URL, lease: PosterBoardLease? = nil) -> Bool {
        if let lease { return lease.permits(url) }
        return normalizedPath(url.resolvingSymlinksInPath().path) == normalizedPath(url.standardizedFileURL.path)
    }
    static func validateIdentity(_ container: URL, lease: PosterBoardLease? = nil) throws {
        for name in [".com.apple.mobile_container_manager.metadata.plist", "com.apple.mobile_container_manager.metadata.plist"] {
            let file = container.appendingPathComponent(name)
            guard unredirected(file, lease: lease) else { continue }
            if let data = try? Data(contentsOf: file),
               let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
               info["MCMMetadataIdentifier"] as? String == "com.apple.PosterBoard" {
                let store = container.appendingPathComponent("Library/Application Support/PRBPosterExtensionDataStore")
                guard (try store.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])).isDirectory == true,
                      unredirected(store, lease: lease) else {
                    throw failure("PosterBoard datastore is missing or redirected.")
                }
                return
            }
        }
        throw failure("Container identity could not be verified as com.apple.PosterBoard.")
    }
    private static func verifiedContainer(_ path: String) -> Bool {
        guard let lease = try? PosterBoardLease(path: path) else { return false }
        let valid = (try? validateIdentity(lease.effectiveURL, lease: lease)) != nil
        do { try lease.close(); return valid } catch { return false }
    }
    private static func entries(_ root: String) throws -> [String] {
        let lease = try PosterBoardLease(path: root)
        do {
            let entries = try FileManager.default.contentsOfDirectory(atPath: lease.effectiveURL.path)
            try lease.close() // release the root alias before acquiring any child
            return entries
        } catch { try? lease.close(); throw error }
    }
    static func discover(cached: String? = nil) throws -> String {
        if let cached, let path = try? canonicalContainer(cached), verifiedContainer(path) { return path }
        for root in roots {
            guard let entries = try? entries(root) else { continue }
            for entry in entries.sorted() where UUID(uuidString: entry) != nil {
                let path = root + "/" + entry
                if verifiedContainer(path) { return path }
            }
        }
        throw failure("PosterBoard container could not be verified with scoped access.")
    }
    struct Layout {
        let version: String
        let extensions: URL
        let providers: Set<String>
    }
    static func layout(_ container: URL) throws -> Layout {
        let store = container.appendingPathComponent("Library/Application Support/PRBPosterExtensionDataStore")
        let versions = try FileManager.default.contentsOfDirectory(atPath: store.path)
            .compactMap { Int($0) }.filter { $0 > 0 }.sorted(by: >)
        for version in versions {
            let extensions = store.appendingPathComponent("\(version)/Extensions")
            if let entries = try? FileManager.default.contentsOfDirectory(atPath: extensions.path) {
                let providers = Set(entries.filter { $0.hasPrefix("com.apple.") && !$0.contains("/") })
                if !providers.isEmpty { return Layout(version: String(version), extensions: extensions, providers: providers) }
            }
        }
        throw failure("No existing PosterBoard datastore version/provider was found; refusing to guess a target.")
    }
    static func providers(for original: String, available: Set<String>) throws -> [String] {
        let aliases: [String]
        switch original {
        case "com.apple.WallpaperKit.CollectionsPoster", "com.apple.Posters.CollectionsPosterApp":
            aliases = ["com.apple.WallpaperKit.CollectionsPoster", "com.apple.Posters.CollectionsPosterApp"]
        case "com.apple.MercuryPoster", "com.apple.Posters.MercuryPosterApp":
            aliases = ["com.apple.MercuryPoster", "com.apple.Posters.MercuryPosterApp"]
        default: aliases = [original]
        }
        let targets = aliases.filter { available.contains($0) }
        guard !targets.isEmpty else { throw failure("No installed provider matches \(original).") }
        return targets
    }
    /// Checks all bytes, relative paths, nonempty contents and symlinks.
    /// A FileComplete transport acknowledgment is never considered proof.
    static func manifest(_ directory: URL) throws -> [String: String] {
        let fm = FileManager.default
        let rootInfo = try directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard rootInfo.isDirectory == true, rootInfo.isSymbolicLink != true else { throw failure("Descriptor root must be a real directory.") }
        var enumerationError: Error?
        guard let enumerator = fm.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
                                             errorHandler: { _, error in enumerationError = error; return false }) else {
            throw failure("Cannot enumerate descriptor.")
        }
        var result: [String: String] = [:]
        for case let url as URL in enumerator {
            let info = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard info.isSymbolicLink != true else { throw failure("Symbolic links are not allowed in wallpaper descriptors.") }
            if info.isRegularFile == true {
                let relative = String(url.path.dropFirst(directory.path.count + 1))
                result[relative] = SHA256.hash(data: try Data(contentsOf: url)).map { String(format: "%02x", $0) }.joined()
            }
        }
        if let enumerationError { throw enumerationError }
        guard !result.isEmpty else { throw failure("Empty wallpaper descriptor.") }
        return result
    }
    /// Copies only new descriptor directories, preserving package identity. Existing wallpapers and SQLite stay untouched.
    /// Caller holds the validated container lease. Local fixture tests exercise this same path.
    static func install(_ descriptors: [(url: URL, ext: String)], container: URL,
                        resetProtections: Bool, backupRoot: URL, lease: PosterBoardLease? = nil, log: (String) -> Void) throws -> Int {
        try validateIdentity(container, lease: lease)
        guard !descriptors.isEmpty else { throw failure("Archive contains no wallpaper descriptors.") }
        let fm = FileManager.default, target = try layout(container)
        let backup = backupRoot.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: backup, withIntermediateDirectories: true)
        let prefs = container.appendingPathComponent("Library/Preferences/com.apple.PosterBoard.unprotectedUserDefaults.plist")
        guard unredirected(prefs, lease: lease) else { throw failure("Redirected preference path rejected.") }
        let existed = fm.fileExists(atPath: prefs.path)
        // A read failure is not an empty preference file. Never overwrite unreadable state.
        let original = existed ? try Data(contentsOf: prefs) : nil
        if let original { try original.write(to: backup.appendingPathComponent("unprotectedUserDefaults.original.plist"), options: .atomic) }
        var preferences = try original.map {
            guard let dict = try PropertyListSerialization.propertyList(from: $0, format: nil) as? [String: Any] else {
                throw failure("PosterBoard preferences are not a dictionary.")
            }
            return dict
        } ?? [:]
        var created: [URL] = [], installedProviders = Set<String>(), proof: [String: [String: String]] = [:]
        var preferencesTouched = false
        do {
            for descriptor in descriptors {
                let expected = try manifest(descriptor.url)
                for provider in try providers(for: descriptor.ext, available: target.providers) {
                    let parent = target.extensions.appendingPathComponent(provider + "/descriptors")
                    guard unredirected(parent, lease: lease) else { throw failure("Redirected descriptor destination rejected.") }
                    try fm.createDirectory(at: parent, withIntermediateDirectories: true)
                    // References may use a non-UUID identifier (including imported SMB packages).
                    // Preserve its exact spelling and reject invalid paths rather than renaming it.
                    let id = descriptor.url.lastPathComponent
                    guard !id.isEmpty, !id.hasPrefix("."), id != "..",
                          !id.contains("/"), !id.contains("\\"), id.utf8.count <= 255 else {
                        throw failure("Invalid descriptor identifier.")
                    }
                    let destination = parent.appendingPathComponent(id)
                    guard !fm.fileExists(atPath: destination.path) else { throw failure("New descriptor collision.") }
                    created.append(destination) // remove even a partially copied new directory on failure
                    try fm.copyItem(at: descriptor.url, to: destination)
                    guard try manifest(destination) == expected else { throw failure("Descriptor readback SHA-256 mismatch.") }
                    let verifiedPath = lease.map {
                        $0.targetURL.path + String(destination.path.dropFirst(container.path.count))
                    } ?? destination.path
                    proof[verifiedPath] = expected
                    installedProviders.insert(provider)
                    log("Verified \(expected.count) files at v\(target.version)/\(provider)/descriptors/\(id)")
                }
            }
            if resetProtections { preferences["PBF_RESET_FILE_PROTECTIONS"] = true }
            // Preserve every other key; unlike the old applier never request locale reset.
            preferences["PBF_LOCALE_DID_CHANGE"] = false
            let oldProviders = preferences["PersistedPosterContainerBundleIdentifiers"] as? [String] ?? []
            preferences["PersistedPosterContainerBundleIdentifiers"] = Set(oldProviders).union(installedProviders).sorted()
            let bytes = try PropertyListSerialization.data(fromPropertyList: preferences, format: .binary, options: 0)
            try fm.createDirectory(at: prefs.deletingLastPathComponent(), withIntermediateDirectories: true)
            preferencesTouched = true
            try bytes.write(to: prefs, options: .atomic)
            guard try Data(contentsOf: prefs) == bytes else { throw failure("Preference readback failed.") }
            let report: [String: Any] = ["container": lease?.targetURL.path ?? container.path, "accessPath": container.path, "version": target.version, "files": proof,
                                        "preferencesExisted": existed, "galleryRegistrationVerified": false]
            try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
                .write(to: backup.appendingPathComponent("verified-copy.json"), options: .atomic)
            log("Backup and SHA-256 readback report saved in Mirsa/TendiesBackups/\(backup.lastPathComponent).")
            return created.count
        } catch {
            var rollbackFailures: [String] = []
            for destination in created where fm.fileExists(atPath: destination.path) {
                do { try fm.removeItem(at: destination) } catch { rollbackFailures.append(destination.path) }
            }
            if preferencesTouched {
                do {
                    if let original { try original.write(to: prefs, options: .atomic) }
                    else if fm.fileExists(atPath: prefs.path) { try fm.removeItem(at: prefs) }
                } catch { rollbackFailures.append(prefs.path) }
            }
            if !rollbackFailures.isEmpty { log("Rollback incomplete: \(rollbackFailures.joined(separator: ", ")). Original preference backup retained.") }
            throw error
        }
    }
}
