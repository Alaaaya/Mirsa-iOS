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

@_silgen_name("mirsa_pb_access_grant_relative")
private func grantRelativeAccess(_ handle: UnsafeMutableRawPointer, _ path: UnsafePointer<CChar>,
                                 _ log: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>) -> Int32
@_silgen_name("mirsa_pb_container_identifier")
private func containerIdentifier(_ path: UnsafePointer<CChar>) -> UnsafeMutablePointer<CChar>?

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
    private var granted = Set<String>()
    /// worse_query can grant an exact path without granting parent or child reads.
    /// Ask separately for known wallpaper metadata/store paths and retain all
    /// tokens until this lease ends. No arbitrary filesystem paths are accepted.
    @discardableResult
    func grant(_ relative: String) -> Bool {
        guard let handle else { return false }
        if granted.contains(relative) { return true }
        var detail: UnsafeMutablePointer<CChar>?
        let result = relative.withCString { grantRelativeAccess(handle, $0, &detail) }
        if let detail {
            let message = String(cString: detail)
            if !message.isEmpty { log(message) }
            freePosterBoardAccessString(detail)
        }
        if result == 1 { granted.insert(relative) }
        return result == 1
    }
    func identityAttribute() -> String? {
        guard let p = targetURL.path.withCString({ containerIdentifier($0) }) else { return nil }
        defer { freePosterBoardAccessString(p) }
        return String(cString: p)
    }
    func grantLayout() {
        for path in ["Library", "Library/Application Support",
                     "Library/Application Support/PRBPosterExtensionDataStore"] { grant(path) }
    }
    /// Only the lease's exact alias may resolve to the corresponding target.
    /// Any additional symlink within Library, providers or descriptors is rejected.
    func permits(_ url: URL) -> Bool {
        guard handle != nil else { return false }
        return PosterBoardStore.permitsLeasePath(url, effective: effectiveURL, target: targetURL)
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
    /// Resolve the known class-7 alias explicitly. Foundation's realpath-style
    /// resolution can leave that alias unchanged when the sandbox grants access
    /// through Caches but not through the canonical container pathname.
    /// Never resolve (or trust) an additional link beneath that alias.
    static func permitsLeasePath(_ url: URL, effective: URL, target: URL) -> Bool {
        let fm = FileManager.default
        let base = effective.standardizedFileURL
        let path = url.standardizedFileURL.path
        guard path == base.path || path.hasPrefix(base.path + "/") else { return false }
        let expected = normalizedPath(target.standardizedFileURL.path)
        if normalizedPath(base.path) != expected {
            guard let link = try? fm.destinationOfSymbolicLink(atPath: base.path) else { return false }
            let resolved = link.hasPrefix("/") ? URL(fileURLWithPath: link) :
                base.deletingLastPathComponent().appendingPathComponent(link)
            guard normalizedPath(resolved.standardizedFileURL.path) == expected else { return false }
        } else {
            guard unredirected(base) else { return false }
        }
        var current = base
        let suffix = String(path.dropFirst(base.path.count))
        for component in suffix.split(separator: "/") {
            current.appendPathComponent(String(component))
            do {
                let attributes = try fm.attributesOfItem(atPath: current.path)
                guard attributes[.type] as? FileAttributeType != .typeSymbolicLink else { return false }
            } catch {
                // New destinations may not exist yet. Permission/read failures
                // are never interpreted as proof of a safe missing path.
                let failure = error as NSError
                guard failure.domain == NSCocoaErrorDomain,
                      failure.code == NSFileNoSuchFileError || failure.code == NSFileReadNoSuchFileError else { return false }
            }
        }
        return true
    }
    static func validateIdentity(_ container: URL, lease: PosterBoardLease? = nil, log: (String) -> Void = { _ in }) throws {
        lease?.grantLayout()
        let attribute = lease?.identityAttribute()
        if let attribute, attribute != "com.apple.PosterBoard" {
            throw failure("Container identity attribute contradicts com.apple.PosterBoard.")
        }
        var identified = attribute == "com.apple.PosterBoard"
        for name in [".com.apple.mobile_container_manager.metadata.plist", "com.apple.mobile_container_manager.metadata.plist"] {
            lease?.grant(name)
            let file = container.appendingPathComponent(name)
            guard unredirected(file, lease: lease) else { continue }
            if let data = try? Data(contentsOf: file) {
                guard let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                      info["MCMMetadataIdentifier"] as? String == "com.apple.PosterBoard" else {
                    throw failure("Readable metadata contradicts com.apple.PosterBoard.")
                }
                identified = true
            }
        }
        guard identified else { throw failure("Container identity could not be verified as com.apple.PosterBoard.") }
        let store = container.appendingPathComponent("Library/Application Support/PRBPosterExtensionDataStore")
        guard (try store.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])).isDirectory == true,
              unredirected(store, lease: lease) else {
            throw failure("PosterBoard datastore is missing or redirected.")
        }
        if let lease { MirsaPosterDiscovery.rememberVerified(lease.targetURL.path) }
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
    static func layout(_ container: URL, lease: PosterBoardLease? = nil) throws -> Layout {
        lease?.grantLayout()
        let store = container.appendingPathComponent("Library/Application Support/PRBPosterExtensionDataStore")
        let versions = try FileManager.default.contentsOfDirectory(atPath: store.path)
            .compactMap { Int($0) }.filter { $0 > 0 }.sorted(by: >)
        for version in versions {
            let base = "Library/Application Support/PRBPosterExtensionDataStore/\(version)"
            lease?.grant(base)
            lease?.grant(base + "/Extensions")
            let extensions = store.appendingPathComponent("\(version)/Extensions")
            if let entries = try? FileManager.default.contentsOfDirectory(atPath: extensions.path) {
                let providers = Set(entries.filter { $0.hasPrefix("com.apple.") && !$0.contains("/") })
                for provider in providers {
                    lease?.grant(base + "/Extensions/" + provider)
                    lease?.grant(base + "/Extensions/" + provider + "/descriptors")
                }
                if !providers.isEmpty { return Layout(version: String(version), extensions: extensions, providers: providers) }
            }
        }
        throw failure("No existing PosterBoard datastore version/provider was found; refusing to guess a target.")
    }
    static func providers(for original: String, available: Set<String>) throws -> [String] {
        guard original == "com.apple.WallpaperKit.CollectionsPoster" ||
              original == "com.apple.Posters.CollectionsPosterApp",
              available.contains("com.apple.WallpaperKit.CollectionsPoster") else {
            throw failure("PB Probe only supports the installed CollectionsPoster provider.")
        }
        return ["com.apple.WallpaperKit.CollectionsPoster"]
    }
    /// Checks all bytes, relative paths, nonempty contents and symlinks.
    /// A FileComplete transport acknowledgment is never considered proof.
    static func manifest(_ directory: URL) throws -> [String: String] {
        let fm = FileManager.default
        let rootInfo = try directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard rootInfo.isDirectory == true, rootInfo.isSymbolicLink != true else { throw failure("Descriptor root must be a real directory.") }
        var enumerationError: Error?
        // Foundation may enumerate /var URLs as /private/var on Darwin.
        // Use the same canonical root for enumeration and relative path slicing.
        let root = directory.resolvingSymlinksInPath().standardizedFileURL
        let prefix = root.path + "/"
        guard let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
                                             errorHandler: { _, error in enumerationError = error; return false }) else {
            throw failure("Cannot enumerate descriptor.")
        }
        var result: [String: String] = [:]
        for case let url as URL in enumerator {
            let info = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard info.isSymbolicLink != true else { throw failure("Symbolic links are not allowed in wallpaper descriptors.") }
            if info.isRegularFile == true {
                let entryPath = url.resolvingSymlinksInPath().standardizedFileURL.path
                guard entryPath.hasPrefix(prefix) else { throw failure("Descriptor entry escaped canonical root. root=\(prefix) entry=\(entryPath) raw=\(url.path)") }
                let relative = String(entryPath.dropFirst(prefix.count))
                result[relative] = SHA256.hash(data: try Data(contentsOf: url)).map { String(format: "%02x", $0) }.joined()
            }
        }
        if let enumerationError { throw enumerationError }
        guard !result.isEmpty else { throw failure("Empty wallpaper descriptor.") }
        return result
    }
}
