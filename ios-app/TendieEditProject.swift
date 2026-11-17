import UIKit
import ZIPFoundation

/// Durable, editable description of one maker-made .tendies. Stored beside (never inside) the archive so the
/// package stays byte-for-byte what PosterBoard expects. Originals are kept untouched, so repeated saves never
/// compound crops or cutouts.
struct TendieEditProject: Codable, Equatable {
    struct Layer: Codable, Equatable {
        var id: UUID
        var role: String
        var scene: String
        var appearance: String
        var zoom: Double, x: Double, y: Double
        var crop: Bool
        var cutoutEnabled: Bool
        var homeOffsetX: Double, homeOffsetY: Double
        var imageFile: String
    }
    struct Fx: Codable, Equatable {
        var mechanism: String?
        var unlock: String, gyro: Bool, gyroStrength: Int, floating: Bool, motion: String, spin: Bool
        var particles: String, particleDirection: String, dimOnSleep: Bool, gradient: Bool, replicate: Bool
        var blend: String, blur: Bool, liquidGlass: Bool
    }
    var version = 1
    var crop: Bool
    var depth: Bool
    var effects: Fx
    var layers: [Layer]
}

extension TendieEditProject.Fx {
    init(_ e: PhotoWallpaper.Effects) {
        self.init(mechanism: e.mechanism?.rawValue, unlock: e.unlock.rawValue, gyro: e.gyro, gyroStrength: e.gyroStrength.rawValue,
                  floating: e.floating, motion: e.motion.rawValue, spin: e.spin, particles: e.particles.rawValue,
                  particleDirection: e.particleDirection.rawValue, dimOnSleep: e.dimOnSleep, gradient: e.gradient,
                  replicate: e.replicate, blend: e.blend.rawValue, blur: e.blur, liquidGlass: e.liquidGlass)
    }
    /// Unknown raw values (written by a newer build) fall back to the default of that single option.
    var effects: PhotoWallpaper.Effects {
        var e = PhotoWallpaper.Effects()
        e.mechanism = mechanism.flatMap { WallpaperMechanism(rawValue: $0) }
        e.unlock = .init(rawValue: unlock) ?? .none
        e.gyro = gyro
        e.gyroStrength = .init(rawValue: gyroStrength) ?? .medium
        e.floating = floating
        e.motion = .init(rawValue: motion) ?? .float
        e.spin = spin
        e.particles = .init(rawValue: particles) ?? .none
        e.particleDirection = .init(rawValue: particleDirection) ?? .falling
        e.dimOnSleep = dimOnSleep; e.gradient = gradient; e.replicate = replicate
        e.blend = .init(rawValue: blend) ?? .normal
        e.blur = blur; e.liquidGlass = liquidGlass
        return e
    }
}

enum TendieEditError: Error, Equatable {
    /// The archive was not made by this maker or its layers cannot be read faithfully.
    case notEditable
}

/// Result of opening a .tendies for editing.
struct TendieEditLoad {
    var layers: [WallpaperPhotoLayer]
    var crop: Bool
    var depth: Bool
    var effects: PhotoWallpaper.Effects
    /// True when no saved project existed and only the pictures could be recovered from the archive.
    var effectsUnknown: Bool
}

enum TendieProjectStore {
    static var root: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("MirsaTendieProjects", isDirectory: true)
    }()

    private static func folder(for fileName: String) -> URL {
        let key = Data(fileName.utf8).base64EncodedString()
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "+", with: "-")
        return root.appendingPathComponent(String(key.prefix(120)), isDirectory: true)
    }

    static func save(layers: [WallpaperPhotoLayer], crop: Bool, depth: Bool, effects: PhotoWallpaper.Effects, forFileName fileName: String) throws {
        let fm = FileManager.default
        let target = folder(for: fileName)
        let staging = root.appendingPathComponent(".staging-" + UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: staging) }
        var out: [TendieEditProject.Layer] = []
        for l in layers {
            guard let data = l.image.pngData() else { throw CocoaError(.fileWriteUnknown) }
            let file = l.id.uuidString + ".png"
            try data.write(to: staging.appendingPathComponent(file))
            out.append(.init(id: l.id, role: l.role.rawValue, scene: l.scene.rawValue, appearance: l.appearance.rawValue,
                             zoom: l.zoom, x: l.x, y: l.y, crop: l.crop, cutoutEnabled: l.cutoutEnabled,
                             homeOffsetX: l.homeOffsetX, homeOffsetY: l.homeOffsetY, imageFile: file))
        }
        let project = TendieEditProject(crop: crop, depth: depth, effects: .init(effects), layers: out)
        try JSONEncoder().encode(project).write(to: staging.appendingPathComponent("project.json"))
        try? fm.removeItem(at: target)
        try fm.moveItem(at: staging, to: target)
    }

    static func hasProject(forFileName fileName: String) -> Bool {
        FileManager.default.fileExists(atPath: folder(for: fileName).appendingPathComponent("project.json").path)
    }

    static func loadProject(forFileName fileName: String) throws -> TendieEditLoad {
        let dir = folder(for: fileName)
        guard let data = try? Data(contentsOf: dir.appendingPathComponent("project.json")),
              let p = try? JSONDecoder().decode(TendieEditProject.self, from: data),
              p.version == 1, !p.layers.isEmpty, p.layers.count <= PhotoWallpaper.maximumLayers else { throw TendieEditError.notEditable }
        var layers: [WallpaperPhotoLayer] = []
        for l in p.layers {
            // Only a plain file name inside the project folder is accepted.
            guard l.imageFile == (l.imageFile as NSString).lastPathComponent, !l.imageFile.hasPrefix("."),
                  let image = try? PhotoWallpaper.loadImage(dir.appendingPathComponent(l.imageFile)) else { throw TendieEditError.notEditable }
            var layer = WallpaperPhotoLayer(image: image, role: .init(rawValue: l.role) ?? .background, id: l.id)
            layer.scene = .init(rawValue: l.scene) ?? .shared
            layer.appearance = .init(rawValue: l.appearance) ?? .both
            layer.zoom = min(4, max(1, l.zoom)); layer.x = min(1, max(-1, l.x)); layer.y = min(1, max(-1, l.y))
            layer.crop = l.crop; layer.cutoutEnabled = l.cutoutEnabled
            layer.homeOffsetX = min(1, max(-1, l.homeOffsetX)); layer.homeOffsetY = min(1, max(-1, l.homeOffsetY))
            layers.append(layer)
        }
        return TendieEditLoad(layers: layers, crop: p.crop, depth: p.depth, effects: p.effects.effects, effectsUnknown: false)
    }

    static func move(from old: String, to new: String) {
        let fm = FileManager.default
        try? fm.removeItem(at: folder(for: new))
        try? fm.createDirectory(at: root, withIntermediateDirectories: true)
        try? fm.moveItem(at: folder(for: old), to: folder(for: new))
    }

    /// Drops projects whose .tendies row no longer exists. Never touches rows or archives.
    static func prune(keeping fileNames: [String]) {
        let fm = FileManager.default
        let keep = Set(fileNames.map { folder(for: $0).lastPathComponent })
        guard let items = try? fm.contentsOfDirectory(atPath: root.path) else { return }
        for name in items where !keep.contains(name) { try? fm.removeItem(at: root.appendingPathComponent(name)) }
    }

    // MARK: Archives made before projects existed

    /// Reads only the pictures of an archive this maker produced (layer-N-role nodes with UUID.png assets).
    /// Bounded: entry count, per-file and total size; nothing is extracted to disk, no symlinks are followed.
    static func loadLegacyArchive(_ url: URL) throws -> TendieEditLoad {
        guard let archive = try? Archive(url: url, accessMode: .read) else { throw TendieEditError.notEditable }
        var count = 0, total: UInt64 = 0
        var mains: [(path: String, entry: Entry)] = []
        var assets: [String: Entry] = [:]
        for entry in archive {
            count += 1
            let size = UInt64(entry.uncompressedSize)
            guard count <= 8192, size <= 64_000_000, total <= 400_000_000 - size else { throw TendieEditError.notEditable }
            total += size
            guard entry.type == .file || entry.type == .directory else { throw TendieEditError.notEditable }
            let parts = entry.path.split(separator: "/", omittingEmptySubsequences: false)
            guard !entry.path.hasPrefix("/"), !parts.contains(".."), !entry.path.contains("\\") else { throw TendieEditError.notEditable }
            if entry.type == .file {
                if entry.path.hasSuffix(".ca/main.caml") { mains.append((entry.path, entry)) }
                else if entry.path.contains(".ca/assets/") { assets[entry.path] = entry }
            }
        }
        guard !mains.isEmpty, mains.count <= 3 else { throw TendieEditError.notEditable }
        // index -> (role, image path)
        var found: [Int: (String, String)] = [:]
        let pattern = try NSRegularExpression(pattern: "name=\"layer-([0-9]+)-(background|middle|foreground)\"[^>]*>\\s*(?:<[^>]*>\\s*)*?<contents type=\"CGImage\" src=\"assets/([0-9A-Fa-f-]{36})\\.png\"")
        for main in mains {
            var data = Data()
            _ = try? archive.extract(main.entry, bufferSize: 65_536) { data.append($0) }
            guard !data.isEmpty, data.count < 8_000_000, let text = String(data: data, encoding: .utf8) else { throw TendieEditError.notEditable }
            let base = String(main.path.dropLast("main.caml".count))
            let ns = text as NSString
            for m in pattern.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
                guard let index = Int(ns.substring(with: m.range(at: 1))) else { continue }
                found[index] = (ns.substring(with: m.range(at: 2)), base + "assets/" + ns.substring(with: m.range(at: 3)) + ".png")
            }
        }
        guard !found.isEmpty, found.count <= PhotoWallpaper.maximumLayers else { throw TendieEditError.notEditable }
        var layers: [WallpaperPhotoLayer] = []
        for index in found.keys.sorted() {
            let (role, path) = found[index]!
            guard let entry = assets[path] else { throw TendieEditError.notEditable }
            var data = Data()
            guard (try? archive.extract(entry, bufferSize: 65_536) { data.append($0) }) != nil else { throw TendieEditError.notEditable }
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
            defer { try? FileManager.default.removeItem(at: tmp) }
            try data.write(to: tmp)
            guard let image = try? PhotoWallpaper.loadImage(tmp) else { throw TendieEditError.notEditable }
            // The archive holds the already-cropped picture, so it is reused as the original: no crop, no cutout.
            var layer = WallpaperPhotoLayer(image: image, role: WallpaperPhotoLayer.Role(rawValue: role) ?? .background)
            layer.cutoutEnabled = false; layer.cutoutStatus = .unavailable; layer.crop = true
            layers.append(layer)
        }
        let depth = Set(layers.map(\.role)).count > 1
        return TendieEditLoad(layers: layers, crop: true, depth: depth, effects: PhotoWallpaper.Effects(floating: true), effectsUnknown: true)
    }

    /// One entry point for the row's pencil: saved project first, then legacy archive, otherwise not editable.
    static func load(fileName: String, archive: URL) throws -> TendieEditLoad {
        if hasProject(forFileName: fileName) { return try loadProject(forFileName: fileName) }
        return try loadLegacyArchive(archive)
    }
}
