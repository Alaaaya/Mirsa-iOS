import Foundation

/// Independent package-only normalization. No access acquisition or system writes.
enum MirsaPosterNormalize {
    static let rawName = "com.apple.posterkit.provider.descriptor.identifier"
    static let userInfoName = "com.apple.posterkit.provider.contents.userInfo"

    static func shouldNormalize(source: URL, packageRoot: URL) throws -> Bool {
        let root = packageRoot.resolvingSymlinksInPath().standardizedFileURL.path + "/"
        let path = source.resolvingSymlinksInPath().standardizedFileURL.path
        guard path == String(root.dropLast()) || path.hasPrefix(root) else { throw PosterBoardStore.failure("Descriptor escaped private extraction root.") }
        return !path.dropFirst(root.count).split(separator: "/").contains { $0.lowercased() == "container" }
    }

    /// Only raw descriptor text and two top-level plist keys are changed.
    /// Directory names, nested identifiers and suggestion metadata stay unchanged.
    static func normalize(source: URL, packageRoot: URL, identifier: Int) throws -> Set<String> {
        guard try shouldNormalize(source: source, packageRoot: packageRoot) else { return [] }
        guard (10_000...99_999).contains(identifier) else { throw PosterBoardStore.failure("Numeric test identity out of range.") }
        let fm = FileManager.default
        let raw = try String(contentsOf: source.appendingPathComponent(rawName), encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        guard Int(raw) != nil, raw.count <= 16 else { throw PosterBoardStore.failure("Unsupported numeric wallpaper identity.") }
        let before = try PosterBoardStore.manifest(source)
        let fields = [
            (rawName, ""),
            (userInfoName, "wallpaperRepresentingIdentifier"),
            ("Wallpaper.plist", "identifier")
        ]
        var updates: [(String, Data)] = []
        for (name, key) in fields {
            let matches = before.keys.filter { $0.split(separator: "/").last.map(String.init) == name }
            guard matches.count == 1, let relative = matches.first else {
                throw PosterBoardStore.failure("Expected one known \(name) in approved package.")
            }
            let url = source.appendingPathComponent(relative)
            let original = try Data(contentsOf: url)
            guard original.count <= 262_144 else { throw PosterBoardStore.failure("Oversized package identity metadata.") }
            let data: Data
            if key.isEmpty {
                guard String(data: original, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) == raw else {
                    throw PosterBoardStore.failure("Approved raw identity differs.")
                }
                data = Data(String(identifier).utf8)
            } else {
                var format = PropertyListSerialization.PropertyListFormat.binary
                guard var object = try PropertyListSerialization.propertyList(from: original, format: &format) as? [String: Any],
                      let old = object[key], String(describing: old) == raw else {
                    throw PosterBoardStore.failure("Approved top-level identity differs in \(name).")
                }
                object[key] = identifier
                data = try PropertyListSerialization.data(fromPropertyList: object, format: format, options: 0)
            }
            updates.append((relative, data))
        }
        for (relative, bytes) in updates {
            let url = source.appendingPathComponent(relative)
            let attributes = try fm.attributesOfItem(atPath: url.path)
            try bytes.write(to: url, options: .atomic)
            // Keep the extracted mode, but leave the atomic rewrite timestamp fresh.
            var retained: [FileAttributeKey: Any] = [:]
            retained[.posixPermissions] = attributes[.posixPermissions]
            try fm.setAttributes(retained, ofItemAtPath: url.path)
        }
        let after = try PosterBoardStore.manifest(source)
        let changed = Set(before.keys.filter { before[$0] != after[$0] })
        guard Set(before.keys) == Set(after.keys), changed == Set(updates.map { $0.0 }) else {
            throw PosterBoardStore.failure("Normalization changed unexpected package files.")
        }
        return changed
    }

}
