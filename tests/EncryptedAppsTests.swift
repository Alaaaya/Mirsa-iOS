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

    // MARK: - FairPlayDecryptor (clean-room core + wrapper)

    /// Minimal thin arm64 Mach-O: header + one LC_ENCRYPTION_INFO_64.
    private func machO(cryptid: UInt32 = 0) -> Data {
        func u32(_ v: UInt32) -> [UInt8] {
            [UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF), UInt8((v >> 16) & 0xFF), UInt8((v >> 24) & 0xFF)]
        }
        var d = Data()
        d.append(contentsOf: u32(0xFEEDFACF)) // MH_MAGIC_64
        d.append(contentsOf: u32(0x0100000C)) // CPU_TYPE_ARM64
        d.append(contentsOf: u32(0))          // cpusubtype
        d.append(contentsOf: u32(2))          // MH_EXECUTE
        d.append(contentsOf: u32(1))          // ncmds
        d.append(contentsOf: u32(24))         // sizeofcmds
        d.append(contentsOf: u32(0))          // flags
        d.append(contentsOf: u32(0))          // reserved
        d.append(contentsOf: u32(0x2C))       // LC_ENCRYPTION_INFO_64
        d.append(contentsOf: u32(24))         // cmdsize
        d.append(contentsOf: u32(0))          // cryptoff
        d.append(contentsOf: u32(0))          // cryptsize
        d.append(contentsOf: u32(cryptid))    // cryptid
        d.append(contentsOf: u32(0))          // pad
        return d
    }

    private func decryptCore(_ url: URL) -> Int32 {
        var errbuf = [CChar](repeating: 0, count: 256)
        let result = url.path.withCString { cpath in
            errbuf.withUnsafeMutableBufferPointer { buf in
                mirsa_fp_decrypt_macho(cpath, buf.baseAddress, buf.count)
            }
        }
        return result.rawValue
    }

    /// Runs on the simulator: no kernel decryption is attempted, only the
    /// no-op and rejection paths of the C core.
    func testDecryptCoreLeavesClearMachOUntouched() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let bytes = machO(cryptid: 0)
        try bytes.write(to: file)
        addTeardownBlock { try? FileManager.default.removeItem(at: file) }
        XCTAssertEqual(decryptCore(file), 1) // MirsaFPAlreadyClear
        XCTAssertEqual(try Data(contentsOf: file), bytes)
    }

    func testDecryptCoreRejectsNonMachO() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("hello world, not a mach-o".utf8).write(to: file)
        addTeardownBlock { try? FileManager.default.removeItem(at: file) }
        XCTAssertEqual(decryptCore(file), -1) // MirsaFPNotMachO
    }

    func testDecryptCoreRejectsMalformedMachO() throws {
        var bytes = machO()
        // ncmds = 5000 at header offset 16.
        bytes[16] = 0x88; bytes[17] = 0x13; bytes[18] = 0; bytes[19] = 0
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try bytes.write(to: file)
        addTeardownBlock { try? FileManager.default.removeItem(at: file) }
        XCTAssertEqual(decryptCore(file), -2) // MirsaFPBadMachO
    }

    func testDecryptorPassesThroughClearIPA() throws {
        let info = try plist(["CFBundleIdentifier": "com.example.notes", "CFBundleExecutable": "Notes",
                              "CFBundleDisplayName": "Notes Pro", "CFBundleShortVersionString": "5.2.1"])
        let meta = try plist(["itemName": "Notes Pro"])
        let bytes = zip([("Payload/Notes.app/Info.plist", info), ("Payload/Notes.app/Notes", machO()),
                         ("iTunesMetadata.plist", meta)])
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("Notes.ipa")
        try bytes.write(to: file)
        let report = try FairPlayDecryptor.decryptIPA(at: file)
        addTeardownBlock { FairPlayDecryptor.endWorkDir(report) }
        XCTAssertEqual(report.decrypted, [])
        XCTAssertEqual(report.alreadyClear, ["Notes"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: report.outputURL.path))
        // The original encrypted (here: clear) IPA is untouched.
        XCTAssertEqual(try Data(contentsOf: file), bytes)
        // The output is a valid zip with the same entries.
        let outData = try Data(contentsOf: report.outputURL, options: .mappedIfSafe)
        let outZip = try ZipReader(data: outData)
        XCTAssertNotNil(outZip.entry("Payload/Notes.app/Notes"))
        XCTAssertNotNil(outZip.entry("Payload/Notes.app/Info.plist"))
        XCTAssertNotNil(outZip.entry("iTunesMetadata.plist"))
    }

    func testDecryptorRejectsNonIPA() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".ipa")
        try Data("not a zip".utf8).write(to: file)
        addTeardownBlock { try? FileManager.default.removeItem(at: file) }
        XCTAssertThrowsError(try FairPlayDecryptor.decryptIPA(at: file)) { error in
            XCTAssertTrue(error is FairPlayDecryptor.Error)
        }
    }
}
