import XCTest
@testable import Mirsa

final class ForgeDebTests: XCTestCase {
    private struct Member { let name: String; let data: Data }
    private func parseAr(_ d: Data) throws -> [Member] {
        XCTAssertEqual(String(decoding: d.prefix(8), as: UTF8.self), "!<arch>\n")
        var out: [Member] = [], p = 8
        while p + 60 <= d.count {
            let h = d.subdata(in: p..<p + 60)
            XCTAssertEqual(h.suffix(2), Data([0x60, 0x0A]))
            let name = String(decoding: h.prefix(16), as: UTF8.self).trimmingCharacters(in: .whitespaces)
            let size = Int(String(decoding: h.subdata(in: 48..<58), as: UTF8.self).trimmingCharacters(in: .whitespaces))!
            out.append(Member(name: name, data: d.subdata(in: p + 60..<p + 60 + size)))
            p += 60 + size + (size % 2)
        }
        XCTAssertEqual(p, d.count)
        return out
    }
    private func tarNames(_ t: Data) -> [String: Data] {
        var r: [String: Data] = [:], p = 0
        while p + 512 <= t.count, t[p] != 0 {
            let h = t.subdata(in: p..<p + 512)
            let name = String(decoding: h.prefix(100).prefix { $0 != 0 }, as: UTF8.self)
            let size = Int(String(decoding: h.subdata(in: 124..<135), as: UTF8.self), radix: 8)!
            r[name] = t.subdata(in: p + 512..<p + 512 + size)
            p += 512 + ((size + 511) / 512) * 512
        }
        return r
    }
    func testDebStructureAndContents() throws {
        var dylib = Data([0xCF, 0xFA, 0xED, 0xFE]); dylib.append(Data((0..<997).map { UInt8($0 % 251) }))
        let deb = ForgeDeb.build(name: "Test Tweak", bundleID: "com.test.app", dylib: dylib)
        let m = try parseAr(deb)
        XCTAssertEqual(m.map(\.name), ["debian-binary", "control.tar", "data.tar"])
        XCTAssertEqual(String(decoding: m[0].data, as: UTF8.self), "2.0\n")
        let control = tarNames(m[1].data)["./control"].map { String(decoding: $0, as: UTF8.self) } ?? ""
        XCTAssertTrue(control.contains("Package: com.mirsa.forge."))
        XCTAssertTrue(control.contains("Architecture: iphoneos-arm"))
        let files = tarNames(m[2].data)
        XCTAssertEqual(files["./Library/MobileSubstrate/DynamicLibraries/Test Tweak.dylib"], dylib)
        XCTAssertNotNil(files.keys.first { $0.hasSuffix(".plist") })
    }
}
