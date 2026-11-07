import XCTest
import Foundation
@testable import Mirsa

final class FileToolsTests: XCTestCase {
    private var tmp: URL!
    override func setUpWithError() throws {
        tmp = FileManager.default.temporaryDirectory.appendingPathComponent("ft-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }
    override func tearDown() { try? FileManager.default.removeItem(at: tmp) }

    // MARK: fixtures
    private func w16(_ v: Int) -> Data { Data([UInt8(v & 255), UInt8((v >> 8) & 255)]) }
    private func w32(_ v: UInt32) -> Data { Data([UInt8(v & 255), UInt8((v >> 8) & 255), UInt8((v >> 16) & 255), UInt8((v >> 24) & 255)]) }
    /// Stored zip; mode lets a test mark an entry as symlink (0xA000).
    private func makeZip(_ files: [(String, Data, UInt32)]) -> Data {
        var out = Data(), central = Data()
        for (name, body, mode) in files {
            let off = out.count, n = Data(name.utf8), crc = CRC32.update(0, body), size = UInt32(body.count)
            out.append(w32(0x04034b50)); out.append(w16(20)); out.append(w16(0)); out.append(w16(0)); out.append(w16(0)); out.append(w16(0))
            out.append(w32(crc)); out.append(w32(size)); out.append(w32(size)); out.append(w16(n.count)); out.append(w16(0)); out.append(n); out.append(body)
            central.append(w32(0x02014b50)); central.append(w16(20)); central.append(w16(20)); central.append(w16(0)); central.append(w16(0)); central.append(w16(0)); central.append(w16(0))
            central.append(w32(crc)); central.append(w32(size)); central.append(w32(size)); central.append(w16(n.count))
            central.append(w16(0)); central.append(w16(0)); central.append(w16(0)); central.append(w16(0)); central.append(w32(mode << 16)); central.append(w32(UInt32(off))); central.append(n)
        }
        let cd = out.count
        out.append(central)
        out.append(w32(0x06054b50)); out.append(w16(0)); out.append(w16(0)); out.append(w16(files.count)); out.append(w16(files.count))
        out.append(w32(UInt32(central.count))); out.append(w32(UInt32(cd))); out.append(w16(0))
        return out
    }
    private func extract(_ zip: Data) throws -> URL {
        let a = tmp.appendingPathComponent("a-\(UUID().uuidString).zip")
        try zip.write(to: a)
        let dest = tmp.appendingPathComponent("out-\(UUID().uuidString)")
        try BundleZipExtractor.extract(archive: a, to: dest)
        return dest
    }
    private func macho64(cpu: UInt32 = 0x0100000C, cryptid: UInt32? = nil, dylibs: [String] = []) -> Data {
        var cmds = Data()
        if let c = cryptid { for v in [UInt32(0x2C), 24, 0, 0x1000, c, 0] { cmds.append(w32(v)) } }
        var n = cryptid == nil ? 0 : 1
        for d in dylibs {
            var name = Data(d.utf8); name.append(0)
            while name.count % 8 != 0 { name.append(0) }
            let size = 24 + name.count
            for v in [UInt32(0x0C), UInt32(size), 24, 0, 0, 0] { cmds.append(w32(v)) }
            cmds.append(name); n += 1
        }
        var d = Data()
        for v in [UInt32(0xFEEDFACF), cpu, 0, 2, UInt32(n), UInt32(cmds.count), 0, 0] { d.append(w32(v)) }
        d.append(cmds); return d
    }
    private func be32(_ v: UInt32) -> Data { Data([UInt8(v >> 24), UInt8((v >> 16) & 255), UInt8((v >> 8) & 255), UInt8(v & 255)]) }

    // MARK: archive traversal
    func testExtractRejectsTraversalAndAbsolutePaths() {
        for bad in ["../evil.txt", "a/../../evil.txt", "/abs.txt", "a\\b.txt"] {
            XCTAssertThrowsError(try extract(makeZip([(bad, Data("x".utf8), 0)])), bad)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: tmp.appendingPathComponent("evil.txt").path))
    }
    func testExtractRejectsSymlinkEntries() {
        XCTAssertThrowsError(try extract(makeZip([("link", Data("/etc/passwd".utf8), 0xA1FF)])))
    }
    func testExtractRejectsDuplicateAndCaseCollisions() {
        XCTAssertThrowsError(try extract(makeZip([("A.txt", Data("1".utf8), 0x81A4), ("a.txt", Data("2".utf8), 0x81A4)])))
        XCTAssertThrowsError(try extract(makeZip([("d/x", Data("1".utf8), 0x81A4), ("d", Data("2".utf8), 0x81A4)])))
    }
    func testExtractRejectsNonZip() {
        XCTAssertThrowsError(try extract(Data("not a zip at all, definitely".utf8)))
    }
    func testExtractWritesFilesAndSkipsMacosxJunk() throws {
        let out = try extract(makeZip([("dir/", Data(), 0x41ED), ("dir/a.txt", Data("hello".utf8), 0x81A4), ("__MACOSX/x", Data("j".utf8), 0x81A4)]))
        XCTAssertEqual(try String(contentsOf: out.appendingPathComponent("dir/a.txt")), "hello")
        XCTAssertFalse(FileManager.default.fileExists(atPath: out.appendingPathComponent("__MACOSX").path))
    }
    func testWriterExtractorRoundTrip() throws {
        let src = tmp.appendingPathComponent("src")
        try FileManager.default.createDirectory(at: src.appendingPathComponent("sub"), withIntermediateDirectories: true)
        try Data("alpha".utf8).write(to: src.appendingPathComponent("a.txt"))
        let big = Data(repeating: 0x41, count: 5000)
        try big.write(to: src.appendingPathComponent("sub/big.bin"))
        try FileManager.default.createSymbolicLink(at: src.appendingPathComponent("sym"), withDestinationURL: URL(fileURLWithPath: "/etc/hosts"))
        let z = tmp.appendingPathComponent("r.zip")
        try BundleZipWriter.write(tree: src, rootName: "root", to: z)
        let out = tmp.appendingPathComponent("rt")
        try BundleZipExtractor.extract(archive: z, to: out)
        XCTAssertEqual(try String(contentsOf: out.appendingPathComponent("root/a.txt")), "alpha")
        XCTAssertEqual(try Data(contentsOf: out.appendingPathComponent("root/sub/big.bin")), big)
        XCTAssertFalse(FileManager.default.fileExists(atPath: out.appendingPathComponent("root/sym").path))
    }

    // MARK: Mach-O
    private func report(_ d: Data) throws -> [MachOSliceReport] {
        let u = tmp.appendingPathComponent("m-\(UUID().uuidString)"); try d.write(to: u)
        return try MachOViewer.report(for: u)
    }
    func testMachOThinEncryptedAndLibraries() throws {
        let r = try report(macho64(cryptid: 1, dylibs: ["/usr/lib/libSystem.B.dylib", "@rpath/X.framework/X"]))
        XCTAssertEqual(r.count, 1)
        XCTAssertEqual(r[0].arch, "arm64")
        XCTAssertTrue(r[0].encrypted)
        XCTAssertEqual(r[0].libraries.map { $0.name }, ["/usr/lib/libSystem.B.dylib", "@rpath/X.framework/X"])
        XCTAssertFalse(try report(macho64(cryptid: 0))[0].encrypted)
    }
    func testMachOFatListsArchs() throws {
        let a = macho64(), b = macho64(cpu: 0x01000007)
        var fat = Data(); fat.append(be32(0xCAFEBABE)); fat.append(be32(2))
        let off1 = 4096, off2 = 8192
        for (cpu, off, sz) in [(UInt32(0x0100000C), off1, a.count), (UInt32(0x01000007), off2, b.count)] {
            fat.append(be32(cpu)); fat.append(be32(0)); fat.append(be32(UInt32(off))); fat.append(be32(UInt32(sz))); fat.append(be32(12))
        }
        fat.append(Data(repeating: 0, count: off1 - fat.count)); fat.append(a)
        fat.append(Data(repeating: 0, count: off2 - fat.count)); fat.append(b)
        XCTAssertEqual(try report(fat).map { $0.arch }, ["arm64", "x86_64"])
    }
    func testMachOMalformedRejected() {
        XCTAssertThrowsError(try report(Data("hello world, not macho, padding padding".utf8)))
        var d = macho64(); d.replaceSubrange(16..<20, with: w32(500))   // ncmds far beyond data
        XCTAssertThrowsError(try report(d))
        XCTAssertThrowsError(try report(Data([0xCA, 0xFE, 0xBA, 0xBE, 0, 0, 0, 2])))
    }

    // MARK: manager integration
    private func bundle() throws -> BundleFileManager {
        let app = tmp.appendingPathComponent("w.app")
        try FileManager.default.createDirectory(at: app.appendingPathComponent("Assets"), withIntermediateDirectories: true)
        let info: [String: Any] = ["CFBundleIdentifier": "com.a.b", "CFBundleExecutable": "Main"]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: app.appendingPathComponent("Info.plist"))
        try macho64().write(to: app.appendingPathComponent("Main"))
        try Data("hello".utf8).write(to: app.appendingPathComponent("Assets/a.txt"))
        return try BundleFileManager(root: app, stagingDirectory: tmp.appendingPathComponent("st-\(UUID().uuidString)"))
    }
    func testCopyMoveZipUnzipSearch() throws {
        let m = try bundle()
        try m.stageMakeDirectory(in: "", name: "New")
        try m.stageCopy("Assets/a.txt", toDirectory: "New")
        XCTAssertEqual(try m.readData("New/a.txt"), Data("hello".utf8))
        XCTAssertThrowsError(try m.stageCopy("Assets", toDirectory: "Assets", name: "inner"))   // into itself
        try m.stageMove("New/a.txt", toDirectory: "", name: "b.txt")
        XCTAssertTrue(m.exists("b.txt")); XCTAssertFalse(m.exists("New/a.txt"))
        let z = try m.stageZip("Assets", intoDirectory: "")
        XCTAssertEqual(z, "Assets.zip")
        let dir = try m.stageUnzip("Assets.zip", intoDirectory: "")
        XCTAssertEqual(try m.readData(dir + "/Assets/a.txt"), Data("hello".utf8))
        XCTAssertTrue(m.search("a.txt", content: false).contains { $0.path == "b.txt" })
        XCTAssertTrue(m.search("hell", content: true).contains { $0.line == 1 })
    }
    func testProtectedItemsCannotBeMovedOrOverwrittenByCopy() throws {
        let m = try bundle()
        XCTAssertThrowsError(try m.stageMove("Main", toDirectory: "Assets"))
        XCTAssertThrowsError(try m.stageCopy("Assets/a.txt", toDirectory: "", name: "info.plist"))
        XCTAssertThrowsError(try m.stageWriteRaw("Info.plist", data: Data()))
    }
    func testHexPatchStaged() throws {
        let m = try bundle()
        var d = try m.readData("Assets/a.txt"); d[0] = 0x4A
        try m.stageWriteRaw("Assets/a.txt", data: d)
        XCTAssertEqual(try m.readData("Assets/a.txt"), Data("Jello".utf8))
    }
}
