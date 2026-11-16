import XCTest
import Foundation
import Darwin
import UIKit
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
    func testPersistentEvidenceSurvivesReloadAndIsBounded() throws {
        let url = try temporaryRoot().appendingPathComponent("evidence/history.json")
        XCTAssertEqual(try MirsaWallpaperEvidence.read(at: url), [])
        try MirsaWallpaperEvidence.append("COPY VERIFIED fixture", at: url)
        try MirsaWallpaperEvidence.append("REFRESH confirmed fixture", at: url)
        XCTAssertEqual(try MirsaWallpaperEvidence.read(at: url), ["COPY VERIFIED fixture", "REFRESH confirmed fixture"])
        for i in 0...MirsaWallpaperEvidence.maxEvents {
            try MirsaWallpaperEvidence.append(String(i) + String(repeating: "x", count: 3000), at: url)
        }
        let restored = try MirsaWallpaperEvidence.read(at: url)
        XCTAssertEqual(restored.count, MirsaWallpaperEvidence.maxEvents)
        XCTAssertTrue(restored.allSatisfy { $0.count <= MirsaWallpaperEvidence.maxLine })
        XCTAssertTrue(restored.first?.hasPrefix("1x") == true)
    }
    func testPersistentEvidenceRejectsLinksAndDoesNotOverwriteCorruption() throws {
        let root = try temporaryRoot(), target = root.appendingPathComponent("keep")
        let bytes = Data("not JSON".utf8)
        try bytes.write(to: target)
        let link = root.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        XCTAssertThrowsError(try MirsaWallpaperEvidence.append("REFRESH", at: link))
        XCTAssertThrowsError(try MirsaWallpaperEvidence.append("REFRESH", at: target))
        XCTAssertEqual(try Data(contentsOf: target), bytes)
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

    private func customSnapshot(_ hashes: [String: String], paths: [String]? = nil) -> MirsaCustomWallpapers.Snapshot {
        .init(expected: hashes, paths: paths ?? hashes.keys.map { "F:" + $0 }.sorted(), device: 7, inode: 19)
    }
    func testCustomTitleSharedIdentityAndKnownUUIDAreNotProvenance() {
        let stock = customSnapshot(["versions/1/contents/7400.DYNAMIC/Wallpaper.plist": "stock",
                                    "versions/1/contents/7400.DYNAMIC/Apple.ca/main.caml": "stock"])
        XCTAssertFalse(MirsaCustomWallpapers.recognizedAnime(stock, title: "Anime Squad"))
        XCTAssertFalse(MirsaCustomWallpapers.recognizedAnime(stock, title: "My custom title"))
        for id in ["CB418767-0B46-4AB0-AF8C-0AB711DB04CB", "642869F5-1FF2-45AD-8062-EA9DD38804DC", UUID().uuidString] {
            XCTAssertNil(MirsaCustomWallpapers.completedJournal([], id: id, container: record().container,
                          relative: record().relative, snapshot: stock))
        }
    }
    func testFullImmutableAnimePayloadRequiredAndUnknownAdditionsHidden() {
        var hashes = MirsaCustomWallpapers.animeImmutable
        for path in MirsaCustomWallpapers.animeVariable { hashes[path] = "normalized fixture" }
        XCTAssertTrue(MirsaCustomWallpapers.recognizedAnime(customSnapshot(hashes), title: "Anime Squad"))
        XCTAssertFalse(MirsaCustomWallpapers.recognizedAnime(customSnapshot(hashes), title: "Stock Wallpaper"))
        for path in MirsaCustomWallpapers.animeImmutable.keys {
            var changed = hashes; changed[path] = "mutated"
            XCTAssertFalse(MirsaCustomWallpapers.recognizedAnime(customSnapshot(changed), title: "Anime Squad"), path)
            changed.removeValue(forKey: path)
            XCTAssertFalse(MirsaCustomWallpapers.recognizedAnime(customSnapshot(changed), title: "Anime Squad"), path)
        }
        var extra = hashes; extra["unrecognized/system-file"] = "preserve"
        XCTAssertFalse(MirsaCustomWallpapers.recognizedAnime(customSnapshot(extra), title: "Anime Squad"))
        let emptyDirectory = customSnapshot(hashes, paths: customSnapshot(hashes).paths + ["D:unknown-empty"])
        XCTAssertFalse(MirsaCustomWallpapers.recognizedAnime(emptyDirectory, title: "Anime Squad"))
        extra = hashes; extra["versions/1/RuntimeSnapshot-lock.png"] = "iOS generated"
        XCTAssertTrue(MirsaCustomWallpapers.recognizedAnime(customSnapshot(extra), title: "Anime Squad"))
    }
    func testCompletedJournalAdmitsUnrelatedCustomPackageButPinsEveryField() throws {
        var journal = record()
        journal.expected = ["unrelated/custom.asset": "custom hash"]
        journal.paths = ["D:unrelated", "F:unrelated/custom.asset"]
        journal.copied = true; journal.device = 7; journal.inode = 19
        let snap = customSnapshot(journal.expected, paths: journal.paths)
        func accepted(_ records: [MirsaWallpaperJournal.Record], _ snapshot: MirsaCustomWallpapers.Snapshot? = nil) -> Bool {
            MirsaCustomWallpapers.completedJournal(records, id: journal.id, container: journal.container,
                                                   relative: journal.relative, snapshot: snapshot ?? snap) != nil
        }
        XCTAssertTrue(accepted([journal]))
        XCTAssertFalse(accepted([])); XCTAssertFalse(accepted([journal, journal]))
        var wrong = journal; wrong.copied = false; XCTAssertFalse(accepted([wrong]))
        wrong = journal; wrong.device = 8; XCTAssertFalse(accepted([wrong]))
        wrong = journal; wrong.inode = 20; XCTAssertFalse(accepted([wrong]))
        wrong = journal; wrong.container = record().container; XCTAssertFalse(accepted([wrong]))
        // Content/hash is not an ownership gate: PosterBoard rewrites files after respring.
        XCTAssertTrue(accepted([journal], customSnapshot(["unrelated/custom.asset": "rewritten by iOS", "added.png": "x"])))
        XCTAssertFalse(accepted([], customSnapshot(["added.png": "x"]))) // no journal => never deletable
        wrong = journal; wrong.relative = "../" + wrong.relative; XCTAssertFalse(accepted([wrong]))
    }
    private func bespokeFixture() -> (MirsaCustomWallpapers.BespokePayload, MirsaCustomWallpapers.Snapshot, MirsaCustomWallpapers.AppleBaseline) {
        let root = "versions/1/contents/CometGarden.wallpaper/"
        let paths = [root + "Wallpaper.plist", root + "CometMotion.ca/main.caml", root + "CometMotion.ca/index.xml",
                     root + "CometMotion.ca/assetManifest.caml", root + "CometMotion.ca/assets/comet-petals.png"]
        return (.init(title: "Comet Garden", identifier: "my-comet-garden", assetNames: ["comet-petals.png"],
                      animations: ["CometMotion.ca"], wallpaperPath: root + "Wallpaper.plist"),
                customSnapshot(Dictionary(uniqueKeysWithValues: paths.map { ($0, "fixture") })),
                .init(complete: true, immutableSystemSource: true, titles: ["Earth"], identifiers: ["7400"], assetNames: ["Earth.png"]))
    }
    func testGenericUnrelatedTendiesRequiresCompleteIndependentAppleBaseline() {
        let (payload, snap, baseline) = bespokeFixture()
        XCTAssertTrue(MirsaCustomWallpapers.bespoke(payload, snapshot: snap, baseline: baseline))
        XCTAssertFalse(MirsaCustomWallpapers.bespoke(payload, snapshot: snap, baseline: nil))
        let partial = MirsaCustomWallpapers.AppleBaseline(complete: false, immutableSystemSource: true,
                            titles: baseline.titles, identifiers: baseline.identifiers, assetNames: baseline.assetNames)
        XCTAssertFalse(MirsaCustomWallpapers.bespoke(payload, snapshot: snap, baseline: partial))
        let circular = MirsaCustomWallpapers.AppleBaseline(complete: true, immutableSystemSource: false,
                            titles: baseline.titles, identifiers: baseline.identifiers, assetNames: baseline.assetNames)
        XCTAssertFalse(MirsaCustomWallpapers.bespoke(payload, snapshot: snap, baseline: circular))
        let empty = MirsaCustomWallpapers.AppleBaseline(complete: true, immutableSystemSource: true,
                            titles: [], identifiers: [], assetNames: [])
        XCTAssertFalse(MirsaCustomWallpapers.bespoke(payload, snapshot: snap, baseline: empty))
    }
    func testGenericStockTitleIdentityOrAssetCollisionEachIndependentlyRejects() {
        let (p, s, b) = bespokeFixture()
        let title = MirsaCustomWallpapers.AppleBaseline(complete: true, immutableSystemSource: true,
                           titles: [" COMET GARDEN "], identifiers: b.identifiers, assetNames: b.assetNames)
        XCTAssertFalse(MirsaCustomWallpapers.bespoke(p, snapshot: s, baseline: title))
        let identity = MirsaCustomWallpapers.AppleBaseline(complete: true, immutableSystemSource: true,
                           titles: b.titles, identifiers: [p.identifier], assetNames: b.assetNames)
        XCTAssertFalse(MirsaCustomWallpapers.bespoke(p, snapshot: s, baseline: identity))
        let assets = MirsaCustomWallpapers.AppleBaseline(complete: true, immutableSystemSource: true,
                           titles: b.titles, identifiers: b.identifiers, assetNames: ["COMET-PETALS.PNG"])
        XCTAssertFalse(MirsaCustomWallpapers.bespoke(p, snapshot: s, baseline: assets))
        var missing = s.expected
        missing.removeValue(forKey: p.wallpaperPath.replacingOccurrences(of: "Wallpaper.plist", with: "CometMotion.ca/main.caml"))
        XCTAssertFalse(MirsaCustomWallpapers.bespoke(p, snapshot: customSnapshot(missing), baseline: b))
    }
    func testBoundedSnapshotTracksBytesEmptyDirectoriesAndRootReplacement() throws {
        let root = try temporaryRoot(), fm = FileManager.default
        try fm.createDirectory(at: root.appendingPathComponent("empty"), withIntermediateDirectories: false)
        let file = root.appendingPathComponent("asset")
        try Data("first".utf8).write(to: file)
        let first = try MirsaCustomWallpapers.snapshot(root)
        XCTAssertEqual(first.paths, ["D:empty", "F:asset"])
        try Data("second".utf8).write(to: file)
        let second = try MirsaCustomWallpapers.snapshot(root)
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(first.inode, second.inode)
        try fm.removeItem(at: root.appendingPathComponent("empty"))
        XCTAssertNotEqual(try MirsaCustomWallpapers.snapshot(root), second)
        try fm.createSymbolicLink(at: root.appendingPathComponent("redirect"), withDestinationURL: file)
        XCTAssertThrowsError(try MirsaCustomWallpapers.snapshot(root))
    }
    func testSnapshotNodeDepthReadLimitsAndTraversalRejectWithoutWriting() throws {
        for path in ["", "../asset", "a//b", "/asset", "a/./b", "a/../b", "a\\b", "a\0b"] {
            XCTAssertFalse(MirsaCustomWallpapers.validRelative(path), path)
        }
        XCTAssertTrue(MirsaCustomWallpapers.validRelative("versions/1/contents/asset.png"))
        let root = try temporaryRoot(), fm = FileManager.default
        try Data([1, 2, 3]).write(to: root.appendingPathComponent("file"))
        XCTAssertThrowsError(try MirsaCustomWallpapers.read(root.appendingPathComponent("file"), limit: 2))
        for n in 0..<MirsaCustomWallpapers.maxNodes {
            try fm.createDirectory(at: root.appendingPathComponent("d" + String(n)), withIntermediateDirectories: false)
        }
        XCTAssertThrowsError(try MirsaCustomWallpapers.snapshot(root))
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("file")), Data([1, 2, 3]))
        let deep = try temporaryRoot()
        let nesting = (0..<22).map { "d" + String($0) }.joined(separator: "/")
        try fm.createDirectory(at: deep.appendingPathComponent(nesting), withIntermediateDirectories: true)
        try Data([1]).write(to: deep.appendingPathComponent("keep"))
        XCTAssertThrowsError(try MirsaCustomWallpapers.snapshot(deep))
    }

    func testAppleCatalogEnumerationRejectsMissingPartialMalformedAndLinkedPackages() throws {
        let root = try temporaryRoot(), fm = FileManager.default
        XCTAssertThrowsError(try MirsaCustomWallpapers.scanAppleCatalog(root))
        let first = root.appendingPathComponent("Stock.wallpaper")
        try plist(["name": "Earth", "identifier": 7400], at: first.appendingPathComponent("Wallpaper.plist"))
        try Data([1]).write(to: first.appendingPathComponent("Earth.png"))
        let complete = try MirsaCustomWallpapers.scanAppleCatalog(root)
        XCTAssertTrue(complete.complete)
        XCTAssertEqual(complete.identifiers, ["7400"])
        XCTAssertTrue(complete.assetNames.contains("Earth.png"))
        let missing = root.appendingPathComponent("Missing.wallpaper")
        try fm.createDirectory(at: missing, withIntermediateDirectories: false)
        XCTAssertThrowsError(try MirsaCustomWallpapers.scanAppleCatalog(root))
        try plist(["identifier": 7500], at: missing.appendingPathComponent("Wallpaper.plist"))
        XCTAssertThrowsError(try MirsaCustomWallpapers.scanAppleCatalog(root))
        try plist(["name": "Stripes", "identifier": 7500], at: missing.appendingPathComponent("Wallpaper.plist"))
        XCTAssertEqual(try MirsaCustomWallpapers.scanAppleCatalog(root).identifiers, ["7400", "7500"])
        try fm.createSymbolicLink(at: root.appendingPathComponent("alias"), withDestinationURL: first)
        XCTAssertThrowsError(try MirsaCustomWallpapers.scanAppleCatalog(root))
    }
    func testWallpaperOperationLockRejectsConcurrentWorkWithoutWaiting() {
        let finished = expectation(description: "contending operation returned")
        MirsaWallpaperJournal.lock.lock()
        defer { MirsaWallpaperJournal.lock.unlock() }
        DispatchQueue.global(qos: .userInitiated).async {
            let start = ProcessInfo.processInfo.systemUptime
            do {
                try MirsaWallpaperJournal.exclusive { XCTFail("Contending mutation ran") }
                XCTFail("Contending operation unexpectedly acquired the lock")
            } catch {
                XCTAssertTrue(error.localizedDescription.contains("already running"))
            }
            XCTAssertLessThan(ProcessInfo.processInfo.systemUptime - start, 1.0)
            finished.fulfill()
        }
        wait(for: [finished], timeout: 2)
    }

    func testQueuedInstallWaitsForReadScanAndKeepsMutationExclusion() {
        let pending = expectation(description: "install pending behind read scan")
        let finished = expectation(description: "install acquired after scan")
        MirsaWallpaperJournal.lock.lock()
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try MirsaWallpaperJournal.exclusiveWaiting(timeout: 2, onWait: { pending.fulfill() }) {
                    // A competing mutation cannot bypass the queued install.
                    let excluded = self.expectation(description: "competing mutation excluded")
                    DispatchQueue.global().async {
                        do {
                            try MirsaWallpaperJournal.exclusive { XCTFail("Overlapping mutation") }
                            XCTFail("Competing mutation unexpectedly acquired the lock")
                        } catch {
                            XCTAssertTrue(error.localizedDescription.contains("already running"))
                        }
                        excluded.fulfill()
                    }
                    self.wait(for: [excluded], timeout: 1)
                }
            } catch { XCTFail("Queued install failed: \(error)") }
            finished.fulfill()
        }
        wait(for: [pending], timeout: 1)
        // Pending is reported while the simulated list still owns the lock.
        MirsaWallpaperJournal.lock.unlock()
        wait(for: [finished], timeout: 3)
    }
    func testQueuedInstallTimeoutDoesNotRunAndLockRecovers() throws {
        let finished = expectation(description: "bounded wait ends")
        MirsaWallpaperJournal.lock.lock()
        DispatchQueue.global(qos: .userInitiated).async {
            let start = ProcessInfo.processInfo.systemUptime
            do {
                try MirsaWallpaperJournal.exclusiveWaiting(timeout: 0.05) {
                    XCTFail("Timed-out install ran")
                }
                XCTFail("Timed-out install unexpectedly acquired the lock")
            } catch {
                XCTAssertTrue(error.localizedDescription.contains("timed out"))
            }
            XCTAssertLessThan(ProcessInfo.processInfo.systemUptime - start, 1)
            finished.fulfill()
        }
        wait(for: [finished], timeout: 2)
        MirsaWallpaperJournal.lock.unlock()
        XCTAssertEqual(try MirsaWallpaperJournal.exclusiveWaiting { 3 }, 3)
        XCTAssertThrowsError(try MirsaWallpaperJournal.exclusiveWaiting { throw PosterBoardStore.failure("fixture") })
        XCTAssertEqual(try MirsaWallpaperJournal.exclusive { 4 }, 4)
    }
    func testQueuedInstallCancellationWhileScanOwnsLockNeverStartsMutation() throws {
        let pending = expectation(description: "async install waiting")
        let cancelled = expectation(description: "async wait cancelled")
        MirsaWallpaperJournal.lock.lock()
        let task = Task.detached {
            do {
                try await MirsaWallpaperJournal.queued(onWait: { pending.fulfill() }) {
                    XCTFail("Cancelled queued install mutated")
                }
                XCTFail("Cancelled queued install returned success")
            } catch { XCTAssertTrue(error is CancellationError) }
            cancelled.fulfill()
        }
        wait(for: [pending], timeout: 2)
        task.cancel()
        // Cancellation finishes even though the read scan still owns the lock.
        wait(for: [cancelled], timeout: 2)
        MirsaWallpaperJournal.lock.unlock()
        XCTAssertEqual(try MirsaWallpaperJournal.exclusive { 9 }, 9)
    }
    func testQueuedInstallChecksCancellationAfterAcquisitionAndRemainsRecursive() throws {
        var checks = 0
        XCTAssertThrowsError(try MirsaWallpaperJournal.exclusiveWaiting(isCancelled: {
            checks += 1; return checks > 1
        }) { XCTFail("Cancelled acquired install ran") }) { XCTAssertTrue($0 is CancellationError) }
        XCTAssertEqual(try MirsaWallpaperJournal.exclusiveWaiting {
            try MirsaWallpaperJournal.exclusive { 12 }
        }, 12)
    }

    func testWallpaperOperationLockRemainsRecursiveAndReleasesAfterThrow() throws {
        XCTAssertEqual(try MirsaWallpaperJournal.exclusive {
            try MirsaWallpaperJournal.exclusive { 42 }
        }, 42)
        XCTAssertThrowsError(try MirsaWallpaperJournal.exclusive {
            throw PosterBoardStore.failure("fixture")
        })
        XCTAssertEqual(try MirsaWallpaperJournal.exclusive { 7 }, 7)
    }

    func testLightweightJournalRowRequiresCompletedExactRootIdentity() throws {
        var rec = record()
        XCTAssertNil(MirsaCustomWallpapers.journalItem(rec, device: 5, inode: 12))
        rec.copied = true; rec.device = 5; rec.inode = 12
        XCTAssertNil(MirsaCustomWallpapers.journalItem(rec, device: 5, inode: 12))
        rec.paths = ["F:versions/1/contents/asset"]
        let item = try XCTUnwrap(MirsaCustomWallpapers.journalItem(rec, device: 5, inode: 12))
        XCTAssertEqual(item.expected, rec.expected)
        XCTAssertNil(MirsaCustomWallpapers.journalItem(rec, device: 6, inode: 12))
        XCTAssertNil(MirsaCustomWallpapers.journalItem(rec, device: 5, inode: 13))
        // Listing can retain a row for review while exact-delete validation
        // MUST still reject mutated/added bytes and root replacements.
        let mutated = MirsaCustomWallpapers.Snapshot(expected: rec.expected.merging(["ios-added": "unknown"]) { _, new in new },
            paths: rec.paths! + ["F:ios-added"], device: 5, inode: 12)
        XCTAssertNotNil(MirsaCustomWallpapers.completedJournal([rec], id: rec.id,
            container: rec.container, relative: rec.relative, snapshot: mutated))
        let replaced = MirsaCustomWallpapers.Snapshot(expected: rec.expected, paths: rec.paths!, device: 5, inode: 99)
        XCTAssertNil(MirsaCustomWallpapers.completedJournal([rec], id: rec.id,
            container: rec.container, relative: rec.relative, snapshot: replaced))
        var invalid = rec; invalid.relative += "/../" + rec.id
        XCTAssertNil(MirsaCustomWallpapers.journalItem(invalid, device: 5, inode: 12))
    }

    func testReconcileRecordBindingIncludesEveryField() {
        let original = record()
        XCTAssertTrue(MirsaWallpaperJournal.sameRecord(original, original))
        var changed = original; changed.title += "changed"
        XCTAssertFalse(MirsaWallpaperJournal.sameRecord(original, changed))
        changed = original; changed.container += "/changed"
        XCTAssertFalse(MirsaWallpaperJournal.sameRecord(original, changed))
        changed = original; changed.relative += "/changed"
        XCTAssertFalse(MirsaWallpaperJournal.sameRecord(original, changed))
        changed = original; changed.expected["new"] = "unknown"
        XCTAssertFalse(MirsaWallpaperJournal.sameRecord(original, changed))
        changed = original; changed.copied = true
        XCTAssertFalse(MirsaWallpaperJournal.sameRecord(original, changed))
        changed = original; changed.device = 1
        XCTAssertFalse(MirsaWallpaperJournal.sameRecord(original, changed))
        changed = original; changed.inode = 1
        XCTAssertFalse(MirsaWallpaperJournal.sameRecord(original, changed))
        changed = original; changed.paths = []
        XCTAssertFalse(MirsaWallpaperJournal.sameRecord(original, changed))
        changed = original; changed.id = UUID().uuidString
        XCTAssertFalse(MirsaWallpaperJournal.sameRecord(original, changed))
    }


    func testAbsentOnlyErrnosAndParentReplacementFailClosed() throws {
        XCTAssertTrue(try MirsaWallpaperJournal.absenceResult(-1, error: ENOENT))
        XCTAssertFalse(try MirsaWallpaperJournal.absenceResult(0, error: EACCES))
        for code in [EACCES, EPERM, ENOTDIR, EIO, ESTALE] {
            XCTAssertThrowsError(try MirsaWallpaperJournal.absenceResult(-1, error: code))
        }
        var original = stat()
        original.st_mode = S_IFDIR; original.st_dev = 1; original.st_ino = 12
        XCTAssertTrue(MirsaWallpaperJournal.sameParent(original, original))
        var replacement = original; replacement.st_ino = 13
        XCTAssertFalse(MirsaWallpaperJournal.sameParent(original, replacement))
        replacement = original; replacement.st_mode = S_IFLNK
        XCTAssertFalse(MirsaWallpaperJournal.sameParent(original, replacement))
        let root = try temporaryRoot(), fifo = root.appendingPathComponent("fifo")
        XCTAssertEqual(mkfifo(fifo.path, 0o600), 0)
        XCTAssertFalse(try MirsaWallpaperJournal.absent(fifo))
        let parentFile = root.appendingPathComponent("regular")
        try Data().write(to: parentFile)
        XCTAssertThrowsError(try MirsaWallpaperJournal.absent(parentFile.appendingPathComponent("child")))
    }
    func testArchivePreservesEvidenceAndRestoresOnTargetAppearance() throws {
        let fm = FileManager.default, root = try temporaryRoot(), rec = record()
        let source = root.appendingPathComponent(rec.id + ".json")
        let bytes = try JSONEncoder().encode(rec)
        try bytes.write(to: source)
        var checks = 0
        XCTAssertThrowsError(try MirsaWallpaperJournal.archiveLocal(rec, at: root) {
            checks += 1
            if checks == 2 { throw NSError(domain: NSPOSIXErrorDomain, code: Int(EEXIST)) }
        })
        XCTAssertEqual(checks, 2)
        XCTAssertEqual(try Data(contentsOf: source), bytes)
        XCTAssertEqual(try fm.contentsOfDirectory(atPath: root.appendingPathComponent("Archived").path).count, 0)
        try MirsaWallpaperJournal.archiveLocal(rec, at: root, revalidate: {})
        XCTAssertFalse(fm.fileExists(atPath: source.path))
        let archived = try fm.contentsOfDirectory(at: root.appendingPathComponent("Archived"), includingPropertiesForKeys: nil)
        XCTAssertEqual(archived.count, 1)
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(archived.first)), bytes)
    }
    func testArchiveFailureAndChangedJournalNeverRemoveOriginal() throws {
        let root = try temporaryRoot(), rec = record(), fm = FileManager.default
        let source = root.appendingPathComponent(rec.id + ".json")
        let bytes = try JSONEncoder().encode(rec)
        try bytes.write(to: source)
        try Data("block".utf8).write(to: root.appendingPathComponent("Archived"))
        XCTAssertThrowsError(try MirsaWallpaperJournal.archiveLocal(rec, at: root, revalidate: {}))
        XCTAssertEqual(try Data(contentsOf: source), bytes)
        try fm.removeItem(at: root.appendingPathComponent("Archived"))
        var changed = rec; changed.expected["another"] = "keep"
        try JSONEncoder().encode(changed).write(to: source)
        XCTAssertThrowsError(try MirsaWallpaperJournal.archiveLocal(rec, at: root, revalidate: {}))
        XCTAssertEqual(try JSONDecoder().decode(MirsaWallpaperJournal.Record.self, from: Data(contentsOf: source)).expected, changed.expected)
        var beforeMove = 0
        XCTAssertThrowsError(try MirsaWallpaperJournal.archiveLocal(changed, at: root) {
            beforeMove += 1; throw NSError(domain: NSPOSIXErrorDomain, code: Int(EACCES))
        })
        XCTAssertEqual(beforeMove, 1)
        XCTAssertTrue(fm.fileExists(atPath: source.path))
    }
    func testReadOnlyDiffReportsExactAddRemoveModifiedAndTypes() throws {
        let fm = FileManager.default, root = try temporaryRoot()
        try Data("original".utf8).write(to: root.appendingPathComponent("modified"))
        try Data("remove".utf8).write(to: root.appendingPathComponent("removed"))
        try fm.createDirectory(at: root.appendingPathComponent("empty"), withIntermediateDirectories: true)
        let baseline = MirsaWallpaperDiagnostics.inventory(try .init(root: root, budget: .init()))
        let expected = baseline.nodes.compactMapValues { $0.hash }
        let paths = baseline.nodes.map { ($0.value.kind == "directory" ? "D:" : "F:") + $0.key }
        try Data("changed".utf8).write(to: root.appendingPathComponent("modified"))
        try fm.removeItem(at: root.appendingPathComponent("removed"))
        try Data("new".utf8).write(to: root.appendingPathComponent("added"))
        try fm.removeItem(at: root.appendingPathComponent("empty"))
        try Data("now-file".utf8).write(to: root.appendingPathComponent("empty"))
        let actual = MirsaWallpaperDiagnostics.inventory(try .init(root: root, budget: .init()))
        XCTAssertTrue(actual.complete)
        let diff = MirsaWallpaperDiagnostics.diff(expected: expected, paths: paths, actual: actual).joined(separator: "\n")
        XCTAssertTrue(diff.contains("status=modified path=\"modified\""))
        XCTAssertTrue(diff.contains("expectedHash=" + (try XCTUnwrap(expected["modified"]))))
        XCTAssertTrue(diff.contains("actualHash=" + MirsaWallpaperDiagnostics.digest(Data("changed".utf8))))
        XCTAssertTrue(diff.contains("status=removed path=\"removed\""))
        XCTAssertTrue(diff.contains("status=added path=\"added\""))
        XCTAssertTrue(diff.contains("status=modified path=\"empty\" expectedType=directory actualType=file"))
        XCTAssertTrue(fm.fileExists(atPath: root.appendingPathComponent("added").path))
    }
    func testDiagnosticRejectsLinksHardlinksAndBudgetWithoutFalseRemoval() throws {
        let fm = FileManager.default, root = try temporaryRoot()
        let secret = root.appendingPathComponent("secret")
        try Data("private".utf8).write(to: secret)
        try fm.createSymbolicLink(at: root.appendingPathComponent("link"), withDestinationURL: secret)
        let reader = try MirsaWallpaperDiagnostics.Reader(root: root, budget: .init())
        XCTAssertThrowsError(try reader.read("link", limit: 100))
        XCTAssertThrowsError(try reader.read("../secret", limit: 100))
        try fm.linkItem(at: secret, to: root.appendingPathComponent("hard"))
        XCTAssertThrowsError(try reader.read("secret", limit: 100))
        let bounded = MirsaWallpaperDiagnostics.inventory(try .init(root: root, budget: .init(nodes: 1)))
        XCTAssertFalse(bounded.complete)
        let lines = MirsaWallpaperDiagnostics.diff(expected: ["unseen": "hash"], paths: ["F:unseen"], actual: bounded).joined(separator: "\n")
        XCTAssertTrue(lines.contains("status=unobserved path=\"unseen\""))
        XCTAssertFalse(lines.contains("status=removed"))
        let outside = try temporaryRoot()
        try fm.createSymbolicLink(at: root.appendingPathComponent("alias"), withDestinationURL: outside)
        XCTAssertThrowsError(try reader.read("alias/value", limit: 100))
        let timeout = MirsaWallpaperDiagnostics.Budget(seconds: -1)
        XCTAssertThrowsError(try timeout.check())
    }
    func testMetadataWhitelistNeverIncludesArbitraryFieldsOrContainers() {
        let result = MirsaWallpaperDiagnostics.whitelist(
            ["name": "fixture", "identifier": 7400, "password": "SECRET", "nested": ["name": "SECRET"], "nameData": Data("SECRET".utf8)],
            keys: ["name", "identifier"])
        XCTAssertEqual(result, ["name": "fixture", "identifier": "7400"])
        XCTAssertFalse(result.description.contains("SECRET"))
        XCTAssertEqual(MirsaWallpaperDiagnostics.quoted("name\nwith\tcontrol"), "\"name\\nwith\\tcontrol\"")
        for key in [MirsaWallpaperActionStrings.Key.unknownWarning, .inspect, .diagnosticDone] {
            for language in [AppLanguage.arabic, .english, .german, .kurmanji, .sorani] {
                XCTAssertFalse(MirsaWallpaperActionStrings.text(key, language: language).isEmpty)
            }
        }
    }

    func testDiagnosticDeniedReadSizeLimitAndRootReplacementArePartial() throws {
        let fm = FileManager.default, root = try temporaryRoot()
        try Data("payload".utf8).write(to: root.appendingPathComponent("file"))
        let denied = try MirsaWallpaperDiagnostics.Reader(root: root, budget: .init()) { _ in
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(EACCES))
        }
        let partial = MirsaWallpaperDiagnostics.inventory(denied)
        XCTAssertFalse(partial.complete)
        XCTAssertEqual(partial.nodes["file"]?.error, EACCES)
        let small = try MirsaWallpaperDiagnostics.Reader(root: root, budget: .init(bytes: 1))
        XCTAssertThrowsError(try small.read("file", limit: 1024))
        let original = try MirsaWallpaperDiagnostics.Reader(root: root, budget: .init())
        let moved = root.appendingPathExtension("moved")
        try fm.moveItem(at: root, to: moved)
        defer { try? fm.removeItem(at: moved) }
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        XCTAssertThrowsError(try original.verify())
        let alias = root.appendingPathComponent("alias")
        try fm.createSymbolicLink(at: alias, withDestinationURL: moved)
        XCTAssertThrowsError(try MirsaWallpaperDiagnostics.Reader(root: alias, budget: .init()))
        XCTAssertEqual(try Data(contentsOf: moved.appendingPathComponent("file")), Data("payload".utf8))
    }

    func testReadScanReuseRequiresRealReadableNodesAndDoesNotFollowLinks() throws {
        let root = try temporaryRoot(), file = root.appendingPathComponent("Wallpaper.plist")
        try Data("readable".utf8).write(to: file)
        XCTAssertTrue(PosterBoardStore.readableNode(root))
        XCTAssertTrue(PosterBoardStore.readableNode(file))
        XCTAssertFalse(PosterBoardStore.readableNode(root.appendingPathComponent("missing")))
        let alias = root.appendingPathComponent("alias")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: file)
        XCTAssertFalse(PosterBoardStore.readableNode(alias))
        let fifo = root.appendingPathComponent("fifo")
        XCTAssertEqual(mkfifo(fifo.path, 0o600), 0)
        XCTAssertFalse(PosterBoardStore.readableNode(fifo))
        let store = "Library/Application Support/PRBPosterExtensionDataStore"
        XCTAssertTrue(PosterBoardStore.readReuseAllowed(store + "/61/Extensions"))
        for path in ["/etc/passwd", "Library/../Secrets", "Library/Secrets", store + "Other", store + "/../Secrets"] {
            XCTAssertFalse(PosterBoardStore.readReuseAllowed(path))
        }
        // Measured LOCAL fixture counts only, not a device speed claim. If an
        // existing directory lease opens these children, no child token is needed.
        var requested = 0, reused = 0
        for _ in 0..<50 {
            if PosterBoardStore.readableNode(file) { reused += 1 } else { requested += 1 }
        }
        XCTAssertEqual(reused, 50)
        XCTAssertEqual(requested, 0)
    }

    func testThumbnailDecodeIsBoundedAndFallsBack() throws {
        XCTAssertNil(MirsaCustomWallpapers.thumbnailData(from: Data("not an image".utf8)))
        XCTAssertNil(MirsaCustomWallpapers.thumbnailData(from: Data(count: MirsaCustomWallpapers.thumbMaxFileBytes + 1)))
        let image = UIGraphicsImageRenderer(size: CGSize(width: 600, height: 900)).image { c in
            UIColor.red.setFill(); c.fill(CGRect(x: 0, y: 0, width: 600, height: 900)) }
        let jpeg = try XCTUnwrap(MirsaCustomWallpapers.thumbnailData(from: try XCTUnwrap(image.pngData())))
        let small = try XCTUnwrap(UIImage(data: jpeg))
        XCTAssertLessThanOrEqual(max(small.size.width * small.scale, small.size.height * small.scale), 128)
    }

    func testAppleCatalogMetadataClassification() {
        let apple: [(String, String, String)] = [("5010.Multicolored.wallpaper", "5010", "Bokeh"), ("7585.Titanium_White-D84.wallpaper", "7585", "Titanium"),
            ("7565.iOS_17-393w-852h@3x~iphone.wallpaper", "7565", "iOS 17"), ("7365.Stripe_Green.wallpaper", "7365", "Stripe"),
            ("7420.Clownfish-402w-874h@3x~iphone.wallpaper", "7420", "Clownfish")]
        for (pkg, id, fam) in apple {
            XCTAssertTrue(MirsaCustomWallpapers.isAppleCatalog(packageName: pkg, plistIdentifier: id, family: fam, userInfoIdentifier: id), pkg)
        }
    }
    func testDeviceSchemaFilesDecodeAppleNumericAndStringIdentifiers() throws {
        // Names/IDs/families transcribed from the FULL build426 and build431
        // device evidence. Both serialized types are exercised because the
        // diagnostic whitelist logs values, not their original plist types.
        let rows = [("5010.Multicolored.wallpaper", 5010, "Bokeh"),
                    ("7585.Titanium_White-D84.wallpaper", 7585, "Titanium"),
                    ("7565.iOS_17-393w-852h@3x~iphone.wallpaper", 7565, "iOS 17"),
                    ("7365.Stripe_Green.wallpaper", 7365, "Stripe"),
                    ("7420.Clownfish-402w-874h@3x~iphone.wallpaper", 7420, "Clownfish")]
        let root = try temporaryRoot()
        for format in [PropertyListSerialization.PropertyListFormat.binary, .xml] {
            for (pkg, id, family) in rows {
                for pid in [id as Any, String(id) as Any] {
                    for uid in [id as Any, String(id) as Any] {
                        let wallpaper = root.appendingPathComponent(pkg + "/Wallpaper.plist")
                        let userInfo = root.appendingPathComponent("com.apple.posterkit.provider.contents.userInfo")
                        try FileManager.default.createDirectory(at: wallpaper.deletingLastPathComponent(), withIntermediateDirectories: true)
                        try PropertyListSerialization.data(fromPropertyList: ["identifier": pid, "name": family, "family": family], format: format, options: 0).write(to: wallpaper)
                        try PropertyListSerialization.data(fromPropertyList: ["wallpaperRepresentingIdentifier": uid], format: format, options: 0).write(to: userInfo)
                        let info = try XCTUnwrap(MirsaCustomWallpapers.descriptorMetadata(packageName: pkg,
                            wallpaperData: Data(contentsOf: wallpaper), userInfoData: Data(contentsOf: userInfo)))
                        XCTAssertTrue(info.apple, pkg)
                        XCTAssertEqual(info.identifier, String(id))
                        XCTAssertEqual(info.name, family)
                    }
                }
            }
        }
    }
    func testUnrecognizedCustomWWDCIdentityStaysVisibleAndBadMetadataIsNotApple() throws {
        let root = try temporaryRoot(), wallpaper = root.appendingPathComponent("Wallpaper.plist"), ui = root.appendingPathComponent("userInfo")
        // A different custom family is not the owner-confirmed WWDC22 identity.
        // The shared 7400 package filename alone must NEVER hide it.
        try plist(["identifier": 19662, "name": "WWDC", "family": "WWDC"], at: wallpaper)
        try plist(["wallpaperRepresentingIdentifier": 19662], at: ui)
        let custom = try XCTUnwrap(MirsaCustomWallpapers.descriptorMetadata(packageName: "7400.WWDC.wallpaper",
            wallpaperData: Data(contentsOf: wallpaper), userInfoData: Data(contentsOf: ui)))
        XCTAssertFalse(custom.apple)
        XCTAssertEqual(custom.identifier, "19662")
        XCTAssertEqual(custom.name, "WWDC")
        for bad: Any in [true, false, 5010.5, ["identifier": 5010], [5010], "not-a-number"] {
            XCTAssertNil(MirsaCustomWallpapers.metadataIdentifier(bad))
        }
        try plist(["identifier": 5010, "name": "Bokeh", "family": "Bokeh"], at: wallpaper)
        for bad in [Data("corrupt".utf8), try PropertyListSerialization.data(fromPropertyList: ["wallpaperRepresentingIdentifier": 9999], format: .binary, options: 0)] {
            XCTAssertFalse(try XCTUnwrap(MirsaCustomWallpapers.descriptorMetadata(packageName: "5010.Multicolored.wallpaper",
                wallpaperData: Data(contentsOf: wallpaper), userInfoData: bad)).apple)
        }
        XCTAssertNil(MirsaCustomWallpapers.descriptorMetadata(packageName: "5010.Multicolored.wallpaper", wallpaperData: Data("corrupt".utf8), userInfoData: nil))
    }
    func testDevice433WWDC22PlistIdentityIsAppleAcrossSerializedTypes() throws {
        let pkg = "7400.WWDC_2022-390w-844h@3x~iphone.wallpaper"
        for format in [PropertyListSerialization.PropertyListFormat.binary, .xml] {
            for pid in [19662 as Any, "19662" as Any] {
                for uid in [19662 as Any, "19662" as Any] {
                    let wallpaper = try PropertyListSerialization.data(fromPropertyList:
                        ["identifier": pid, "family": "WWDC22", "name": "WWDC 2022"], format: format, options: 0)
                    let userInfo = try PropertyListSerialization.data(fromPropertyList:
                        ["wallpaperRepresentingIdentifier": uid], format: format, options: 0)
                    let info = try XCTUnwrap(MirsaCustomWallpapers.descriptorMetadata(packageName: pkg,
                        wallpaperData: wallpaper, userInfoData: userInfo))
                    XCTAssertTrue(info.apple)
                    XCTAssertEqual(info.name, "WWDC 2022")
                    XCTAssertEqual(info.identifier, "19662")
                }
            }
        }
        // The confirmed plist identity works even when filename/catalog IDs differ.
        XCTAssertTrue(MirsaCustomWallpapers.isAppleCatalog(packageName: "7777.Other.wallpaper",
            plistIdentifier: "19662", family: "WWDC22", userInfoIdentifier: "19662"))
        for (id, family, userID) in [("99999", "WWDC22", "99999"),
                                     ("19662", "Custom", "19662"),
                                     ("19662", "WWDC22", "99999"),
                                     ("7400", "Custom", "19662")] {
            XCTAssertFalse(MirsaCustomWallpapers.isAppleCatalog(packageName: pkg,
                plistIdentifier: id, family: family, userInfoIdentifier: userID))
        }
    }

    func testDiagnosticWaitsBehindListAndExcludesConcurrentMutation() {
        let pending = expectation(description: "diagnostic pending behind list")
        let finished = expectation(description: "diagnostic finished")
        MirsaWallpaperJournal.lock.lock()
        DispatchQueue.global().async {
            do {
                try MirsaWallpaperDiagnostics.withInspectionAccess(timeout: 2, onWait: { pending.fulfill() }) {
                    let excluded = self.expectation(description: "mutation excluded during diagnostic")
                    DispatchQueue.global().async {
                        do {
                            try MirsaWallpaperJournal.exclusive { XCTFail("Mutation overlapped diagnostic") }
                            XCTFail("Mutation acquired diagnostic lock")
                        } catch { XCTAssertTrue(error.localizedDescription.contains("already running")) }
                        excluded.fulfill()
                    }
                    self.wait(for: [excluded], timeout: 1)
                }
            } catch { XCTFail("Diagnostic wait failed: \(error)") }
            finished.fulfill()
        }
        wait(for: [pending], timeout: 1)
        MirsaWallpaperJournal.lock.unlock()
        wait(for: [finished], timeout: 3)
    }

    func testDiagnosticWaitCancellationTimeoutAndErrorRelease() throws {
        let finished = expectation(description: "diagnostic timeout and cancellation")
        MirsaWallpaperJournal.lock.lock()
        DispatchQueue.global().async {
            XCTAssertThrowsError(try MirsaWallpaperDiagnostics.withInspectionAccess(timeout: 0.05) {
                XCTFail("Timed out diagnostic opened lease")
            })
            var waiting = false
            XCTAssertThrowsError(try MirsaWallpaperDiagnostics.withInspectionAccess(timeout: 1,
                isCancelled: { waiting }, onWait: { waiting = true }) {
                XCTFail("Cancelled diagnostic opened lease")
            }) { XCTAssertTrue($0 is CancellationError) }
            finished.fulfill()
        }
        wait(for: [finished], timeout: 2)
        MirsaWallpaperJournal.lock.unlock()
        XCTAssertThrowsError(try MirsaWallpaperDiagnostics.withInspectionAccess {
            throw PosterBoardStore.failure("diagnostic fixture failure")
        })
        XCTAssertEqual(try MirsaWallpaperJournal.exclusive { 7 }, 7)
        XCTAssertEqual(try MirsaWallpaperDiagnostics.withInspectionAccess {
            try MirsaWallpaperJournal.exclusive { 8 }
        }, 8)
    }

    func testCustomEnvelopeNotMisclassifiedAsApple() {
        XCTAssertFalse(MirsaCustomWallpapers.isAppleCatalog(packageName: "Anime.wallpaper", plistIdentifier: "5010", family: "Bokeh"))
        XCTAssertFalse(MirsaCustomWallpapers.isAppleCatalog(packageName: "5010.Mine.wallpaper", plistIdentifier: "9999", family: "Bokeh"))
        XCTAssertFalse(MirsaCustomWallpapers.isAppleCatalog(packageName: "5010.Mine.wallpaper", plistIdentifier: "5010", family: nil))
        XCTAssertFalse(MirsaCustomWallpapers.isAppleCatalog(packageName: "5010.Mine.wallpaper", plistIdentifier: "5010", family: "X", userInfoIdentifier: "1"))
        XCTAssertFalse(MirsaCustomWallpapers.isAppleCatalog(packageName: "5010.Mine", plistIdentifier: "5010", family: "X"))
    }
    func testFallbackNameLocalized() {
        XCTAssertEqual(MirsaWallpaperActionStrings.fallbackName(1, language: .english), "Wallpaper 1")
        XCTAssertEqual(MirsaWallpaperActionStrings.fallbackName(1, language: .arabic), "خلفية 1")
        XCTAssertTrue(MirsaWallpaperActionStrings.fallbackName(2, language: .german).hasPrefix("Hintergrund"))
        XCTAssertFalse(MirsaWallpaperActionStrings.fallbackName(2, language: .kurmanji).isEmpty)
        XCTAssertFalse(MirsaWallpaperActionStrings.fallbackName(2, language: .sorani).isEmpty)
    }
}
