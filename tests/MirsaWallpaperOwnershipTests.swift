import XCTest
import Foundation
@testable import Mirsa

/// These fixtures call production package/path helpers on private temporary files.
/// They never acquire a lease, discover containers, delete system files or respring.
final class MirsaWallpaperOwnershipTests: XCTestCase {
    private let provider = "com.apple.WallpaperKit.CollectionsPoster"
    private func record() -> MirsaWallpaperJournal.Record {
        let id = UUID().uuidString
        return .init(id: id, title: "fixture", container: "/var/mobile/Containers/Data/Application/" + UUID().uuidString,
                     relative: "Library/Application Support/PRBPosterExtensionDataStore/73/Extensions/" + provider + "/descriptors/" + id,
                     expected: ["versions/1/contents/asset": String(repeating: "a", count: 64)])
    }
    private func temporaryRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("mirsa-ownership-fixture-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }
    private func plist(_ value: [String: Any], at url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try PropertyListSerialization.data(fromPropertyList: value, format: .binary, options: 0).write(to: url)
    }
    private func object(_ url: URL) throws -> [String: Any] {
        try XCTUnwrap(try PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil) as? [String: Any])
    }
    func testExactOwnedUUIDPathAndRecordRoundTrip() throws {
        let original = record()
        XCTAssertFalse(original.copied)
        XCTAssertNil(original.device); XCTAssertNil(original.inode)
        XCTAssertNoThrow(try MirsaWallpaperJournal.validatePath(original))
        var completed = original
        completed.device = 4; completed.inode = 123; completed.copied = true
        let decoded = try JSONDecoder().decode(MirsaWallpaperJournal.Record.self, from: JSONEncoder().encode(completed))
        XCTAssertEqual(decoded.id, completed.id); XCTAssertEqual(decoded.title, completed.title)
        XCTAssertEqual(decoded.container, completed.container); XCTAssertEqual(decoded.relative, completed.relative)
        XCTAssertEqual(decoded.expected, completed.expected)
        XCTAssertEqual(decoded.device, 4); XCTAssertEqual(decoded.inode, 123); XCTAssertTrue(decoded.copied)
        XCTAssertNoThrow(try MirsaWallpaperJournal.validatePath(decoded))
    }
    func testRejectsSharedIdentifiersOtherProvidersWrongUUIDAndTraversal() throws {
        let original = record()
        for shared in ["7400", "7400.DYNAMIC"] {
            var invalid = original
            invalid.id = shared
            invalid.relative = String(original.relative.dropLast(original.id.count)) + shared
            XCTAssertThrowsError(try MirsaWallpaperJournal.validatePath(invalid), shared)
        }
        for relative in [
            original.relative.replacingOccurrences(of: provider, with: "com.apple.MercuryPoster"),
            original.relative.replacingOccurrences(of: provider, with: "com.apple.Posters.CollectionsPosterApp"),
            String(original.relative.dropLast(original.id.count)) + UUID().uuidString,
            original.relative + "/../" + original.id,
            "/" + original.relative,
            original.relative.replacingOccurrences(of: "/73/", with: "//73/"),
            original.relative.replacingOccurrences(of: "/73/", with: "/../"),
            original.relative.replacingOccurrences(of: "/73/", with: "/0/"),
            original.relative.replacingOccurrences(of: "/73/", with: "/-1/")
        ] {
            var invalid = original; invalid.relative = relative
            XCTAssertThrowsError(try MirsaWallpaperJournal.validatePath(invalid), relative)
        }
        for path in ["../asset", "/absolute", "versions/../asset"] {
            var invalid = original; invalid.expected = [path: "hash"]
            XCTAssertThrowsError(try MirsaWallpaperJournal.validatePath(invalid), path)
        }
        for container in ["/var/mobile/Library", original.container + "/../" + UUID().uuidString,
                          original.container + "/Library", "/private" + original.container] {
            var invalid = original; invalid.container = container
            XCTAssertThrowsError(try MirsaWallpaperJournal.validatePath(invalid), container)
        }
        var empty = original; empty.expected = [:]
        XCTAssertThrowsError(try MirsaWallpaperJournal.validatePath(empty))
    }
    func testAbsenceRequiresExactExistingRealParentAndDoesNotTreatLinksAsAbsent() throws {
        let fm = FileManager.default, root = try temporaryRoot()
        let target = root.appendingPathComponent(UUID().uuidString)
        XCTAssertTrue(try MirsaWallpaperJournal.absent(target))
        try Data("keep".utf8).write(to: target)
        XCTAssertFalse(try MirsaWallpaperJournal.absent(target))
        let directory = root.appendingPathComponent("directory")
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        XCTAssertFalse(try MirsaWallpaperJournal.absent(directory))
        let broken = root.appendingPathComponent("broken")
        try fm.createSymbolicLink(at: broken, withDestinationURL: root.appendingPathComponent("missing"))
        XCTAssertFalse(try MirsaWallpaperJournal.absent(broken))
        XCTAssertThrowsError(try MirsaWallpaperJournal.absent(root.appendingPathComponent("missing-parent/child")))
        let alias = root.appendingPathComponent("alias")
        try fm.createSymbolicLink(at: alias, withDestinationURL: directory)
        XCTAssertThrowsError(try MirsaWallpaperJournal.absent(alias.appendingPathComponent("missing")))
        XCTAssertEqual(try Data(contentsOf: target), Data("keep".utf8))
    }
    func testNormalizeChangesOnlyThreeTopLevelFieldsWithFreshTimesAndOriginalPermissions() throws {
        let fm = FileManager.default, package = try temporaryRoot()
        let source = package.appendingPathComponent("Extensions/" + provider + "/descriptors/" + UUID().uuidString)
        try fm.createDirectory(at: source, withIntermediateDirectories: true)
        let raw = MirsaPosterNormalize.rawName, user = MirsaPosterNormalize.userInfoName
        let wallpaper = "versions/1/contents/7400.DYNAMIC/Wallpaper.plist"
        try Data("7400\n".utf8).write(to: source.appendingPathComponent(raw))
        try plist(["wallpaperRepresentingIdentifier": 7400, "nested": ["wallpaperRepresentingIdentifier": 7400],
                   "wallpaperRepresentingFileName": "7400.DYNAMIC"], at: source.appendingPathComponent(user))
        try plist(["identifier": 7400, "nested": ["identifier": 7400], "asset": "7400.DYNAMIC"],
                  at: source.appendingPathComponent(wallpaper))
        let suggestion = source.appendingPathComponent("com.apple.posterkit.provider.identifierURL.suggestionMetadata.plist")
        try plist(["identifier": 7400, "nested": ["id": "7400"]], at: suggestion)
        let asset = source.appendingPathComponent("versions/1/contents/7400.DYNAMIC/asset.bin")
        try Data([0, 255, 1, 128]).write(to: asset)
        let expectedChanges: Set<String> = [raw, user, wallpaper]
        let old = Date(timeIntervalSince1970: 1_600_000_000)
        for path in try PosterBoardStore.manifest(source).keys {
            try fm.setAttributes([.posixPermissions: 0o640, .modificationDate: old],
                                 ofItemAtPath: source.appendingPathComponent(path).path)
        }
        let before = try PosterBoardStore.manifest(source)
        let suggestionBytes = try Data(contentsOf: suggestion)
        let changed = try MirsaPosterNormalize.normalize(source: source, packageRoot: package, identifier: 50757)
        XCTAssertEqual(changed, expectedChanges)
        let after = try PosterBoardStore.manifest(source)
        XCTAssertEqual(Set(before.keys), Set(after.keys))
        XCTAssertEqual(Set(before.keys.filter { before[$0] != after[$0] }), expectedChanges)
        XCTAssertEqual(try String(contentsOf: source.appendingPathComponent(raw), encoding: .utf8), "50757")
        let info = try object(source.appendingPathComponent(user)), wall = try object(source.appendingPathComponent(wallpaper))
        XCTAssertEqual(info["wallpaperRepresentingIdentifier"] as? Int, 50757)
        XCTAssertEqual(wall["identifier"] as? Int, 50757)
        XCTAssertEqual((info["nested"] as? [String: Int])?["wallpaperRepresentingIdentifier"], 7400)
        XCTAssertEqual((wall["nested"] as? [String: Int])?["identifier"], 7400)
        XCTAssertEqual(info["wallpaperRepresentingFileName"] as? String, "7400.DYNAMIC")
        XCTAssertEqual(wall["asset"] as? String, "7400.DYNAMIC")
        XCTAssertEqual(try Data(contentsOf: suggestion), suggestionBytes)
        XCTAssertEqual(try Data(contentsOf: asset), Data([0, 255, 1, 128]))
        for path in before.keys {
            let attributes = try fm.attributesOfItem(atPath: source.appendingPathComponent(path).path)
            XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o640)
            let modified = try XCTUnwrap(attributes[.modificationDate] as? Date)
            if expectedChanges.contains(path) { XCTAssertGreaterThan(modified, old) }
            else { XCTAssertEqual(modified.timeIntervalSince1970, old.timeIntervalSince1970, accuracy: 0.001) }
        }
    }
    func testNormalizeAcceptsArbitraryAgreedNumericIdentityAndRejectsContradictionsBeforeWrites() throws {
        let root = try temporaryRoot(), source = root.appendingPathComponent("descriptor")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        let raw = source.appendingPathComponent(MirsaPosterNormalize.rawName)
        let user = source.appendingPathComponent(MirsaPosterNormalize.userInfoName)
        let wallpaper = source.appendingPathComponent("versions/1/contents/Wallpaper.plist")
        try Data("9183".utf8).write(to: raw)
        try plist(["wallpaperRepresentingIdentifier": 9183], at: user)
        try plist(["identifier": 7400], at: wallpaper)
        var before = try PosterBoardStore.manifest(source)
        XCTAssertThrowsError(try MirsaPosterNormalize.normalize(source: source, packageRoot: root, identifier: 60527))
        XCTAssertEqual(try PosterBoardStore.manifest(source), before)
        try plist(["identifier": 9183], at: wallpaper)
        try plist(["wallpaperRepresentingIdentifier": 7400], at: user)
        before = try PosterBoardStore.manifest(source)
        XCTAssertThrowsError(try MirsaPosterNormalize.normalize(source: source, packageRoot: root, identifier: 60527))
        XCTAssertEqual(try PosterBoardStore.manifest(source), before)
        try plist(["wallpaperRepresentingIdentifier": 9183], at: user)
        XCTAssertEqual(try MirsaPosterNormalize.normalize(source: source, packageRoot: root, identifier: 60527).count, 3)
        XCTAssertEqual(try String(contentsOf: raw, encoding: .utf8), "60527")
        XCTAssertEqual(try object(user)["wallpaperRepresentingIdentifier"] as? Int, 60527)
        XCTAssertEqual(try object(wallpaper)["identifier"] as? Int, 60527)
    }
    func testNormalizeRejectsEscapeAndInvalidIdentityWithoutWritesAndSkipsContainerPackages() throws {
        let root = try temporaryRoot(), other = try temporaryRoot()
        let source = root.appendingPathComponent("descriptor")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        let raw = source.appendingPathComponent(MirsaPosterNormalize.rawName)
        try Data("7400".utf8).write(to: raw)
        let before = try PosterBoardStore.manifest(source)
        XCTAssertThrowsError(try MirsaPosterNormalize.normalize(source: source, packageRoot: other, identifier: 50757))
        for value in [9999, 100000] {
            XCTAssertThrowsError(try MirsaPosterNormalize.normalize(source: source, packageRoot: root, identifier: value))
        }
        // Missing required plist fields must fail before rewriting even the valid raw identifier.
        XCTAssertThrowsError(try MirsaPosterNormalize.normalize(source: source, packageRoot: root, identifier: 50757))
        XCTAssertEqual(try PosterBoardStore.manifest(source), before)
        let container = root.appendingPathComponent("Container/descriptor")
        try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
        let marker = container.appendingPathComponent("keep")
        try Data("unchanged".utf8).write(to: marker)
        XCTAssertEqual(try MirsaPosterNormalize.normalize(source: container, packageRoot: root, identifier: 50757), [])
        XCTAssertEqual(try Data(contentsOf: marker), Data("unchanged".utf8))
    }
    func testFlatDescriptorArchiveRootIsSupported() throws {
        let root = try temporaryRoot()
        XCTAssertTrue(try MirsaPosterNormalize.shouldNormalize(source: root, packageRoot: root))
    }
    func testTypedTreeTracksEmptyDirectoriesAndRejectsSpecialNodes() throws {
        let root = try temporaryRoot(), fm = FileManager.default
        try Data("fixture".utf8).write(to: root.appendingPathComponent("file"))
        let before = try MirsaPosterCopy.typedPaths(root)
        XCTAssertEqual(before, ["F:file"])
        try fm.createDirectory(at: root.appendingPathComponent("empty"), withIntermediateDirectories: false)
        XCTAssertEqual(try MirsaPosterCopy.typedPaths(root), ["D:empty", "F:file"])
        try fm.createSymbolicLink(at: root.appendingPathComponent("link"), withDestinationURL: root)
        XCTAssertThrowsError(try MirsaPosterCopy.typedPaths(root))
    }
}
