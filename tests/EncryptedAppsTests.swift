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
        func le16(_ v: Int) -> Data { Data([UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF)]) }
        func le32(_ v: UInt32) -> Data { Data([UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF), UInt8((v >> 16) & 0xFF), UInt8(v >> 24)]) }
        var out = Data(), central = Data()
        for (name, body) in files {
            let n = Data(name.utf8), crc = CRC32.update(0, body), offset = UInt32(out.count)
            out += le32(0x04034b50) + le16(20) + le16(0) + le16(0) + le16(0) + le16(0) + le32(crc)
            out += le32(UInt32(body.count)) + le32(UInt32(body.count)) + le16(n.count) + le16(0) + n + body
            central += le32(0x02014b50) + le16(20) + le16(20) + le16(0) + le16(0) + le16(0) + le16(0) + le32(crc)
            central += le32(UInt32(body.count)) + le32(UInt32(body.count)) + le16(n.count) + le16(0) + le16(0) + le16(0) + le16(0)
            central += le32(0x81A40000) + le32(offset) + n
        }
        let cd = UInt32(out.count)
        out += central
        out += le32(0x06054b50) + le16(0) + le16(0) + le16(files.count) + le16(files.count) + le32(UInt32(central.count)) + le32(cd) + le16(0)
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
