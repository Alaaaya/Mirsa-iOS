import XCTest
import CryptoKit
@testable import Mirsa

final class RuntimeTranslationScanner25Tests: XCTestCase {
    private func put(_ value: UInt64, at offset: Int, bytes: Int = 4, little: Bool = true, in data: inout Data) {
        for i in 0..<bytes {
            data[offset + i] = UInt8(truncatingIfNeeded: value >> ((little ? i : bytes - i - 1) * 8))
        }
    }
    private func binary(_ text: String = "保存 %@", utf16: Bool = false, encrypted: Bool = false) -> Data {
        let payload = text.data(using: utf16 ? .utf16LittleEndian : .utf8)! + Data(repeating: 0, count: utf16 ? 2 : 1)
        let commands = 152 + 24, offset = 32 + commands
        var data = Data(repeating: 0, count: offset)
        put(0xFEEDFACF, at: 0, in: &data)
        put(0x0100000C, at: 4, in: &data)
        put(2, at: 16, in: &data)
        put(UInt64(commands), at: 20, in: &data)
        put(0x19, at: 32, in: &data)
        put(152, at: 36, in: &data)
        put(1, at: 96, in: &data)
        let segmentName = Data("__TEXT".utf8)
        data.replaceSubrange(40..<(40 + segmentName.count), with: segmentName)
        let section = 104
        let name = Data((utf16 ? "__ustring" : "__cstring").utf8)
        data.replaceSubrange(section..<(section + name.count), with: name)
        data.replaceSubrange((section + 16)..<(section + 16 + segmentName.count), with: segmentName)
        put(UInt64(payload.count), at: section + 40, bytes: 8, in: &data)
        put(UInt64(offset), at: section + 48, in: &data)
        put(0x2C, at: 184, in: &data)
        put(24, at: 188, in: &data)
        put(encrypted ? 1 : 0, at: 200, in: &data)
        data.append(payload)
        return data
    }
    private func fat(_ slices: [Data], little: Bool = false, wide: Bool = false) -> Data {
        let stride = wide ? 32 : 20
        var data = Data(repeating: 0, count: 8 + slices.count * stride)
        put(wide ? 0xCAFEBABF : 0xCAFEBABE, at: 0, little: little, in: &data)
        put(UInt64(slices.count), at: 4, little: little, in: &data)
        for (i, slice) in slices.enumerated() {
            let p = 8 + i * stride
            put(0x0100000C, at: p, little: little, in: &data)
            put(UInt64(data.count), at: p + 8, bytes: wide ? 8 : 4, little: little, in: &data)
            put(UInt64(slice.count), at: p + (wide ? 16 : 12), bytes: wide ? 8 : 4, little: little, in: &data)
            data.append(slice)
        }
        return data
    }
    private func app(_ data: Data) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("Fixture.app")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try info(at: url)
        try data.write(to: url.appendingPathComponent("Main"))
        return url
    }
    private func info(at url: URL) throws {
        try PropertyListSerialization.data(fromPropertyList: ["CFBundleExecutable": "Main"], format: .binary, options: 0)
            .write(to: url.appendingPathComponent("Info.plist"))
    }
    private func assertFailure(_ data: Data, _ expected: RuntimeTranslationScanError, file: StaticString = #filePath, line: UInt = #line) throws {
        let url = try app(data)
        XCTAssertThrowsError(try RuntimeTranslationScanner.scan(app: url), file: file, line: line) {
            XCTAssertEqual($0 as? RuntimeTranslationScanError, expected, file: file, line: line)
        }
    }
    func testUTF8UTF16FrameworksAndDeterministicSHAIDs() throws {
        let url = try app(binary())
        let framework = url.appendingPathComponent("Frameworks/Example.framework")
        try FileManager.default.createDirectory(at: framework, withIntermediateDirectories: true)
        try info(at: framework)
        try binary("说明 %1$@", utf16: true).write(to: framework.appendingPathComponent("Main"))
        let a = try RuntimeTranslationScanner.scan(app: url)
        let b = try RuntimeTranslationScanner.scan(app: url)
        XCTAssertEqual(a.items, b.items)
        XCTAssertEqual(a.revision, b.revision)
        XCTAssertEqual(Set(a.items.map(\.text)), Set(["保存 %@", "说明 %1$@"]))
        for item in a.items {
            let expected = SHA256.hash(data: Data(item.text.utf8)).map { String(format: "%02x", $0) }.joined()
            XCTAssertEqual(item.id, expected)
        }
        try binary("构建").write(to: framework.appendingPathComponent("Main"))
        XCTAssertNotEqual(a.revision, try RuntimeTranslationScanner.scan(app: url).revision)
    }
    func testFatBothEndiannessesAndWidths() throws {
        for little in [true, false] {
            for wide in [true, false] {
                let url = try app(fat([binary(), binary("設定", utf16: true)], little: little, wide: wide))
                XCTAssertEqual(Set(try RuntimeTranslationScanner.scan(app: url).items.map(\.text)), Set(["保存 %@", "設定"]))
            }
        }
    }
    func testEncryptedAnySliceAndFrameworkRejected() throws {
        try assertFailure(binary(encrypted: true), .encrypted)
        try assertFailure(fat([binary(), binary(encrypted: true)]), .encrypted)
        try assertFailure(fat([binary(encrypted: true), binary()], little: true, wide: true), .encrypted)
        let url = try app(binary())
        let framework = url.appendingPathComponent("Frameworks/Secret.framework")
        try FileManager.default.createDirectory(at: framework, withIntermediateDirectories: true)
        try info(at: framework)
        try binary(encrypted: true).write(to: framework.appendingPathComponent("Main"))
        XCTAssertThrowsError(try RuntimeTranslationScanner.scan(app: url)) {
            XCTAssertEqual($0 as? RuntimeTranslationScanError, .encrypted)
        }
    }
    func testTruncationOverflowAndSectionBounds() throws {
        for n in [0, 3, 20, 31, 33, 100, 207] {
            try assertFailure(Data(binary().prefix(n)), .malformed)
        }
        var bad = binary()
        put(UInt64.max, at: 144, bytes: 8, in: &bad)
        try assertFailure(bad, .malformed)
        bad = binary()
        put(1, at: 152, in: &bad)
        try assertFailure(bad, .malformed)
        bad = fat([binary()], wide: true)
        put(UInt64.max, at: 16, bytes: 8, little: false, in: &bad)
        try assertFailure(bad, .malformed)
        bad = binary()
        put(0, at: 188, in: &bad)
        try assertFailure(bad, .malformed)
    }
    func testFiltersAndPlaceholders() {
        for text in ["Start Location", "Settings", "Location", "Save", "保存 %@", "已完成 %1$ld / %2$@", "設定", "构建", "説明", "설정"] {
            XCTAssertTrue(RuntimeTranslationScanner.eligible(text), text)
        }
        for text in ["$s4Main8SettingsV", "_OBJC_CLASS_$_Main", "startLocation", "https://网站.example", "用户 a@b.com", "/用户/目录", "用户 123456789", "密钥 token=abc", "保存 " , String(repeating: "中", count: 513)] {
            XCTAssertFalse(RuntimeTranslationScanner.eligible(text), text)
        }
    }
    func testStaticLatinAndLocalizationAndNoOriginalMutation() throws {
        let url = try app(binary("Save"))
        let english = url.appendingPathComponent("en.lproj")
        try FileManager.default.createDirectory(at: english, withIntermediateDirectories: true)
        let resource = english.appendingPathComponent("Localizable.strings")
        let data = try PropertyListSerialization.data(fromPropertyList: ["save": "Save changes %@"], format: .binary, options: 0)
        try data.write(to: resource)
        XCTAssertEqual(try RuntimeTranslationScanner.scan(app: url).items.map(\.text), ["Save", "Save changes %@"])
        XCTAssertEqual(try Data(contentsOf: resource), data)
        try FileManager.default.createDirectory(at: url.appendingPathComponent("ar.lproj"), withIntermediateDirectories: true)
        XCTAssertEqual(Set(try RuntimeTranslationScanner.scan(app: url).items.map(\.text)), Set(["Save", "Save changes %@"]))
    }
    func testSymlinkFrameworkIsNotFollowedAndMainTraversalRejected() throws {
        let url = try app(binary())
        let frameworks = url.appendingPathComponent("Frameworks")
        try FileManager.default.createDirectory(at: frameworks, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: frameworks.appendingPathComponent("Outside.framework"), withDestinationURL: url.deletingLastPathComponent())
        XCTAssertEqual(try RuntimeTranslationScanner.scan(app: url).items.count, 1)
        try FileManager.default.removeItem(at: url.appendingPathComponent("Main"))
        try FileManager.default.createSymbolicLink(at: url.appendingPathComponent("Main"), withDestinationURL: url.appendingPathComponent("Info.plist"))
        XCTAssertThrowsError(try RuntimeTranslationScanner.scan(app: url))
    }
    private func alphabetic(_ number: Int) -> String {
        var n = number
        var result = ""
        for _ in 0..<4 {
            result.append(Character(UnicodeScalar(97 + n % 26)!))
            n /= 26
        }
        return result
    }
    @discardableResult
    private func resources(_ values: [String], at app: URL, locale: String = "en") throws -> [URL: Data] {
        let dir = app.appendingPathComponent(locale + ".lproj")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var originals: [URL: Data] = [:]
        // Preserve the existing 1 MiB per-file bound even in large fixtures.
        for start in stride(from: 0, to: values.count, by: 500) {
            var table: [String: String] = [:]
            for i in start..<min(start + 500, values.count) { table["label" + alphabetic(i)] = values[i] }
            let file = dir.appendingPathComponent("Table" + alphabetic(start) + ".strings")
            let data = try PropertyListSerialization.data(fromPropertyList: table, format: .binary, options: 0)
            XCTAssertLessThan(data.count, ArabicIPALocalizer.maxFileBytes)
            try data.write(to: file)
            originals[file] = data
        }
        return originals
    }
    func testTenThousandPublicEnglishResourcesUnchangedAndPrivateTextExcluded() throws {
        let url = try app(binary(""))
        let labels = (0..<10_000).map { "Public label " + alphabetic($0) }
        let originals = try resources(labels + ["password=private", "Contact abc@host", "/home/private"], at: url)
        let result = try RuntimeTranslationScanner.scan(app: url)
        XCTAssertEqual(Set(result.items.map(\.text)), Set(labels))
        XCTAssertEqual(result.items.count, 10_000)
        for (file, bytes) in originals { XCTAssertEqual(try Data(contentsOf: file), bytes) }
    }
    func testRuntimeTwentyThousandBoundaryAndCombinedResourceCJKOverflowThrows() throws {
        let url = try app(binary(""))
        try resources((0..<20_000).map { "Public label " + alphabetic($0) }, at: url)
        XCTAssertEqual(try RuntimeTranslationScanner.scan(app: url).items.count, 20_000)
        try binary("保存").write(to: url.appendingPathComponent("Main"))
        XCTAssertThrowsError(try RuntimeTranslationScanner.scan(app: url)) {
            XCTAssertEqual($0 as? RuntimeTranslationScanError, .tooLarge)
        }
    }
    func testBinaryCJKTwentyThousandBoundaryAndOverflowThrows() throws {
        let labels = (0..<20_000).map { "选项 " + alphabetic($0) }
        let url = try app(binary(labels.joined(separator: "\0")))
        XCTAssertEqual(try RuntimeTranslationScanner.scan(app: url).items.count, 20_000)
        try binary((labels + ["额外"]).joined(separator: "\0")).write(to: url.appendingPathComponent("Main"))
        XCTAssertThrowsError(try RuntimeTranslationScanner.scan(app: url)) {
            XCTAssertEqual($0 as? RuntimeTranslationScanError, .tooLarge)
        }
    }
    func testRuntimeExactFourMiBBoundaryAndCombinedCJKByteOverflow() throws {
        let url = try app(binary(""))
        let prefix = String(repeating: "Public label ", count: 19) + "xxxxx"
        XCTAssertEqual(prefix.utf8.count, 252)
        let labels = (0..<16_384).map { prefix + alphabetic($0) }
        XCTAssertEqual(labels.reduce(0) { $0 + $1.utf8.count }, RuntimeTranslationScanner.maxTotalTextBytes)
        try resources(labels, at: url)
        XCTAssertEqual(try RuntimeTranslationScanner.scan(app: url).items.count, labels.count)
        try binary("保存").write(to: url.appendingPathComponent("Main"))
        XCTAssertThrowsError(try RuntimeTranslationScanner.scan(app: url)) {
            XCTAssertEqual($0 as? RuntimeTranslationScanError, .tooLarge)
        }
    }
    func testRuntimeFourMiBTextOverflowThrowsInsteadOfPartialScan() throws {
        let url = try app(binary(""))
        let prefix = String(repeating: "Public label ", count: 18)
        let labels = (0..<20_000).map { prefix + alphabetic($0) }
        XCTAssertTrue(labels.allSatisfy { RuntimeTranslationScanner.safeText($0) })
        XCTAssertGreaterThan(labels.reduce(0) { $0 + $1.utf8.count }, RuntimeTranslationScanner.maxTotalTextBytes)
        try resources(labels, at: url)
        XCTAssertThrowsError(try RuntimeTranslationScanner.scan(app: url)) {
            XCTAssertEqual($0 as? RuntimeTranslationScanError, .tooLarge)
        }
    }
    func testLegacyDefaultStillRejectsOverFifteenHundredItemsAndTotalCharacters() throws {
        let url = try app(binary(""))
        try resources((0..<1500).map { "Public label " + alphabetic($0) }, at: url)
        XCTAssertEqual(try ArabicIPALocalizer.scan(app: url).items.count, 1500)
        try resources((0..<1501).map { "Public label " + alphabetic($0) }, at: url)
        XCTAssertThrowsError(try ArabicIPALocalizer.scan(app: url)) {
            XCTAssertEqual(($0 as? CocoaError)?.code, .fileReadTooLarge)
        }
        let long = try app(binary(""))
        try resources((0..<1000).map { String(repeating: "Public label ", count: 13) + alphabetic($0) }, at: long)
        XCTAssertThrowsError(try ArabicIPALocalizer.scan(app: long)) {
            XCTAssertEqual(($0 as? CocoaError)?.code, .fileReadTooLarge)
        }
    }
    func testRelocStyleNamedEnglishKeysWinOverSecondaryChineseResources() throws {
        let url = try app(binary(""))
        let english = ["start_location": "Start Location", "ready": "Ready · Pick a Point",
                       "diagnostics": "Diagnostics", "settings": "Settings", "location": "Location"]
        for (locale, table) in [("en", english), ("zh-Hans", ["start_location": "开始定位", "ready": "准备"])] {
            let dir = url.appendingPathComponent(locale + ".lproj")
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try PropertyListSerialization.data(fromPropertyList: table, format: .binary, options: 0)
                .write(to: dir.appendingPathComponent("Localizable.strings"))
        }
        XCTAssertEqual(Set(try RuntimeTranslationScanner.scan(app: url).items.map(\.text)), Set(english.values))
    }
    func testEnglishOnlySwiftUILiteralSectionsAndConstCandidates() throws {
        let labels = ["Start Location", "Ready · Pick a Point", "Diagnostics", "Settings", "Location"]
        for section in ["__cstring", "__const"] {
            var data = binary((labels + ["$s4Main8SettingsV", "token=private", "abc@example.com"]).joined(separator: "\0"))
            data.replaceSubrange(104..<120, with: Data(repeating: 0, count: 16))
            data.replaceSubrange(104..<(104 + section.utf8.count), with: Data(section.utf8))
            let url = try app(data)
            XCTAssertEqual(Set(try RuntimeTranslationScanner.scan(app: url).items.map(\.text)), Set(labels))
        }
    }
    func testCatalogSourceValuesVariantsFallbackAndPartialArabic() throws {
        let url = try app(binary(""))
        try FileManager.default.createDirectory(at: url.appendingPathComponent("ar.lproj"), withIntermediateDirectories: true)
        try resources(["English retained"], at: url)
        let catalog: [String: Any] = [
            "sourceLanguage": "en", "strings": [
                "named_key": ["localizations": [
                    "en": ["stringUnit": ["value": "Start Location"]],
                    "de": ["stringUnit": ["value": "German should not escape"]]]],
                "Ready · Pick a Point": [:],
                "internal_key": [:],
                "source_unit": ["sourceUnit": ["value": "Diagnostics"]],
                "plural_key": ["localizations": ["en": ["variations": ["plural": [
                    "one": ["stringUnit": ["value": "One place"]],
                    "other": ["stringUnit": ["value": "Many places"]]]]]]],
                "sensitive": ["localizations": ["en": ["stringUnit": ["value": "password=private"]]]]
            ]]
        let data = try JSONSerialization.data(withJSONObject: catalog)
        let file = url.appendingPathComponent("Localizable.xcstrings")
        try data.write(to: file)
        XCTAssertEqual(Set(try RuntimeTranslationScanner.scan(app: url).items.map(\.text)),
                       Set(["English retained", "Start Location", "Ready · Pick a Point", "Diagnostics", "One place", "Many places"]))
        XCTAssertEqual(try Data(contentsOf: file), data)
        XCTAssertTrue(try ArabicIPALocalizer.scan(app: url).hasArabic)
        XCTAssertTrue(try ArabicIPALocalizer.scan(app: url).items.isEmpty)
    }
    func testDynamicExternalFilesAndSymlinkCatalogNotRead() throws {
        let url = try app(binary("Settings"))
        let external = url.deletingLastPathComponent().appendingPathComponent("UserInput.xcstrings")
        try Data(#"{"sourceLanguage":"en","strings":{"Dynamically entered private text":{}}}"#.utf8).write(to: external)
        try FileManager.default.createSymbolicLink(at: url.appendingPathComponent("Linked.xcstrings"), withDestinationURL: external)
        try Data("Dynamically entered private text".utf8).write(to: url.appendingPathComponent("userdata.txt"))
        XCTAssertEqual(try RuntimeTranslationScanner.scan(app: url).items.map(\.text), ["Settings"])
    }
    func testNonSectionBytesIgnored() throws {
        var bytes = binary("")
        bytes.append(Data("忽略此文本\0".utf8))
        let url = try app(bytes)
        XCTAssertTrue(try RuntimeTranslationScanner.scan(app: url).items.isEmpty)
    }
    func testContractUTF16AndSensitiveMarkers() {
        XCTAssertTrue(RuntimeTranslationScanner.safeText(String(repeating: "中", count: 256)))
        XCTAssertFalse(RuntimeTranslationScanner.safeText(String(repeating: "中", count: 257)))
        XCTAssertFalse(RuntimeTranslationScanner.safeText(String(repeating: "𠀀", count: 129)))
        for text in ["用户 example.com", "用户 abc@host", "用户 123-456-789", "姓名：张三",
                     "密码=测试", "用户 email:foo", "用户 sk-abcdefghijklmnop",
                     "用户 eyJabcdefghijklmnop", "用户 example.app", "用户 https:foo",
                     "用户\u{202E}", "用户\u{007F}"] {
            XCTAssertFalse(RuntimeTranslationScanner.safeText(text), text)
        }
    }
    func testGlobalEncryptionGateInExtensionsAppClipsAndLooseBinaries() throws {
        for path in ["PlugIns/Widget.appex", "AppClips/Clip.app"] {
            let url = try app(binary())
            let nested = url.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
            try info(at: nested)
            try binary(encrypted: true).write(to: nested.appendingPathComponent("Main"))
            XCTAssertThrowsError(try RuntimeTranslationScanner.scan(app: url)) {
                XCTAssertEqual($0 as? RuntimeTranslationScanError, .encrypted)
            }
        }
        let url = try app(binary())
        try binary(encrypted: true).write(to: url.appendingPathComponent("Loose.dylib"))
        XCTAssertThrowsError(try RuntimeTranslationScanner.scan(app: url)) {
            XCTAssertEqual($0 as? RuntimeTranslationScanError, .encrypted)
        }
    }
    func testUnsupportedAndAbsentMainFailSafe() throws {
        let url = try app(Data("not executable".utf8))
        XCTAssertThrowsError(try RuntimeTranslationScanner.scan(app: url))
        try FileManager.default.removeItem(at: url.appendingPathComponent("Main"))
        XCTAssertThrowsError(try RuntimeTranslationScanner.scan(app: url))
    }

}
