import XCTest
@testable import Mirsa

final class WallpaperEffectCatalogTests: XCTestCase {
    private let languages: [AppLanguage] = [.english, .arabic, .german, .kurmanji, .sorani]

    func testFriendlyCatalogueHasOnlyUsableUniqueSelections() {
        let entries = WallpaperEffectCatalog.entries
        XCTAssertFalse(entries.isEmpty)
        XCTAssertEqual(Set(entries.map(\.id)).count, entries.count)
        XCTAssertEqual(WallpaperEffectCatalog.Group.allCases.flatMap(\.entries).map(\.id), entries.map(\.id))
        for entry in entries {
            XCTAssertTrue(entry.mechanism.isSupported)
            XCTAssertEqual(entry.id, entry.mechanism.rawValue)
            XCTAssertEqual(WallpaperMechanism(rawValue: entry.id), entry.mechanism)
            XCTAssertFalse(["class:", "type:", "renderMode:"].contains { entry.id.hasPrefix($0) })
        }
        // The underlying catalogue remains complete for existing projects and export tests.
        XCTAssertEqual(WallpaperMechanism.allCases.count, 70)
        for mechanism in WallpaperMechanism.allCases where !mechanism.isSupported {
            XCTAssertNil(WallpaperEffectCatalog.entry(for: mechanism))
        }
    }

    func testEveryVisibleLabelAndGroupHasFiveFriendlyTranslations() {
        let internalTerms = ["CAFilter", "CALayer", "CABackdrop", "CAEmitter", "transform.",
                             "position.", "unavailable", "additive", "unordered", "Saturate 1", "Blur 1"]
        for language in languages {
            var labels: [String] = []
            for entry in WallpaperEffectCatalog.entries {
                let label = entry.title(language: language)
                XCTAssertFalse(label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                XCTAssertNotEqual(label, entry.mechanism.title)
                labels.append(label)
            }
            XCTAssertEqual(Set(labels).count, labels.count, "Duplicate visible effect names")
            for group in WallpaperEffectCatalog.Group.allCases {
                XCTAssertFalse(group.entries.isEmpty)
                labels.append(group.title(language: language))
                labels.append(group.subtitle(language: language))
            }
            labels.append(WallpaperEffectCatalog.savedEffectTitle(language: language))
            for label in labels {
                for term in internalTerms { XCTAssertFalse(label.contains(term), label) }
            }
        }
        for entry in WallpaperEffectCatalog.entries {
            XCTAssertNotEqual(entry.title(language: .arabic), entry.title(language: .english))
            XCTAssertNotEqual(entry.title(language: .kurmanji), entry.title(language: .english))
            XCTAssertNotEqual(entry.title(language: .sorani), entry.title(language: .english))
        }
    }

    func testOwnerExamplesUsePlainArabic() throws {
        let examples: [(WallpaperMechanism, String)] = [
            (.filterGaussianBlur1, "تغبيش"), (.filterSaturate1, "تشبع ألوان"),
            (.filterSepia1, "لون قديم"), (.propertyposition, "تحريك"),
            (.propertytransformrotationz, "تدوير"), (.propertytransformscale, "تكبير")
        ]
        for (mechanism, title) in examples {
            XCTAssertEqual(try XCTUnwrap(WallpaperEffectCatalog.entry(for: mechanism)).title(language: .arabic), title)
        }
    }

    func testHiddenLegacyRecipesRemainDecodableWithoutBecomingPickerChoices() {
        for mechanism in [WallpaperMechanism.classCABackdropLayer, .classCAEmitterCell,
                          .classscriptObject, .typeCAFilter, .renderModeadditive, .renderModeunordered,
                          .propertyautoreverses, .propertysublayers] {
            XCTAssertNil(WallpaperEffectCatalog.entry(for: mechanism))
            XCTAssertEqual(WallpaperMechanism(rawValue: mechanism.rawValue), mechanism)
        }
        XCTAssertEqual(WallpaperEffectCatalog.savedEffectTitle(language: .arabic), "التأثير المحفوظ")
    }
}
