import SwiftUI
import ImageIO
import UIKit
import AssetCatalogWrapper
import CryptoKit

/// Lists only the persistent output directory populated AFTER certificate signing.
/// Imported IPAs and PersonalLibraryApp.signed are deliberately not evidence here.
enum SignedAppsCatalog {
    struct Item: Identifiable {
        let url: URL
        let name: String
        let version: String
        let date: Date
        let bytes: Int64
        /// PNG thumbnail extracted from the retained SIGNED IPA itself; nil means use the generic fallback.
        var iconPNG: Data? = nil
        var id: String { url.path }
    }

    static var root: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MirsaSignedExports", isDirectory: true)
    }

    static func available(_ url: URL, root: URL = SignedAppsCatalog.root) -> Bool {
        let canonical = root.standardizedFileURL.resolvingSymlinksInPath()
        let parent = url.deletingLastPathComponent().standardizedFileURL.resolvingSymlinksInPath()
        guard url.isFileURL, url.pathExtension.lowercased() == "ipa",
              parent.deletingLastPathComponent() == canonical,
              UUID(uuidString: parent.lastPathComponent) != nil,
              (try? url.deletingLastPathComponent().resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == false,
              (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == false,
              let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
              values.isRegularFile == true, (values.fileSize ?? 0) > 0 else { return false }
        return FileManager.default.isReadableFile(atPath: url.path)
    }

    /// Remove only the validated retained export directory, never an imported IPA or a symlink target.
    static func delete(_ urls: [URL], root: URL = SignedAppsCatalog.root) throws {
        // Validate the entire selection before touching any directory.
        guard urls.allSatisfy({ available($0, root: root) }) else {
            throw CocoaError(.fileWriteNoPermission)
        }
        let directories = Set(urls.map { $0.deletingLastPathComponent().standardizedFileURL })
        for directory in directories { try FileManager.default.removeItem(at: directory) }
    }

    static func load(root: URL = SignedAppsCatalog.root) throws -> [Item] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: root.path) else { return [] }
        let directories = try fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey],
                                                     options: .skipsHiddenFiles)
        var items: [Item] = []
        for directory in directories {
            guard UUID(uuidString: directory.lastPathComponent) != nil,
                  (try? directory.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == false,
                  (try? directory.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
            // Failure to read a retained folder is surfaced instead of misreported as empty.
            let files = try fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey, .creationDateKey],
                                                   options: .skipsHiddenFiles)
            var info: [String: Any] = [:]
            let metadata = directory.appendingPathComponent("Info.plist")
            if let size = try? metadata.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 2 * 1024 * 1024,
               (try? metadata.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == false,
               let data = try? Data(contentsOf: metadata),
               let parsed = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] {
                info = parsed
            }
            for file in files where available(file, root: root) {
                let values = try file.resourceValues(forKeys: [.fileSizeKey, .creationDateKey])
                let label = (info["CFBundleDisplayName"] as? String) ?? (info["CFBundleName"] as? String)
                let name = label?.trimmingCharacters(in: .whitespacesAndNewlines)
                items.append(Item(url: file, name: name?.isEmpty == false ? name! : file.deletingPathExtension().lastPathComponent,
                                  version: info["CFBundleShortVersionString"] as? String ?? "",
                                  date: values.creationDate ?? .distantPast, bytes: Int64(values.fileSize ?? 0),
                                  iconPNG: SignedIPAIcon.thumbnailPNG(in: file)))
            }
        }
        return items.sorted { $0.date == $1.date ? $0.id < $1.id : $0.date > $1.date }
    }
}

/// Safe, read-only icon lookup inside a retained signed IPA. Never executes or loads any code from the IPA.
/// Loose PNGs are decoded in memory. A compiled Assets.car is copied (bounded, validated) into a private random
/// temporary directory as the single file "Assets.car", read through the existing CoreUI bridge as DATA only, then removed.
/// Reuses ZipReader (bounded entries, no traversal, symlinks rejected, ratio and size limits).
enum SignedIPAIcon {
    static let maxEntryBytes: UInt64 = 4 * 1024 * 1024
    static let maxPixels = 4096
    static let maxPlistBytes: UInt64 = 2 * 1024 * 1024
    static let maxCarBytes: UInt64 = 32 * 1024 * 1024
    // Caps our callback work, not CoreUI's internal enumeration or parsing time.
    static let maxCarLookups = 512
    static let maxCarDecodes = 4
    static let maxCarTotalPixels = 16 * 1024 * 1024
    static let maxCarSide = 4096
    static let maxCarImagePixels = 8 * 1024 * 1024
    static let quarantineKey = "mirsa.signedFolder.carParseInProgress"
    private static let carLock = NSLock()

    /// CoreUI parses the catalog in-process and cannot be fully sandboxed: a malformed car could crash the app
    /// (an ObjC exception catch would not help against SIGSEGV). Residual risk is documented, not eliminated.
    /// Mitigation: a persisted in-progress marker keyed by SHA256 of the car bytes is written BEFORE parsing and
    /// cleared after a normal return. A marker found for the same digest means a previous parse never returned,
    /// so that car is skipped (icon falls back to generic) instead of crash-looping on every launch.
    static func carDigest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
    static func isQuarantined(_ digest: String, defaults: UserDefaults = .standard) -> Bool {
        (defaults.stringArray(forKey: quarantineKey) ?? []).contains(digest)
    }
    private static func setMarker(_ digest: String, present: Bool, defaults: UserDefaults) {
        var list = defaults.stringArray(forKey: quarantineKey) ?? []
        list.removeAll { $0 == digest }
        if present { list.append(digest) }
        if list.count > 64 { list.removeFirst(list.count - 64) }
        defaults.set(list, forKey: quarantineKey)
        defaults.synchronize()
    }

    private static func primaryNames(_ info: [String: Any], key: String) -> [String] {
        var out: [String] = []
        guard let icons = info[key] as? [String: Any] else { return out }
        if let p = icons["CFBundlePrimaryIcon"] as? [String: Any] {
            out += (p["CFBundleIconFiles"] as? [String]) ?? []
            if let n = p["CFBundleIconName"] as? String { out.append(n) }
        } else if let s = icons["CFBundlePrimaryIcon"] as? String {
            out.append(s)
        }
        return out
    }

    /// Icon names in precedence order: primary CFBundleIcons, its iPad variant, top-level files (and iPad variant), legacy file, AppIcon.
    static func iconNames(_ info: [String: Any]) -> [String] {
        var names: [String] = []
        names += primaryNames(info, key: "CFBundleIcons")
        names += primaryNames(info, key: "CFBundleIcons~ipad")
        names += (info["CFBundleIconFiles"] as? [String]) ?? []
        names += (info["CFBundleIconFiles~ipad"] as? [String]) ?? []
        if let n = info["CFBundleIconFile"] as? String { names.append(n) }
        names.append("AppIcon")
        var seen = Set<String>()
        var out: [String] = []
        for n in names {
            if n.isEmpty || n.count > 128 || n.contains("/") || n.contains("\\") { continue }
            if seen.insert(n).inserted { out.append(n) }
            if out.count == 32 { break }
        }
        return out
    }

    private static let suffixPattern: NSRegularExpression? = try? NSRegularExpression(
        pattern: "^(?:([0-9]{1,4}(?:\\.[0-9])?)x([0-9]{1,4}(?:\\.[0-9])?))?(?:@([23])x)?(?:~(ipad|iphone))?$")

    private static func stripPNG(_ s: String) -> String {
        s.lowercased().hasSuffix(".png") ? String(s.dropLast(4)) : s
    }

    /// Strict icon file/asset match: the name, optionally followed by a valid square size, @2x/@3x scale and ~ipad/~iphone idiom.
    /// "IconBanner" never matches "Icon". An optional ".png" is accepted on either side.
    static func matches(file: String, name: String) -> Bool {
        let base = stripPNG(file)
        let wanted = stripPNG(name)
        guard !wanted.isEmpty, base.hasPrefix(wanted) else { return false }
        let rest = String(base.dropFirst(wanted.count))
        if rest.isEmpty { return true }
        guard let regex = suffixPattern else { return false }
        let range = NSRange(location: 0, length: rest.utf16.count)
        guard let m = regex.firstMatch(in: rest, options: [], range: range), m.range == range else { return false }
        let wRange = m.range(at: 1)
        let hRange = m.range(at: 2)
        if wRange.location == NSNotFound && hRange.location == NSNotFound { return true }
        guard wRange.location != NSNotFound, hRange.location != NSNotFound,
              let wr = Range(wRange, in: rest), let hr = Range(hRange, in: rest),
              let w = Double(rest[wr]), let h = Double(rest[hr]) else { return false }
        return w == h && w >= 8 && w <= 1024
    }

    static func thumbnailPNG(in ipa: URL) -> Data? {
        var limits = IPALimits()
        limits.maxEntries = 20_000
        limits.rejectSymlinks = true
        guard let values = try? ipa.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey]),
              values.isRegularFile == true, values.isSymbolicLink != true,
              let size = values.fileSize, size > 22, Int64(size) <= 4 * 1024 * 1024 * 1024,
              let data = try? Data(contentsOf: ipa, options: .mappedIfSafe),
              let zip = try? ZipReader(data: data, limits: limits) else { return nil }
        return thumbnailPNG(zip: zip, limits: limits)
    }

    static func thumbnailPNG(zip: ZipReader, limits: IPALimits) -> Data? {
        var apps = Set<String>()
        for e in zip.entries {
            let c = e.name.split(separator: "/", omittingEmptySubsequences: true)
            if c.count >= 2, c[0] == "Payload", c[1].hasSuffix(".app") { apps.insert(String(c[1])) }
        }
        guard apps.count == 1, let app = apps.first else { return nil }
        let base = "Payload/\(app)/"
        guard let infoEntry = zip.entry(base + "Info.plist"), infoEntry.uncompressedSize <= maxPlistBytes,
              let infoData = try? zip.read(infoEntry, length: infoEntry.uncompressedSize, limits: limits),
              let info = (try? PropertyListSerialization.propertyList(from: infoData, format: nil)) as? [String: Any]
        else { return nil }
        let names = iconNames(info)
        let pngs = zip.entries.filter { e in
            guard e.name.hasPrefix(base), e.name.lowercased().hasSuffix(".png"),
                  e.uncompressedSize > 0, e.uncompressedSize <= maxEntryBytes else { return false }
            return !e.name.dropFirst(base.count).contains("/")
        }
        for name in names {
            let matched = pngs.filter { matches(file: String($0.name.dropFirst(base.count)), name: name) }
            let ordered = matched.sorted { $0.uncompressedSize == $1.uncompressedSize ? $0.name < $1.name : $0.uncompressedSize > $1.uncompressedSize }
            for e in ordered {
                if let png = decode(zip: zip, entry: e, limits: limits) { return png }
            }
        }
        // Compiled asset catalog (modern apps ship icons only inside Assets.car).
        if let car = zip.entry(base + "Assets.car"), car.uncompressedSize > 0, car.uncompressedSize <= maxCarBytes,
           let carData = try? zip.read(car, length: car.uncompressedSize, limits: limits),
           UInt64(carData.count) == car.uncompressedSize {
            return thumbnailPNG(carData: carData, names: names)
        }
        return nil
    }

    /// Cheap structural check of the BOMStore container before any CoreUI parsing.
    static func isPlausibleBOMStore(_ d: Data) -> Bool {
        guard d.count >= 512, d.count <= Int(maxCarBytes) else { return false }
        let magic = Data("BOMStore".utf8)
        guard d.prefix(8) == magic else { return false }
        func be(_ offset: Int) -> UInt64 {
            var v: UInt64 = 0
            for i in 0..<4 { v = (v << 8) | UInt64(d[d.startIndex + offset + i]) }
            return v
        }
        let blocks = be(12), indexOffset = be(16), indexLength = be(20), varsOffset = be(24), varsLength = be(28)
        let total = UInt64(d.count)
        guard blocks > 0, blocks <= 1_000_000, indexLength >= 4, varsLength >= 4 else { return false }
        guard indexOffset >= 32, varsOffset >= 32 else { return false }
        guard indexOffset + indexLength <= total, varsOffset + varsLength <= total else { return false }
        return true
    }

    static func thumbnailPNG(carData: Data, names: [String], defaults: UserDefaults = .standard) -> Data? {
        guard UInt64(carData.count) <= maxCarBytes, isPlausibleBOMStore(carData) else { return nil }
        let digest = carDigest(carData)
        carLock.lock()
        defer { carLock.unlock() }
        guard !isQuarantined(digest, defaults: defaults) else { return nil }
        setMarker(digest, present: true, defaults: defaults)
        let result = autoreleasepool { parseCar(carData: carData, names: names) }
        setMarker(digest, present: false, defaults: defaults)
        return result
    }

    private static func parseCar(carData: Data, names: [String]) -> Data? {
        let wanted = names.filter { !$0.isEmpty && $0.count <= 128 }
        guard !wanted.isEmpty else { return nil }
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("mirsa-car-" + UUID().uuidString, isDirectory: true)
        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        } catch { return nil }
        defer { try? fm.removeItem(at: dir) }
        let carURL = dir.appendingPathComponent("Assets.car")
        do { try carData.write(to: carURL, options: [.atomic]) } catch { return nil }
        guard let catalog = try? CUICatalog(url: carURL) else { return nil }
        var seen = 0
        var decodes = 0
        var pixels = 0
        var best: CGImage?
        catalog.enumerateNamedLookups { lookup in
            seen += 1
            guard seen <= SignedIPAIcon.maxCarLookups, decodes < SignedIPAIcon.maxCarDecodes else { return }
            let lookupName: String = lookup.name
            guard lookupName.count <= 128 else { return }
            var allowed = false
            for n in wanted where SignedIPAIcon.matches(file: lookupName, name: n) { allowed = true; break }
            guard allowed else { return }
            let rendition = Rendition(lookup)
            guard rendition.type == .image || rendition.type == .icon else { return }
            // Bounds BEFORE decoding.
            let size = rendition.cuiRend.unslicedSize()
            guard size.width.isFinite, size.height.isFinite, size.width >= 16, size.height >= 16,
                  size.width <= CGFloat(SignedIPAIcon.maxCarSide), size.height <= CGFloat(SignedIPAIcon.maxCarSide) else { return }
            let area = Int(size.width) * Int(size.height)
            guard area <= SignedIPAIcon.maxCarImagePixels, pixels + area <= SignedIPAIcon.maxCarTotalPixels else { return }
            decodes += 1
            pixels += area
            guard let image = rendition.image, image.width >= 16, image.height >= 16,
                  image.width <= SignedIPAIcon.maxCarSide, image.height <= SignedIPAIcon.maxCarSide else { return }
            if let current = best, current.width >= image.width { return }
            best = image
        }
        guard let image = best else { return nil }
        return thumbnail(from: image)
    }

    private static func thumbnail(from cg: CGImage) -> Data? {
        let longest = CGFloat(max(cg.width, cg.height))
        guard longest > 0 else { return nil }
        let scale = min(1, 180 / longest)
        let target = CGSize(width: max(1, (CGFloat(cg.width) * scale).rounded()), height: max(1, (CGFloat(cg.height) * scale).rounded()))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: target, format: format)
        let image = UIImage(cgImage: cg)
        return renderer.pngData { _ in image.draw(in: CGRect(origin: .zero, size: target)) }
    }

    private static func decode(zip: ZipReader, entry: ZipEntry, limits: IPALimits) -> Data? {
        guard let bytes = try? zip.read(entry, length: entry.uncompressedSize, limits: limits),
              UInt64(bytes.count) == entry.uncompressedSize,
              let source = CGImageSourceCreateWithData(bytes as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetCount(source) > 0,
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int, let h = props[kCGImagePropertyPixelHeight] as? Int,
              w >= 16, h >= 16, w <= maxPixels, h <= maxPixels,
              let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 180,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { return nil }
        return UIImage(cgImage: cg).pngData()
    }
}

struct SignedAppsFolderView: View {
    static var title: String { personalText("Signed apps", "التطبيقات الموقّعة") }
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var items: [SignedAppsCatalog.Item] = []
    @State private var loading = true
    @State private var error: String?
    @State private var selecting = false
    @State private var selected = Set<String>()
    @State private var pendingDelete: [SignedAppsCatalog.Item] = []
    @State private var deleteError: String?
    @State private var deleting = false
    @State private var sharing: SignedAppsCatalog.Item?

    var body: some View {
        NavigationStack {
            ZStack {
                AuroraBackground()
                if loading {
                    ProgressView()
                } else if let error {
                    ContentUnavailableView {
                        Label(Self.title, systemImage: "folder.badge.questionmark")
                    } description: {
                        Text(error)
                    } actions: {
                        Button(personalText("Try again", "جرّب مرة تانية")) { Task { await reload() } }
                    }
                } else if items.isEmpty {
                    ContentUnavailableView {
                        Label(personalText("No signed apps yet", "ما في تطبيقات موقّعة بعد"), systemImage: "folder")
                    } description: {
                        Text(personalText("Your signed IPA files will appear here, ready to share.",
                                          "ملفات IPA اللي بتوقّعها بتظهر هون، وجاهزة للمشاركة."))
                    }
                    .accessibilityIdentifier("signed-folder-empty")
                } else {
                    List {
                            ForEach(items) { item in
                                HStack(spacing: MirsaSpacing.m) {
                                    if selecting {
                                        Button {
                                            if !selected.insert(item.id).inserted { selected.remove(item.id) }
                                        } label: {
                                            Image(systemName: selected.contains(item.id) ? "checkmark.circle.fill" : "circle")
                                                .frame(width: 44, height: 44)
                                        }
                                        .buttonStyle(.borderless)
                                        .accessibilityLabel(personalText("Select", "تحديد") + " " + item.name)
                                        .accessibilityIdentifier("signed-file-select")
                                        .accessibilityValue(selected.contains(item.id) ? "1" : "0")
                                    }
                                    if let png = item.iconPNG, let image = UIImage(data: png) {
                                        Image(uiImage: image).resizable().scaledToFill()
                                            .frame(width: 44, height: 44)
                                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                            .accessibilityLabel(item.name)
                                            .accessibilityIdentifier("signed-file-icon-real")
                                    } else {
                                        ZStack {
                                            Image(systemName: "app.badge.checkmark")
                                                .font(.title2).foregroundStyle(MirsaPalette.accentGradient)
                                                .accessibilityHidden(true)
                                        }
                                            .frame(width: 44, height: 44)
                                            .contentShape(Rectangle())
                                            .accessibilityElement(children: .ignore)
                                            .accessibilityAddTraits(.isImage)
                                            .accessibilityLabel(personalText("Default app icon for", "أيقونة تطبيق افتراضية لـ") + " " + item.name)
                                            .accessibilityIdentifier("signed-file-icon-generic")
                                    }
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(item.name).font(MirsaFont.cardTitle).lineLimit(2)
                                        if !item.version.isEmpty {
                                            Text(item.version).font(.caption).foregroundStyle(.secondary)
                                        }
                                        Text(ByteCountFormatter.string(fromByteCount: item.bytes, countStyle: .file))
                                            .font(.caption).foregroundStyle(.secondary)
                                        Text(item.date, style: .date).font(.caption2).foregroundStyle(.secondary)
                                    }
                                    Spacer(minLength: 8)
                                    if !selecting {
                                    Button {
                                        guard SignedAppsCatalog.available(item.url) else {
                                            error = personalText("This signed file is no longer available.", "ملف التوقيع ما عاد متاح.")
                                            return
                                        }
                                        sharing = item
                                    } label: {
                                        MirsaRoundIcon(systemName: "square.and.arrow.up")
                                    }
                                    .buttonStyle(.mirsaPress)
                                    .accessibilityLabel(personalText("Share", "مشاركة") + " " + item.name)
                                    .accessibilityIdentifier("signed-file-share")
                                    }
                                }
                                .padding(MirsaSpacing.card).appsGlass(cornerRadius: MirsaRadius.l)
                                .accessibilityElement(children: .contain)
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    if !selecting {
                                        Button(role: .destructive) { pendingDelete = [item] } label: {
                                            Label(personalText("Delete", "حذف"), systemImage: "trash")
                                        }
                                    }
                                }
                            }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .disabled(deleting)
                    .refreshable { await reload() }
                }
            }
            .navigationTitle(Self.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if !items.isEmpty {
                        Button(selecting ? personalText("Done", "تم") : personalText("Select", "تحديد")) {
                            selecting.toggle(); selected.removeAll()
                        }
                        .accessibilityIdentifier("signed-folder-select")
                        if selecting {
                            Button(personalText("Delete selected", "حذف المحدد"), role: .destructive) {
                                pendingDelete = items.filter { selected.contains($0.id) }
                            }
                            .disabled(selected.isEmpty || deleting)
                            .accessibilityIdentifier("signed-folder-delete-selected")
                        } else {
                            Button(personalText("Delete all", "حذف الكل"), role: .destructive) { pendingDelete = items }
                                .disabled(deleting)
                                .accessibilityIdentifier("signed-folder-delete-all")
                        }
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { Image(systemName: "chevron.left") }
                        .accessibilityLabel(personalText("Back", "رجوع"))
                        .accessibilityIdentifier("signed-folder-back")
                }
            }
        }
        .environment(\.layoutDirection, .leftToRight)
        .preferredColorScheme(.dark)
        .task { await reload() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await reload() } }
        }
        .alert(personalText("Delete retained IPA files?", "تحذف ملفات IPA المحفوظة؟"),
               isPresented: Binding(get: { !pendingDelete.isEmpty }, set: { if !$0 { pendingDelete = [] } }),
               presenting: pendingDelete.isEmpty ? nil : pendingDelete) { candidates in
            Button(personalText("Delete", "حذف"), role: .destructive) {
                let urls = candidates.map(\.url)
                pendingDelete = []
                Task { await remove(urls) }
            }
            Button(personalText("Cancel", "إلغاء"), role: .cancel) { pendingDelete = [] }
        } message: { _ in
            Text(personalText("This removes the saved signed files, not the installed apps.",
                              "بينحذف الملف المحفوظ، مو التطبيق المثبّت على جهازك."))
        }
        .alert(personalText("Couldn’t delete files", "ما قدرت احذف الملفات"),
               isPresented: Binding(get: { deleteError != nil }, set: { if !$0 { deleteError = nil } })) {
            Button(personalText("OK", "تمام")) { deleteError = nil }
        } message: { Text(deleteError ?? "") }
        .sheet(item: $sharing) { item in
            // Export the existing retained IPA, never the original unsigned import.
            PersonalSignedShare(url: item.url)
        }
    }

    @MainActor private func remove(_ urls: [URL]) async {
        guard !deleting else { return }
        deleting = true
        defer { deleting = false }
        do {
            try await Task.detached { try SignedAppsCatalog.delete(urls) }.value
            selected.removeAll()
            selecting = false
        } catch {
            deleteError = personalText("Some files couldn’t be deleted. Try again.", "بعض الملفات ما انحذفت. جرّب مرة تانية.")
        }
        await reload()
    }

    @MainActor private func reload() async {
        do {
            items = try await Task.detached { try SignedAppsCatalog.load() }.value
            error = nil
        } catch {
            self.error = personalText("Couldn’t read the signed apps. Unlock your device and try again.",
                                      "ما قدرت افتح التطبيقات الموقّعة. افتح قفل الجهاز وجرّب مرة تانية.")
        }
        loading = false
    }
}
