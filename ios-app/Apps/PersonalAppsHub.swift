import SwiftUI
import Compression
import UniformTypeIdentifiers
import ImageIO

struct PersonalLibraryApp: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var bundleID: String
    var version: String
    let signed: Bool
    let date: Date
    var filename: String { id.uuidString + ".ipa" }
}

/// Deliberately separate from AppsStore, DownloadsLibrary, Apple ID and container.
@MainActor
final class PersonalAppsLibrary: ObservableObject {
    static let shared = PersonalAppsLibrary()
    @Published private(set) var apps: [PersonalLibraryApp] = []
    @Published private(set) var loadError: String?
    let root: URL
    private let index: URL
    private var triedIcons = Set<UUID>()
    private let iconCache = NSCache<NSString, UIImage>()
    init() {
        root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MirsaPersonalApps", isDirectory: true)
        index = root.appendingPathComponent("library.json")
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true,
                attributes: [.protectionKey: FileProtectionType.complete])
            var url = root
            var values = URLResourceValues(); values.isExcludedFromBackup = true
            try url.setResourceValues(values)
            if FileManager.default.fileExists(atPath: index.path) {
                apps = try JSONDecoder().decode([PersonalLibraryApp].self, from: Data(contentsOf: index))
            }
        } catch { loadError = error.localizedDescription }
    }
    func url(_ app: PersonalLibraryApp) -> URL { projectFile(app, name: app.filename) }
    func iconURL(_ app: PersonalLibraryApp) -> URL { projectFile(app, name: "icon-\(app.id.uuidString).png") }
    func draftURL(_ app: PersonalLibraryApp) -> URL { projectFile(app, name: "project-\(app.id.uuidString).json") }
    private func projectFile(_ app: PersonalLibraryApp, name: String) -> URL {
        // Existing installations keep their flat files until the explicit browse migration.
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        if let directory = try? PersonalProjectFolder.directory(documents: documents, id: app.id, create: false),
           FileManager.default.fileExists(atPath: directory.appendingPathComponent(app.filename).path) {
            let target = directory.appendingPathComponent(name)
            let legacy = root.appendingPathComponent(name)
            // Recover an interrupted migration without hiding legacy draft/icon files.
            if FileManager.default.fileExists(atPath: target.path) || !FileManager.default.fileExists(atPath: legacy.path) {
                return target
            }
            return legacy
        }
        return root.appendingPathComponent(name)
    }
    func browseDirectory(_ app: PersonalLibraryApp) throws -> URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let directory = try PersonalProjectFolder.directory(documents: documents, id: app.id)
        // Inspect legacy names directly, even when an interrupted migration already moved the IPA.
        let files = [app.filename, "icon-\(app.id.uuidString).png", "project-\(app.id.uuidString).json"]
            .map { root.appendingPathComponent($0) }
        try PersonalProjectFolder.migrate(files: files, to: directory)
        return directory
    }

    private func persist(_ list: [PersonalLibraryApp]) throws {
        guard loadError == nil else { throw SideloadError.message(personalText("Personal library could not be opened. Unlock your device and reopen Mirsa.", "المكتبة ما انفتحت. افتح قفل الجهاز وافتح ميرسا من جديد.")) }
        try JSONEncoder().encode(list).write(to: index, options: [.atomic, .completeFileProtection])
        apps = list
    }
    func delete(_ app: PersonalLibraryApp) throws {
        try persist(apps.filter { $0.id != app.id })
        let fm = FileManager.default
        for u in [url(app), iconURL(app), draftURL(app)] { try? fm.removeItem(at: u) }
        iconCache.removeObject(forKey: app.id.uuidString as NSString)
    }

    /// Cached icon. Never decodes anything bigger than the 180px PNG we wrote ourselves.
    func icon(for app: PersonalLibraryApp) -> UIImage? {
        let key = app.id.uuidString as NSString
        let stamp = Self.stamp(url(app))
        if let hit = iconCache.object(forKey: key), iconStamps[app.id] == stamp { return hit }
        iconCache.removeObject(forKey: key)
        guard let image = UIImage(contentsOfFile: iconURL(app).path) else { return nil }
        iconCache.setObject(image, forKey: key); iconStamps[app.id] = stamp
        return image
    }
    private var iconStamps: [UUID: String] = [:]
    nonisolated static func stamp(_ u: URL) -> String {
        // URL resource values are cached per URL instance; query fresh filesystem attributes.
        let v = try? FileManager.default.attributesOfItem(atPath: u.path)
        let size = (v?[.size] as? NSNumber)?.int64Value ?? 0
        let modified = (v?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        return "\(size)-\(modified)"
    }
    /// Legacy apps imported before icons were stored. Tried once per launch, bounded to 512 MB.
    func ensureIcon(for app: PersonalLibraryApp) async -> UIImage? {
        if let image = icon(for: app) { return image }
        guard !triedIcons.contains(app.id) else { return nil }
        triedIcons.insert(app.id)
        let source = url(app), target = iconURL(app)
        let ok: Bool = await Task.detached(priority: .utility) {
            let fm = FileManager.default
            guard let size = try? source.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > 0, size <= 512 * 1024 * 1024 else { return false }
            let stage = fm.temporaryDirectory.appendingPathComponent("personal-icon-\(UUID().uuidString)")
            defer { try? fm.removeItem(at: stage) }
            do {
                try fm.createDirectory(at: stage, withIntermediateDirectories: true)
                try IPAEditorService.run("extract", input: source, output: stage.appendingPathComponent("a"))
                let bundle = try IPAEditorService.app(in: stage.appendingPathComponent("a"))
                let info = try IPAEditorService.info(in: bundle)
                guard let png = Self.iconPNG(bundle: bundle, info: info) else { return false }
                try png.write(to: target, options: [.atomic, .completeFileProtection])
                return true
            } catch { return false }
        }.value
        return ok ? icon(for: app) : nil
    }
    nonisolated static func iconPNG(bundle: URL, info: [String: Any]) -> Data? {
        var names = Set<String>()
        func collect(_ dict: [String: Any]?) {
            guard let primary = dict?["CFBundlePrimaryIcon"] as? [String: Any] else { return }
            (primary["CFBundleIconFiles"] as? [String])?.forEach { names.insert($0) }
        }
        collect(info["CFBundleIcons"] as? [String: Any])
        collect(info["CFBundleIcons~ipad"] as? [String: Any])
        (info["CFBundleIconFiles"] as? [String])?.forEach { names.insert($0) }
        if let n = info["CFBundleIconFile"] as? String { names.insert(n) }
        // Foreign Assets.car catalogs must never enter UIKit's asset machinery.
        // A missing/unsupported icon is cosmetic; returning nil uses the UI placeholder.
        names.insert("AppIcon")
        let prefixes = names.map { ($0 as NSString).lastPathComponent }
            .map { ($0 as NSString).deletingPathExtension }.filter { !$0.isEmpty }
        let root = bundle.resolvingSymlinksInPath().standardizedFileURL.path + "/"
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: bundle, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey]
        ) else { return nil }
        let candidates = files.compactMap { file -> (URL, Int)? in
            guard file.pathExtension.lowercased() == "png",
                  prefixes.contains(where: { file.lastPathComponent.hasPrefix($0) }),
                  file.resolvingSymlinksInPath().standardizedFileURL.path.hasPrefix(root),
                  let values = try? file.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey]),
                  values.isRegularFile == true, values.isSymbolicLink != true,
                  let size = values.fileSize, size > 0, size <= 2 * 1024 * 1024 else { return nil }
            return (file, size)
        }.sorted { $0.1 == $1.1 ? $0.0.lastPathComponent < $1.0.lastPathComponent : $0.1 > $1.1 }
        for (file, _) in candidates.prefix(32) {
            guard let data = try? Data(contentsOf: file),
                  let png = validatedIconPNG(data) else { continue }
            return png
        }
        return nil
    }

    /// Converts Xcode's CgBI PNG (raw deflate, BGRA premultiplied) to a normal 180px PNG. Pure Compression/CoreGraphics/ImageIO.
    nonisolated static func cgbiIconPNG(_ data: Data) -> Data? {
        let bytes = [UInt8](data)
        guard bytes.count >= 33, bytes.count <= 2 * 1024 * 1024 else { return nil }
        func be(_ o: Int) -> Int { bytes[o..<(o + 4)].reduce(0) { ($0 << 8) | Int($1) } }
        var offset = 8, width = 0, height = 0, idat = [UInt8](), ok = false
        while offset <= bytes.count - 12 {
            let length = be(offset)
            guard length >= 0, length <= bytes.count - offset - 12 else { return nil }
            let kind = String(decoding: bytes[(offset + 4)..<(offset + 8)], as: UTF8.self)
            let body = offset + 8
            if kind == "IHDR" {
                guard length == 13 else { return nil }
                width = be(body); height = be(body + 4)
                // only 8-bit RGBA, non-interlaced (what Xcode emits)
                guard bytes[body + 8] == 8, bytes[body + 9] == 6, bytes[body + 12] == 0 else { return nil }
            } else if kind == "IDAT" { idat += bytes[body..<(body + length)] }
            else if kind == "IEND" { ok = true; break }
            offset += length + 12
        }
        guard ok, width > 0, height > 0, width <= 4096, height <= 4096, !idat.isEmpty else { return nil }
        let stride = width * 4, rawSize = height * (stride + 1)
        var raw = [UInt8](repeating: 0, count: rawSize)
        let got = idat.withUnsafeBufferPointer { src in raw.withUnsafeMutableBufferPointer { dst in
            compression_decode_buffer(dst.baseAddress!, rawSize, src.baseAddress!, idat.count, nil, COMPRESSION_ZLIB) } }
        guard got == rawSize else { return nil }
        var pix = [UInt8](repeating: 0, count: stride * height)
        for y in 0..<height {
            let f = raw[y * (stride + 1)]
            let rs = y * (stride + 1) + 1
            for x in 0..<stride {
                let a = x >= 4 ? Int(pix[y * stride + x - 4]) : 0
                let b = y > 0 ? Int(pix[(y - 1) * stride + x]) : 0
                let c = (x >= 4 && y > 0) ? Int(pix[(y - 1) * stride + x - 4]) : 0
                let r = Int(raw[rs + x])
                let v: Int
                switch f {
                case 0: v = r
                case 1: v = r + a
                case 2: v = r + b
                case 3: v = r + (a + b) / 2
                case 4:
                    let pp = a + b - c, pa = abs(pp - a), pb = abs(pp - b), pc = abs(pp - c)
                    v = r + ((pa <= pb && pa <= pc) ? a : (pb <= pc ? b : c))
                default: return nil
                }
                pix[y * stride + x] = UInt8(truncatingIfNeeded: v)
            }
        }
        let info = CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
        guard let provider = CGDataProvider(data: Data(pix) as CFData),
              let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: stride,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: info), provider: provider,
                                  decode: nil, shouldInterpolate: true, intent: .defaultIntent) else { return nil }
        let side = min(180, max(width, height))
        guard let ctx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
        guard let out = ctx.makeImage() else { return nil }
        let output = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(output, "public.png" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, out, nil)
        return CGImageDestinationFinalize(dest) ? output as Data : nil
    }

    /// ImageIO only, safe to call from the import worker. No UIKit/Bundle asset lookups.
    nonisolated static func validatedIconPNG(_ data: Data) -> Data? {
        let signature: [UInt8] = [137, 80, 78, 71, 13, 10, 26, 10]
        guard data.count >= 33, data.count <= 2 * 1024 * 1024,
              Array(data.prefix(8)) == signature else { return nil }
        // Apple's crushed (CgBI) PNG is converted by cgbiIconPNG with ImageIO/CoreGraphics only, never UIKit.
        var offset = 8
        var sawHeader = false
        while offset <= data.count - 12 {
            let length = data[offset..<(offset + 4)].reduce(0) { ($0 << 8) | Int($1) }
            guard length <= data.count - offset - 12 else { return nil }
            let kind = Array(data[(offset + 4)..<(offset + 8)])
            if kind == Array("CgBI".utf8) { return cgbiIconPNG(data) }
            if !sawHeader {
                guard kind == Array("IHDR".utf8), length == 13 else { return nil }
                sawHeader = true
            }
            offset += length + 12
            if kind == Array("IEND".utf8) { break }
        }
        guard sawHeader, offset == data.count,
              let source = CGImageSourceCreateWithData(data as CFData,
                [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetStatus(source) == .statusComplete,
              CGImageSourceGetCount(source) == 1,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let height = properties[kCGImagePropertyPixelHeight] as? NSNumber,
              width.intValue > 0, height.intValue > 0,
              width.intValue <= 4096, height.intValue <= 4096,
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 180,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, "public.png" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, thumbnail, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }

    func add(_ input: URL, signed: Bool, onAdded: ((PersonalLibraryApp) -> Void)? = nil) async throws {
        // Never overwrite an unreadable index with a partial library.
        guard loadError == nil else { throw SideloadError.message("Personal library could not be opened. Unlock your device and reopen Mirsa.") }
        let destination = root
        let app = try await Task.detached(priority: .userInitiated) {
            let access = input.startAccessingSecurityScopedResource()
            defer { if access { input.stopAccessingSecurityScopedResource() } }
            let fm = FileManager.default
            let size = try input.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            guard size.isRegularFile == true, let bytes = size.fileSize, bytes > 0, bytes <= 512 * 1024 * 1024 else {
                throw SideloadError.message("Choose an IPA smaller than 512 MB.")
            }
            let stage = fm.temporaryDirectory.appendingPathComponent("personal-library-\(UUID().uuidString)")
            try fm.createDirectory(at: stage, withIntermediateDirectories: true,
                attributes: [.protectionKey: FileProtectionType.complete])
            defer { try? fm.removeItem(at: stage) }
            let snapshot = stage.appendingPathComponent("Input.ipa")
            try fm.copyItem(at: input, to: snapshot)
            let extracted = stage.appendingPathComponent("archive")
            try IPAEditorService.run("extract", input: snapshot, output: extracted)
            let bundle = try IPAEditorService.app(in: extracted)
            let info = try IPAEditorService.info(in: bundle)
            guard let bundleID = info["CFBundleIdentifier"] as? String, IPAEditorService.validBundleID(bundleID) else {
                throw SideloadError.message("IPA has no valid bundle identifier.")
            }
            let item = PersonalLibraryApp(id: UUID(),
                name: info["CFBundleDisplayName"] as? String ?? info["CFBundleName"] as? String ?? bundleID,
                bundleID: bundleID, version: info["CFBundleShortVersionString"] as? String ?? "—",
                signed: signed, date: Date())
            let target = destination.appendingPathComponent(item.filename)
            try fm.copyItem(at: snapshot, to: target)
            do { try fm.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: target.path) }
            catch { try? fm.removeItem(at: target); throw error }
            // Icon is best effort; a missing icon never blocks the import.
            if let png = Self.iconPNG(bundle: bundle, info: info) {
                try? png.write(to: destination.appendingPathComponent("icon-\(item.id.uuidString).png"),
                               options: [.atomic, .completeFileProtection])
            }
            return item
        }.value
        do { try persist([app] + apps) }
        catch {
            try? FileManager.default.removeItem(at: url(app))
            try? FileManager.default.removeItem(at: iconURL(app))
            throw error
        }
        onAdded?(app)
    }
}

private struct PersonalAppIcon: View {
    let app: PersonalLibraryApp
    @ObservedObject var library: PersonalAppsLibrary
    @State private var image: UIImage?
    @ObservedObject private var progressState = MirsaOperationProgress.shared
    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Text(String(app.name.prefix(1)).uppercased())
                    .font(MirsaFont.sheetTitle).foregroundStyle(Color.white.opacity(0.8))
                    .frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.white.opacity(0.08))
            }
        }
        .frame(width: 56, height: 56)
        .overlay {
            if let e = progressState.entry(for: app.id.uuidString) {
                ZStack {
                    Color.black.opacity(0.45)
                    if let f = e.fraction {
                        Circle().stroke(.white.opacity(0.25), lineWidth: 3).frame(width: 28, height: 28)
                        Circle().trim(from: 0, to: f).stroke(.white, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                            .frame(width: 28, height: 28).rotationEffect(.degrees(-90))
                    } else { ProgressView().tint(.white) }
                }.accessibilityElement(children: .ignore)
                 .accessibilityLabel(app.name + ", " + personalText("Signing", "جاري التوقيع") + (e.fraction.map { " \(Int($0 * 100))%" } ?? ""))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
        .task(id: app.id) {
            image = library.icon(for: app)
            if image == nil { image = await library.ensureIcon(for: app) }
        }
    }
}

struct PersonalAppsHub: View {
    /// The store is injectable so tests can isolate from the (unsigned-simulator) keychain; production uses .shared and stays fail-closed.
    init(hiddenStore: HiddenAppsStore = .shared) { _hiddenStore = ObservedObject(wrappedValue: hiddenStore) }
    @StateObject private var library = PersonalAppsLibrary.shared
    @State private var importing = false
    @State private var importingURL = false
    @State private var showBrowser = false
    @State private var busy = false
    @State private var message: String?
    @State private var detail: PersonalLibraryApp?
    @State private var showCertificates = false
    @State private var sharing: PersonalLibraryApp?
    @State private var deleting: PersonalLibraryApp?
    @AppStorage("mirsa.personal.projects.sort") private var sort = "newest"
    @State private var drafts: [UUID: PersonalProjectDraft] = [:]
    @StateObject private var tweaks = IPATweakLibrary.shared
    @ObservedObject private var hiddenStore: HiddenAppsStore
    @State private var showHidden = false
    @State private var pendingHide: UUID?
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("mirsa.personal.projects.grid") private var gridMode = false

    private var sortedApps: [PersonalLibraryApp] {
        let base = hiddenStore.visible(library.apps, ns: .personal, id: { $0.id.uuidString })
        switch sort {
        case "name": return base.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case "oldest": return base.sorted { $0.date < $1.date }
        default: return base.sorted { $0.date > $1.date }
        }
    }
    private func hide(_ app: PersonalLibraryApp) {
        if hiddenStore.hide(HiddenAppID(.personal, app.id.uuidString)) { return }
        if hiddenStore.health == .faulted {
            message = personalText("Hidden apps are unavailable right now. Nothing was hidden.", "التطبيقات المخفية مو متاحة هلأ. ما انخفى شي.")
        } else { pendingHide = app.id; showHidden = true }
    }
    @ViewBuilder
    private func appMenu(_ app: PersonalLibraryApp) -> some View {
        Button { detail = app } label: { Label(personalText("Project details", "تفاصيل المشروع"), systemImage: "slider.horizontal.3") }
        Button { sharing = app } label: { Label(personalText("Export IPA", "تصدير IPA"), systemImage: "square.and.arrow.up") }
        Button { hide(app) } label: { Label(personalText("Hide", "إخفاء"), systemImage: "eye.slash") }
        Button(role: .destructive) { deleting = app } label: { Label(personalText("Delete", "حذف"), systemImage: "trash") }
    }
    private func compactTile(_ app: PersonalLibraryApp) -> some View {
        Button { detail = app } label: {
            VStack(spacing: 8) {
                PersonalAppIcon(app: app, library: library)
                Text(app.name).font(.caption.weight(.semibold)).lineLimit(1)
            }.frame(maxWidth: .infinity).padding(.vertical, MirsaSpacing.s).appsGlass(cornerRadius: MirsaRadius.l)
        }.buttonStyle(.mirsaPress)
    }
    private func reloadDrafts() {
        drafts = Dictionary(uniqueKeysWithValues: library.apps.compactMap { app in
            guard let data = try? Data(contentsOf: library.draftURL(app)),
                  let draft = try? JSONDecoder().decode(PersonalProjectDraft.self, from: data) else { return nil }
            return (app.id, draft)
        })
    }
    private func removeTweak(_ id: UUID, from app: PersonalLibraryApp) {
        do {
            let data = try Data(contentsOf: library.draftURL(app))
            var draft = try JSONDecoder().decode(PersonalProjectDraft.self, from: data)
            draft.tweakIDs.removeAll { $0 == id }
            try JSONEncoder().encode(draft).write(to: library.draftURL(app), options: [.atomic, .completeFileProtection])
            drafts[app.id] = draft
        } catch { message = error.localizedDescription }
    }
    private func chip(_ text: String, blue: Bool = false) -> some View {
        Text(text).font(.caption2.weight(.medium)).foregroundStyle(blue ? Color.cyan : Color.white.opacity(0.75))
            .padding(.horizontal, 9).padding(.vertical, 5)
            .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
    private func projectCard(_ app: PersonalLibraryApp) -> some View {
        let draft = drafts[app.id]
        let ids = draft?.tweakIDs ?? []
        let selected = ids.compactMap { id in tweaks.items.first { $0.id == id } }
        return VStack(alignment: .leading, spacing: 12) {
            Button { detail = app } label: {
                HStack(spacing: 13) {
                    PersonalAppIcon(app: app, library: library)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(draft?.name.isEmpty == false ? draft!.name : app.name).font(.headline).lineLimit(1)
                        Text(draft?.bundleID.isEmpty == false ? draft!.bundleID : app.bundleID)
                            .font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }.contentShape(Rectangle())
            }.buttonStyle(.mirsaPress)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    Button { detail = app } label: { chip("v" + (draft?.version.isEmpty == false ? draft!.version : app.version), blue: true) }
                        .buttonStyle(.mirsaPress)
                    ForEach(selected) { item in
                        HStack(spacing: 5) {
                            Button { detail = app } label: {
                                Text(item.name).lineLimit(1).truncationMode(.middle)
                                    .frame(maxWidth: 150, alignment: .leading)
                            }.buttonStyle(.mirsaPress)
                            Button { removeTweak(item.id, from: app) } label: {
                                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                                    .frame(width: 28, height: 28).contentShape(Rectangle())
                            }.buttonStyle(.mirsaPress).accessibilityLabel(personalText("Remove ", "إزالة ") + item.name)
                        }.font(.caption2).padding(.horizontal, 9).padding(.vertical, 5)
                            .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    }
                    Button { detail = app } label: {
                        chip(MirsaTr.p("addons", ids.count))
                    }.buttonStyle(.mirsaPress)
                }
            }
        }.padding(MirsaSpacing.card).frame(maxWidth: .infinity, alignment: .leading).appsGlass(cornerRadius: MirsaRadius.l)
    }

    var body: some View {
        ZStack {
            AuroraBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: MirsaSpacing.l) {
                    MirsaPageHeader(title: personalText("Projects", "المشاريع")) {
                        Menu {
                            Button { importing = true } label: { Label(personalText("From Files", "من الملفات"), systemImage: "folder") }
                            Button { importingURL = true } label: { Label(personalText("From link", "من رابط"), systemImage: "link") }
                            Button { showBrowser = true } label: { Label(personalText("Browser", "المتصفح"), systemImage: "safari") }
                        } label: {
                            MirsaRoundIcon(systemName: "plus")
                        }.disabled(busy || library.loadError != nil)
                        Button { gridMode.toggle() } label: {
                            MirsaRoundIcon(systemName: gridMode ? "list.bullet" : "square.grid.2x2")
                        }.buttonStyle(.mirsaPress)
                        .accessibilityLabel(personalText("Toggle list and grid", "تبديل القائمة والشبكة"))
                        Menu {
                            Picker(personalText("Sort projects", "ترتيب المشاريع"), selection: $sort) {
                                Text(personalText("Newest first", "الأحدث أولاً")).tag("newest")
                                Text(personalText("Oldest first", "الأقدم أولاً")).tag("oldest")
                                Text(personalText("Name", "الاسم")).tag("name")
                            }
                        } label: {
                            MirsaRoundIcon(systemName: "line.3.horizontal.decrease")
                        }
                    }
                    Button { showCertificates = true } label: {
                        HStack(spacing: MirsaSpacing.s) {
                            Image(systemName: "signature")
                                .font(.system(size: MirsaIconSize.m, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: MirsaIconSize.well, height: MirsaIconSize.well)
                                .background(MirsaPalette.accentGradient, in: RoundedRectangle(cornerRadius: MirsaRadius.s, style: .continuous))
                            Text(personalText("Signing certificates", "شهادات التوقيع")).font(MirsaFont.cardTitle)
                            Spacer()
                            Image(systemName: "chevron.right").font(.system(size: MirsaIconSize.s, weight: .bold)).foregroundStyle(MirsaPalette.textTertiary)
                        }.padding(MirsaSpacing.card).appsGlass(cornerRadius: MirsaRadius.l)
                    }.buttonStyle(.mirsaPress)
                    .mirsaAppear()
                    if busy { ProgressView() }
                    if library.apps.isEmpty {
                        VStack(spacing: MirsaSpacing.s) {
                            Image(systemName: "square.stack.3d.up").font(.system(size: 40, weight: .regular)).foregroundStyle(MirsaPalette.accentSoft)
                            Text(personalText("Your personal library starts here", "مكتبتك الخاصة بتبدأ هون")).font(MirsaFont.cardTitle).multilineTextAlignment(.center)
                            Text(personalText("Import an IPA, then open it to edit and sign. Nothing is installed automatically.",
                                      "استورد IPA وافتحه لتعدّله وتوقّعه. ما بينثبت شي تلقائياً."))
                                .font(.footnote).foregroundStyle(MirsaPalette.textSecondary).multilineTextAlignment(.center)
                        }.frame(maxWidth: .infinity).padding(MirsaSpacing.xl).appsGlass(cornerRadius: MirsaRadius.l)
                        .mirsaAppear(delay: 0.05)
                    }
                    if gridMode {
                        PersonalAppsHome(apps: sortedApps, allAppIDs: library.apps.map(\.id), library: library,
                                         onOpen: { detail = $0 }, menu: { appMenu($0) }, iconOverlay: { _ in EmptyView() })
                            .frame(minHeight: 520)
                    } else {
                    ForEach(sortedApps) { app in
                        projectCard(app)
                        .contextMenu { appMenu(app) }
                    }
                    }
                    if let error = library.loadError ?? message {
                        Text(error).font(.footnote).foregroundStyle(.secondary)
                    }
                }.padding(.horizontal, MirsaSpacing.page).padding(.top, MirsaSpacing.xs).padding(.bottom, MirsaSpacing.xl)
            }.scrollIndicators(.hidden)
            .mirsaStatusBarScrim()
        }
        .preferredColorScheme(.dark)
        .environment(\.layoutDirection, .leftToRight)
        .task { reloadDrafts() }
        .onChange(of: library.apps) { _ in
            reloadDrafts()
            if library.loadError == nil { hiddenStore.prune(.personal, existing: Set(library.apps.map { $0.id.uuidString })) }
        }
        .onChange(of: scenePhase) { p in if p != .active { hiddenStore.lock() } }
        .sheet(isPresented: $showHidden) {
            HiddenAppsView(store: hiddenStore) {
                PersonalHiddenGrid(apps: library.apps, pendingHide: $pendingHide)
            }
        }
        .sheet(isPresented: $importing) {
            DocumentPickerView(allowedContentTypes: [UTType(filenameExtension: "ipa") ?? .data]) { url in
                busy = true; message = nil
                Task {
                    let op = UUID()
                    do { try await library.add(url, signed: false); MirsaCompletionFeedback.shared.finish(operationID: op, outcome: .success) }
                    catch { MirsaCompletionFeedback.shared.finish(operationID: op, outcome: MirsaCompletionFeedback.outcome(for: error)); message = error.localizedDescription }
                    busy = false
                }
            }
        }
        .fullScreenCover(isPresented: $showBrowser) { MirsaBrowserView(initialURL: nil) { showBrowser = false } }
        .onReceive(NotificationCenter.default.publisher(for: .mirsaIncomingIPA)) { _ in showBrowser = false }
        .sheet(isPresented: $importingURL) { PersonalURLImportSheet(disabled: library.loadError != nil) { try await library.add($0, signed: false) } }
        .sheet(isPresented: $showCertificates) {
            PersonalCertificateManagerView()
        }
        .sheet(item: $detail, onDismiss: reloadDrafts) { app in
            PersonalProjectDetailView(app: app)
        }
        .sheet(item: $sharing) { app in
            PersonalLibraryShare(url: library.url(app))
        }
        .confirmationDialog(personalText("Delete this app from your personal library?", "حذف هالتطبيق من مكتبتك؟"),
                            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                            titleVisibility: .visible, presenting: deleting) { app in
            Button(personalText("Delete", "حذف"), role: .destructive) {
                do { try library.delete(app) } catch { message = error.localizedDescription }
                deleting = nil
            }
        } message: { app in
            Text(app.name)
        }
    }
}

private struct PersonalLibraryShare: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

struct PersonalHiddenGrid: View {
    let apps: [PersonalLibraryApp]
    @Binding var pendingHide: UUID?
    @ObservedObject var hidden: HiddenAppsStore = .shared
    var body: some View {
        let items = hidden.hiddenItems(apps, ns: .personal, id: { $0.id.uuidString })
        List {
            if items.isEmpty { Text(personalText("No hidden projects", "ما في مشاريع مخفية")).foregroundStyle(.secondary) }
            ForEach(items) { app in
                HStack {
                    Text(app.name).foregroundStyle(.white)
                    Spacer()
                    Button(personalText("Unhide", "إظهار")) { _ = hidden.unhide(HiddenAppID(.personal, app.id.uuidString)) }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .onAppear { if let id = pendingHide { pendingHide = nil; _ = hidden.hide(HiddenAppID(.personal, id.uuidString)) } }
    }
}
