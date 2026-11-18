import Foundation
@preconcurrency import ApplePackage
import ZIPFoundation

// BEGIN STORE DOWNLOAD PROGRESS
struct StoreDownloadProgress: Sendable {
    enum Phase: Int, Sendable { case preparing, downloading, packaging, validating, saving, saved, failed }
    struct Event: Sendable {
        let phase: Phase
        var received: Int64 = 0
        var expected: Int64 = 0
        var time: Double = ProcessInfo.processInfo.systemUptime
        var restarted = false
    }
    @TaskLocal static var report: (@Sendable (Event) -> Void)?
    var phase = Phase.preparing
    var received: Int64 = 0
    var expected: Int64 = 0
    var speed: Double = 0
    var fraction: Double? = 0
    private var lastTime: Double?
    private var lastBytes: Int64 = 0
    private var terminal = false
    mutating func apply(_ event: Event) {
        guard !terminal, event.phase.rawValue >= phase.rawValue else { return }
        phase = event.phase
        if phase == .failed { terminal = true; fraction = nil; speed = 0; return }
        if phase == .downloading {
            if event.restarted { received = 0; lastBytes = 0; lastTime = nil; speed = 0; fraction = 0 }
            let bytes = max(received, max(0, event.received))
            if let lastTime, event.time > lastTime {
                speed = max(0, Double(bytes - lastBytes) / (event.time - lastTime))
            }
            lastTime = event.time; lastBytes = bytes
            received = bytes
            expected = event.expected > 0 ? event.expected : 0
            if expected > 0 {
                let value = 0.05 + 0.89 * min(1, Double(received) / Double(expected))
                fraction = max(fraction ?? 0, value)
            } else { fraction = nil }
        } else {
            let value: Double
            switch phase {
            case .preparing: value = 0
            case .packaging: value = 0.94
            case .validating: value = 0.97
            case .saving: value = 0.99
            case .saved: value = 1; terminal = true
            default: return
            }
            fraction = max(fraction ?? 0, value)
        }
    }
}
// END STORE DOWNLOAD PROGRESS

protocol MirsaStorePackages {
    func cancel()
    func fetch(output: DownloadOutput, bundleID: String) async throws -> URL
}

/// A private, transient download. No Authorization/Cookie headers are forwarded to the CDN.
final class AppleStorePackages: MirsaStorePackages {
    private let lock = NSLock()
    private var activeRun: StoreTransferRun?
    func cancel() {
        // Client lifecycle cancellation is terminal, unlike leaving a screen.
        lock.lock(); let run = activeRun; lock.unlock()
        run?.requestDiscard()
    }
    private func setRun(_ run: StoreTransferRun?) {
        lock.lock(); activeRun = run; lock.unlock()
    }
    func fetch(output: DownloadOutput, bundleID: String) async throws -> URL {
        guard let url = URL(string: output.downloadURL) else { throw MirsaStoreError.untrustedURL }
        try MirsaStorePolicy.downloadURL(url)
        let directory = try MirsaManagedTmp.begin("store-download")
        var handedOff = false
        defer { if !handedOff { MirsaManagedTmp.end(directory) } }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                               attributes: Self.protection)
        let destination = directory.appendingPathComponent("App.ipa")
        do {
            let report = StoreDownloadProgress.report
            report?(.init(phase: .downloading))
            let account = StoreResumeContext.account
            let folder = account.map { StoreResumeStore.folder(account: $0, bundleID: bundleID, version: output.bundleVersion) }
                ?? directory.appendingPathComponent("partial")
            let control = StoreTransferControl.shared
            let run = control.begin()
            setRun(run)
            defer { setRun(nil); control.end(run) }
            let download = StoreResumableDownload(folder: folder, validate: { try MirsaStorePolicy.downloadURL($0) },
                phase: { control.setPhase(run, $0) },
                report: { r, e, restarted in
                    control.progress(run, r, e)
                    report?(.init(phase: .downloading, received: r, expected: e, restarted: restarted))
                })
            do { try await download.download(url, to: destination, run: run) }
            catch {
                if run.discardRequested || account == nil || (!(error is CancellationError) && !(error is URLError)) {
                    StoreResumeStore.clear(folder)
                }
                throw error
            }
            try Task.checkCancellation()
            report?(.init(phase: .packaging))
            try Self.assemble(destination, output: output, bundleID: bundleID)
            report?(.init(phase: .validating))
            guard (try destination.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) > 0 else {
                throw MirsaStoreError.invalidPackage
            }
            try FileManager.default.setAttributes(Self.protection, ofItemAtPath: destination.path)
            handedOff = true
            return destination
        } catch {
            MirsaManagedTmp.end(directory)
            throw error
        }
    }

    private static var protection: [FileAttributeKey: Any] {
        #if os(iOS)
        return [.protectionKey: FileProtectionType.complete]
        #else
        return [:]
        #endif
    }

    /// Modifies only SINF/metadata entries, never executable bytes. No filesystem extraction.
    static func assemble(_ url: URL, output: DownloadOutput, bundleID: String) throws {
        let archive = try Archive(url: url, accessMode: .update)
        var paths = Set<String>()
        var expanded: UInt64 = 0
        var count = 0
        for entry in archive {
            try MirsaStorePolicy.archivePath(entry.path)
            count += 1
            guard count <= 100_000, paths.insert(entry.path).inserted, entry.type != .symlink else {
                throw MirsaStoreError.invalidPackage
            }
            let (sum, overflow) = expanded.addingReportingOverflow(UInt64(entry.uncompressedSize))
            guard !overflow, sum <= 16 * 1024 * 1024 * 1024 else { throw MirsaStoreError.invalidPackage }
            expanded = sum
        }
        let infos = paths.filter {
            let components = $0.split(separator: "/")
            return components.count == 3 && components[0] == "Payload" &&
                components[1].hasSuffix(".app") && components[2] == "Info.plist"
        }
        guard infos.count == 1, let infoPath = infos.first, let infoEntry = archive[infoPath] else {
            throw MirsaStoreError.invalidPackage
        }
        let info = try plist(archive, entry: infoEntry)
        guard info["CFBundleIdentifier"] as? String == bundleID,
              info["CFBundleShortVersionString"].map({ String(describing: $0) }) == output.bundleShortVersionString,
              info["CFBundleVersion"].map({ String(describing: $0) }) == output.bundleVersion,
              let executable = info["CFBundleExecutable"] as? String, !executable.contains("/"),
              !executable.isEmpty else { throw MirsaStoreError.invalidPackage }
        try MirsaStorePolicy.archivePath(executable)
        let root = String(infoPath.dropLast("Info.plist".count))
        guard archive[root + executable] != nil else { throw MirsaStoreError.invalidPackage }
        let sinfPaths: [String]
        if let manifest = archive[root + "SC_Info/Manifest.plist"] {
            guard let relative = try plist(archive, entry: manifest)["SinfPaths"] as? [String],
                  relative.count == output.sinfs.count, !relative.isEmpty else {
                throw MirsaStoreError.invalidPackage
            }
            for path in relative {
                try MirsaStorePolicy.archivePath(path)
                guard path.hasPrefix("SC_Info/"), path.hasSuffix(".sinf") else { throw MirsaStoreError.invalidPackage }
            }
            sinfPaths = relative.map { root + $0 }
        } else {
            guard output.sinfs.count == 1 else { throw MirsaStoreError.invalidPackage }
            sinfPaths = [root + "SC_Info/" + executable + ".sinf"]
        }
        guard Set(sinfPaths).count == sinfPaths.count else { throw MirsaStoreError.invalidPackage }
        for (path, sinf) in zip(sinfPaths, output.sinfs) { try add(sinf.sinf, path: path, archive: archive) }
        // Replace vendor metadata, if present, with the exact account-bound Apple response.
        if let old = archive["iTunesMetadata.plist"] { try archive.remove(old) }
        try add(output.iTunesMetadata, path: "iTunesMetadata.plist", archive: archive)
    }

    private static func plist(_ archive: Archive, entry: Entry) throws -> [String: Any] {
        guard entry.type == .file, entry.uncompressedSize <= 2 * 1024 * 1024 else {
            throw MirsaStoreError.invalidPackage
        }
        var bytes = Data()
        _ = try archive.extract(entry) { chunk in
            guard bytes.count + chunk.count <= 2 * 1024 * 1024 else { throw MirsaStoreError.invalidPackage }
            bytes.append(chunk)
        }
        guard let result = try PropertyListSerialization.propertyList(from: bytes, format: nil) as? [String: Any] else {
            throw MirsaStoreError.invalidPackage
        }
        return result
    }
    private static func add(_ data: Data, path: String, archive: Archive) throws {
        guard archive[path] == nil else { throw MirsaStoreError.invalidPackage }
        try archive.addEntry(with: path, type: .file, uncompressedSize: Int64(data.count),
                             compressionMethod: .deflate) { position, size in
            let start = Int(position)
            guard start >= 0, start <= data.count, size >= 0, size <= data.count - start else {
                throw MirsaStoreError.invalidPackage
            }
            return data.subdata(in: start..<(start + size))
        }
    }
}
