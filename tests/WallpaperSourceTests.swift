import XCTest
@testable import Mirsa

/// These exercise the production Swift Codable model and its native validator,
/// not a parallel regular expression or a reimplementation of feed parsing.
final class WallpaperSourceTests: XCTestCase {
    private func entry() -> [String: Any] {
        [
            "id": "mirsa-original-01", "name": "Original test wallpaper", "author": "Mirsa",
            "previewImage": "https://example.com/preview.png",
            "previewVideo": "https://example.com/preview.mp4",
            "url": "https://example.com/original.tendies", "size": 1024,
            "category": "Original"
        ]
    }

    private func decode(_ entries: [[String: Any]], name: String = "Mirsa Wallpapers",
                        author: String = "Mirsa") throws -> WallpaperSourceFeed {
        let object: [String: Any] = ["name": name, "author": author, "wallpapers": entries]
        return try JSONDecoder().decode(WallpaperSourceFeed.self,
            from: JSONSerialization.data(withJSONObject: object)).validated()
    }

    func testNativeDecoderRoundTripWithOptionalVideo() throws {
        let feed = try decode([entry()])
        XCTAssertEqual(feed.name, "Mirsa Wallpapers")
        XCTAssertEqual(feed.wallpapers.first?.size, 1024)
        XCTAssertEqual(feed.wallpapers.first?.previewVideo?.pathExtension, "mp4")
        XCTAssertEqual(try JSONDecoder().decode(WallpaperSourceFeed.self,
            from: JSONEncoder().encode(feed)).validated(), feed)
        var still = entry()
        still.removeValue(forKey: "previewVideo")
        XCTAssertNil(try decode([still]).wallpapers.first?.previewVideo)
        still["previewVideo"] = NSNull()
        XCTAssertNil(try decode([still]).wallpapers.first?.previewVideo)
    }

    func testEmptyOfficialCatalogIsValid() throws {
        XCTAssertTrue(try decode([]).wallpapers.isEmpty)
    }

    func testNativeDecoderRejectsAppsFeedMalformedJSONAndMissingFields() {
        for json in [
            #"{"name":"Apps","apps":[]}"#,
            #"{"name":"Wallpapers","author":"Mirsa","wallpapers":"wrong-type"}"#,
            #"{"name":"Wallpapers","author":"Mirsa","wallpapers":[{}]}"#,
            "{"
        ] {
            XCTAssertThrowsError(try JSONDecoder().decode(WallpaperSourceFeed.self,
                from: Data(json.utf8)).validated(), json)
        }
        for key in entry().keys {
            if key == "previewVideo" { continue }
            var candidate = entry()
            candidate.removeValue(forKey: key)
            XCTAssertThrowsError(try decode([candidate]), key)
        }
    }

    func testEveryRemoteAssetRequiresHTTPSWithoutCredentials() {
        let invalid = [
            "http://example.com/file.tendies", "file:///tmp/file.tendies",
            "data:text/plain,test", "ftp://example.com/file.tendies",
            "https://user:password@example.com/file.tendies",
            "https://user@example.com/file.tendies", "/relative/file.tendies"
        ]
        for key in ["url", "previewImage", "previewVideo"] {
            for value in invalid {
                var candidate = entry()
                candidate[key] = value
                XCTAssertThrowsError(try decode([candidate]), key + " " + value)
            }
        }
        XCTAssertTrue(WallpaperSourceFeed.allowed(URL(string: "https://example.com/feed.json")!))
        XCTAssertFalse(WallpaperSourceFeed.allowed(URL(string: "http://example.com/feed.json")!))
    }

    func testOnlyTendiesDownloadsAccepted() throws {
        for path in ["file.ipa", "file.zip", "file.tendies.exe", "file", "file.tendies/child"] {
            var candidate = entry()
            candidate["url"] = "https://example.com/" + path
            XCTAssertThrowsError(try decode([candidate]), path)
        }
        var candidate = entry()
        candidate["url"] = "https://example.com/ORIGINAL.TENDIES?download=1"
        XCTAssertEqual(try decode([candidate]).wallpapers.count, 1)
    }

    func testSizeRequiresPositiveBoundedIntegralByteCount() throws {
        for size in [Int64(-1), 0, 536_870_913, Int64.max] {
            var candidate = entry()
            candidate["size"] = size
            XCTAssertThrowsError(try decode([candidate]), String(size))
        }
        for size: Any in ["1024", 1.5, NSNull(), true] {
            var candidate = entry()
            candidate["size"] = size
            XCTAssertThrowsError(try decode([candidate]))
        }
        for size in [1, 536_870_912] {
            var candidate = entry()
            candidate["size"] = size
            XCTAssertEqual(try decode([candidate]).wallpapers.first?.size, Int64(size))
        }
    }

    func testDuplicateIdentifiersAndMetadataLimits() throws {
        XCTAssertThrowsError(try decode([entry(), entry()]))
        XCTAssertThrowsError(try decode([], name: " \n\t "))
        XCTAssertThrowsError(try decode([], name: String(repeating: "n", count: 161)))
        XCTAssertThrowsError(try decode([], author: String(repeating: "a", count: 161)))
        for key in ["id", "name"] {
            var candidate = entry()
            candidate[key] = ""
            XCTAssertThrowsError(try decode([candidate]), key)
        }
        for (key, count) in [("id", 161), ("name", 161), ("author", 161), ("category", 101)] {
            var candidate = entry()
            candidate[key] = String(repeating: "x", count: count)
            XCTAssertThrowsError(try decode([candidate]), key)
        }
        var boundary = entry()
        for key in ["id", "name", "author"] { boundary[key] = String(repeating: "x", count: 160) }
        boundary["category"] = String(repeating: "x", count: 100)
        XCTAssertEqual(try decode([boundary]).wallpapers.count, 1)
    }

    func testCatalogEntryCountLimit() throws {
        let entries = (0..<1001).map { index -> [String: Any] in
            var item = entry()
            item["id"] = "wallpaper-\(index)"
            return item
        }
        XCTAssertEqual(try decode(Array(entries.prefix(1000))).wallpapers.count, 1000)
        XCTAssertThrowsError(try decode(entries))
    }

    func testEveryUIStringIsLocalizedInAllFiveActualAppLanguages() {
        XCTAssertEqual(Set(AppLanguage.allCases.map(\.rawValue)), Set(["ar", "en", "de", "kmr", "ckb"]))
        let keys: [WallpaperSourceText.Key] = [.title, .add, .empty, .failed, .install, .preview, .remove, .url, .working]
        for key in keys {
            let translations = AppLanguage.allCases.map { WallpaperSourceText.text(key, language: $0) }
            XCTAssertTrue(translations.allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
            XCTAssertEqual(Set(translations).count, 5, "No English fallback for \(key)")
        }
        XCTAssertEqual(WallpaperSourceText.text(.title, language: .english), "Wallpaper sources")
        XCTAssertEqual(WallpaperSourceText.text(.title, language: .arabic), "مصادر الخلفيات")
        XCTAssertEqual(WallpaperSourceText.text(.title, language: .german), "Hintergrundquellen")
        XCTAssertEqual(WallpaperSourceText.text(.title, language: .kurmanji), "Çavkaniyên wêneyan")
        XCTAssertEqual(WallpaperSourceText.text(.title, language: .sorani), "سەرچاوەی وێنەکان")
    }

    func testOfficialStagedJSONUsesProductionNativeDecoder() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("docs/wallpaper-source/wallpapers.json"))
        let feed = try JSONDecoder().decode(WallpaperSourceFeed.self, from: data).validated()
        XCTAssertEqual(feed.name, "Mirsa Wallpapers")
        XCTAssertEqual(feed.author, "Mirsa")
        XCTAssertTrue(feed.wallpapers.isEmpty, "Do not publish third-party artwork through this staging fixture")
    }

    func testCatalogCallbackOnlyImportsPreselectsAndReturnsToExistingReadyScreen() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent("ios-app/Apps/ToolsStoreView.swift"), encoding: .utf8)
        let start = try XCTUnwrap(source.range(of: "WallpaperSourcesView(busy:"))
        let end = try XCTUnwrap(source.range(of: "if showSaved {",
                                           range: start.upperBound..<source.endIndex))
        let callback = String(source[start.lowerBound..<end.lowerBound])
        // Store hiding changed the following sibling, not this import callback.
        // Keep the same required/forbidden contract and strengthen operation ordering.
        XCTAssertEqual(source.components(separatedBy: "WallpaperSourcesView(busy:").count - 1, 1)
        let busyGuard = try XCTUnwrap(callback.range(of: "guard !wallpaperSourceBusy else { return }"))
        let importCall = try XCTUnwrap(callback.range(of: "vm.importTendieFiles(urls: [archive])"))
        let nonemptyGuard = try XCTUnwrap(callback.range(of: "guard !ids.isEmpty else { return }"))
        let selection = try XCTUnwrap(callback.range(of: "ids.contains(vm.tendieItems[index].id)"))
        let notification = try XCTUnwrap(callback.range(of: "mirsa.wallpaper.imported.open"))
        XCTAssertLessThan(busyGuard.lowerBound, importCall.lowerBound)
        XCTAssertLessThan(importCall.lowerBound, nonemptyGuard.lowerBound)
        XCTAssertLessThan(nonemptyGuard.lowerBound, selection.lowerBound)
        XCTAssertLessThan(selection.lowerBound, notification.lowerBound)
        XCTAssertTrue(source.contains("model.category == .wallpapers && !showSaved"))
        let tendies = try String(contentsOf: root.appendingPathComponent("ios-app/TendiesView.swift"), encoding: .utf8)
        XCTAssertFalse(tendies.contains("WallpaperSourcesView("))
        for required in ["vm.importTendieFiles(urls: [archive])", "ids.contains(vm.tendieItems[index].id)",
                         "mirsa.wallpaper.imported.open"] {
            XCTAssertTrue(callback.contains(required), required)
        }
        for forbidden in ["installSelectedNow(", "flashTendies(", "TendiesEngine.", "PosterBoard",
                          "respring(", "WallpapersEngine"] {
            XCTAssertFalse(callback.contains(forbidden), "Catalog must not mutate system state: " + forbidden)
        }
        for file in ["ios-app/WallpaperSource.swift", "ios-app/WallpaperSourceView.swift"] {
            let catalog = try String(contentsOf: root.appendingPathComponent(file), encoding: .utf8)
            for forbidden in ["installSelectedNow(", "flashTendies(", "TendiesEngine.", "PosterBoardStore.",
                              "respring(", "WallpapersEngine"] {
                XCTAssertFalse(catalog.contains(forbidden), file + " " + forbidden)
            }
        }
    }

    #if DEBUG
    func testOriginalGridFixtureUsesValidNativeFeedAndIsExplicitlyHarnessGated() throws {
        let feed = try WallpaperSourceFixture.feed.validated()
        XCTAssertEqual(feed.wallpapers.count, 6)
        XCTAssertEqual(feed.wallpapers.first?.name, "Solar arc")
        XCTAssertEqual(Set(feed.wallpapers.map(\.id)).count, 6)
        XCTAssertFalse(WallpaperSourceFixture.active, "Unit launch must never silently enable UI fixture")
        XCTAssertNil(WallpaperSourceFixture.image(for: feed.wallpapers[0]))
    }
    #endif

    @MainActor
    func testOfficialSourceIsPresentDeduplicatedAndCannotBeRemoved() throws {
        let suite = "WallpaperSourceTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let official = WallpaperSourceStore.official
        let custom = URL(string: "https://example.com/wallpapers.json")!
        defaults.set([official.absoluteString, custom.absoluteString, custom.absoluteString,
                      "http://insecure.example.com/feed.json"], forKey: "mirsa.wallpaper.sources.v1")
        let store = WallpaperSourceStore(defaults: defaults)
        XCTAssertEqual(store.urls, [official, custom, CAPlaygroundSource.manifest])
        store.remove(official)
        XCTAssertEqual(store.urls, [official, custom, CAPlaygroundSource.manifest])
        store.remove(custom)
        XCTAssertEqual(store.urls, [official, CAPlaygroundSource.manifest])
        XCTAssertEqual(WallpaperSourceStore(defaults: defaults).urls, [official, CAPlaygroundSource.manifest])
        XCTAssertEqual(official.absoluteString, "https://mirsa-source.mooo.com/wallpapers.json")
    }
}

extension WallpaperSourceTests {
    @MainActor
    func testCommunityDefaultMigratesOnceAndExplicitRemovalSurvivesRelaunch() throws {
        let suite = "WallpaperSourceMigration." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let custom = URL(string: "https://example.com/custom.json")!
        let official = WallpaperSourceStore.official
        let community = CAPlaygroundSource.manifest
        defaults.set([custom.absoluteString, community.absoluteString, community.absoluteString],
                     forKey: "mirsa.wallpaper.sources.v1")
        let migrated = WallpaperSourceStore(defaults: defaults)
        XCTAssertEqual(migrated.urls, [official, custom, community])
        XCTAssertTrue(defaults.bool(forKey: "mirsa.wallpaper.sources.caplayground.default.v1"))
        XCTAssertEqual(defaults.stringArray(forKey: "mirsa.wallpaper.sources.v1"),
                       [official, custom, community].map(\.absoluteString))
        migrated.remove(community)
        XCTAssertEqual(WallpaperSourceStore(defaults: defaults).urls, [official, custom])
        migrated.remove(custom)
        XCTAssertEqual(WallpaperSourceStore(defaults: defaults).urls, [official])
    }

    @MainActor
    func testLegacyOfficialOnlyStoreReceivesCommunityDefault() throws {
        let suite = "WallpaperSourceLegacy." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set([WallpaperSourceStore.official.absoluteString], forKey: "mirsa.wallpaper.sources.v1")
        let store = WallpaperSourceStore(defaults: defaults)
        XCTAssertEqual(store.urls, [WallpaperSourceStore.official, CAPlaygroundSource.manifest])
        XCTAssertEqual(WallpaperSourceStore(defaults: defaults).urls, store.urls)
    }
}

/// Intentional network gate, selected by the private wallpaper-load verification workflow.
/// Uses the shipping bounded transport and decoder, never a fixture or duplicate parser.
final class WallpaperSourceLiveTests: XCTestCase {
    func testBothApprovedLiveSourcesUseProductionTransportAndDecoder() async throws {
        let official = try await WallpaperSourceNetwork.feed(WallpaperSourceStore.official)
        XCTAssertEqual(official.name, "Mirsa Wallpapers")
        XCTAssertEqual(official.author, "Mirsa")
        XCTAssertTrue(official.wallpapers.isEmpty, "Official catalog is intentionally empty, community is separate")
        let community = try await WallpaperSourceNetwork.feed(CAPlaygroundSource.manifest)
        XCTAssertEqual(community.name, "CAPlayground")
        XCTAssertFalse(community.wallpapers.isEmpty)
        XCTAssertEqual(Set(community.wallpapers.map(\.id)).count, community.wallpapers.count)
        XCTAssertTrue(community.wallpapers.allSatisfy { $0.category == "CAPlayground" })
        let attachment = XCTAttachment(string: "Production HTTPS decode succeeded. Official entries \(official.wallpapers.count), CAPlayground entries \(community.wallpapers.count).")
        attachment.name = "Live source production decoder proof"
        attachment.lifetime = .keepAlways
        add(attachment)
        print("MIRSA_LIVE_SOURCE_PROOF official=\(official.wallpapers.count) caplayground=\(community.wallpapers.count)")
    }
}
