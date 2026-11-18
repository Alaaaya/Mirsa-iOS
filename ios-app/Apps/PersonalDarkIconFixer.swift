import Foundation
import AssetCatalogWrapper

/// Rewrite only a disposable signing workspace, before any resource seal is made.
/// The catalog is never deleted and a failed rewrite never replaces the source.
enum PersonalDarkIconFixer {
    struct Record: Hashable {
        let name: String
        let type: String
        let appearance: Int64
        let key: [Int64]
    }

    static func primaryNames(_ info: [String: Any]) -> Set<String> {
        var names = Set<String>()
        if let name = info["CFBundleIconName"] as? String, !name.isEmpty { names.insert(name) }
        for field in ["CFBundleIcons", "CFBundleIcons~iphone", "CFBundleIcons~ipad"] {
            guard let icons = info[field] as? [String: Any],
                  let primary = icons["CFBundlePrimaryIcon"] as? [String: Any],
                  let name = primary["CFBundleIconName"] as? String, !name.isEmpty else { continue }
            names.insert(name)
        }
        return names
    }

    /// Include every key attribute except appearance, not just name and scale.
    /// Never remove a dark rendition whose exact default counterpart is absent.
    static func record(_ r: Rendition) -> Record {
        let k = r.namedLookup.key
        return Record(name: r.namedLookup.name, type: r.type.description,
                      appearance: k.themeAppearance,
                      key: [k.themeElement, k.themePart, k.themeSize, k.themeDirection,
                            k.themeValue, k.themeDimension1, k.themeDimension2, k.themeState,
                            k.themeLayer, k.themeScale, k.themeLocalization, k.themePresentationState,
                            k.themeIdiom, k.themeSubtype, k.themeIdentifier, k.themePreviousState,
                            k.themePreviousValue, k.themeSizeClassHorizontal, k.themeSizeClassVertical,
                            k.themeMemoryClass, k.themeGraphicsClass, k.themeDisplayGamut,
                            k.themeDeploymentTarget, k.themeGlyphWeight, k.themeGlyphSize])
    }

    static func counts(_ records: [Record]) -> [Record: Int] {
        records.reduce(into: [:]) { $0[$1, default: 0] += 1 }
    }

    @discardableResult static func repair(app: URL, info: [String: Any]) throws -> Int {
        let fm = FileManager.default
        let source = app.appendingPathComponent("Assets.car")
        let names = primaryNames(info)
        guard !names.isEmpty, fm.fileExists(atPath: source.path) else { return 0 }
        let values = try source.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true,
              let size = values.fileSize, size <= 512 * 1024 * 1024 else {
            throw SideloadError.message("The icon asset catalog is not a safe regular file.")
        }
        let temporary = app.appendingPathComponent(".mirsa-icon-\(UUID().uuidString).car")
        try fm.copyItem(at: source, to: temporary)
        defer { try? fm.removeItem(at: temporary) }
        let (_, collection) = try AssetCatalogWrapper.shared.renditions(forCarArchive: temporary)
        let all = collection.flatMap(\.renditions)
        let before = all.map(record)
        let defaults = Set(before.filter { $0.appearance == 0 })
        let targets = all.filter { rendition in
            guard rendition.type == .icon || rendition.type == .image else { return false }
            let item = record(rendition)
            guard names.contains(item.name), item.appearance == 1 || item.appearance == 3 else { return false }
            let fallback = Record(name: item.name, type: item.type, appearance: 0, key: item.key)
            return defaults.contains(fallback)
        }
        guard !targets.isEmpty else { return 0 }
        let removing = counts(targets.map(record))
        // Reopen after each compacting write, rather than reusing a stale CoreUI
        // theme store or rendition pointer from before the catalog changed.
        for target in targets.map(record) {
            let (catalog, current) = try AssetCatalogWrapper.shared.renditions(forCarArchive: temporary)
            guard let item = current.flatMap(\.renditions).first(where: { record($0) == target }) else {
                throw SideloadError.message("Icon catalog changed unexpectedly while rewriting.")
            }
            try catalog.removeItem(item, fileURL: temporary)
        }
        let (_, result) = try AssetCatalogWrapper.shared.renditions(forCarArchive: temporary)
        let after = counts(result.flatMap(\.renditions).map(record))
        var expected = counts(before)
        for (record, count) in removing {
            let left = expected[record, default: 0] - count
            if left == 0 { expected.removeValue(forKey: record) } else { expected[record] = left }
        }
        guard after == expected else {
            throw SideloadError.message("Icon catalog validation failed. The original was kept.")
        }
        let output = try Data(contentsOf: temporary, options: .mappedIfSafe)
        guard !output.isEmpty, output.count <= 512 * 1024 * 1024 else {
            throw SideloadError.message("Rewritten icon catalog has an invalid size.")
        }
        try output.write(to: source, options: .atomic)
        return targets.count
    }
}
