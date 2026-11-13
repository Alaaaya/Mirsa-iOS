import XCTest
@testable import Mirsa

final class ForgeDylibInspectorTests: XCTestCase {
    private func u32(_ value: UInt32, big: Bool = false) -> Data {
        var n = big ? value.bigEndian : value.littleEndian
        return withUnsafeBytes(of: &n) { Data($0) }
    }
    private func thin(cpu: UInt32 = 0x0100000c, subtype: UInt32 = 0, commands: Data = Data(), count: UInt32 = 0) -> Data {
        [u32(0xfeedfacf), u32(cpu), u32(subtype), u32(6), u32(count), u32(UInt32(commands.count)), u32(0), u32(0), commands].reduce(Data(), +)
    }
    private func fat(cpu: UInt32 = 0x0100000c, subtype: UInt32 = 0, offset: UInt32 = 28) -> Data {
        let binary = thin(cpu: cpu, subtype: subtype)
        return [u32(0xcafebabe, big: true), u32(1, big: true),
                u32(cpu, big: true), u32(subtype, big: true), u32(offset, big: true),
                u32(UInt32(binary.count), big: true), u32(0, big: true), binary].reduce(Data(), +)
    }
    func testThinArm64AndArm64e() throws {
        XCTAssertEqual(try ForgeDylibInspector.inspect(thin()).arch, "arm64")
        XCTAssertEqual(try ForgeDylibInspector.inspect(thin(subtype: 2)).arch, "arm64e")
        XCTAssertEqual(try ForgeDylibInspector.inspect(thin()).size, 32)
    }
    func testUnsupportedCPUAndSubtype() {
        XCTAssertThrowsError(try ForgeDylibInspector.inspect(thin(cpu: 0x01000007)))
        XCTAssertThrowsError(try ForgeDylibInspector.inspect(thin(subtype: 19)))
        XCTAssertThrowsError(try ForgeDylibInspector.inspect(thin(cpu: 12)))
    }
    func testFatWithArm64AcceptedAndWithoutArm64Rejected() throws {
        XCTAssertEqual(try ForgeDylibInspector.inspect(fat()).arch, "arm64")
        XCTAssertEqual(try ForgeDylibInspector.inspect(fat(subtype: 2)).arch, "arm64e")
        XCTAssertThrowsError(try ForgeDylibInspector.inspect(fat(cpu: 0x01000007)))
    }
    func testFatBadOffsetsAndSubtypeMismatch() {
        for offset: UInt32 in [0, 8, 27, 29, UInt32.max] {
            XCTAssertThrowsError(try ForgeDylibInspector.inspect(fat(offset: offset)))
        }
        var data = fat()
        data.replaceSubrange(12..<16, with: u32(2, big: true))
        XCTAssertThrowsError(try ForgeDylibInspector.inspect(data))
    }
    func testFatOverlappingSlicesRejected() {
        let data = [u32(0xcafebabe, big: true), u32(2, big: true),
                    u32(0x0100000c, big: true), u32(0, big: true), u32(48, big: true), u32(32, big: true), u32(0, big: true),
                    u32(0x0100000c, big: true), u32(0, big: true), u32(48, big: true), u32(32, big: true), u32(0, big: true), thin()].reduce(Data(), +)
        XCTAssertThrowsError(try ForgeDylibInspector.inspect(data))
    }
    func testAllTruncatedHeaderLengthsRejectWithoutTrap() {
        let binary = fat()
        for end in 0..<binary.count {
            XCTAssertThrowsError(try ForgeDylibInspector.inspect(Data(binary.prefix(end))))
        }
    }
    func testMalformedLoadCommandsRejectWithoutTrap() {
        for length: UInt32 in [0, 4, 7, 16, UInt32.max] {
            let commands = u32(0x19) + u32(length)
            XCTAssertThrowsError(try ForgeDylibInspector.inspect(thin(commands: commands, count: 1)))
        }
        XCTAssertThrowsError(try ForgeDylibInspector.inspect(thin(commands: Data(), count: 999)))
    }
    func testBadSegmentAndSymbolOffsetsReject() {
        var segment = Data(repeating: 0, count: 72)
        segment.replaceSubrange(0..<4, with: u32(0x19))
        segment.replaceSubrange(4..<8, with: u32(72))
        segment.replaceSubrange(40..<44, with: u32(UInt32.max))
        XCTAssertThrowsError(try ForgeDylibInspector.inspect(thin(commands: segment, count: 1)))
        let symbols = [u32(2), u32(24), u32(UInt32.max), u32(1), u32(0), u32(0)].reduce(Data(), +)
        XCTAssertThrowsError(try ForgeDylibInspector.inspect(thin(commands: symbols, count: 1)))
    }
    func testLinkedLibraryAndHonestSummary() throws {
        let name = Data("/usr/lib/libobjc.A.dylib\0".utf8)
        let length = ((24 + name.count + 7) / 8) * 8
        var command = [u32(0xc), u32(UInt32(length)), u32(24), u32(0), u32(0), u32(0), name].reduce(Data(), +)
        command.append(Data(repeating: 0, count: length - command.count))
        let info = try ForgeDylibInspector.inspect(thin(commands: command, count: 1))
        XCTAssertEqual(info.linked, ["/usr/lib/libobjc.A.dylib"])
        XCTAssertTrue(info.summary.contains("NEW companion"))
        XCTAssertTrue(info.summary.contains("never instructions"))
        XCTAssertLessThanOrEqual(info.summary.utf8.count, 4000)
    }
    func testCompanionSummaryIsByteBoundedForArabicAndEmoji() throws {
        let text = String(repeating: "مرحبا🐈", count: 300)
        let info = ForgeDylibInfo(arch: text, size: Int.max, linked: Array(repeating: text, count: 100),
                                 classes: Array(repeating: text, count: 100), selectors: Array(repeating: text, count: 100), summary: "not trusted")
        let summary = ForgeDylibInspector.companionSummary(info)
        XCTAssertLessThanOrEqual(summary.utf8.count, 4000)
        XCTAssertNotNil(summary.range(of: "\n"))
        let json = summary.components(separatedBy: "\n").dropFirst().joined(separator: "\n")
        XCTAssertNoThrow(try JSONSerialization.jsonObject(with: Data(json.utf8)))
        XCTAssertFalse(summary.contains("not trusted"))
    }
    func testEncryptedAndNonDylibRejected() {
        let command = [u32(0x2c), u32(24), u32(0), u32(0), u32(1), u32(0)].reduce(Data(), +)
        XCTAssertThrowsError(try ForgeDylibInspector.inspect(thin(commands: command, count: 1)))
        var binary = thin()
        binary.replaceSubrange(12..<16, with: u32(2))
        XCTAssertThrowsError(try ForgeDylibInspector.inspect(binary))
    }
}
