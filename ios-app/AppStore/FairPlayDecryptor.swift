import Foundation
import ZIPFoundation

/// FairPlay decryption for App Store IPAs the user's own Apple ID bought.
///
/// Flow: extract the IPA, decrypt every encrypted Mach-O (main executable,
/// frameworks, app extensions) with the on-device kernel entry point, then
/// re-zip. The original encrypted IPA is never modified. Decryption only
/// works when fairplayd can find the account's licence
/// (<dir>/SC_Info/<name>.sinf next to each binary); the main licence is
/// staged next to extension/framework binaries that ship without their own,
/// exactly as installd replicates it on install, and the staged copies are
/// removed afterwards.
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
        var workDir: URL            // MirsaManagedTmp lease; caller must end it after consuming outputURL.
    }

    enum Error: LocalizedError {
        case notIPA
        case noApp
        case noExecutable
        case noLicence(binary: String)
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
            case .noLicence(let binary):
                return tr("No purchase licence (sinf) for \(binary). Decryption needs the Apple ID that bought the app.",
                          "ما في رخصة شراء (sinf) لـ\(binary). فك التشفير بدو حساب Apple يلي اشترى التطبيق.",
                          ckb: "هیچ مۆڵەتی کڕین (sinf) بۆ \(binary) نییە. ڕەمزکردنەوە پێویستی بە Apple IDی کڕیار هەیە.",
                          kmr: "Ji bo \(binary) lîsansa kirînê (sinf) tune. Vekirina şîfreyê Apple ID ya kirrîyar dixwaze.")
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
        let work = try MirsaManagedTmp.begin("fairplay-decrypt")
        var handedOff = false
        defer { if !handedOff { MirsaManagedTmp.end(work) } }
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
            let staged = try stageLicences(appDir: appDir, executable: executable, binaries: encrypted)
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
            return Report(decrypted: decrypted, alreadyClear: alreadyClear, outputURL: output, workDir: work)
        } catch let e as Error {
            throw e
        } catch {
            throw Error.ioError(error.localizedDescription)
        }
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

    /// Main executable, top-level frameworks, app extensions, and frameworks
    /// nested inside app extensions. Watch apps are skipped: they cannot run
    /// on iPhone.
    private static func collectBinaries(appDir: URL, executable: String) throws -> [Binary] {
        let fm = FileManager.default
        var out: [Binary] = []
        let main = appDir.appendingPathComponent(executable)
        guard fm.fileExists(atPath: main.path), isMachO(main) else { throw Error.noExecutable }
        out.append(Binary(name: executable, url: main))
        func scanFrameworks(in dir: URL) {
            for name in (try? fm.contentsOfDirectory(atPath: dir.path)) ?? [] where name.hasSuffix(".framework") {
                let binaryName = String(name.dropLast(".framework".count))
                let binary = dir.appendingPathComponent(name, isDirectory: true).appendingPathComponent(binaryName)
                if fm.fileExists(atPath: binary.path), isMachO(binary) {
                    out.append(Binary(name: binaryName, url: binary))
                }
            }
        }
        scanFrameworks(in: appDir.appendingPathComponent("Frameworks", isDirectory: true))
        let plugins = appDir.appendingPathComponent("PlugIns", isDirectory: true)
        for name in (try? fm.contentsOfDirectory(atPath: plugins.path)) ?? [] where name.hasSuffix(".appex") {
            let appexDir = plugins.appendingPathComponent(name, isDirectory: true)
            let binaryName = String(name.dropLast(".appex".count))
            let binary = appexDir.appendingPathComponent(binaryName)
            if fm.fileExists(atPath: binary.path), isMachO(binary) {
                out.append(Binary(name: binaryName, url: binary))
            }
            scanFrameworks(in: appexDir.appendingPathComponent("Frameworks", isDirectory: true))
        }
        return out
    }

    // MARK: - Licences (SINF staging)

    private struct StagedLicence {
        var sinfURL: URL
        var createdDir: URL?
    }

    /// Ensures every binary has SC_Info/<name>.sinf next to it, because
    /// fairplayd looks the licence up by the binary's own path. Prefers the
    /// binary's own licence from the app's SC_Info, falls back to the main
    /// executable's licence (the replication installd performs on install).
    private static func stageLicences(appDir: URL, executable: String, binaries: [Binary]) throws -> [StagedLicence] {
        let fm = FileManager.default
        let scInfo = appDir.appendingPathComponent("SC_Info", isDirectory: true)
        let mainSinf = scInfo.appendingPathComponent(executable + ".sinf")
        var staged: [StagedLicence] = []
        for binary in binaries {
            let dir = binary.url.deletingLastPathComponent()
            let target = dir.appendingPathComponent("SC_Info", isDirectory: true)
                .appendingPathComponent(binary.name + ".sinf")
            if fm.fileExists(atPath: target.path) { continue }
            let own = scInfo.appendingPathComponent(binary.name + ".sinf")
            let source: URL
            if fm.fileExists(atPath: own.path) { source = own }
            else if fm.fileExists(atPath: mainSinf.path) { source = mainSinf }
            else { throw Error.noLicence(binary: binary.name) }
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
        guard let enumerator = fm.enumerator(at: tree, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey]) else {
            throw Error.ioError("cannot list extracted files")
        }
        var files: [(rel: String, url: URL, isDir: Bool)] = []
        var total: UInt64 = 0
        for case let item as URL in enumerator {
            let values = try item.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey])
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
                let size = (try fm.attributesOfItem(atPath: entry.url.path)[.size] as? NSNumber)?.int64Value ?? 0
                let handle = try FileHandle(forReadingFrom: entry.url)
                defer { try? handle.close() }
                try archive.addEntry(with: entry.rel, type: .file, uncompressedSize: size,
                                     compressionMethod: .deflate) { position, size in
                    try handle.seek(toOffset: UInt64(position))
                    guard let bytes = try handle.read(upToCount: size), !bytes.isEmpty else {
                        throw Error.ioError("short read: " + entry.rel)
                    }
                    return bytes
                }
            }
        }
        // Archive deallocates (and finalises the file) when it leaves scope.
    }
}
