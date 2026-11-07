import XCTest
@testable import Mirsa
final class StructuredPlistTests: XCTestCase {
    func testAllTypesBothFormatsAndMutations() throws {
        for format: PropertyListSerialization.PropertyListFormat in [.xml, .binary] {
            let values: [String: Any] = [
                "text": "عربي < &", "integer": NSNumber(value: Int64.max),
                "real": 1.25, "flag": true, "data": Data([0, 1, 255]),
                "date": Date(timeIntervalSince1970: 1000),
                "array": ["one", ["nested": "value"]] as [Any], "dict": ["key": "value"]
            ]
            var doc = try PlistDocument(data: PropertyListSerialization.data(fromPropertyList: values, format: format, options: 0))
            try doc.add(at: [.key("dict")], key: "new", type: "string", text: "kept")
            try doc.rename(at: [.key("dict"), .key("new")], to: "renamed")
            XCTAssertThrowsError(try doc.rename(at: [.key("dict"), .key("renamed")], to: "key"))
            try doc.remove(at: [.key("array"), .index(0)])
            let reread = try PlistDocument(data: doc.serialized())
            XCTAssertEqual(reread.format, format)
            XCTAssertEqual((reread.value(at: [.key("integer")]) as? NSNumber)?.int64Value, Int64.max)
            XCTAssertEqual(reread.value(at: [.key("data")]) as? Data, Data([0, 1, 255]))
            XCTAssertEqual(reread.value(at: [.key("date")]) as? Date, values["date"] as? Date)
            XCTAssertEqual(reread.value(at: [.key("dict"), .key("renamed")]) as? String, "kept")
            XCTAssertEqual(reread.value(at: [.key("array"), .index(0), .key("nested")]) as? String, "value")
            let raw = try PlistDocument(xmlText: reread.xmlText(), preserving: format)
            XCTAssertEqual(try raw.serialized().prefix(6), try reread.serialized().prefix(6))
        }
    }
    func testInvalidRawDuplicateEntityAndFiniteNumbers() throws {
        XCTAssertThrowsError(try PlistDocument(xmlText: "<plist><dict><key>a</key><string>one</string><key>a</key><string>two</string></dict></plist>", preserving: .binary))
        XCTAssertThrowsError(try PlistDocument(xmlText: "<!DOCTYPE plist [<!ENTITY x SYSTEM 'https://example.com'>]><plist><string>&x;</string></plist>", preserving: .xml))
        XCTAssertThrowsError(try PlistDocument.parse("nan", as: "real"))
        XCTAssertThrowsError(try PlistDocument.parse("1.5", as: "integer"))
    }
    func testInvalidSaveKeepsOriginalBytesAndOverlay() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let bundle = root.appendingPathComponent("Test.app")
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
        let bytes = try PropertyListSerialization.data(fromPropertyList: ["key": "original"], format: .binary, options: 0)
        let file = bundle.appendingPathComponent("settings.plist")
        try bytes.write(to: file)
        let manager = try BundleFileManager(root: bundle, stagingDirectory: root.appendingPathComponent("staged"))
        XCTAssertThrowsError(try manager.stageWrite("settings.plist", data: Data("invalid XML".utf8)))
        XCTAssertTrue(manager.overlay.isEmpty)
        XCTAssertEqual(try Data(contentsOf: file), bytes)
    }
}
