import SwiftUI
import ImageIO
import UIKit

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

/// Safe, read-only icon lookup inside a retained signed IPA. Never executes or extracts to disk.
/// Reuses ZipReader (bounded entries, no traversal, symlinks rejected, ratio and size limits).
enum SignedIPAIcon {
    static let maxEntryBytes: UInt64 = 4 * 1024 * 1024
    static let maxPixels = 4096
    static let maxPlistBytes: UInt64 = 2 * 1024 * 1024

    /// Icon names in precedence order: primary CFBundleIcons files, icon name, top-level files, legacy file, AppIcon.
    static func iconNames(_ info: [String: Any]) -> [String] {
        var names: [String] = []
        if let icons = info["CFBundleIcons"] as? [String: Any], let p = icons["CFBundlePrimaryIcon"] as? [String: Any] {
            names += (p["CFBundleIconFiles"] as? [String]) ?? []
            if let n = p["CFBundleIconName"] as? String { names.append(n) }
        } else if let icons = info["CFBundleIcons"] as? [String: Any], let p = icons["CFBundlePrimaryIcon"] as? String {
            names.append(p)
        }
        names += (info["CFBundleIconFiles"] as? [String]) ?? []
        if let n = info["CFBundleIconFile"] as? String { names.append(n) }
        names.append("AppIcon")
        var seen = Set<String>()
        return names.filter { !$0.isEmpty && !$0.contains("/") && !$0.contains("\\") && seen.insert($0).inserted }
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
        let pngs = zip.entries.filter { e in
            guard e.name.hasPrefix(base), e.name.lowercased().hasSuffix(".png"),
                  e.uncompressedSize > 0, e.uncompressedSize <= maxEntryBytes else { return false }
            return !e.name.dropFirst(base.count).contains("/")
        }
        for name in iconNames(info) {
            let matches = pngs.filter { String($0.name.dropFirst(base.count)).hasPrefix(name) }
                .sorted { $0.uncompressedSize == $1.uncompressedSize ? $0.name < $1.name : $0.uncompressedSize > $1.uncompressedSize }
            for e in matches {
                if let png = decode(zip: zip, entry: e, limits: limits) { return png }
            }
        }
        return nil
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
                    ScrollView {
                        LazyVStack(spacing: MirsaSpacing.s) {
                            ForEach(items) { item in
                                HStack(spacing: MirsaSpacing.m) {
                                    if let png = item.iconPNG, let image = UIImage(data: png) {
                                        Image(uiImage: image).resizable().scaledToFill()
                                            .frame(width: 44, height: 44)
                                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                            .accessibilityLabel(item.name)
                                            .accessibilityIdentifier("signed-file-icon-real")
                                    } else {
                                        Image(systemName: "app.badge.checkmark")
                                            .font(.title2).foregroundStyle(MirsaPalette.accentGradient)
                                            .frame(width: 44, height: 44)
                                            .accessibilityHidden(true)
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
                                .padding(MirsaSpacing.card).appsGlass(cornerRadius: MirsaRadius.l)
                                .accessibilityElement(children: .contain)
                            }
                        }.padding(MirsaSpacing.page)
                    }.refreshable { await reload() }
                }
            }
            .navigationTitle(Self.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
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
        .sheet(item: $sharing) { item in
            // Export the existing retained IPA, never the original unsigned import.
            PersonalSignedShare(url: item.url)
        }
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
