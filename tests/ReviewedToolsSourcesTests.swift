import XCTest
@testable import Mirsa

final class ReviewedToolsSourcesTests: XCTestCase {
    private var suite: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suite = "ReviewedToolsSourcesTests." + UUID().uuidString
        defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        defaults = nil
        suite = nil
        super.tearDown()
    }

    // Synthetic records exercise production controls, never fetch live content.
    private func fixture(_ id: ReviewedToolsSourceID = .kenney,
                         category: ToolsStoreCategory = .sounds,
                         page: String = "https://kenney.nl/assets/ui-audio") -> ReviewedToolsSource {
        .init(id: id, category: category, name: "Synthetic fixture", notice: .rightsPending,
              entries: [.init(id: "synthetic", title: "Synthetic entry",
                              detail: .uiAudio, officialPage: page)])
    }

    func testEverySourceStartsOptedOutAndLinksAreAbsent() {
        let preferences = ReviewedToolsPreferences(defaults: defaults)
        for id in ReviewedToolsSourceID.allCases {
            let source = fixture(id)
            XCTAssertFalse(preferences.isEnabled(id))
            XCTAssertTrue(preferences.visibleEntries(in: source).isEmpty)
            XCTAssertNil(preferences.link(for: source.entries[0], source: source))
        }
    }

    func testConsentIsSourceSpecificAndPersists() throws {
        let source = fixture()
        var preferences = ReviewedToolsPreferences(defaults: defaults)
        preferences.setEnabled(true, source: .kenney)
        XCTAssertEqual(preferences.visibleEntries(in: source).count, 1)
        XCTAssertEqual(try XCTUnwrap(preferences.link(for: source.entries[0], source: source)).scheme, "https")
        let reloaded = ReviewedToolsPreferences(defaults: defaults)
        XCTAssertTrue(reloaded.isEnabled(.kenney))
        XCTAssertFalse(reloaded.isEnabled(.chariz))
        XCTAssertEqual(reloaded.visibleEntries(in: source).count, 1)
    }

    func testHideRestoreSourcePersistsWithoutChangingConsent() {
        let source = fixture()
        var preferences = ReviewedToolsPreferences(defaults: defaults)
        preferences.setHidden(true, source: .kenney)
        preferences.setHidden(false, source: .kenney)
        XCTAssertFalse(preferences.isEnabled(.kenney))
        preferences.setEnabled(true, source: .kenney)
        preferences.setHidden(true, source: .kenney)
        XCTAssertTrue(ReviewedToolsPreferences(defaults: defaults).isHidden(.kenney))
        XCTAssertNil(preferences.link(for: source.entries[0], source: source))
        preferences.setHidden(false, source: .kenney)
        XCTAssertEqual(preferences.visibleEntries(in: source).count, 1)
        XCTAssertFalse(ReviewedToolsPreferences(defaults: defaults).isHidden(.kenney))
    }

    func testItemHideRestoreAndRevocationPersist() {
        let source = fixture()
        let item = source.entries[0]
        var preferences = ReviewedToolsPreferences(defaults: defaults)
        preferences.setEnabled(true, source: .kenney)
        preferences.setHidden(true, item: item, source: source)
        XCTAssertTrue(ReviewedToolsPreferences(defaults: defaults).isHidden(item, source: source))
        XCTAssertTrue(preferences.visibleEntries(in: source).isEmpty)
        XCTAssertNil(preferences.link(for: item, source: source))
        preferences.setEnabled(false, source: .kenney)
        preferences.setHidden(false, item: item, source: source)
        XCTAssertFalse(preferences.isEnabled(.kenney))
        XCTAssertNil(preferences.link(for: item, source: source))
        preferences.setEnabled(true, source: .kenney)
        XCTAssertEqual(preferences.visibleEntries(in: source).count, 1)
        preferences.setEnabled(false, source: .kenney)
        let reloaded = ReviewedToolsPreferences(defaults: defaults)
        XCTAssertFalse(reloaded.isEnabled(.kenney))
        XCTAssertTrue(reloaded.visibleEntries(in: source).isEmpty)
    }

    func testItemHidingIsScopedToSourceAndRejectsForeignItems() {
        let source = fixture()
        let foreign = ReviewedToolsEntry(id: "foreign", title: "Synthetic", detail: .uiAudio,
                                         officialPage: source.entries[0].officialPage)
        var preferences = ReviewedToolsPreferences(defaults: defaults)
        preferences.setHidden(true, item: foreign, source: source)
        XCTAssertFalse(preferences.isHidden(foreign, source: source))
        preferences.setHidden(true, item: source.entries[0], source: source)
        let other = fixture(.chariz)
        XCTAssertFalse(preferences.isHidden(other.entries[0], source: other))
    }

    func testExactLandingPagePolicyRejectsUnsafeAndUnreviewedLinks() {
        let bad = [
            "http://kenney.nl/assets/ui-audio",
            "file:///assets/ui-audio",
            "javascript:alert(1)",
            "sileo://source/https://kenney.nl",
            "https://kenney.nl.evil.test/assets/ui-audio",
            "https://kenney.nl@evil.test/assets/ui-audio",
            "https://evil.test@kenney.nl/assets/ui-audio",
            "https://kenney.nl:443/assets/ui-audio",
            "https://kenney.nl/assets/ui-audio?download=1",
            "https://kenney.nl/assets/ui-audio#download",
            "https://kenney.nl/assets/ui-audio/",
            "https://kenney.nl/assets/%75i-audio",
            "https://kenney.nl/assets/../assets/ui-audio",
            "https://kenney.nl/assets/payload.deb",
            "https://kenney.nl/assets/payload.dylib",
            "https://kenney.nl/depiction.html",
            "https://kenney.nl/assets/ui-audio\n",
            " https://kenney.nl/assets/ui-audio",
            "https://KENNEY.NL/assets/ui-audio"
        ]
        for raw in bad {
            XCTAssertNil(ReviewedToolsLinkPolicy.officialPage(raw, source: .kenney), raw)
        }
        XCTAssertNotNil(ReviewedToolsLinkPolicy.officialPage("https://kenney.nl/assets/ui-audio", source: .kenney))
        XCTAssertNil(ReviewedToolsLinkPolicy.officialPage("https://kenney.nl/assets/ui-audio", source: .chariz))
    }

    func testEnabledSourceDoesNotExposeUnreviewedFixtureLinks() {
        let source = fixture(page: "https://kenney.nl/assets/not-reviewed")
        var preferences = ReviewedToolsPreferences(defaults: defaults)
        preferences.setEnabled(true, source: source.id)
        XCTAssertTrue(preferences.visibleEntries(in: source).isEmpty)
        XCTAssertNil(preferences.link(for: source.entries[0], source: source))
    }

    func testOptInCannotGrantBinaryOrRepositoryCapabilities() {
        let source = fixture()
        var preferences = ReviewedToolsPreferences(defaults: defaults)
        preferences.setEnabled(true, source: source.id)
        XCTAssertFalse(source.allowsDownloads)
        XCTAssertFalse(source.allowsImport)
        XCTAssertFalse(source.allowsInstallation)
        XCTAssertFalse(source.allowsRepositoryIngestion)
    }

    func testWallpapersNeverEnterThisFeature() {
        XCTAssertTrue(ReviewedToolsDirectory.sources(for: .wallpapers).isEmpty)
        let source = fixture(category: .wallpapers)
        var preferences = ReviewedToolsPreferences(defaults: defaults)
        preferences.setEnabled(true, source: source.id)
        XCTAssertTrue(preferences.visibleEntries(in: source).isEmpty)
        XCTAssertNil(preferences.link(for: source.entries[0], source: source))
    }

    func testEveryTextKeyHasAllFiveExplicitLocales() {
        XCTAssertEqual(Set(AppLanguage.allCases.map(\.rawValue)), ["ar", "en", "de", "kmr", "ckb"])
        for key in ReviewedToolsText.Key.allCases {
            let translations = AppLanguage.allCases.map { ReviewedToolsText.text(key, language: $0) }
            XCTAssertTrue(translations.allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
            XCTAssertEqual(Set(translations).count, 5, "Missing translation for \(key)")
        }
    }
}
