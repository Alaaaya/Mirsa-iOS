import XCTest
import ZIPFoundation
@testable import Mirsa

final class ForgeFrameworkClassesTests: XCTestCase {
    private func le32(_ v: UInt32) -> [UInt8] { (0..<4).map { UInt8((v >> (8 * UInt32($0))) & 0xff) } }
    private func le64(_ v: UInt64) -> [UInt8] { (0..<8).map { UInt8((v >> (8 * UInt64($0))) & 0xff) } }
    private func be32(_ v: UInt32) -> [UInt8] { le32(v).reversed() }
    private func name16(_ s: String) -> [UInt8] { Array(s.utf8) + [UInt8](repeating: 0, count: 16 - s.utf8.count) }

    /// Real-shaped arm64/arm64e slice: __TEXT with __objc_classname, __DATA_CONST with a chained-pointer __objc_classlist,
    /// LC_DYLD_CHAINED_FIXUPS, no symbol table (stripped). Class names are read from the strings section, so no pointer decoding is needed.
    private func slice(subtype: UInt32, classNames: [String], cryptid: UInt32 = 0) -> [UInt8] {
        let strings = classNames.flatMap { Array($0.utf8) + [0] }
        let seg = 72 + 80 * 2, enc = 20, fix = 16
        let hdr = 32, cmdsSize = seg + enc + fix
        let strOff = 0x1000
        let listOff = strOff + ((strings.count + 15) & ~15)
        var b = le32(0xFEEDFACF) + le32(0x0100000C) + le32(subtype) + le32(6) + le32(3) + le32(UInt32(cmdsSize)) + le32(0x00200085) + le32(0)
        b += le32(0x19) + le32(UInt32(seg)) + name16("__TEXT") + name16("") + le64(0) + le64(0x4000) + le64(0) + le64(0x4000) + le32(5) + le32(5) + le32(2) + le32(0)
        b += name16("__objc_classname") + name16("__TEXT") + le64(UInt64(strOff)) + le64(UInt64(strings.count)) + le32(UInt32(strOff)) + le32(0) + le32(0) + le32(0) + le32(2) + le32(0) + le32(0) + le32(0)
        b += name16("__objc_classlist") + name16("__DATA_CONST") + le64(UInt64(listOff)) + le64(8) + le32(UInt32(listOff)) + le32(3) + le32(0) + le32(0) + le32(0) + le32(0) + le32(0) + le32(0)
        b += le32(0x2C) + le32(UInt32(enc)) + le32(UInt32(hdr)) + le32(0x4000) + le32(cryptid)
        b += le32(0x80000034) + le32(UInt32(fix)) + le32(0) + le32(0)
        b += [UInt8](repeating: 0, count: strOff - b.count) + strings
        b += [UInt8](repeating: 0, count: listOff - b.count) + le64(0x8010_0000_0000_1000) // chained rebase-looking pointer
        return b
    }
    private func fat(_ s: [UInt8]) -> [UInt8] {
        let off = 0x4000
        var b = be32(0xCAFEBABE) + be32(2)
        b += be32(0x0100000C) + be32(0) + be32(UInt32(off)) + be32(UInt32(s.count)) + be32(14) // arm64 header (empty-ish)
        b += be32(0x0100000C) + be32(2) + be32(UInt32(off)) + be32(UInt32(s.count)) + be32(14)
        b += [UInt8](repeating: 0, count: off - b.count) + s
        return b
    }
    private func ipa(files: [String: Data]) throws -> URL {
        let u = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".ipa")
        let a = try Archive(url: u, accessMode: .create)
        for (p, d) in files { try a.addEntry(with: p, type: .file, uncompressedSize: Int64(d.count), provider: { pos, size in d.subdata(in: Int(pos)..<Int(pos) + size) }) }
        return u
    }

    func testMainWithoutClassesButFrameworkHasThem() throws {
        let main = Data(slice(subtype: 0, classNames: []))
        let fw = Data(fat(slice(subtype: 2, classNames: ["AWEFeedCell", "_TtC8TikTokUI9FeedModel", "BHTikTokPlus"])))
        let u = try ipa(files: ["Payload/TikTok.app/TikTok": main, "Payload/TikTok.app/Frameworks/AwemeCore.framework/AwemeCore": fw,
                                 "Payload/TikTok.app/Frameworks/Junk.framework/Other": Data(slice(subtype: 0, classNames: ["Ignored"]))])
        defer { try? FileManager.default.removeItem(at: u) }
        let c = ForgeFrameworkClasses.classes(ipa: u)
        XCTAssertEqual(Set(c), ["AWEFeedCell", "_TtC8TikTokUI9FeedModel", "BHTikTokPlus"])
    }
    func testChainedFixupsStrippedArm64eMainBinary() throws {
        let f = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data(fat(slice(subtype: 2, classNames: ["A", "_TtC1M3Foo"]))).write(to: f); defer { try? FileManager.default.removeItem(at: f) }
        let i = try ForgeMachO.inspect(f)
        XCTAssertFalse(i.encrypted); XCTAssertEqual(i.classes, ["A", "_TtC1M3Foo"])
    }
    func testEncryptedFrameworkSkipped() throws {
        let fw = Data(slice(subtype: 0, classNames: ["Secret"], cryptid: 1))
        let u = try ipa(files: ["Payload/X.app/X": Data(slice(subtype: 0, classNames: [])), "Payload/X.app/Frameworks/F.framework/F": fw])
        defer { try? FileManager.default.removeItem(at: u) }
        let r = ForgeFrameworkClasses.scan(ipa: u); XCTAssertTrue(r.classes.isEmpty); XCTAssertEqual(r.encrypted, 1)
    }
    func testMixedEncryptedAndClearFrameworksKeepsClear() throws {
        let u = try ipa(files: ["Payload/X.app/X": Data(slice(subtype: 0, classNames: [])),
            "Payload/X.app/Frameworks/E.framework/E": Data(slice(subtype: 0, classNames: ["Secret"], cryptid: 1)),
            "Payload/X.app/Frameworks/C.framework/C": Data(slice(subtype: 0, classNames: ["Clear"]))])
        defer { try? FileManager.default.removeItem(at: u) }
        let r = ForgeFrameworkClasses.scan(ipa: u); XCTAssertEqual(r.classes, ["Clear"]); XCTAssertEqual(r.encrypted, 1)
    }
    // Fixtures exercise __objc_classname strings and framework discovery only; __objc_classlist and chained pointers are not parsed.
    func testTruncatedBinaryDoesNotCrash() {
        let f = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? Data(fat(slice(subtype: 0, classNames: ["A"])).prefix(0x4010)).write(to: f); defer { try? FileManager.default.removeItem(at: f) }
        _ = try? ForgeMachO.inspect(f)
    }
}
