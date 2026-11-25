import XCTest
@testable import Mirsa

final class GeneralArabicLocalization24Tests: XCTestCase {
    func testHookDependencyErrorsAreLocalizedAndDoNotLeakSymbolsOrPaths() {
        let errors = [
            "Missing dependency: /private/user/secrets.dylib. Mirsa never bundles CydiaSubstrate or ElleKit.",
            "Hook engine validation: Unsupported hook engine API: _EKPrivateSecret",
            "Existing CydiaSubstrate.framework conflicts with Mirsa hook engine",
            "CydiaSubstrate.framework is reserved for Mirsa hook engine",
            "Case-colliding hook engine destination",
            "Hook engine preparation: Permission denied /private/user",
            "Hook engine validation: Invalid symbol strings",
            "Hook engine resolution: No such file or directory"
        ]
        for error in errors {
            let messages = AppLanguage.allCases.map { IPAEditorService.editingError(error, language: $0) }
            XCTAssertEqual(Set(messages).count, AppLanguage.allCases.count)
            for message in messages {
                XCTAssertNotEqual(message, error)
                XCTAssertFalse(message.contains("/private"))
                XCTAssertFalse(message.contains("_EKPrivateSecret"))
                XCTAssertFalse(message.contains("never bundles"))
            }
            let arabic = IPAEditorService.editingError(error, language: .arabic)
            XCTAssertTrue(arabic.unicodeScalars.contains { (0x0600...0x06FF).contains($0.value) })
        }
        XCTAssertEqual(IPAEditorService.editingError("unrelated detail", language: .english), "unrelated detail")
    }

    func testHookNoticeDescribesLimitedOwnEngineInAllLanguages() {
        let notices = AppLanguage.allCases.map { IPAEditorService.injectionNotice(language: $0) }
        XCTAssertEqual(Set(notices).count, AppLanguage.allCases.count)
        for notice in notices {
            XCTAssertTrue(notice.contains("Objective-C"))
            XCTAssertFalse(notice.contains("no CydiaSubstrate"))
            XCTAssertFalse(notice.isEmpty)
        }
        XCTAssertTrue(IPAEditorService.injectionNotice(language: .english).contains("not inline"))
    }

    private func app() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("Fixture.app")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try put(["CFBundleDevelopmentRegion": "ja"], in: url, path: "Info.plist")
        return url
    }
    private func put(_ root: [String: Any], in app: URL, path: String) throws {
        let url = app.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try PropertyListSerialization.data(fromPropertyList: root, format: .binary, options: 0).write(to: url)
    }
    func testUnicodeSourcesAndPreservedTokens() {
        for text in ["設定", "保存", "Настройки", "开始 %@", "Öffnen", "保存 %1$@"] {
            XCTAssertTrue(ArabicIPALocalizer.worthTranslating(text), text)
        }
        for text in ["الإعدادات", "%d", "123", "https://example.com"] {
            XCTAssertFalse(ArabicIPALocalizer.worthTranslating(text), text)
        }
        XCTAssertTrue(ArabicIPALocalizer.acceptable(source: "保存 %@", translated: "حفظ %@"))
        XCTAssertFalse(ArabicIPALocalizer.acceptable(source: "保存 %@", translated: "حفظ"))
    }
    func testRegionalEnglishWinsAndOtherLanguagesFillMissingTablesAndKeys() throws {
        let url = try app()
        try put(["same": "保存", "onlyJapanese": "設定"], in: url, path: "ja.lproj/Localizable.strings")
        try put(["same": "Save"], in: url, path: "en-GB.lproj/Localizable.strings")
        try put(["other": "Настройки"], in: url, path: "ru.lproj/Extra.strings")
        let first = try ArabicIPALocalizer.scan(app: url)
        XCTAssertEqual(Set(first.items.map(\.text)), Set(["Save", "設定", "Настройки"]))
        XCTAssertEqual(first.contentHash, try ArabicIPALocalizer.scan(app: url).contentHash)
    }
    func testDevelopmentLanguageBeforeArbitraryFallbackAndEnglishBeforeDevelopment() throws {
        let url = try app()
        try put(["key": "Speichern"], in: url, path: "de.lproj/Localizable.strings")
        try put(["key": "保存"], in: url, path: "ja.lproj/Localizable.strings")
        XCTAssertEqual(try ArabicIPALocalizer.scan(app: url).items.map(\.text), ["保存"])
        try put(["key": "Save"], in: url, path: "en.lproj/Localizable.strings")
        XCTAssertEqual(try ArabicIPALocalizer.scan(app: url).items.map(\.text), ["Save"])
    }
    func testExistingArabicResourcesRemainUntouched() throws {
        let url = try app()
        try put(["key": "Save"], in: url, path: "en.lproj/Localizable.strings")
        try put(["key": "حفظ"], in: url, path: "ar.lproj/Localizable.strings")
        let resource = url.appendingPathComponent("ar.lproj/Localizable.strings")
        let original = try Data(contentsOf: resource)
        let scan = try ArabicIPALocalizer.scan(app: url)
        XCTAssertTrue(scan.hasArabic)
        XCTAssertTrue(scan.items.isEmpty)
        XCTAssertEqual(try Data(contentsOf: resource), original)
    }
    func testPluralRulesStayTogetherAndResourcesWriteWithoutChangingSources() throws {
        let url = try app()
        let plural: [String: Any] = ["count": ["NSStringLocalizedFormatKey": "%#@items@", "items":
            ["NSStringFormatSpecTypeKey": "NSStringPluralRuleType", "NSStringFormatValueTypeKey": "d",
             "one": "%d Datei", "other": "%d Dateien"]]]
        try put(plural, in: url, path: "de.lproj/Localizable.stringsdict")
        try put(["key": "保存 %@"], in: url, path: "ja.lproj/Localizable.strings")
        let original = try Data(contentsOf: url.appendingPathComponent("ja.lproj/Localizable.strings"))
        let scan = try ArabicIPALocalizer.scan(app: url)
        let translations = Dictionary(uniqueKeysWithValues: scan.items.map { item in
            (item.id, item.text == "保存 %@" ? "حفظ %@" : item.text)
        })
        XCTAssertEqual(ArabicIPALocalizer.write(scan: scan, translations: translations, app: url), .applied(scan.items.count))
        XCTAssertEqual(try Data(contentsOf: url.appendingPathComponent("ja.lproj/Localizable.strings")), original)
        let data = try Data(contentsOf: url.appendingPathComponent("ar.lproj/Localizable.strings"))
        let root = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: String])
        XCTAssertEqual(root["key"], "حفظ %@")
    }
    func testSymlinkLocalizationNeverRead() throws {
        let url = try app()
        let outside = url.deletingLastPathComponent().appendingPathComponent("outside")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: url.appendingPathComponent("en.lproj"), withDestinationURL: outside)
        XCTAssertTrue(try ArabicIPALocalizer.scan(app: url).items.isEmpty)
    }
}
