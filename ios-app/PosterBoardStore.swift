import Foundation
import CryptoKit

@_silgen_name("mirsa_pb_access_acquire")
private func acquirePosterBoardAccess(_ path: UnsafePointer<CChar>) -> Int64
@_silgen_name("mirsa_pb_access_release")
private func releasePosterBoardAccess(_ handle: Int64)

/// Access is scoped to one container, released on every exit. No app-group
/// entitlement, Library rename, global preferences or database reset is used.
final class PosterBoardLease {
    let handle: Int64
    init(path: String) throws {
        handle = path.withCString { acquirePosterBoardAccess($0) }
        guard handle >= 0 else { throw PosterBoardStore.failure("Direct PosterBoard access unavailable (lease \(handle)). No wallpaper was applied.") }
    }
    deinit { releasePosterBoardAccess(handle) }
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
    /// /var is an OS-owned alias of /private/var on iOS. Ignore only that
    /// alias, never arbitrary symlinks inside a container or descriptor path.
    static func unredirected(_ url: URL) -> Bool {
        func normalize(_ path: String) -> String {
            path.hasPrefix("/private/var/") ? String(path.dropFirst(8)) : path
        }
        return normalize(url.resolvingSymlinksInPath().path) == normalize(url.standardizedFileURL.path)
    }
    static func validateIdentity(_ container: URL) throws {
        for name in [".com.apple.mobile_container_manager.metadata.plist", "com.apple.mobile_container_manager.metadata.plist"] {
            let file = container.appendingPathComponent(name)
            if let data = try? Data(contentsOf: file),
               let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
               info["MCMMetadataIdentifier"] as? String == "com.apple.PosterBoard" {
                // Metadata alone is insufficient if this is an uninitialized/old container.
                let store = container.appendingPathComponent("Library/Application Support/PRBPosterExtensionDataStore")
                guard (try store.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])).isDirectory == true,
                      unredirected(store) else {
                    throw failure("PosterBoard datastore is missing or redirected.")
                }
                return
            }
        }
        throw failure("Container identity could not be verified as com.apple.PosterBoard.")
    }
    static func discover(cached: String? = nil) throws -> String {
        if let cached, let path = try? canonicalContainer(cached),
           let lease = try? PosterBoardLease(path: path) {
            if (try? validateIdentity(URL(fileURLWithPath: path))) != nil {
                return withExtendedLifetime(lease) { path }
            }
        }
        for root in roots {
            guard let lease = try? PosterBoardLease(path: root) else { continue }
            let result: String? = withExtendedLifetime(lease) {
                guard let entries = try? FileManager.default.contentsOfDirectory(atPath: root) else { return nil }
                for entry in entries.sorted() where UUID(uuidString: entry) != nil {
                    let path = root + "/" + entry
                    guard let child = try? PosterBoardLease(path: path) else { continue }
                    let valid = withExtendedLifetime(child) { (try? validateIdentity(URL(fileURLWithPath: path))) != nil }
                    if valid { return path }
                }
                return nil
            }
            if let result { return result }
        }
        throw failure("PosterBoard container could not be verified with direct access.")
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
                        resetProtections: Bool, backupRoot: URL, log: (String) -> Void) throws -> Int {
        try validateIdentity(container)
        guard !descriptors.isEmpty else { throw failure("Archive contains no wallpaper descriptors.") }
        let fm = FileManager.default, target = try layout(container)
        let backup = backupRoot.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: backup, withIntermediateDirectories: true)
        let prefs = container.appendingPathComponent("Library/Preferences/com.apple.PosterBoard.unprotectedUserDefaults.plist")
        guard unredirected(prefs) else { throw failure("Redirected preference path rejected.") }
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
                    guard unredirected(parent) else { throw failure("Redirected descriptor destination rejected.") }
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
                    proof[destination.path] = expected
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
            let report: [String: Any] = ["container": container.path, "version": target.version, "files": proof,
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
