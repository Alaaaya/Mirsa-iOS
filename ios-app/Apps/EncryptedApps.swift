import Foundation
import UIKit
import ImageIO

// MARK: - "App Store" tab: App Store IPAs installed exactly as they are.
//
// Mirsa never decrypts, re-signs or edits these packages. It reads the package
// metadata (iTunesMetadata.plist, Info.plist, SC_Info/*.sinf) to show who bought
// the app, then hands the original file to installation_proxy on Wi-Fi or serves it
// locally to the iOS installer on cellular. iOS
// alone decides whether the FairPlay purchase is valid on this device.

enum EncryptedText {
    static func t(_ en: String, _ ar: String, _ ckb: String, _ kmr: String) -> String {
        tr(en, ar, ckb: ckb, kmr: kmr)
    }
    static var tabTitle: String { t("App Store", "متجر أبل", "فرۆشگای ئەپڵ", "Firoşgeha Apple") }
}

/// What the package says about itself. Pure data, parsed without touching the archive.
struct EncryptedIPAMetadata: Codable, Equatable {
    var itemName: String?
    var itemID: Int64?
    var bundleID: String?
    var version: String?
    var purchaserAppleID: String?
    var purchaserName: String?
    var artistName: String?

    /// Reads an iTunesMetadata.plist (binary or XML). Handles the classic App Store
    /// layout (`com.apple.iTunesStore.downloadInfo.accountInfo.AppleID`), the older
    /// top-level `appleId`, and the `apple-id` / `userName` keys that ipatool writes.
    static func parse(_ data: Data) -> EncryptedIPAMetadata? {
        guard let root = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any] else { return nil }
        func str(_ v: Any?) -> String? {
            if let s = v as? String { let t = s.trimmingCharacters(in: .whitespacesAndNewlines); return t.isEmpty ? nil : t }
            if let n = v as? NSNumber { return n.stringValue }
            return nil
        }
        let downloadInfo = root["com.apple.iTunesStore.downloadInfo"] as? [String: Any]
        let account = downloadInfo?["accountInfo"] as? [String: Any]
        var m = EncryptedIPAMetadata()
        m.itemName = str(root["itemName"]) ?? str(root["playlistName"])
        m.itemID = (root["itemId"] as? NSNumber)?.int64Value ?? str(root["itemId"]).flatMap { Int64($0) }
        m.bundleID = str(root["softwareVersionBundleId"])
        m.version = str(root["bundleShortVersionString"]) ?? str(root["bundleVersion"])
        m.artistName = str(root["artistName"])
        m.purchaserAppleID = str(account?["AppleID"]) ?? str(root["appleId"]) ?? str(root["apple-id"])
            ?? str(account?["UserName"]) ?? str(root["userName"])
        let first = str(account?["FirstName"]), last = str(account?["LastName"])
        let full = [first, last].compactMap { $0 }.joined(separator: " ")
        m.purchaserName = full.isEmpty ? (str(account?["AccountName"]) ?? nil) : full
        return m
    }
}

enum EncryptedAccountMatch: Equatable {
    case match
    case mismatch(signedIn: String)
    case noSignedInAccount
    case unknownPurchaser

    /// Case-insensitive compare of the purchaser with every Apple ID the user signed in to Mirsa with.
    static func evaluate(purchaser: String?, signedIn: [String]) -> EncryptedAccountMatch {
        let accounts = signedIn.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard let p = purchaser?.trimmingCharacters(in: .whitespacesAndNewlines), !p.isEmpty else { return .unknownPurchaser }
        guard !accounts.isEmpty else { return .noSignedInAccount }
        if accounts.contains(where: { $0.caseInsensitiveCompare(p) == .orderedSame }) { return .match }
        return .mismatch(signedIn: accounts[0])
    }
}

/// One imported encrypted package in the library.
struct EncryptedIPAEntry: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var bundleID: String
    var version: String
    var sizeBytes: Int64
    var hasSinf: Bool
    var hasMetadata: Bool
    var encryptedBinary: Bool?
    var metadata: EncryptedIPAMetadata?
    var addedAt: Date
    var installedAt: Date?
}

enum EncryptedIPAError: LocalizedError {
    case notIPA, noApp, noInfo
    var errorDescription: String? {
        switch self {
        case .notIPA: return EncryptedText.t("This file is not a valid IPA.", "هالملف مو IPA صالح.", "ئەم فایلە IPAی دروست نییە.", "Ev pel ne IPA ya derbasdar e.")
        case .noApp: return EncryptedText.t("No app was found inside the IPA.", "ما في تطبيق جوّا الـIPA.", "هیچ ئەپێک لەناو IPA نییە.", "Di IPA de sepan nehat dîtin.")
        case .noInfo: return EncryptedText.t("The app's Info.plist could not be read.", "ما قدرنا نقرأ Info.plist تبع التطبيق.", "Info.plistی ئەپ نەخوێندرایەوە.", "Info.plist ya sepanê nehat xwendin.")
        }
    }
}

/// Read-only inspection of an encrypted IPA (no extraction to disk, nothing modified).
enum EncryptedIPAInspector {
    struct Result {
        var entry: EncryptedIPAEntry
        var icon: Data?
    }

    static func inspect(_ url: URL) throws -> Result {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        let zip: ZipReader
        do { zip = try ZipReader(data: data) } catch { throw EncryptedIPAError.notIPA }
        var appDir: String?
        for e in zip.entries {
            let c = e.name.split(separator: "/", omittingEmptySubsequences: true)
            if c.count >= 2, c[0] == "Payload", c[1].hasSuffix(".app") { appDir = String(c[1]); break }
        }
        guard let app = appDir else { throw EncryptedIPAError.noApp }
        let base = "Payload/\(app)/"
        func read(_ name: String, max: UInt64 = 4 * 1024 * 1024) -> Data? {
            guard let e = zip.entry(name), e.uncompressedSize <= max else { return nil }
            return try? zip.read(e, length: e.uncompressedSize)
        }
        guard let infoData = read(base + "Info.plist"),
              let info = (try? PropertyListSerialization.propertyList(from: infoData, format: nil)) as? [String: Any],
              let bid = info["CFBundleIdentifier"] as? String, !bid.isEmpty else { throw EncryptedIPAError.noInfo }
        let exe = info["CFBundleExecutable"] as? String ?? ""
        let sinf = exe.isEmpty || exe.contains("/") ? false : zip.entry(base + "SC_Info/\(exe).sinf") != nil
        let meta = read("iTunesMetadata.plist").flatMap(EncryptedIPAMetadata.parse)
        var encrypted: Bool?
        if !exe.isEmpty, let e = zip.entry(base + exe) {
            if let head = try? zip.read(e, length: min(e.uncompressedSize, 64 * 1024)) {
                if let slices = MachOInspector.fatSlices(head), let arm = slices.first(where: { $0.cpu == MachOInspector.cpuArm64 }) {
                    if let thin = try? zip.read(e, offset: arm.offset, length: min(arm.size, 64 * 1024)) {
                        encrypted = (try? MachOInspector.inspectThin(thin))?.encrypted
                    }
                } else {
                    encrypted = (try? MachOInspector.inspectThin(head))?.encrypted
                }
            }
        }
        let display = (info["CFBundleDisplayName"] as? String) ?? (info["CFBundleName"] as? String) ?? meta?.itemName ?? bid
        let version = (info["CFBundleShortVersionString"] as? String) ?? meta?.version ?? "?"
        let size = Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? data.count)
        let entry = EncryptedIPAEntry(id: UUID(), name: display, bundleID: bid, version: version, sizeBytes: size,
                                      hasSinf: sinf, hasMetadata: meta != nil, encryptedBinary: encrypted,
                                      metadata: meta, addedAt: Date(), installedAt: nil)
        return Result(entry: entry, icon: icon(zip: zip, base: base, info: info))
    }

    private static func icon(zip: ZipReader, base: String, info: [String: Any]) -> Data? {
        var names: [String] = []
        if let icons = info["CFBundleIcons"] as? [String: Any], let p = icons["CFBundlePrimaryIcon"] as? [String: Any] {
            names += p["CFBundleIconFiles"] as? [String] ?? []
            if let n = p["CFBundleIconName"] as? String { names.append(n) }
        }
        names += info["CFBundleIconFiles"] as? [String] ?? []
        if let n = info["CFBundleIconFile"] as? String { names.append(n) }
        names.append("AppIcon")
        let candidates = zip.entries.filter { e in
            guard e.name.hasPrefix(base), e.name.lowercased().hasSuffix(".png"), e.uncompressedSize <= 4 * 1024 * 1024 else { return false }
            let rest = String(e.name.dropFirst(base.count))
            return !rest.contains("/") && names.contains(where: { rest.hasPrefix($0) })
        }.sorted { $0.uncompressedSize > $1.uncompressedSize }
        for e in candidates {
            guard let bytes = try? zip.read(e, length: e.uncompressedSize),
                  let src = CGImageSourceCreateWithData(bytes as CFData, nil),
                  let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceThumbnailMaxPixelSize: 180,
                  ] as CFDictionary),
                  let png = UIImage(cgImage: cg).pngData() else { continue }
            return png
        }
        return nil
    }
}

/// The library of imported encrypted IPAs, kept in Application Support (not backed up).
@MainActor
final class EncryptedAppsStore: ObservableObject {
    static let shared = EncryptedAppsStore()

    @Published private(set) var entries: [EncryptedIPAEntry] = []
    @Published var busy: String?
    @Published var progress: Double = 0
    @Published var installingID: UUID?
    private var installAttemptID: UUID?
    @Published var error: String?
    @Published var toast: String?

    nonisolated static let root: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("EncryptedApps", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        var u = base
        var rv = URLResourceValues(); rv.isExcludedFromBackup = true
        try? u.setResourceValues(rv)
        return base
    }()
    nonisolated static func ipaURL(_ id: UUID) -> URL { root.appendingPathComponent("\(id.uuidString).ipa") }
    nonisolated static func iconURL(_ id: UUID) -> URL { root.appendingPathComponent("\(id.uuidString).png") }
    private var indexURL: URL { Self.root.appendingPathComponent("index.json") }

    init() {
        #if DEBUG
        if MirsaStyleShots.page == "encrypted" { entries = Self.fixtures; return }
        #endif
        if let d = try? Data(contentsOf: indexURL), let list = try? JSONDecoder().decode([EncryptedIPAEntry].self, from: d) {
            entries = list.filter { FileManager.default.fileExists(atPath: Self.ipaURL($0.id).path) }
        }
    }

    private func save() {
        guard let d = try? JSONEncoder().encode(entries) else { return }
        try? d.write(to: indexURL, options: .atomic)
    }

    /// Apple IDs the user signed in to Mirsa with: the sideloader login and the App Store login.
    nonisolated static func signedInAppleIDs() -> [String] {
        var out: [String] = []
        if let d = Keychain.get("appleid.email"), !out.contains(where: { $0.caseInsensitiveCompare(d) == .orderedSame }) { out.append(d) }
        return out
    }

    func match(_ entry: EncryptedIPAEntry) -> EncryptedAccountMatch {
        EncryptedAccountMatch.evaluate(purchaser: entry.metadata?.purchaserAppleID, signedIn: Self.signedInAppleIDs())
    }

    /// Copies the picked file into the library untouched (byte-for-byte).
    func importIPA(from url: URL) async {
        guard busy == nil else { return }
        busy = EncryptedText.t("Reading IPA…", "عم نقرأ الـIPA…", "IPA دەخوێنرێتەوە…", "IPA tê xwendin…")
        defer { busy = nil }
        do {
            let snapshot = try await Task.detached(priority: .userInitiated) { try OpenInIPA.snapshot(url) }.value
            defer { OpenInIPA.remove(snapshot) }
            let entry = try await Self.adopt(file: snapshot, move: false)
            StoreIPAProtection.markSaved(id: entry.id)
            add(entry)
        } catch { self.error = error.localizedDescription }
    }

    /// Takes ownership of a package (e.g. one downloaded from the App Store) and inspects it.
    nonisolated static func adopt(file: URL, move: Bool) async throws -> EncryptedIPAEntry {
        try await Task.detached(priority: .userInitiated) {
            let result = try EncryptedIPAInspector.inspect(file)
            let dest = ipaURL(result.entry.id)
            try? FileManager.default.removeItem(at: dest)
            if move { try FileManager.default.moveItem(at: file, to: dest) }
            else { try FileManager.default.copyItem(at: file, to: dest) }
            if let icon = result.icon { try? icon.write(to: iconURL(result.entry.id), options: .atomic) }
            return result.entry
        }.value
    }

    func add(_ entry: EncryptedIPAEntry) {
        entries.insert(entry, at: 0)
        save()
        toast = EncryptedText.t("Added \(entry.name)", "انضاف \(entry.name)", "\(entry.name) زیادکرا", "\(entry.name) hat zêdekirin")
    }

    func delete(_ entry: EncryptedIPAEntry) {
        try? FileManager.default.removeItem(at: Self.ipaURL(entry.id))
        try? FileManager.default.removeItem(at: Self.iconURL(entry.id))
        entries.removeAll { $0.id == entry.id }
        save()
    }

    func icon(_ entry: EncryptedIPAEntry) -> UIImage? {
        UIImage(contentsOfFile: Self.iconURL(entry.id).path)
    }

    /// Keeps the existing Wi-Fi tunnel path; cellular serves the same IPA locally, without signing or upload.
    func install(_ entry: EncryptedIPAEntry, vm: AppViewModel?) async {
        guard busy == nil, AppsStore.shared.busy == nil else {
            error = tr("Finish the current import first.", "خلّص الاستيراد الحالي أولاً.")
            return
        }
        let apps = AppsStore.shared
        // Reserve before the first await, including path resolution, so repeated
        // taps or a certificate install cannot race this handoff.
        busy = L.t("busy.installing"); apps.busy = busy; progress = 0; installingID = entry.id
        let attemptID = UUID()
        installAttemptID = attemptID
        var ok = false
        defer {
            if installAttemptID == attemptID {
                busy = nil; apps.busy = nil; installingID = nil
                installAttemptID = nil
                if !ok { progress = 0 }
            }
        }
        apps.error = nil
        let cellular = await WiFiPathMonitor.shared.resolve() == .notWifi
        if !cellular {
            guard await apps.realAppNetworkReady(vm) else {
                error = apps.error ?? EncryptedText.t("Installing needs Wi-Fi + LocalDevVPN", "التثبيت بدو واي فاي + LocalDevVPN",
                                                      "دامەزراندن پێویستی بە Wi-Fi + LocalDevVPN هەیە", "Sazkirin Wi-Fi + LocalDevVPN dixwaze")
                apps.error = nil
                return
            }
        }
        let file = Self.ipaURL(entry.id)
        let path = file.path
        guard FileManager.default.fileExists(atPath: path) else {
            error = InstallErrorText.sanitize("MIRSA_SOURCE_IPA_MISSING", arabic: L.isArabic); return
        }
        if cellular {
            do {
                try await EncryptedLocalInstall.handoff(file)
                guard installAttemptID == attemptID else { return }
                // Receiving bytes is not installation proof, especially when an
                // older copy with the same bundle ID already exists.
                progress = 0
                toast = EncryptedLocalInstall.unconfirmed
            } catch {
                guard installAttemptID == attemptID else { return }
                if error is CancellationError { toast = EncryptedLocalInstall.unconfirmed }
                else { self.error = error.localizedDescription }
            }
            return
        }
        do {
            _ = try await Task.detached {
                try SideloadService.installStoreIPA(ipaPath: path) { f, _ in
                    Task { @MainActor in
                        guard self.installAttemptID == attemptID else { return }
                        self.progress = f
                    }
                }
            }.value
            ok = true
            if let i = entries.firstIndex(where: { $0.id == entry.id }) { entries[i].installedAt = Date(); save() }
            toast = L.f("toast.installed", entry.name)
            // Tunnel installation returned confirmed success; OTA handoff never reaches here.
            if StoreIPAProtection.mayClean(entry, confirmed: true) { delete(entry) }
        } catch {
            self.error = AppsStore.friendly(error)
        }
    }

    #if DEBUG
    private static let fixtures: [EncryptedIPAEntry] = [
        EncryptedIPAEntry(id: UUID(uuidString: "00000000-0000-0000-0000-0000000E0001")!, name: "Notes Pro", bundleID: "com.example.notes",
                          version: "5.2.1", sizeBytes: 84_000_000, hasSinf: true, hasMetadata: true, encryptedBinary: true,
                          metadata: EncryptedIPAMetadata(itemName: "Notes Pro", itemID: 123456789, bundleID: "com.example.notes", version: "5.2.1",
                                                         purchaserAppleID: "buyer@example.com", purchaserName: "Sample Buyer", artistName: "Example Inc."),
                          addedAt: Date(timeIntervalSince1970: 1_760_000_000), installedAt: nil),
        EncryptedIPAEntry(id: UUID(uuidString: "00000000-0000-0000-0000-0000000E0002")!, name: "Weather", bundleID: "com.example.weather",
                          version: "2.0", sizeBytes: 41_000_000, hasSinf: false, hasMetadata: false, encryptedBinary: true,
                          metadata: nil, addedAt: Date(timeIntervalSince1970: 1_760_000_100), installedAt: nil),
    ]
    #endif
}
