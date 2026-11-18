import Foundation
import Darwin
import CryptoKit
import ImageIO

/// Diagnostic listing. Unclassified entries remain visible but never deletable.
/// A title, UUID or Apple's shared 7400 identity is never provenance by itself.
enum MirsaCustomWallpapers {
    struct Item: Identifiable, Equatable {
        let title: String
        let id: String
        let container: String
        let relative: String
        let expected: [String: String]
        let device: UInt64
        let inode: UInt64
        let paths: [String]
        var canDelete: Bool = true
        /// Small read-only preview (JPEG, <=128px) from the wallpaper's own files; nil = fallback icon.
        var thumbnail: Data? = nil
        /// >0: no name found; UI shows localized numbered fallback with UUID as secondary text.
        var fallbackIndex: Int = 0
    }
    struct Snapshot: Equatable {
        let expected: [String: String]
        let paths: [String]
        let device: UInt64
        let inode: UInt64
    }
    static let maxNodes = 512
    static let maxFileBytes = 16 * 1024 * 1024
    static let maxTreeBytes = 64 * 1024 * 1024
    static let animeWallpaper = "versions/1/contents/7400.WWDC_2022-390w-844h@3x~iphone.wallpaper/Wallpaper.plist"
    // Generated from the approved Anime-Squad.tendies, not from an installed
    // descriptor. Excludes ONLY the three known normalized identity files.
    static let animeImmutable: [String: String] = [
        "com.apple.posterkit.provider.identifierURL.suggestionMetadata.plist": "b359d11cdb7eaabd1878ce935edecfb7e98ac38c1c78e8394518b57f5e3f2c65",
        "com.apple.posterkit.role.identifier": "ce6a53a6eef62fe767aaa54a33ca9dcc29cce6f84f471d71f1d0167abe087ce7",
        "providerInfo.plist": "697dc3b7a7d93849757f664fea1b830d3bdc661a9fcdad43b71870fd602083f1",
        "versions/1/RuntimeSnapshotMetadata-home.plist": "78c6651211d4abdde0e987f3420a3102e113361201c78331e9aa50d3b6db1d99",
        "versions/1/RuntimeSnapshotMetadata-lock.plist": "1e971720e91261d9369a4029b70081ccf33ce6ce9b1945c3319dbeeb465dda48",
        "versions/1/com.apple.posterkit.provider.instance.complicationLayout.plist": "6f70cdde0e28fec881f8e3fb1712d5b72d892bd4f885a53bc6d93174da03d745",
        "versions/1/com.apple.posterkit.provider.instance.titleStyleConfiguration.plist": "2bc4be91f199c2c5db7acfb7ae8f9581eb292498ecd0cddbe8d1ac3edf43e92a",
        "versions/1/contents/.com.apple.posterkit.provider.contents.configurableOptions.plist": "2b5decfc32306577b28df137eed469628f02307c3caed18ee3bc4a141e1caf55",
        "versions/1/contents/7400.WWDC_2022-390w-844h@3x~iphone.wallpaper/7400.WWDC_2022_Background-390w-844h@3x~iphone.ca/assetManifest.caml": "6a2ce34b3c37b6c49f6081f98fd274838c50bf88ac4b5a6afadacbd61212f11f",
        "versions/1/contents/7400.WWDC_2022-390w-844h@3x~iphone.wallpaper/7400.WWDC_2022_Background-390w-844h@3x~iphone.ca/assets/back.png": "789da70a0436e23a8dbe938afe7d949d9913048b79c5bcdc7cf01dbe2768c847",
        "versions/1/contents/7400.WWDC_2022-390w-844h@3x~iphone.wallpaper/7400.WWDC_2022_Background-390w-844h@3x~iphone.ca/assets/gojo.png": "19952ff5568d115c643a5f61b07c4d93c96580a13f310c5c4859de98ffab15bb",
        "versions/1/contents/7400.WWDC_2022-390w-844h@3x~iphone.wallpaper/7400.WWDC_2022_Background-390w-844h@3x~iphone.ca/index.xml": "6a0870d93f39195c9e5e5652ad1e8447e90efbc0615b2d03f3ee4bd3ee40c60d",
        "versions/1/contents/7400.WWDC_2022-390w-844h@3x~iphone.wallpaper/7400.WWDC_2022_Background-390w-844h@3x~iphone.ca/main.caml": "7e8fb9e413cf81db584eb1fad2f963dd7e6030c8fc72d4bd4375ba9079e774ee",
        "versions/1/contents/7400.WWDC_2022-390w-844h@3x~iphone.wallpaper/7400.WWDC_2022_Floating-390w-844h@3x~iphone.ca/assetManifest.caml": "6a2ce34b3c37b6c49f6081f98fd274838c50bf88ac4b5a6afadacbd61212f11f",
        "versions/1/contents/7400.WWDC_2022-390w-844h@3x~iphone.wallpaper/7400.WWDC_2022_Floating-390w-844h@3x~iphone.ca/assets/boruto.png": "31bb6435d02f4559d9425e39608d24b1de28f04e186f1f27b140b17b8b8b03df",
        "versions/1/contents/7400.WWDC_2022-390w-844h@3x~iphone.wallpaper/7400.WWDC_2022_Floating-390w-844h@3x~iphone.ca/index.xml": "6a0870d93f39195c9e5e5652ad1e8447e90efbc0615b2d03f3ee4bd3ee40c60d",
        "versions/1/contents/7400.WWDC_2022-390w-844h@3x~iphone.wallpaper/7400.WWDC_2022_Floating-390w-844h@3x~iphone.ca/main.caml": "61ae56f631d4e272191bcb725607cd28bf73d83d35e5f03440ab586d03f733e3",
        "versions/1/contents/7400.WWDC_2022-390w-844h@3x~iphone.wallpaper/7400.WWDC_2022_Foreground-390w-844h@3x~iphone.ca/assetManifest.caml": "6a2ce34b3c37b6c49f6081f98fd274838c50bf88ac4b5a6afadacbd61212f11f",
        "versions/1/contents/7400.WWDC_2022-390w-844h@3x~iphone.wallpaper/7400.WWDC_2022_Foreground-390w-844h@3x~iphone.ca/assets/naruto.png": "a9d6615f7a5418e8a515af419291e60d5cd21d9ec64c2e7a61dcde945e64c26a",
        "versions/1/contents/7400.WWDC_2022-390w-844h@3x~iphone.wallpaper/7400.WWDC_2022_Foreground-390w-844h@3x~iphone.ca/index.xml": "6a0870d93f39195c9e5e5652ad1e8447e90efbc0615b2d03f3ee4bd3ee40c60d",
        "versions/1/contents/7400.WWDC_2022-390w-844h@3x~iphone.wallpaper/7400.WWDC_2022_Foreground-390w-844h@3x~iphone.ca/main.caml": "741018e92c81238f428298d076944d723c81220541e0d6a761c3d433711a74df",
        "versions/1/contents/com.apple.posterkit.provider.contents.otherMetadata.plist": "415d32c8a0461649b1dce0e6463959d65997a261c1e95f1995b075863201f11d",
        "versions/1/supplements/0/com.apple.posterkit.provider.supplementURL.homescreenConfiguration.plist": "92ffd3ddccc732421f5219e006cae6d08aefb583076124ba31821d365e3a87ad",
    ]
    static let animeVariable: Set<String> = [MirsaPosterNormalize.rawName,
        "versions/1/contents/" + MirsaPosterNormalize.userInfoName, animeWallpaper]

    static func validRelative(_ path: String) -> Bool {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        return !parts.isEmpty && path.utf8.count <= 1024 && !path.contains("\\") && !path.contains("\0") &&
            parts.allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." }
    }
    private static func identity(_ url: URL, kind: mode_t) throws -> stat {
        var value = stat()
        guard lstat(url.path, &value) == 0, value.st_mode & S_IFMT == kind else {
            throw PosterBoardStore.failure("Custom wallpaper has a missing, linked or special node.")
        }
        return value
    }
    /// Open without following final links, bound reads, and compare fd identity
    /// before/after. Ancestors are checked by the caller for every node.
    static func read(_ url: URL, limit: Int) throws -> Data {
        let before = try identity(url, kind: S_IFREG)
        guard before.st_nlink >= 1, before.st_size >= 0, before.st_size <= Int64(limit) else {
            throw PosterBoardStore.failure("Wallpaper file exceeds bounded read limit.")
        }
        let fd = open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        guard fd >= 0 else { throw PosterBoardStore.failure("Cannot open wallpaper file safely.") }
        defer { Darwin.close(fd) }
        var opened = stat()
        guard fstat(fd, &opened) == 0, opened.st_dev == before.st_dev, opened.st_ino == before.st_ino,
              opened.st_mode & S_IFMT == S_IFREG, opened.st_size == before.st_size else {
            throw PosterBoardStore.failure("Wallpaper file changed while opening.")
        }
        var result = Data(), buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            let count = buffer.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress!, $0.count) }
            guard count >= 0 else { throw PosterBoardStore.failure("Wallpaper read failed.") }
            if count == 0 { break }
            guard count <= limit - result.count else { throw PosterBoardStore.failure("Wallpaper file grew past limit.") }
            result.append(contentsOf: buffer.prefix(count))
        }
        var after = stat(), final = stat()
        guard fstat(fd, &after) == 0, lstat(url.path, &final) == 0,
              after.st_size == opened.st_size, result.count == Int(after.st_size),
              final.st_ino == after.st_ino, final.st_dev == after.st_dev,
              final.st_mode & S_IFMT == S_IFREG,
              after.st_mtimespec.tv_sec == opened.st_mtimespec.tv_sec,
              after.st_mtimespec.tv_nsec == opened.st_mtimespec.tv_nsec,
              after.st_ctimespec.tv_sec == opened.st_ctimespec.tv_sec,
              after.st_ctimespec.tv_nsec == opened.st_ctimespec.tv_nsec else {
            throw PosterBoardStore.failure("Wallpaper file mutated during read.")
        }
        return result
    }
    /// Bounded manual traversal, no Foundation recursive enumerator following
    /// aliases. The lease's one intended alias is permitted, nothing below it.
    static func snapshot(_ root: URL, lease: PosterBoardLease? = nil,
                         ownedRecord: MirsaWallpaperJournal.Record? = nil) throws -> Snapshot {
        func safe(_ url: URL) throws {
            if let lease {
                let prefix = lease.effectiveURL.path + "/"
                guard url.path.hasPrefix(prefix) else { throw PosterBoardStore.failure("Wallpaper escaped lease.") }
                let relative = String(url.path.dropFirst(prefix.count))
                _ = try grant(relative, lease: lease)
            }
            guard PosterBoardStore.unredirected(url, lease: lease) else {
                throw PosterBoardStore.failure("Redirected custom wallpaper path.")
            }
        }
        try safe(root)
        let before = try identity(root, kind: S_IFDIR)
        if let record = ownedRecord {
            // Only an exact app-private completed journal grants unlink authority.
            // Payload size/hardlinks are irrelevant to unlink, not to bounded reads.
            let binding = Snapshot(expected: [:], paths: [], device: UInt64(before.st_dev), inode: UInt64(before.st_ino))
            guard root.lastPathComponent == record.id,
                  root.path.hasSuffix("/" + record.relative),
                  completedJournal([record], id: record.id, container: record.container,
                                   relative: record.relative, snapshot: binding) != nil else {
                throw PosterBoardStore.failure("Owned wallpaper root does not match its completed journal.")
            }
        }
        var expected: [String: String] = [:], paths: [String] = [], total = 0
        func walk(_ directory: URL, prefix: String, depth: Int) throws {
            guard depth <= 20 else { throw PosterBoardStore.failure("Wallpaper tree too deep.") }
            try safe(directory)
            _ = try identity(directory, kind: S_IFDIR)
            let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            guard names.count <= maxNodes, names.count <= maxNodes - paths.count else {
                throw PosterBoardStore.failure("Wallpaper tree exceeds node limit.")
            }
            for name in names.sorted() {
                guard !name.contains("/"), validRelative(name) else { throw PosterBoardStore.failure("Invalid wallpaper filename.") }
                let relative = prefix + name, url = directory.appendingPathComponent(name)
                guard validRelative(relative), paths.count < maxNodes else { throw PosterBoardStore.failure("Invalid or excessive wallpaper paths.") }
                try safe(url)
                var node = stat()
                guard lstat(url.path, &node) == 0, node.st_dev == before.st_dev else { throw PosterBoardStore.failure("Wallpaper node changed volume.") }
                switch node.st_mode & S_IFMT {
                case S_IFDIR:
                    paths.append("D:" + relative)
                    try walk(url, prefix: relative + "/", depth: depth + 1)
                case S_IFREG:
                    paths.append("F:" + relative)
                    if ownedRecord != nil {
                        // No content read, truncate, chmod or write to a shared inode.
                        // Repeated snapshots still catch replacement/size/time changes.
                        guard node.st_nlink >= 1, node.st_size >= 0 else {
                            throw PosterBoardStore.failure("Invalid owned wallpaper file.")
                        }
                        expected[relative] = "unlink:\(node.st_dev):\(node.st_ino):\(node.st_size):\(node.st_nlink):\(node.st_mtimespec.tv_sec):\(node.st_mtimespec.tv_nsec):\(node.st_ctimespec.tv_sec):\(node.st_ctimespec.tv_nsec)"
                    } else {
                        let data = try read(url, limit: min(maxFileBytes, maxTreeBytes - total))
                        total += data.count
                        expected[relative] = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
                    }
                default: throw PosterBoardStore.failure("Special wallpaper node rejected.")
                }
            }
        }
        try walk(root, prefix: "", depth: 0)
        try safe(root)
        let after = try identity(root, kind: S_IFDIR)
        guard !expected.isEmpty, before.st_dev == after.st_dev, before.st_ino == after.st_ino else {
            throw PosterBoardStore.failure("Wallpaper root changed or is empty.")
        }
        return Snapshot(expected: expected, paths: paths.sorted(), device: UInt64(after.st_dev), inode: UInt64(after.st_ino))
    }
    private static func scratch(_ path: String) -> Bool {
        // Known iOS-generated snapshots only. Unknown additions remain hidden.
        ["versions/1/RuntimeSnapshot-home.png", "versions/1/RuntimeSnapshot-lock.png",
         "versions/1/RuntimeSnapshot-home.heic", "versions/1/RuntimeSnapshot-lock.heic"].contains(path)
    }
    static func recognizedAnime(_ snapshot: Snapshot, title: String?) -> Bool {
        guard title == "Anime Squad", animeImmutable.allSatisfy({ snapshot.expected[$0.key] == $0.value }),
              animeVariable.isSubset(of: Set(snapshot.expected.keys)),
              snapshot.expected.keys.allSatisfy({ animeImmutable[$0] != nil || animeVariable.contains($0) || scratch($0) }) else { return false }
        let allowedFiles = Set(snapshot.expected.keys)
        // Empty unknown directories cannot be silently swept into deletion.
        return snapshot.paths.allSatisfy { typed in
            let path = String(typed.dropFirst(2))
            if typed.hasPrefix("F:") { return allowedFiles.contains(path) }
            return typed.hasPrefix("D:") && allowedFiles.contains { $0.hasPrefix(path + "/") }
        }
    }
    /// An Apple baseline is useful ONLY when an authoritative stock inventory
    /// was fully read from the immutable system volume, not from PRB descriptors.
    /// Existing device descriptors are a mixed stock/custom subset and cannot
    /// establish either Apple's full inventory or negative provenance.
    struct AppleBaseline {
        let complete: Bool
        let immutableSystemSource: Bool
        let titles: Set<String>
        let identifiers: Set<String>
        let assetNames: Set<String>
    }
    struct BespokePayload {
        let title: String
        let identifier: String
        let assetNames: Set<String>
        let animations: Set<String>
        let wallpaperPath: String
    }
    static func bespoke(_ payload: BespokePayload, snapshot: Snapshot, baseline: AppleBaseline?) -> Bool {
        guard let baseline, baseline.complete, baseline.immutableSystemSource,
              !baseline.titles.isEmpty, !baseline.identifiers.isEmpty, !baseline.assetNames.isEmpty,
              validRelative(payload.wallpaperPath), snapshot.expected[payload.wallpaperPath] != nil,
              !payload.title.isEmpty, payload.title.count <= 120,
              !payload.identifier.isEmpty, payload.identifier.count <= 120,
              !payload.identifier.hasPrefix("com.apple."),
              !payload.title.lowercased().contains("apple"),
              !payload.animations.isEmpty, payload.animations.count <= 8,
              !payload.assetNames.isEmpty, payload.assetNames.count <= 32 else { return false }
        let normalized: (String) -> String = { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        let stockTitles = Set(baseline.titles.map(normalized))
        let stockIDs = Set(baseline.identifiers.map(normalized))
        let stockAssets = Set(baseline.assetNames.map(normalized))
        // Three independent negative comparisons, PLUS positive tendies-shaped
        // CA payload. A renamed title or unknown UUID alone never passes.
        guard !stockTitles.contains(normalized(payload.title)),
              !stockIDs.contains(normalized(payload.identifier)),
              payload.assetNames.allSatisfy({ !stockAssets.contains(normalized($0)) }),
              payload.animations.allSatisfy({ validRelative($0) && !$0.contains("/") && $0.hasSuffix(".ca") }) else { return false }
        let parent = String(payload.wallpaperPath.dropLast("Wallpaper.plist".count))
        guard parent.hasSuffix(".wallpaper/") else { return false }
        for animation in payload.animations {
            let prefix = parent + animation + "/"
            guard snapshot.expected[prefix + "main.caml"] != nil,
                  snapshot.expected[prefix + "index.xml"] != nil,
                  snapshot.expected[prefix + "assetManifest.caml"] != nil,
                  snapshot.expected.keys.contains(where: { $0.hasPrefix(prefix + "assets/") }) else { return false }
        }
        return payload.assetNames.allSatisfy { name in
            validRelative(name) && !name.contains("/") &&
            snapshot.expected.keys.contains { $0.hasPrefix(parent) && $0.hasSuffix("/assets/" + name) }
        }
    }
    /// CollectionsPoster stock resources ship in /Library/Wallpaper/Collections.
    /// Never derive Apple provenance from the mutable PosterBoard datastore.
    /// The entire accessible on-device Collections catalog must enumerate cleanly
    /// on the same read-only system mount, with every .wallpaper metadata parsed.
    /// Missing/model-specific inaccessible resources, alternate schema or mutable
    /// mounts disable generic classification rather than reducing the baseline.
    private static func systemBaseline(log: (String) -> Void) -> AppleBaseline? {
        do {
            let root = URL(fileURLWithPath: "/Library/Wallpaper/Collections", isDirectory: true)
            guard PosterBoardStore.unredirected(root) else { throw PosterBoardStore.failure("Stock catalog redirected.") }
            var volume = statfs(), system = statfs()
            guard statfs(root.path, &volume) == 0, statfs("/System/Library", &system) == 0,
                  volume.f_flags & UInt32(MNT_RDONLY) != 0,
                  system.f_flags & UInt32(MNT_RDONLY) != 0,
                  volume.f_fsid.val.0 == system.f_fsid.val.0,
                  volume.f_fsid.val.1 == system.f_fsid.val.1 else {
                throw PosterBoardStore.failure("Stock catalog is not on the verified read-only system mount.")
            }
            let baseline = try scanAppleCatalog(root)
            log("CUSTOM BASELINE complete on-device read-only Collections catalog: \(baseline.identifiers.count) IDs, \(baseline.assetNames.count) asset names.")
            log("CUSTOM PROBE JOURNAL unavailable: Mirsa cannot authenticate a journal in Probe's sandbox; no guessed access.")
            return baseline
        } catch {
            log("CUSTOM BASELINE unavailable or partial; generic tendies hidden: " + error.localizedDescription)
            log("CUSTOM PROBE JOURNAL unavailable: no authenticated Probe journal accessible in Mirsa.")
            return nil
        }
    }
    /// Read-only bounded parser shared with offline fixtures. Caller MUST verify
    /// immutable system-volume provenance before using this result in production.
    static func scanAppleCatalog(_ root: URL) throws -> AppleBaseline {
        var titles = Set<String>(), identifiers = Set<String>(), assets = Set<String>()
        var nodes = 0, packages = 0, metadata = 0, metadataBytes = 0
        func walk(_ directory: URL, depth: Int) throws {
            guard depth <= 24, PosterBoardStore.unredirected(directory) else {
                throw PosterBoardStore.failure("Stock catalog depth or redirect rejected.")
            }
            _ = try identity(directory, kind: S_IFDIR)
            let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            guard names.count <= 12_000 - nodes else { throw PosterBoardStore.failure("Stock catalog exceeds bounded inventory.") }
            nodes += names.count
            let packagesBefore = packages
            if directory.pathExtension == "wallpaperCollection" {
                guard names.contains("Wallpapers") else { throw PosterBoardStore.failure("Stock collection inventory missing.") }
            }
            if directory.pathExtension == "wallpaper" {
                packages += 1
                guard names.contains("Wallpaper.plist") else { throw PosterBoardStore.failure("Stock wallpaper metadata missing.") }
            }
            for name in names.sorted() {
                guard validRelative(name), !name.contains("/") else { throw PosterBoardStore.failure("Invalid stock catalog filename.") }
                let url = directory.appendingPathComponent(name)
                guard PosterBoardStore.unredirected(url) else { throw PosterBoardStore.failure("Linked stock catalog entry.") }
                var node = stat()
                guard lstat(url.path, &node) == 0 else { throw PosterBoardStore.failure("Stock catalog entry unreadable.") }
                switch node.st_mode & S_IFMT {
                case S_IFDIR: try walk(url, depth: depth + 1)
                case S_IFREG:
                    assets.insert(name)
                    if name == "Wallpaper.plist" {
                        guard directory.pathExtension == "wallpaper" else { throw PosterBoardStore.failure("Unexpected stock metadata placement.") }
                        let data = try read(url, limit: 524_288)
                        metadataBytes += data.count
                        guard metadataBytes <= 8 * 1024 * 1024,
                              let info = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                              let title = info["name"] as? String, !title.isEmpty,
                              let identifier = info["identifier"], !String(describing: identifier).isEmpty else {
                            throw PosterBoardStore.failure("Incomplete or unknown stock wallpaper metadata schema.")
                        }
                        titles.insert(title); identifiers.insert(String(describing: identifier)); metadata += 1
                    }
                default: throw PosterBoardStore.failure("Special stock catalog node rejected.")
                }
            }
            if directory.pathExtension == "wallpaperCollection", packages == packagesBefore {
                throw PosterBoardStore.failure("Stock collection has no readable wallpaper packages.")
            }
        }
        try walk(root, depth: 0)
        guard packages > 0, metadata == packages, !titles.isEmpty, !identifiers.isEmpty, !assets.isEmpty else {
            throw PosterBoardStore.failure("Stock catalog is empty or partial.")
        }
        return AppleBaseline(complete: true, immutableSystemSource: true, titles: titles, identifiers: identifiers, assetNames: assets)
    }
    private static func payload(_ target: URL, snapshot: Snapshot) throws -> BespokePayload? {
        let wallpapers = snapshot.expected.keys.filter { $0.hasSuffix("/Wallpaper.plist") }
        guard wallpapers.count == 1, let wallpaper = wallpapers.first else { return nil }
        let bytes = try read(target.appendingPathComponent(wallpaper), limit: 262_144)
        guard let object = try PropertyListSerialization.propertyList(from: bytes, format: nil) as? [String: Any],
              let title = object["name"] as? String, let rawID = object["identifier"] else { return nil }
        let parent = String(wallpaper.dropLast("Wallpaper.plist".count))
        let raw = try read(target.appendingPathComponent(MirsaPosterNormalize.rawName), limit: 128)
        let infoPath = wallpaper.split(separator: "/").dropLast(2).joined(separator: "/") + "/" + MirsaPosterNormalize.userInfoName
        guard snapshot.expected[infoPath] != nil else { return nil }
        let infoBytes = try read(target.appendingPathComponent(infoPath), limit: 262_144)
        guard let rawIdentity = String(data: raw, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              rawIdentity == String(describing: rawID),
              let userInfo = try PropertyListSerialization.propertyList(from: infoBytes, format: nil) as? [String: Any],
              let userIdentity = userInfo["wallpaperRepresentingIdentifier"],
              String(describing: userIdentity) == rawIdentity,
              userInfo["wallpaperRepresentingFileName"] as? String == target.appendingPathComponent(wallpaper).deletingLastPathComponent().lastPathComponent else { return nil }
        let animations = Set(snapshot.paths.filter { $0.hasPrefix("D:" + parent) && $0.hasSuffix(".ca") }
            .map { String($0.dropFirst(2 + parent.count)) }.filter { !$0.contains("/") })
        let assets = Set(snapshot.expected.keys.filter { $0.hasPrefix(parent) && $0.contains(".ca/assets/") }
            .map { URL(fileURLWithPath: $0).lastPathComponent })
        return BespokePayload(title: title, identifier: String(describing: rawID), assetNames: assets,
                              animations: animations, wallpaperPath: wallpaper)
    }
    static func completedJournal(_ records: [MirsaWallpaperJournal.Record], id: String,
                                 container: String, relative: String, snapshot: Snapshot) -> MirsaWallpaperJournal.Record? {
        let matches = records.filter { $0.id == id }
        guard matches.count == 1, let record = matches.first,
              (try? MirsaWallpaperJournal.validatePath(record)) != nil,
              record.copied, record.container == container, record.relative == relative,
              record.device == snapshot.device, record.inode == snapshot.inode else { return nil }
        // Ownership is the trusted app-private journal identity (UUID, canonical path, root inode).
        // PosterBoard legitimately rewrites files after respring, so content hashes are NOT a gate.
        return record
    }

    static let thumbMaxNodes = 160, thumbMaxFileBytes = 6 * 1024 * 1024, thumbMaxSide = 8192
    static let thumbExtensions: Set<String> = ["png", "jpg", "jpeg", "heic"]
    /// Bounded, read-only preview from the wallpaper's own files. Every node is lease/identity checked,
    /// no symlinks or hardlinks, no network, small decode via ImageIO downsample. Any problem = nil (icon).
    static func previewThumbnail(_ root: URL, lease: PosterBoardLease, isCancelled: () -> Bool = { false }) -> Data? {
        let deadline = ProcessInfo.processInfo.systemUptime + 3
        func active() -> Bool { !isCancelled() && ProcessInfo.processInfo.systemUptime < deadline }
        let prefix = lease.effectiveURL.path + "/"
        guard root.path.hasPrefix(prefix), let rootNode = try? identity(root, kind: S_IFDIR) else { return nil }
        var candidates: [(rank: Int, url: URL)] = []
        var visited = 0
        func safe(_ url: URL) -> Bool {
            guard url.path.hasPrefix(prefix),
                  (try? grant(String(url.path.dropFirst(prefix.count)), lease: lease)) != nil,
                  PosterBoardStore.unredirected(url, lease: lease) else { return false }
            return true
        }
        func walk(_ dir: URL, depth: Int) {
            guard active(), depth <= 8, visited < thumbMaxNodes, safe(dir),
                  let names = try? FileManager.default.contentsOfDirectory(atPath: dir.path), names.count <= thumbMaxNodes else { return }
            for name in names.sorted() {
                visited += 1
                guard active(), visited <= thumbMaxNodes, validRelative(name) else { return }
                if name.hasPrefix(".") { continue }
                let url = dir.appendingPathComponent(name)
                var node = stat()
                guard lstat(url.path, &node) == 0, node.st_dev == rootNode.st_dev, safe(url) else { continue }
                switch node.st_mode & S_IFMT {
                case S_IFDIR: walk(url, depth: depth + 1)
                case S_IFREG:
                    guard thumbExtensions.contains(url.pathExtension.lowercased()), node.st_nlink == 1,
                          node.st_size > 0, node.st_size <= Int64(thumbMaxFileBytes) else { continue }
                    let lower = url.path.lowercased()
                    let snapshotFile = lower.contains("snapshot")
                    let rank = lower.contains("/assets/") ? 0 : (lower.contains("preview") || lower.contains("thumb") ? 1 : (snapshotFile ? 3 : 2))
                    candidates.append((rank, url))
                default: continue
                }
            }
        }
        walk(root, depth: 0)
        for candidate in candidates.sorted(by: { $0.rank < $1.rank }).prefix(3) {
            guard active() else { return nil }
            if let data = try? read(candidate.url, limit: thumbMaxFileBytes), let jpeg = thumbnailData(from: data) { return jpeg }
        }
        return nil
    }

    struct DescriptorInfo: Equatable {
        var name: String? = nil
        var family: String? = nil
        var identifier: String? = nil
        var packageName: String? = nil
        var apple = false
    }
    /// Read-only list classification, never deletion authority. Stock packages
    /// usually match their numeric filename; the device's WWDC22 plist uses
    /// identifier 19662 inside a shared 7400 envelope instead.
    static func isAppleCatalog(packageName: String, plistIdentifier: String?, family: String?, userInfoIdentifier: String? = nil) -> Bool {
        guard packageName.hasSuffix(".wallpaper"), let dot = packageName.firstIndex(of: ".") else { return false }
        let numeric = String(packageName[packageName.startIndex..<dot])
        guard (3...6).contains(numeric.count), numeric.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }),
              let pid = plistIdentifier,
              let fam = family, !fam.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        if let u = userInfoIdentifier, u != pid { return false }
        // Explicit owner-confirmed Apple plist identity, not a blanket 7400,
        // WWDC display-name or family-only rule. Custom identities stay visible.
        if fam == "WWDC22", pid == "19662" { return true }
        return pid == numeric
    }
    /// Plist IDs on device may be NSString OR integer NSNumber. Do not stringify
    /// arbitrary containers, bools or floating-point IDs into catalog evidence.
    static func metadataIdentifier(_ value: Any?) -> String? {
        let text: String
        if let string = value as? String { text = string.trimmingCharacters(in: .whitespacesAndNewlines) }
        else if let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() {
            text = number.stringValue
        } else { return nil }
        guard !text.isEmpty, text.count <= 16,
              text.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }) else { return nil }
        return text
    }
    /// Decode the real serialized Wallpaper.plist and provider userInfo schema.
    /// Used by the bounded lease reader below and by binary/XML file regressions.
    static func descriptorMetadata(packageName: String, wallpaperData: Data, userInfoData: Data?) -> DescriptorInfo? {
        guard wallpaperData.count <= 64 * 1024,
              let d = try? PropertyListSerialization.propertyList(from: wallpaperData, format: nil) as? [String: Any] else { return nil }
        let clean = { (key: String) -> String? in
            guard let value = d[key] as? String else { return nil }
            let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : String(text.prefix(80))
        }
        var userInfoId: String? = nil
        if let data = userInfoData {
            // Present-but-unreadable/malformed metadata is NOT evidence of Apple.
            guard data.count <= 64 * 1024,
                  let ui = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                  let id = metadataIdentifier(ui["wallpaperRepresentingIdentifier"]) else {
                return DescriptorInfo(name: clean("name"), family: clean("family"), identifier: metadataIdentifier(d["identifier"]), packageName: packageName)
            }
            userInfoId = id
        }
        var info = DescriptorInfo(name: clean("name"), family: clean("family"),
                                  identifier: metadataIdentifier(d["identifier"]), packageName: packageName)
        info.apple = isAppleCatalog(packageName: packageName, plistIdentifier: info.identifier,
                                    family: info.family, userInfoIdentifier: userInfoId)
        return info
    }
    /// Descriptor metadata from its own Wallpaper.plist, bounded and lease-checked (exact paths, no recursion).
    static func descriptorInfo(_ root: URL, lease: PosterBoardLease, log: (String) -> Void) -> DescriptorInfo {
        var info = DescriptorInfo()
        let prefix = lease.effectiveURL.path + "/"
        guard root.path.hasPrefix(prefix) else { return info }
        let base = String(root.path.dropFirst(prefix.count))
        func names(_ rel: String) -> [String]? {
            guard let url = try? grant(rel, lease: lease), PosterBoardStore.unredirected(url, lease: lease),
                  let n = try? FileManager.default.contentsOfDirectory(atPath: url.path), n.count <= 64 else { return nil }
            return n.filter { validRelative($0) }.sorted()
        }
        guard let versions = names(base + "/versions") else { log("CUSTOM NAME no versions dir"); return info }
        for v in versions.filter({ !$0.isEmpty && $0.utf8.allSatisfy { $0 >= 48 && $0 <= 57 } }).reversed().prefix(3) {
            let contents = base + "/versions/" + v + "/contents"
            var userInfoData: Data? = nil
            let ui = contents + "/com.apple.posterkit.provider.contents.userInfo"
            if let url = try? grant(ui, lease: lease), PosterBoardStore.unredirected(url, lease: lease) {
                userInfoData = try? read(url, limit: 64 * 1024)
            }
            for pkg in (names(contents) ?? []).filter({ $0.hasSuffix(".wallpaper") }).prefix(3) {
                let rel = contents + "/" + pkg + "/Wallpaper.plist"
                do {
                    let url = try grant(rel, lease: lease)
                    guard PosterBoardStore.unredirected(url, lease: lease) else { continue }
                    let data = try read(url, limit: 64 * 1024)
                    if let decoded = descriptorMetadata(packageName: pkg, wallpaperData: data, userInfoData: userInfoData) {
                        info = decoded
                        if info.name != nil || info.apple { return info }
                    }
                } catch { log("CUSTOM NAME unreadable " + rel + ": " + error.localizedDescription) }
            }
        }
        return info
    }
    static func descriptorName(_ root: URL, lease: PosterBoardLease, log: (String) -> Void) -> String? {
        descriptorInfo(root, lease: lease, log: log).name
    }
    /// ImageIO downsample with pixel-dimension caps; never a full decode of oversized images.
    static func thumbnailData(from data: Data) -> Data? {
        guard data.count <= thumbMaxFileBytes,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int, let h = props[kCGImagePropertyPixelHeight] as? Int,
              w > 0, h > 0, w <= thumbMaxSide, h <= thumbMaxSide, w * h <= 40_000_000,
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 128] as CFDictionary) else { return nil }
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, "public.jpeg" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: 0.7] as CFDictionary)
        guard CGImageDestinationFinalize(dest), out.length > 0, out.length < 64 * 1024 else { return nil }
        return out as Data
    }
    private static func journals() throws -> [MirsaWallpaperJournal.Record] {
        let root = MirsaWallpaperJournal.root
        try MirsaWallpaperJournal.safeLocal(root)
        guard FileManager.default.fileExists(atPath: root.path) else { return [] }
        _ = try identity(root, kind: S_IFDIR)
        let names = try FileManager.default.contentsOfDirectory(atPath: root.path)
        guard names.count <= 256 else { throw PosterBoardStore.failure("Too many wallpaper journals; preserved.") }
        return names.filter { $0.hasSuffix(".json") }.compactMap { name in
            let id = String(name.dropLast(5)), url = root.appendingPathComponent(name)
            guard UUID(uuidString: id) != nil, PosterBoardStore.unredirected(url),
                  let data = try? read(url, limit: 1024 * 1024),
                  let record = try? JSONDecoder().decode(MirsaWallpaperJournal.Record.self, from: data),
                  record.id == id, (try? MirsaWallpaperJournal.validatePath(record)) != nil else { return nil }
            return record
        }
    }
    private static func grant(_ relative: String, lease: PosterBoardLease) throws -> URL {
        guard validRelative(relative) else { throw PosterBoardStore.failure("Invalid wallpaper path.") }
        var prefix = ""
        for part in relative.split(separator: "/") {
            prefix += (prefix.isEmpty ? "" : "/") + part
            guard lease.grant(prefix), lease.permits(lease.effectiveURL.appendingPathComponent(prefix)) else {
                throw PosterBoardStore.failure("Custom wallpaper path access denied.")
            }
        }
        return lease.effectiveURL.appendingPathComponent(relative)
    }
    private static func classify(id: String, container: String, relative: String, lease: PosterBoardLease,
                                 records: [MirsaWallpaperJournal.Record], baseline: AppleBaseline?) throws -> Item? {
        let record = MirsaWallpaperJournal.Record(id: id, title: "", container: container, relative: relative,
                                                  expected: ["placeholder": "placeholder"])
        try MirsaWallpaperJournal.validatePath(record)
        let target = try grant(relative, lease: lease)
        let node = try identity(target, kind: S_IFDIR)
        let binding = Snapshot(expected: [:], paths: [], device: UInt64(node.st_dev), inode: UInt64(node.st_ino))
        let owned = completedJournal(records, id: id, container: container, relative: relative, snapshot: binding)
        let first = try snapshot(target, lease: lease, ownedRecord: owned)
        let candidate: BespokePayload? = owned == nil ? (try? payload(target, snapshot: first)) : nil
        guard owned != nil || recognizedAnime(first, title: candidate?.title) ||
              candidate.map({ bespoke($0, snapshot: first, baseline: baseline) }) == true else { return nil }
        // Metadata read and full classification must refer to one stable tree.
        guard try snapshot(target, lease: lease, ownedRecord: owned) == first else { throw PosterBoardStore.failure("Custom wallpaper changed while classifying.") }
        let label = owned?.title ?? candidate?.title ?? "Custom wallpaper"
        return Item(title: label.isEmpty ? "Mirsa wallpaper" : String(label.prefix(120)), id: id,
                    container: container, relative: relative, expected: first.expected,
                    device: first.device, inode: first.inode, paths: first.paths)
    }
    /// Listing is identity-only. Payload hashing is reserved for the exact
    /// confirmed delete, not repeated for every descriptor/asset on refresh.
    static func journalItem(_ record: MirsaWallpaperJournal.Record, device: UInt64, inode: UInt64) -> Item? {
        guard (try? MirsaWallpaperJournal.validatePath(record)) != nil,
              record.copied, record.device == device, record.inode == inode,
              let paths = record.paths else { return nil }
        return Item(title: record.title.isEmpty ? "Mirsa wallpaper" : String(record.title.prefix(120)),
                    id: record.id, container: record.container, relative: record.relative,
                    expected: record.expected, device: device, inode: inode, paths: paths)
    }
    private static func list(lease: PosterBoardLease, records: [MirsaWallpaperJournal.Record], log: @escaping (String) -> Void) throws -> [Item] {
        try PosterBoardStore.validateIdentity(lease.effectiveURL, lease: lease)
        let parent = try MirsaPosterCopy.destination(lease: lease)
        let root = try grant(parent, lease: lease)
        let names = try FileManager.default.contentsOfDirectory(atPath: root.path)
        guard names.count <= 256 else { throw PosterBoardStore.failure("Too many wallpaper descriptors; no deletion allowed.") }
        var found: [Item] = []
        var processed = 0, unavailable = 0
        let deadline = ProcessInfo.processInfo.systemUptime + 30
        // Include exact recorded older versions as well as the current provider.
        let candidates = records.filter { $0.container == lease.targetURL.path }.sorted { $0.id < $1.id }
        for record in candidates {
            if ProcessInfo.processInfo.systemUptime >= deadline {
                log("CUSTOM LIST budget reached; returning " + String(found.count) + " partial rows.")
                break
            }
            processed += 1
            do {
                let target = try MirsaWallpaperJournal.grantExact(record, lease: lease)
                MirsaWallpaperEvidence.observe(target, context: "list uuid=" + record.id + " copied=" + String(record.copied), log: log)
                let node = try identity(target, kind: S_IFDIR)
                if let item = journalItem(record, device: UInt64(node.st_dev), inode: UInt64(node.st_ino)) {
                    found.append(item)
                } else {
                    unavailable += 1
                    log("CUSTOM LIST journal root incomplete or replaced " + record.id + "; retained for management review.")
                }
            } catch {
                unavailable += 1
                log("CUSTOM LIST exact journal row unavailable " + record.id + ": " + error.localizedDescription)
                continue // uncertainty never becomes absence or deletion authority
            }
        }
        let visible = Set(found.map { $0.relative })
        let current = names.filter { UUID(uuidString: $0) != nil }.sorted()
        var unknownCount = 0
        // No historical UUIDs or provider/basename heuristics confer provenance.
        var unnamed = 0, appleHidden = 0
        for id in current.prefix(64) where !visible.contains(parent + "/" + id) {
            unknownCount += 1
            let rel = parent + "/" + id
            var title = ""
            if let target = try? grant(rel, lease: lease), ProcessInfo.processInfo.systemUptime < deadline - 5 {
                let info = descriptorInfo(target, lease: lease, log: log)
                if info.apple {
                    appleHidden += 1
                    log("CUSTOM LIST hidden Apple catalog descriptor " + id + " package=" + (info.packageName ?? "?"))
                    continue
                }
                title = info.name ?? ""
            }
            if title.isEmpty { unnamed += 1 }
            found.append(Item(title: title, id: id, container: lease.targetURL.path,
                              relative: rel, expected: [:], device: 0, inode: 0,
                              paths: [], canDelete: false, fallbackIndex: title.isEmpty ? unnamed : 0))
        }
        // Deep diagnostics remain available through Inspect. Refresh reads only
        // cheap metadata, never walks Apple assets or decodes any thumbnails.
        log("CUSTOM LIST ACCESS requested=" + String(lease.grantRequests) + " reusedReadable=" + String(lease.reusedReads) + " thumbnails=0")
        log("CUSTOM LIST SUMMARY currentDescriptors=" + String(names.count) +
            " journalCandidates=" + String(candidates.count) + " shown=" + String(found.count) +
            " unavailable=" + String(unavailable) + " unprocessed=" + String(candidates.count - processed) +
            " appleHidden=" + String(appleHidden) + " unknownVisible=" + String(unknownCount - appleHidden) + " notShownByRowCap=" + String(max(0, current.count - 64)) +
            "; partial diagnostic build, not all-custom deletion. Unknown/possible Apple rows inspect only.")

        return found
    }
    static func list(log: @escaping (String) -> Void) throws -> [Item] {
        try MirsaWallpaperJournal.exclusive {
            let container = try MirsaPosterDiscovery.discover(log: log)
            let started = ProcessInfo.processInfo.systemUptime
            let lease = try PosterBoardLease(path: container, reuseReadableAccess: true, log: log)
            defer { try? lease.close() }
            do {
                let items = try list(lease: lease, records: journals(), log: log)
                try lease.close()
                log("CUSTOM LIST elapsed=" + String(ProcessInfo.processInfo.systemUptime - started))
                log("CUSTOM LIST identity-checked journal rows \(items.count); payload validation deferred until confirmed delete. Unclassified rows visible with warnings and inspect only; no generic all-custom deletion.")
                return items
            } catch { try? lease.close(); throw error }
        }
    }
    /// Called lazily for visible rows, independently of list completion. The
    /// same mutation lock and short lease protect every read; no cached authority.
    static func thumbnail(_ item: Item) async -> Data? {
        try? await MirsaWallpaperJournal.queued(timeout: 2) { cancelled in
            if cancelled() { return nil as Data? }
            let record = MirsaWallpaperJournal.Record(id: item.id, title: item.title,
                container: item.container, relative: item.relative, expected: ["preview": "read-only"])
            try MirsaWallpaperJournal.validatePath(record)
            let lease = try PosterBoardLease(path: item.container, reuseReadableAccess: true)
            defer { try? lease.close() }
            try PosterBoardStore.validateIdentity(lease.effectiveURL, lease: lease)
            let target = try grant(item.relative, lease: lease)
            let node = try identity(target, kind: S_IFDIR)
            guard !cancelled(), item.device == 0 ||
                (item.device == UInt64(node.st_dev) && item.inode == UInt64(node.st_ino)) else { return nil }
            guard !descriptorInfo(target, lease: lease, log: { _ in }).apple else { return nil }
            let data = previewThumbnail(target, lease: lease, isCancelled: cancelled)
            try lease.close()
            return cancelled() ? nil : data
        }
    }
    /// UI must obtain separate per-item destructive confirmation before calling.
    static func delete(_ requested: Item, log: @escaping (String) -> Void) throws {
        let started = ProcessInfo.processInfo.systemUptime
        func timing(_ stage: String, lease: PosterBoardLease? = nil) {
            let elapsed = ProcessInfo.processInfo.systemUptime - started
            log("DELETE TIMING " + stage + " elapsedSeconds=" + String(elapsed) +
                " grants=" + String(lease?.grantRequests ?? 0) + " reusedReads=" + String(lease?.reusedReads ?? 0))
        }
        defer { timing("finished") }
        try MirsaWallpaperJournal.exclusive {
            timing("lock-acquired")
            guard requested.canDelete else { throw PosterBoardStore.failure("Unclassified wallpaper is inspect-only. Nothing deleted.") }
            let container = try MirsaPosterDiscovery.discover(log: log)
            guard container == requested.container else { throw PosterBoardStore.failure("PosterBoard container changed; refresh the list.") }
            // Only skip token acquisition for exact nodes already proven readable.
            // This grants no unlink authority: every journal, snapshot, inode,
            // symlink and absence check below still runs unchanged.
            let lease = try PosterBoardLease(path: container, reuseReadableAccess: true, log: log)
            timing("access-ready", lease: lease)
            defer { try? lease.close() }
            do {
                let records = try journals()
                // Lightweight rows currently require an exact completed journal;
                // no broad immutable stock-catalog scan is needed for ownership.
                let baseline: AppleBaseline? = nil
                guard let fresh = try classify(id: requested.id, container: requested.container,
                                              relative: requested.relative, lease: lease,
                                              records: records, baseline: baseline),
                      fresh.id == requested.id, fresh.container == requested.container,
                      fresh.relative == requested.relative, fresh.device == requested.device,
                      fresh.inode == requested.inode,
                      completedJournal(records, id: fresh.id, container: fresh.container, relative: fresh.relative,
                                       snapshot: Snapshot(expected: fresh.expected, paths: fresh.paths,
                                                          device: fresh.device, inode: fresh.inode)) != nil else { throw PosterBoardStore.failure("Wallpaper changed or is no longer proven custom. Nothing deleted.") }
                timing("classified", lease: lease)
                let target = try grant(fresh.relative, lease: lease)
                guard let owned = completedJournal(records, id: fresh.id, container: fresh.container,
                    relative: fresh.relative, snapshot: Snapshot(expected: fresh.expected, paths: fresh.paths,
                    device: fresh.device, inode: fresh.inode)) else {
                    throw PosterBoardStore.failure("Completed journal missing before deletion.")
                }
                let final = try snapshot(target, lease: lease, ownedRecord: owned)
                guard final.expected == fresh.expected, final.paths == fresh.paths,
                      final.device == fresh.device, final.inode == fresh.inode,
                      let classified = try classify(id: fresh.id, container: fresh.container, relative: fresh.relative,
                                                    lease: lease, records: try journals(), baseline: baseline),
                      classified.id == fresh.id, classified.device == fresh.device, classified.inode == fresh.inode,
                      lease.permits(target) else { throw PosterBoardStore.failure("Wallpaper changed before deletion; preserved.") }
                timing("revalidated", lease: lease)
                let last = try identity(target, kind: S_IFDIR)
                guard UInt64(last.st_dev) == fresh.device, UInt64(last.st_ino) == fresh.inode else {
                    throw PosterBoardStore.failure("Wallpaper root changed before deletion.")
                }
                try FileManager.default.removeItem(at: target)
                guard try MirsaWallpaperJournal.absent(target) else { throw PosterBoardStore.failure("Custom deletion absence not proven.") }
                timing("removed-and-absence-verified", lease: lease)
                try lease.close()
                timing("lease-closed", lease: lease)
                // Existing owned-journal deletion remains untouched. Cleanup can
                // later reconcile this now-absent entry through its normal path.
                log("CUSTOM DELETE VERIFIED exact UUID " + fresh.id + "; lease closed; refresh pending.")
            } catch { try? lease.close(); throw error }
        }
    }
}
