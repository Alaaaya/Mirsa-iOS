import Foundation
import Darwin
import Security
import ZIPFoundation

/// FairPlay decryption for App Store IPAs the user's own Apple ID bought.
///
/// Flow: extract the IPA, decrypt every encrypted Mach-O (main executable,
/// frameworks, app extensions) with the on-device kernel entry point, then
/// re-zip. The original encrypted IPA is never modified.
///
/// Two staging rules, both learned the hard way (errno 12 on every app
/// until they were fixed):
/// 1. The workdir must live in the app's own App Group container. A copy
///    under tmp is refused by the kernel (errno 12) even when the SINF is
///    present and correct, because fairplayd only reads licences from
///    system-recognised containers. Falls back to tmp only when the app
///    was signed without an App Group (then decryption is expected to fail).
/// 2. Every binary gets its OWN licence (SC_Info/<name>.sinf next to it),
///    resolved from the Manifest's SinfPaths when it is not already there.
///    Frameworks in App Store packages usually have no licence of their own
///    - the Manifest lists only the main licence - so a binary with no
///    licence of its own falls back to the main executable's licence, which
///    covers the whole purchase (the app's own licence, for the user's own
///    bought app). The licence is staged next to the binary because
///    fairplayd looks it up by the binary's own path.
/// Staged copies are removed afterwards.
///
/// No network calls. No signing, no re-signing, no key material anywhere:
/// the kernel + fairplayd do the decryption, Mirsa only hands them the
/// mapped pages. The decrypted IPA still needs Mirsa's normal signing to
/// install, exactly like any other IPA.
enum FairPlayDecryptor {
    struct Report {
        var decrypted: [String]     // Binary names that were encrypted and are now clear.
        var alreadyClear: [String]  // Binaries that were already unencrypted.
        var outputURL: URL          // Decrypted IPA. Caller must consume it, then end workDir.
        var workDir: URL            // Workdir lease; caller must end it (see endWorkDir) after consuming outputURL.
        var workDirIsAppGroup: Bool // True when workDir lives in the App Group container (not tmp).
    }

    enum Error: LocalizedError {
        case notIPA
        case noApp
        case noExecutable
        case noLicence(binary: String, detail: String)
        case decryptFailed(binary: String, message: String)
        case verificationFailed(binary: String)
        case ioError(String)

        var errorDescription: String? {
            switch self {
            case .notIPA:
                return tr("This file is not a valid IPA.", "هالملف مو IPA صالح.",
                          ckb: "ئەم فایلە IPAی دروست نییە.", kmr: "Ev pel ne IPA ya derbasdar e.")
            case .noApp:
                return tr("No app was found inside the IPA.", "ما في تطبيق جوّا الـIPA.",
                          ckb: "هیچ ئەپێک لەناو IPA نییە.", kmr: "Di IPA de sepan nehat dîtin.")
            case .noExecutable:
                return tr("The app's executable could not be found.", "ما لقينا الملف التنفيذي تبع التطبيق.",
                          ckb: "فایلی جێبەجێکراوی ئەپ نەدۆزرایەوە.", kmr: "Pelê cîbicîkirî ya sepanê nehat dîtin.")
            case .noLicence(let binary, let detail):
                return tr("No purchase licence (sinf) for \(binary). Decryption needs the Apple ID that bought the app.\n\(detail)",
                          "ما في رخصة شراء (sinf) لـ\(binary). فك التشفير بدو حساب Apple يلي اشترى التطبيق.\n\(detail)",
                          ckb: "هیچ مۆڵەتی کڕین (sinf) بۆ \(binary) نییە. ڕەمزکردنەوە پێویستی بە Apple IDی کڕیار هەیە.\n\(detail)",
                          kmr: "Ji bo \(binary) lîsansa kirînê (sinf) tune. Vekirina şîfreyê Apple ID ya kirrîyar dixwaze.\n\(detail)")
            case .decryptFailed(let binary, let message):
                return tr("Could not decrypt \(binary): \(message)", "ما قدرنا نفك تشفير \(binary): \(message)",
                          ckb: "نەتوانرا \(binary) ڕەمز بکرێتەوە: \(message)", kmr: "Nehat \(binary) şîfre kirin: \(message)")
            case .verificationFailed(let binary):
                return tr("\(binary) is still encrypted after decryption.", "\(binary) لسا مشفّر بعد فك التشفير.",
                          ckb: "\(binary) هێشتا شفرەکراوە دوای ڕەمزکردنەوە.", kmr: "\(binary) piştî vekirina şîfreyê hêj şîfrekirî ye.")
            case .ioError(let detail):
                return tr("Decryption failed: \(detail)", "فشل فك التشفير: \(detail)",
                          ckb: "ڕەمزکردنەوە سەرکەوتوو نەبوو: \(detail)", kmr: "Vekirina şîfreyê têk çû: \(detail)")
            }
        }
    }

    private static let maxEntries = 30_000
    private static let maxTotalUncompressed: UInt64 = 6 * 1024 * 1024 * 1024
    private static let chunk: UInt64 = 4 << 20

    /// Decrypts the encrypted IPA at `url` into a new IPA. The input file is
    /// never modified. Must run off the main actor (blocking file I/O + syscalls).
    static func decryptIPA(at url: URL) throws -> Report {
        let (work, isAppGroup) = try workDir()
        var handedOff = false
        defer { if !handedOff { endWorkDir(work, isAppGroup: isAppGroup) } }
        let extracted = work.appendingPathComponent("extracted", isDirectory: true)
        let output = work.appendingPathComponent("decrypted.ipa")
        do {
            try extract(archive: url, to: extracted)
            let appDir = try findApp(in: extracted)
            let executable = try mainExecutable(in: appDir)
            let binaries = try collectBinaries(appDir: appDir, executable: executable)
            guard !binaries.isEmpty else { throw Error.noExecutable }
            // Licences are only staged for binaries that are actually
            // encrypted: an already-clear binary never talks to fairplayd.
            var encrypted: [Binary] = [], alreadyClear: [String] = []
            for binary in binaries {
                if try isEncrypted(binary.url) { encrypted.append(binary) } else { alreadyClear.append(binary.name) }
            }
            let staged = try stageLicences(appDir: appDir, binaries: encrypted)
            defer { removeStaged(staged) }
            var decrypted: [String] = []
            for binary in encrypted {
                switch decryptFile(binary.url) {
                case .decrypted: decrypted.append(binary.name)
                case .alreadyClear: alreadyClear.append(binary.name)
                case .failed(let message): throw Error.decryptFailed(binary: binary.name, message: message)
                }
            }
            for binary in binaries {
                guard try isClear(binary.url) else { throw Error.verificationFailed(binary: binary.name) }
            }
            try rezip(tree: extracted, to: output)
            handedOff = true
            return Report(decrypted: decrypted, alreadyClear: alreadyClear, outputURL: output, workDir: work, workDirIsAppGroup: isAppGroup)
        } catch let e as Error {
            throw e
        } catch {
            throw Error.ioError(error.localizedDescription)
        }
    }

    /// Removes a workdir created by decryptIPA. The caller ends the lease
    /// after consuming the decrypted IPA (see Report.workDir).
    static func endWorkDir(_ report: Report) {
        endWorkDir(report.workDir, isAppGroup: report.workDirIsAppGroup)
    }

    private static func endWorkDir(_ dir: URL, isAppGroup: Bool) {
        if isAppGroup {
            try? FileManager.default.removeItem(at: dir)
        } else {
            MirsaManagedTmp.end(dir)
        }
    }

    /// The App Group container is the only place fairplayd will read a
    /// licence from: a temp-dir copy is refused with errno 12 even when the
    /// SINF is present and correct. Resolves the app's own groups from its
    /// entitlements and returns the first usable container, or nil when the
    /// app was signed without an App Group.
    private static func appGroupContainer() -> URL? {
        guard let groups = appGroupIdentifiers(), !groups.isEmpty else { return nil }
        let fm = FileManager.default
        for id in groups {
            guard let url = fm.containerURL(forSecurityApplicationGroupIdentifier: id) else { continue }
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                return url
            }
        }
        return nil
    }

    /// The app's declared App Group identifiers from its runtime
    /// entitlements, or nil when they cannot be read. SecTask is not
    /// exposed to Swift (even with `import Security`), so the two SecTask
    /// entry points are resolved at runtime with dlsym — the same pattern
    /// PosterBoardAccess.m uses — instead of being called directly.
    private static func appGroupIdentifiers() -> [String]? {
        typealias CreateTaskFn = @convention(c) (CFDictionary?) -> CFTypeRef?
        typealias CopyEntitlementFn = @convention(c) (CFTypeRef, CFString, UnsafeMutablePointer<CFError?>?) -> CFTypeRef?

        func resolve(_ name: String) -> UnsafeMutableRawPointer? {
            // RTLD_DEFAULT is the C macro ((void *) -2); Swift cannot import it,
            // so its pointer value is spelled out here.
            let rtldDefault = UnsafeMutableRawPointer(bitPattern: -2)!
            if let sym = dlsym(rtldDefault, name) { return sym }
            guard let handle = dlopen("/System/Library/Frameworks/Security.framework/Security", RTLD_NOW | RTLD_LOCAL) else { return nil }
            return dlsym(handle, name)
        }
        guard let createPtr = resolve("SecTaskCreateFromSelf"),
              let copyPtr = resolve("SecTaskCopyValueForEntitlement") else {
            return nil
        }
        let create = unsafeBitCast(createPtr, to: CreateTaskFn.self)
        let copy = unsafeBitCast(copyPtr, to: CopyEntitlementFn.self)
        guard let task = create(nil) else { return nil }
        var error: CFError?
        guard let value = copy(task, "com.apple.security.application-groups" as CFString, &error) else {
            return nil
        }
        if let groups = value as? [String] { return groups }
        if let group = value as? String { return [group] }
        return nil
    }

    /// Workdir for one decrypt operation. Prefers the App Group container;
    /// falls back to the tmp lease only when no App Group is available.
    /// Stale fairplay-decrypt dirs in the group container are leftovers of
    /// crashed runs (only one decrypt runs at a time) and are swept first.
    private static func workDir() throws -> (URL, Bool) {
        if let group = appGroupContainer() {
            let fm = FileManager.default
            for name in (try? fm.contentsOfDirectory(atPath: group.path)) ?? [] where name.hasPrefix("mirsa-fairplay-decrypt-") {
                try? fm.removeItem(at: group.appendingPathComponent(name, isDirectory: true))
            }
            let dir = group.appendingPathComponent("mirsa-fairplay-decrypt-" + UUID().uuidString, isDirectory: true)
            try fm.createDirectory(at: dir, withIntermediateDirectories: false)
            return (dir, true)
        }
        return (try MirsaManagedTmp.begin("fairplay-decrypt"), false)
    }

    // MARK: - Extraction (ZipReader with the standard IPA limits, not the
    // 64 MB file-tools cap: real IPAs are far larger).

    private static func extract(archive: URL, to dest: URL) throws {
        var limits = IPALimits.standard
        limits.rejectSymlinks = true
        let data: Data
        do { data = try Data(contentsOf: archive, options: .mappedIfSafe) } catch { throw Error.notIPA }
        let zip: ZipReader
        do { zip = try ZipReader(data: data, limits: limits) } catch { throw Error.notIPA }
        let fm = FileManager.default
        try fm.createDirectory(at: dest, withIntermediateDirectories: false)
        var seen = Set<String>(), dirs = Set<String>()
        for e in zip.entries {
            let isDir = e.name.hasSuffix("/")
            let clean = isDir ? String(e.name.dropLast()) : e.name
            if clean.isEmpty { continue }
            // Diagnostics: a path-guard failure must name the entry that
            // caused it. Without this the UI only shows a bare
            // "BundleFileError error 1" and the offending entry is hidden.
            do {
                let parts = try BundlePath.components(clean)
                if parts.first == "__MACOSX" || parts.last == ".DS_Store" { continue }
                let key = clean.lowercased()
                guard seen.insert(key).inserted else { throw Error.ioError("duplicate entry " + clean) }
                for i in 1..<max(parts.count, 1) { dirs.insert(parts[0..<i].joined(separator: "/").lowercased()) }
                if isDir { dirs.insert(key) }
                let target = try BundlePath.resolve(clean, in: dest, mustExist: false)
                if isDir { try fm.createDirectory(at: target, withIntermediateDirectories: true); continue }
                guard !dirs.contains(key) else { throw Error.ioError("file/folder clash " + clean) }
                try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                _ = try BundlePath.resolve(BundlePath.parent(clean), in: dest, mustExist: false)
                guard fm.createFile(atPath: target.path, contents: nil) else { throw Error.ioError(clean) }
                let h = try FileHandle(forWritingTo: target)
                defer { try? h.close() }
                var off: UInt64 = 0
                while off < e.uncompressedSize {
                    let bytes = try zip.read(e, offset: off, length: min(chunk, e.uncompressedSize - off), limits: limits)
                    if bytes.isEmpty { break }
                    try h.write(contentsOf: bytes)
                    off += UInt64(bytes.count)
                }
                guard off == e.uncompressedSize else { throw Error.ioError("corrupt entry " + clean) }
            } catch let error as BundleFileError {
                throw Error.ioError("extracting \(clean): \(String(describing: error))")
            } catch let error as Error {
                throw error
            } catch {
                throw Error.ioError("extracting \(clean): \(error.localizedDescription)")
            }
        }
    }

    // MARK: - App layout

    private static func findApp(in extracted: URL) throws -> URL {
        let payload = extracted.appendingPathComponent("Payload", isDirectory: true)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: payload.path)) ?? []
        let apps = names.filter { $0.hasSuffix(".app") }
        guard apps.count == 1 else { throw Error.noApp }
        return payload.appendingPathComponent(apps[0], isDirectory: true)
    }

    private static func mainExecutable(in appDir: URL) throws -> String {
        let infoURL = appDir.appendingPathComponent("Info.plist")
        guard let data = try? Data(contentsOf: infoURL),
              let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let exe = info["CFBundleExecutable"] as? String, !exe.isEmpty, !exe.contains("/") else {
            throw Error.noExecutable
        }
        return exe
    }

    private struct Binary {
        var name: String
        var url: URL
    }

    private static let machOMagics: [Data] = [
        Data([0xCF, 0xFA, 0xED, 0xFE]), // MH_MAGIC_64 (little-endian)
        Data([0xCE, 0xFA, 0xED, 0xFE]), // MH_MAGIC (little-endian)
        Data([0xCA, 0xFE, 0xBA, 0xBE]), // FAT_MAGIC (big-endian)
        Data([0xCA, 0xFE, 0xBA, 0xBF]), // FAT_MAGIC_64 (big-endian)
    ]

    private static func isMachO(_ url: URL) -> Bool {
        guard let h = try? FileHandle(forReadingFrom: url), let head = try? h.read(upToCount: 4) else { return false }
        try? h.close()
        return machOMagics.contains(head)
    }

    /// Every Mach-O in the app bundle, found by a recursive scan: the main
    /// executable first, then every other file whose header is a Mach-O
    /// (frameworks at any depth, app extensions, bare .dylib files, and any
    /// other place the app hides a binary). A hardcoded Frameworks /
    /// PlugIns walk misses nested frameworks and bare dylibs, and a binary
    /// it misses stays FairPlay-encrypted: the decrypt then reports success
    /// and the install fails later at signing with "not a valid Mach-O
    /// file". Watch apps are skipped: they cannot run on iPhone.
    private static func collectBinaries(appDir: URL, executable: String) throws -> [Binary] {
        let fm = FileManager.default
        var out: [Binary] = []
        var seen = Set<String>()
        let main = appDir.appendingPathComponent(executable)
        guard fm.fileExists(atPath: main.path), isMachO(main) else { throw Error.noExecutable }
        out.append(Binary(name: executable, url: main))
        seen.insert(main.standardizedFileURL.path)
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey, .isRegularFileKey]
        guard let enumerator = fm.enumerator(at: appDir, includingPropertiesForKeys: keys) else { return out }
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: Set(keys))
            if values?.isSymbolicLink == true { continue }
            if values?.isDirectory == true {
                if url.lastPathComponent == "Watch" { enumerator.skipDescendants() }
                continue
            }
            guard values?.isRegularFile == true else { continue }
            let path = url.standardizedFileURL.path
            guard !seen.contains(path), isMachO(url) else { continue }
            seen.insert(path)
            out.append(Binary(name: url.lastPathComponent, url: url))
        }
        return out
    }

    // MARK: - Licences (SINF staging)

    private struct StagedLicence {
        var sinfURL: URL
        var createdDir: URL?
    }

    /// Ensures every binary has SC_Info/<name>.sinf next to it, because
    /// fairplayd looks the licence up by the binary's own path. The licence
    /// is resolved from SC_Info/Manifest.plist's SinfPaths (the server's
    /// per-component list) when it is not already there. A binary with no
    /// licence of its own falls back to the main executable's licence (the
    /// app's own licence, covering the whole purchase); only when that is
    /// missing too does it fail with noLicence.
    private static func stageLicences(appDir: URL, binaries: [Binary]) throws -> [StagedLicence] {
        let fm = FileManager.default
        let scInfo = appDir.appendingPathComponent("SC_Info", isDirectory: true)
        let manifestPaths: [String] = {
            let manifest = scInfo.appendingPathComponent("Manifest.plist")
            guard let data = try? Data(contentsOf: manifest),
                  let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                  let paths = plist["SinfPaths"] as? [String] else { return [] }
            return paths
        }()
        // The main executable's licence, used as a fallback for binaries
        // that have no licence of their own (frameworks in App Store
        // packages: the Manifest lists only the main licence). It is the
        // app's own licence for the user's own bought app, staged next to
        // the binary because fairplayd looks it up by the binary's path.
        // The binary's own signature is registered before decrypt
        // (F_ADDFILESIGS), so the kernel validates the staged licence.
        let mainLicence: URL? = {
            guard let main = binaries.first else { return nil }
            let own = scInfo.appendingPathComponent(main.name + ".sinf")
            if fm.fileExists(atPath: own.path) { return own }
            if let rel = manifestPaths.first(where: { ($0 as NSString).lastPathComponent == main.name + ".sinf" }) {
                let candidate = appDir.appendingPathComponent(rel)
                if fm.fileExists(atPath: candidate.path) { return candidate }
            }
            return nil
        }()
        var staged: [StagedLicence] = []
        for binary in binaries {
            let dir = binary.url.deletingLastPathComponent()
            let target = dir.appendingPathComponent("SC_Info", isDirectory: true)
                .appendingPathComponent(binary.name + ".sinf")
            if fm.fileExists(atPath: target.path) { continue }
            // The binary's own licence: the Manifest entry named after it,
            // then the app's SC_Info copy under the same name. If neither
            // exists, fall back to the main executable's licence.
            let source: URL
            if let rel = manifestPaths.first(where: { ($0 as NSString).lastPathComponent == binary.name + ".sinf" }) {
                let candidate = appDir.appendingPathComponent(rel)
                if fm.fileExists(atPath: candidate.path) {
                    source = candidate
                } else if let main = mainLicence {
                    source = main
                } else {
                    throw Error.noLicence(binary: binary.name, detail: licenceDiagnostic(appDir: appDir, binary: binary, manifestPaths: manifestPaths, searched: [target.path, candidate.path]))
                }
            } else {
                let own = scInfo.appendingPathComponent(binary.name + ".sinf")
                if fm.fileExists(atPath: own.path) {
                    source = own
                } else if let main = mainLicence {
                    source = main
                } else {
                    throw Error.noLicence(binary: binary.name, detail: licenceDiagnostic(appDir: appDir, binary: binary, manifestPaths: manifestPaths, searched: [target.path, own.path]))
                }
            }
            var createdDir: URL? = nil
            let dirURL = target.deletingLastPathComponent()
            if !fm.fileExists(atPath: dirURL.path) {
                try fm.createDirectory(at: dirURL, withIntermediateDirectories: false)
                createdDir = dirURL
            }
            try fm.copyItem(at: source, to: target)
            staged.append(StagedLicence(sinfURL: target, createdDir: createdDir))
        }
        return staged
    }

    /// Diagnostic for a missing licence: what .sinf files exist, what the
    /// Manifest lists, and which paths were searched. Shown in the error so
    /// the user can see whether the IPA lacks the licence or the lookup is
    /// wrong. Diagnostic only; it never creates, copies or alters a licence.
    private static func licenceDiagnostic(appDir: URL, binary: Binary, manifestPaths: [String], searched: [String]) -> String {
        let fm = FileManager.default
        let scInfo = appDir.appendingPathComponent("SC_Info", isDirectory: true)
        let scExists = fm.fileExists(atPath: scInfo.path)
        let sinfFiles: [String] = {
            guard scExists, let names = try? fm.contentsOfDirectory(atPath: scInfo.path) else { return [] }
            return names.filter { $0.hasSuffix(".sinf") }.sorted()
        }()
        let manifestList = manifestPaths.isEmpty ? "(empty/missing)" : manifestPaths.joined(separator: ", ")
        let sinfList = sinfFiles.isEmpty ? "(none)" : sinfFiles.joined(separator: ", ")
        return """
        [diag] binary: \(binary.name)
        [diag] binary path: \(binary.url.path)
        [diag] SC_Info exists: \(scExists ? "yes" : "no")
        [diag] .sinf in app SC_Info: \(sinfList)
        [diag] Manifest SinfPaths: \(manifestList)
        [diag] searched: \(searched.joined(separator: " | "))
        """
    }

    private static func removeStaged(_ staged: [StagedLicence]) {
        let fm = FileManager.default
        for item in staged {
            try? fm.removeItem(at: item.sinfURL)
            if let dir = item.createdDir { try? fm.removeItem(at: dir) }
        }
    }

    // MARK: - Decrypt + verify

    private enum FileOutcome {
        case decrypted, alreadyClear
        case failed(String)
    }

    private static func decryptFile(_ url: URL) -> FileOutcome {
        var errbuf = [CChar](repeating: 0, count: 512)
        let result = url.path.withCString { cpath in
            errbuf.withUnsafeMutableBufferPointer { buf in
                mirsa_fp_decrypt_macho(cpath, buf.baseAddress, buf.count)
            }
        }
        switch result.rawValue {
        case 0: return .decrypted
        case 1: return .alreadyClear
        default:
            let detail = errbuf.withUnsafeBufferPointer { ptr in
                ptr.baseAddress.map { String(cString: $0) } ?? ""
            }
            let message = detail.isEmpty ? String(cString: mirsa_fp_result_message(result)) : detail
            return .failed(message)
        }
    }

    /// Confirms every slice of the file has cryptid == 0 after decryption.
    private static func isClear(_ url: URL) throws -> Bool {
        let slices = try MachOViewer.report(for: url)
        return slices.allSatisfy { !$0.encrypted }
    }

    /// True when any slice of the file carries a non-zero cryptid.
    private static func isEncrypted(_ url: URL) throws -> Bool {
        let slices = try MachOViewer.report(for: url)
        return slices.contains { $0.encrypted }
    }

    // MARK: - Re-zip (ZIPFoundation, streaming, deterministic order)

    private static func rezip(tree: URL, to dest: URL) throws {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: tree, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey, .isRegularFileKey]) else {
            throw Error.ioError("cannot list extracted files")
        }
        var files: [(rel: String, url: URL, isDir: Bool)] = []
        var total: UInt64 = 0
        for case let item as URL in enumerator {
            let values = try item.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey, .isRegularFileKey])
            guard values.isSymbolicLink == false else { throw Error.ioError("symlink in IPA: " + item.lastPathComponent) }
            let rel = String(item.standardizedFileURL.path.dropFirst(tree.standardizedFileURL.path.count + 1))
            guard !rel.isEmpty else { continue }
            if values.isDirectory == true {
                files.append((rel, item, true))
            } else if values.isRegularFile == true {
                total += UInt64(values.fileSize ?? 0)
                guard total <= maxTotalUncompressed else { throw Error.ioError("IPA too large") }
                files.append((rel, item, false))
            }
        }
        guard files.count <= maxEntries else { throw Error.ioError("too many files in IPA") }
        files.sort { $0.rel < $1.rel }
        try? fm.removeItem(at: dest)
        let archive = try Archive(url: dest, accessMode: .create)
        for entry in files {
            if entry.isDir {
                try archive.addEntry(with: entry.rel + "/", type: .directory, uncompressedSize: Int64(0),
                                     compressionMethod: .none) { _, _ in Data() }
            } else {
                let fileSize =
                    (try fm.attributesOfItem(atPath: entry.url.path)[.size] as? NSNumber)?
                    .int64Value ?? 0

                let handle = try FileHandle(forReadingFrom: entry.url)
                defer { try? handle.close() }

                try archive.addEntry(
                    with: entry.rel,
                    type: .file,
                    uncompressedSize: fileSize,
                    compressionMethod: .deflate
                ) { position, requestedSize in
                    // ZIPFoundation may call the provider at end-of-file or
                    // with a zero-sized request; an empty read there is
                    // expected, not a failure. Only a genuinely short read
                    // (fewer bytes than remain) is an error.
                    if Int64(position) >= fileSize {
                        return Data()
                    }

                    try handle.seek(toOffset: UInt64(position))

                    let remaining = fileSize - Int64(position)
                    let amount = min(Int64(requestedSize), remaining)

                    guard amount > 0,
                          let bytes = try handle.read(upToCount: Int(amount)),
                          !bytes.isEmpty else {
                        throw Error.ioError("short read: " + entry.rel)
                    }

                    return bytes
                }
            }
        }
        // Archive deallocates (and finalises the file) when it leaves scope.
    }
}
