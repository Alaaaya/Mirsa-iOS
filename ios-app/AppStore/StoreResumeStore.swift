import Foundation
import CryptoKit

/// Carries the signed-in account (email) into the package layer. Without it nothing is persisted for resume.
enum StoreResumeContext {
    @TaskLocal static var account: String?
}

/// Partial downloads live in Application Support, one hashed folder per account + app + version.
/// No URL, token or raw account is ever written.
enum StoreResumeStore {
    static let maxAge: TimeInterval = 7 * 24 * 3600
    static let maxTotal: Int64 = 8 * 1024 * 1024 * 1024

    static var root: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MirsaDownloads", isDirectory: true)
    }

    static func folder(account: String, bundleID: String, version: String, root: URL = root) -> URL {
        let digest = SHA256.hash(data: Data((account.lowercased() + "\u{1F}" + bundleID + "\u{1F}" + version).utf8))
        let name = digest.map { String(format: "%02x", $0) }.joined().prefix(40)
        return root.appendingPathComponent(String(name), isDirectory: true)
    }

    static func partial(_ folder: URL) -> URL { folder.appendingPathComponent("partial.bin") }
    private static func stateURL(_ folder: URL) -> URL { folder.appendingPathComponent("state.json") }

    static func prepare(_ folder: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        var parent = folder.deletingLastPathComponent()
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try? parent.setResourceValues(values)
        var own = folder
        try? own.setResourceValues(values)
        #if os(iOS)
        try? fm.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: folder.path)
        #endif
    }

    static func load(_ folder: URL) -> StoreResumeState {
        guard let data = try? Data(contentsOf: stateURL(folder)),
              let state = try? JSONDecoder().decode(StoreResumeState.self, from: data),
              state.version == 1, state.bytes >= 0, (state.total ?? 1) > 0 else { return StoreResumeState() }
        return state
    }

    static func save(_ state: StoreResumeState, _ folder: URL) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: stateURL(folder), options: [.atomic])
    }

    static func clear(_ folder: URL) { try? FileManager.default.removeItem(at: folder) }

    /// Log out / account switch: no partial of anyone survives.
    static func clearAll(root: URL = root) { try? FileManager.default.removeItem(at: root) }

    static func fileSize(_ url: URL) -> Int64 {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? NSNumber else { return 0 }
        return size.int64Value
    }

    /// Makes state and file agree. Returns the usable state and whether stored bytes had to be thrown away.
    static func reconcile(_ state: StoreResumeState, folder: URL) -> (state: StoreResumeState, discarded: Bool) {
        let fm = FileManager.default
        let file = partial(folder)
        let size = fileSize(file)
        let usable = state.bytes > 0 && state.hasValidator && size >= state.bytes && (state.total.map { state.bytes < $0 } ?? true)
        if usable {
            if size > state.bytes, let h = try? FileHandle(forWritingTo: file) {
                try? h.truncate(atOffset: UInt64(state.bytes)); try? h.close()
            }
            return (state, false)
        }
        let hadBytes = state.bytes > 0 || size > 0
        try? fm.removeItem(at: file)
        fm.createFile(atPath: file.path, contents: nil)
        var fresh = StoreResumeState()
        fresh.bytes = 0
        return (fresh, hadBytes)
    }

    /// Old or excess partials of OTHER downloads are removed; the active folder is always kept.
    static func prune(root: URL = root, keep: URL? = nil, now: Date = Date(),
                      maxAge: TimeInterval = maxAge, maxTotal: Int64 = maxTotal) {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
        var entries: [(url: URL, date: Date, size: Int64)] = []
        for url in items where url.standardizedFileURL != keep?.standardizedFileURL {
            let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let sub = (try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? []
            let size = sub.reduce(Int64(0)) { $0 + fileSize($1) }
            let stateDate = (try? stateURL(url).resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? date
            entries.append((url, max(date, stateDate), size))
        }
        var kept: [(url: URL, date: Date, size: Int64)] = []
        for e in entries {
            if now.timeIntervalSince(e.date) > maxAge { try? fm.removeItem(at: e.url) } else { kept.append(e) }
        }
        var total = kept.reduce(Int64(0)) { $0 + $1.size } + (keep.map { size(of: $0) } ?? 0)
        for e in kept.sorted(by: { $0.date < $1.date }) where total > maxTotal {
            try? fm.removeItem(at: e.url); total -= e.size
        }
    }

    private static func size(of folder: URL) -> Int64 {
        ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []).reduce(0) { $0 + fileSize($1) }
    }
}
