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
        let section = 104
        let name = Data((utf16 ? "__ustring" : "__cstring").utf8)
        data.replaceSubrange(section..<(section + name.count), with: name)
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
        for text in ["保存 %@", "已完成 %1$ld / %2$@", "設定", "构建", "説明", "설정"] {
            XCTAssertTrue(RuntimeTranslationScanner.eligible(text), text)
        }
        for text in ["Save", "https://网站.example", "用户 a@b.com", "/用户/目录", "用户 123456789", "密钥 token=abc", "保存 " , String(repeating: "中", count: 513)] {
            XCTAssertFalse(RuntimeTranslationScanner.eligible(text), text)
        }
    }
    func testLatinOnlyFromLocalizationAndNoOriginalMutation() throws {
        let url = try app(binary("Save"))
        let english = url.appendingPathComponent("en.lproj")
        try FileManager.default.createDirectory(at: english, withIntermediateDirectories: true)
        let resource = english.appendingPathComponent("Localizable.strings")
        let data = try PropertyListSerialization.data(fromPropertyList: ["save": "Save changes %@"], format: .binary, options: 0)
        try data.write(to: resource)
        XCTAssertEqual(try RuntimeTranslationScanner.scan(app: url).items.map(\.text), ["Save changes %@"])
        XCTAssertEqual(try Data(contentsOf: resource), data)
        try FileManager.default.createDirectory(at: url.appendingPathComponent("ar.lproj"), withIntermediateDirectories: true)
        XCTAssertTrue(try RuntimeTranslationScanner.scan(app: url).items.isEmpty)
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
    func testItemCapAndNonSectionBytesIgnored() throws {
        let texts = (0..<1600).map { "选项 \($0)" }.joined(separator: "\0")
        let url = try app(binary(texts))
        let scan = try RuntimeTranslationScanner.scan(app: url)
        XCTAssertEqual(scan.items.count, 1500)
        var bytes = binary("Save")
        bytes.append(Data("忽略此文本\0".utf8))
        try bytes.write(to: url.appendingPathComponent("Main"))
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
