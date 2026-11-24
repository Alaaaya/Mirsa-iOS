import XCTest
@testable import Mirsa

final class ArabicLocalize31Tests: XCTestCase {
    func testTokensMustMatch() {
        XCTAssertTrue(ArabicIPALocalizer.acceptable(source: "Hello %@, %d items", translated: "مرحبا %@، %d عناصر"))
        XCTAssertFalse(ArabicIPALocalizer.acceptable(source: "Hello %@", translated: "مرحبا"))
        XCTAssertFalse(ArabicIPALocalizer.acceptable(source: "Hi", translated: "  "))
    }
    func testWorthTranslating() {
        XCTAssertTrue(ArabicIPALocalizer.worthTranslating("Settings"))
        XCTAssertFalse(ArabicIPALocalizer.worthTranslating("https://example.com"))
        XCTAssertFalse(ArabicIPALocalizer.worthTranslating("%d"))
    }
    func testScanDetectsArabicAndStrings() throws {
        let fm = FileManager.default
        let app = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("T.app")
        let en = app.appendingPathComponent("en.lproj")
        try fm.createDirectory(at: en, withIntermediateDirectories: true)
        try "\"hello\" = \"Hello %@\";\n\"CFBundleName\" = \"T\";".write(to: en.appendingPathComponent("Localizable.strings"), atomically: true, encoding: .utf8)
        let s = try ArabicIPALocalizer.scan(app: app)
        XCTAssertFalse(s.hasArabic); XCTAssertEqual(s.items.count, 1)
        try fm.createDirectory(at: app.appendingPathComponent("ar.lproj"), withIntermediateDirectories: true)
        XCTAssertTrue(try ArabicIPALocalizer.scan(app: app).hasArabic)
    }
}
