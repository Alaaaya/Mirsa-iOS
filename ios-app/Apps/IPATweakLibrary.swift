import Foundation
import SwiftUI

struct IPATweak: Identifiable, Codable {
    let id: UUID
    let name: String
    let roots: [String] // paths relative to this item's private directory
    let addedAt: Date
    let packageOnlyCode: Bool
}

/// User-supplied code is stored inertly until explicitly selected in the editor.
/// No package scripts, system installation or automatic third-party downloads.
@MainActor
final class IPATweakLibrary: ObservableObject {
    static let shared = IPATweakLibrary()
    @Published private(set) var items: [IPATweak] = []
    @Published var importing = false
    @Published var pendingImport: IPATweakImportChoice?
    private var selectionContinuation: CheckedContinuation<[String]?, Never>?
    private var activeCancellation: URL?

    func finishImportSelection(_ ids: [String]?) {
        let continuation = selectionContinuation
        selectionContinuation = nil
        pendingImport = nil
        continuation?.resume(returning: ids)
    }
    func cancelImport() {
        if let url = activeCancellation { try? Data().write(to: url) }
        finishImportSelection(nil)
    }


    nonisolated static var root: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MirsaTweakLibrary", isDirectory: true)
    }
    private init() {
        try? FileManager.default.createDirectory(at: Self.root, withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: Self.root.appendingPathComponent("index.json")),
           let saved = try? JSONDecoder().decode([IPATweak].self, from: data) {
            // Persisted index is not a source of arbitrary absolute paths.
            items = saved.filter { item in
                item.roots.allSatisfy { Self.safeRelative($0) } &&
                item.roots.allSatisfy { FileManager.default.fileExists(atPath: Self.root.appendingPathComponent(item.id.uuidString).appendingPathComponent($0).path) }
            }
        }
    }
    nonisolated private static func safeRelative(_ p: String) -> Bool {
        !p.isEmpty && !p.hasPrefix("/") && !p.contains("\\") && !p.contains("\0") &&
        !p.split(separator: "/", omittingEmptySubsequences: false).contains(where: { $0.isEmpty || $0 == "." || $0 == ".." })
    }
    private func save() throws {
        try JSONEncoder().encode(items).write(to: Self.root.appendingPathComponent("index.json"), options: .atomic)
    }
    func delete(_ item: IPATweak) throws {
        let previous = items
        items.removeAll { $0.id == item.id }
        do { try save() } catch { items = previous; throw error }
        try? FileManager.default.removeItem(at: Self.root.appendingPathComponent(item.id.uuidString))
    }
    /// Stable per-component id: package UUID + normalized root-relative path.
    static func componentID(_ item: IPATweak, _ root: String) -> String { item.id.uuidString + ":" + root }
    /// Like urls(for:) but skips components the user excluded; order of roots is kept.
    func urls(for id: UUID, excluding excluded: Set<String>) throws -> [URL] {
        guard let item = items.first(where: { $0.id == id }) else {
            throw SideloadError.message("A selected tweak is missing. Select it again.")
        }
        return item.roots.filter { !excluded.contains(Self.componentID(item, $0)) }.map {
            Self.root.appendingPathComponent(item.id.uuidString).appendingPathComponent($0)
        }
    }
    func urls(for ids: Set<UUID>) throws -> [URL] {
        guard ids.isSubset(of: Set(items.map(\.id))) else {
            throw SideloadError.message("A selected tweak is missing. Select it again.")
        }
        return items.filter { ids.contains($0.id) }.flatMap { item in
            item.roots.map { Self.root.appendingPathComponent(item.id.uuidString).appendingPathComponent($0) }
        }
    }

    /// A single result is automatic; archives with several roots require explicit selection.
    func addFile(_ url: URL, allowSelection: Bool = false) async throws {
        guard !importing else { throw SideloadError.message(IPATweakImportText.error("busy")) }
        importing = true
        defer { importing = false }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let session = try MirsaManagedTmp.begin("tweak-import")
        defer { activeCancellation = nil; MirsaManagedTmp.end(session) }
        let cancellation = session.appendingPathComponent("cancel")
        activeCancellation = cancellation
        let candidates = try await withTaskCancellationHandler(operation: {
            try await Task.detached {
                do { return try Self.prepare(url, session: session, cancellation: cancellation) }
                catch is CancellationError { throw CancellationError() }
                catch { throw SideloadError.message(IPATweakImportText.error("corrupt")) }
            }.value
        }, onCancel: { try? Data().write(to: cancellation) })
        try Task.checkCancellation()
        let chosen: [IPATweakImportCandidate]
        if candidates.count == 1 { chosen = candidates }
        else {
            guard allowSelection else { throw SideloadError.message(IPATweakImportText.error("selection_required")) }
            let ids: [String]? = await withTaskCancellationHandler(operation: {
                await withCheckedContinuation { continuation in
                    selectionContinuation = continuation
                    pendingImport = IPATweakImportChoice(candidates: candidates)
                }
            }, onCancel: { Task { @MainActor in self.cancelImport() } })
            guard let ids else { throw CancellationError() }
            chosen = candidates.filter { ids.contains($0.id) }
            guard !chosen.isEmpty, chosen.count == Set(ids).count,
                  Set(chosen.map(\.identity)).count == chosen.count else {
                throw SideloadError.message(IPATweakImportText.error("collision"))
            }
        }
        try Task.checkCancellation()
        let item = try await withTaskCancellationHandler(operation: {
            try await Task.detached { try Self.commit(chosen, session: session, cancellation: cancellation, name: url.deletingPathExtension().lastPathComponent) }.value
        }, onCancel: { try? Data().write(to: cancellation) })
        if Task.isCancelled || FileManager.default.fileExists(atPath: cancellation.path) {
            try? FileManager.default.removeItem(at: Self.root.appendingPathComponent(item.id.uuidString))
            throw CancellationError()
        }
        items.insert(item, at: 0)
        do { try save() } catch {
            items.removeAll { $0.id == item.id }
            try? FileManager.default.removeItem(at: Self.root.appendingPathComponent(item.id.uuidString))
            throw error
        }
    }

    nonisolated private static func prepare(_ source: URL, session: URL, cancellation: URL) throws -> [IPATweakImportCandidate] {
        let fm = FileManager.default
        guard ["zip", "deb", "dylib", "framework"].contains(source.pathExtension.lowercased()), safeRelative(source.lastPathComponent) else {
            throw SideloadError.message(IPATweakImportText.error("unsupported"))
        }
        let input = session.appendingPathComponent("input", isDirectory: true)
        try fm.createDirectory(at: input, withIntermediateDirectories: false)
        let snapshot = input.appendingPathComponent(source.lastPathComponent)
        try copyValidated(source, to: snapshot, cancellation: cancellation)
        try IPAEditorService.run("tweak_import", input: snapshot, output: session, cancellation: cancellation)
        let manifest = session.appendingPathComponent("candidates.json")
        guard let size = try manifest.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 2_000_000 else {
            throw SideloadError.message(IPATweakImportText.error("limits"))
        }
        let candidates = try JSONDecoder().decode([IPATweakImportCandidate].self, from: Data(contentsOf: manifest))
        guard !candidates.isEmpty, candidates.count <= 256, candidates.allSatisfy({ safeRelative($0.path) && $0.id == $0.path }) else {
            throw SideloadError.message(IPATweakImportText.error("corrupt"))
        }
        return candidates
    }

    nonisolated private static func commit(_ candidates: [IPATweakImportCandidate], session: URL, cancellation: URL, name: String) throws -> IPATweak {
        let fm = FileManager.default, id = UUID()
        let folder = root.appendingPathComponent(id.uuidString, isDirectory: true)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        do {
            var roots: [String] = []
            for (index, candidate) in candidates.enumerated() {
                guard safeRelative(candidate.path), safeRelative(candidate.name), !candidate.name.contains("/") else { throw CocoaError(.fileReadCorruptFile) }
                let group = folder.appendingPathComponent(String(index), isDirectory: true)
                try fm.createDirectory(at: group, withIntermediateDirectories: false)
                let target = group.appendingPathComponent(candidate.name)
                try copyValidated(session.appendingPathComponent(candidate.path), to: target, cancellation: cancellation)
                roots.append(String(index) + "/" + candidate.name)
            }
            return IPATweak(id: id, name: name, roots: roots, addedAt: Date(), packageOnlyCode: candidates.contains { $0.origin.hasPrefix("deb") })
        } catch { try? fm.removeItem(at: folder); throw error }
    }

    func addURL(_ string: String) async throws {
        guard !importing else { throw SideloadError.message("Wait for the current library import.") }
        guard let url = URL(string: string.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme?.lowercased() == "https", url.host != nil, url.user == nil, url.password == nil,
              ["dylib", "deb"].contains(url.pathExtension.lowercased()) else {
            throw SideloadError.message("Enter a direct HTTPS URL ending in .dylib or .deb. Import .framework folders from Files.")
        }
        let temporary = try await IPATweakDownload.fetch(url)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let folder = try MirsaManagedTmp.begin("tweak-url")
        defer { MirsaManagedTmp.end(folder) }
        let named = folder.appendingPathComponent(url.lastPathComponent)
        try FileManager.default.moveItem(at: temporary, to: named)
        try await addFile(named, allowSelection: true)
    }

    /// Validate before copying, then stream with a second actual-byte quota and cancellation.
    /// Framework symlinks are deliberately unsupported, never recreated or followed.
    nonisolated private static func copyValidated(_ source: URL, to dest: URL, cancellation: URL? = nil) throws {
        let fm = FileManager.default
        var entries = [source], count = 0
        var declared: Int64 = 0, actual: Int64 = 0
        let sourceValues = try source.resourceValues(forKeys: [.isDirectoryKey])
        if sourceValues.isDirectory == true {
            guard let e = fm.enumerator(at: source, includingPropertiesForKeys: [.isSymbolicLinkKey, .isRegularFileKey, .isDirectoryKey, .fileSizeKey]) else { throw CocoaError(.fileReadCorruptFile) }
            while let url = e.nextObject() as? URL {
                entries.append(url)
                if entries.count > 10_000 { throw SideloadError.message(IPATweakImportText.error("limits")) }
                if (try url.resourceValues(forKeys: [.isSymbolicLinkKey])).isSymbolicLink == true { e.skipDescendants(); throw SideloadError.message(IPATweakImportText.error("links")) }
            }
        }
        func checkCancellation() throws {
            if let cancellation, fm.fileExists(atPath: cancellation.path) { throw CancellationError() }
        }
        for url in entries {
            try checkCancellation(); count += 1
            let value = try url.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey, .isDirectoryKey, .fileSizeKey])
            guard count <= 10_000, url.pathComponents.count - source.pathComponents.count <= 64,
                  value.isSymbolicLink != true, value.isRegularFile == true || value.isDirectory == true else {
                throw SideloadError.message(IPATweakImportText.error("links"))
            }
            let size = Int64(value.fileSize ?? 0)
            if value.isRegularFile == true {
                guard size <= 128 * 1024 * 1024 else { throw SideloadError.message(IPATweakImportText.error("limits")) }
                declared += size
                guard declared <= 256 * 1024 * 1024 else { throw SideloadError.message(IPATweakImportText.error("limits")) }
            }
        }
        let available = try dest.deletingLastPathComponent().resourceValues(forKeys: [.volumeAvailableCapacityKey]).volumeAvailableCapacity ?? 0
        guard Int64(available) > declared + 16 * 1024 * 1024 else { throw SideloadError.message(IPATweakImportText.error("disk")) }
        for url in entries {
            try checkCancellation()
            let suffix = url == source ? "" : String(url.path.dropFirst(source.path.count + 1))
            guard suffix.isEmpty || safeRelative(suffix) else { throw CocoaError(.fileReadCorruptFile) }
            let target = suffix.isEmpty ? dest : dest.appendingPathComponent(suffix)
            let value = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isRegularFileKey, .fileSizeKey])
            guard value.isSymbolicLink != true else { throw CocoaError(.fileReadCorruptFile) }
            if value.isDirectory == true { try fm.createDirectory(at: target, withIntermediateDirectories: true); continue }
            guard value.isRegularFile == true, !fm.fileExists(atPath: target.path) else { throw CocoaError(.fileReadCorruptFile) }
            try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            guard fm.createFile(atPath: target.path, contents: nil) else { throw CocoaError(.fileWriteUnknown) }
            let reader = try FileHandle(forReadingFrom: url), writer = try FileHandle(forWritingTo: target)
            defer { try? reader.close(); try? writer.close() }
            var fileBytes: Int64 = 0
            while true {
                try checkCancellation()
                let chunk = try reader.read(upToCount: 65536) ?? Data()
                if chunk.isEmpty { break }
                fileBytes += Int64(chunk.count); actual += Int64(chunk.count)
                guard fileBytes <= 128 * 1024 * 1024, actual <= 256 * 1024 * 1024,
                      fileBytes <= Int64(value.fileSize ?? 0) else { throw SideloadError.message(IPATweakImportText.error("limits")) }
                try writer.write(contentsOf: chunk)
            }
            guard fileBytes == Int64(value.fileSize ?? 0) else { throw CocoaError(.fileReadCorruptFile) }
        }
    }
}
