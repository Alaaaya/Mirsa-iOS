import XCTest
@testable import Mirsa

final class EncryptedAppsTests: XCTestCase {
    private func plist(_ d: [String: Any]) throws -> Data {
        try PropertyListSerialization.data(fromPropertyList: d, format: .xml, options: 0)
    }

    func testParsesClassicAppStoreMetadata() throws {
        let data = try plist([
            "itemName": "Notes Pro", "itemId": 123456789, "softwareVersionBundleId": "com.example.notes",
            "bundleShortVersionString": "5.2.1", "artistName": "Example Inc.",
            "com.apple.iTunesStore.downloadInfo": ["accountInfo": ["AppleID": "Buyer@Example.com", "FirstName": "Sam", "LastName": "Buyer"]],
        ])
        let m = try XCTUnwrap(EncryptedIPAMetadata.parse(data))
        XCTAssertEqual(m.itemName, "Notes Pro")
        XCTAssertEqual(m.itemID, 123456789)
        XCTAssertEqual(m.bundleID, "com.example.notes")
        XCTAssertEqual(m.version, "5.2.1")
        XCTAssertEqual(m.purchaserAppleID, "Buyer@Example.com")
        XCTAssertEqual(m.purchaserName, "Sam Buyer")
    }

    func testParsesIpatoolStyleAndBinaryPlist() throws {
        let d: [String: Any] = ["itemName": "Weather", "apple-id": "me@example.com", "userName": "me@example.com", "bundleVersion": "200"]
        let bin = try PropertyListSerialization.data(fromPropertyList: d, format: .binary, options: 0)
        let m = try XCTUnwrap(EncryptedIPAMetadata.parse(bin))
        XCTAssertEqual(m.purchaserAppleID, "me@example.com")
        XCTAssertEqual(m.version, "200")
        XCTAssertNil(EncryptedIPAMetadata.parse(Data("not a plist".utf8)))
    }

    func testAccountMatching() {
        XCTAssertEqual(EncryptedAccountMatch.evaluate(purchaser: "A@x.com", signedIn: ["a@X.com"]), .match)
        XCTAssertEqual(EncryptedAccountMatch.evaluate(purchaser: "a@x.com", signedIn: ["b@x.com"]), .mismatch(signedIn: "b@x.com"))
        XCTAssertEqual(EncryptedAccountMatch.evaluate(purchaser: "a@x.com", signedIn: []), .noSignedInAccount)
        XCTAssertEqual(EncryptedAccountMatch.evaluate(purchaser: nil, signedIn: ["b@x.com"]), .unknownPurchaser)
    }

    /// Stored (uncompressed) zip, enough for ZipReader.
    private func zip(_ files: [(String, Data)]) -> Data {
        func u16(_ d: inout Data, _ v: Int) { d.append(UInt8(v & 0xFF)); d.append(UInt8((v >> 8) & 0xFF)) }
        func u32(_ d: inout Data, _ v: UInt32) {
            d.append(UInt8(v & 0xFF)); d.append(UInt8((v >> 8) & 0xFF))
            d.append(UInt8((v >> 16) & 0xFF)); d.append(UInt8(v >> 24))
        }
        var out = Data()
        var central = Data()
        for (name, body) in files {
            let n = Data(name.utf8)
            let crc: UInt32 = CRC32.update(0, body)
            let offset = UInt32(out.count)
            let size = UInt32(body.count)
            u32(&out, 0x04034b50); u16(&out, 20); u16(&out, 0); u16(&out, 0); u16(&out, 0); u16(&out, 0)
            u32(&out, crc); u32(&out, size); u32(&out, size); u16(&out, n.count); u16(&out, 0)
            out.append(n); out.append(body)
            u32(&central, 0x02014b50); u16(&central, 20); u16(&central, 20); u16(&central, 0); u16(&central, 0)
            u16(&central, 0); u16(&central, 0); u32(&central, crc); u32(&central, size); u32(&central, size)
            u16(&central, n.count); u16(&central, 0); u16(&central, 0); u16(&central, 0); u16(&central, 0)
            u32(&central, 0x81A40000); u32(&central, offset); central.append(n)
        }
        let cd = UInt32(out.count)
        let cdSize = UInt32(central.count)
        out.append(central)
        u32(&out, 0x06054b50); u16(&out, 0); u16(&out, 0); u16(&out, files.count); u16(&out, files.count)
        u32(&out, cdSize); u32(&out, cd); u16(&out, 0)
        return out
    }

    func testInspectorReadsPackageWithoutChangingIt() throws {
        let info = try plist(["CFBundleIdentifier": "com.example.notes", "CFBundleExecutable": "Notes",
                              "CFBundleDisplayName": "Notes Pro", "CFBundleShortVersionString": "5.2.1"])
        let meta = try plist(["itemName": "Notes Pro", "com.apple.iTunesStore.downloadInfo": ["accountInfo": ["AppleID": "buyer@example.com"]]])
        let bytes = zip([("Payload/Notes.app/Info.plist", info), ("Payload/Notes.app/Notes", Data([0xCF, 0xFA, 0xED, 0xFE])),
                         ("Payload/Notes.app/SC_Info/Notes.sinf", Data("SINF".utf8)), ("iTunesMetadata.plist", meta)])
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("Notes.ipa")
        try bytes.write(to: file)
        let r = try EncryptedIPAInspector.inspect(file)
        XCTAssertEqual(r.entry.bundleID, "com.example.notes")
        XCTAssertEqual(r.entry.name, "Notes Pro")
        XCTAssertEqual(r.entry.version, "5.2.1")
        XCTAssertTrue(r.entry.hasSinf)
        XCTAssertTrue(r.entry.hasMetadata)
        XCTAssertEqual(r.entry.metadata?.purchaserAppleID, "buyer@example.com")
        XCTAssertEqual(try Data(contentsOf: file), bytes)

        let bare = zip([("Payload/Notes.app/Info.plist", info)])
        try bare.write(to: file)
        let r2 = try EncryptedIPAInspector.inspect(file)
        XCTAssertFalse(r2.entry.hasSinf)
        XCTAssertFalse(r2.entry.hasMetadata)
    }

    func testInspectorRejectsNonIPA() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".ipa")
        try Data("hello".utf8).write(to: file)
        addTeardownBlock { try? FileManager.default.removeItem(at: file) }
        XCTAssertThrowsError(try EncryptedIPAInspector.inspect(file))
    }
}
