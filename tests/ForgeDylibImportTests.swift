import XCTest
@testable import Mirsa

final class ForgeDylibImportTests: XCTestCase {
    private func thin() -> Data {
        var result = Data()
        for word: UInt32 in [0xfeedfacf, 0x0100000c, 0, 6, 0, 0, 0, 0] {
            var value = word.littleEndian
            result.append(withUnsafeBytes(of: &value) { Data($0) })
        }
        return result
    }
    private func temporary(_ ext: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension(ext)
    }
    private func ar(_ tar: Data) -> Data {
        let header = "data.tar/".padding(toLength: 16, withPad: " ", startingAt: 0) +
            "0".padding(toLength: 12, withPad: " ", startingAt: 0) +
            "0     0     100644  " +
            String(tar.count).padding(toLength: 10, withPad: " ", startingAt: 0) + "`\n"
        var data = Data("!<arch>\n".utf8) + Data(header.utf8) + tar
        if tar.count % 2 != 0 { data.append(10) }
        return data
    }
    private func maliciousTar(path: String, type: UInt8 = 48, size: Int = 0) -> Data {
        var h = [UInt8](repeating: 0, count: 512)
        func put(_ string: String, _ offset: Int, _ limit: Int) {
            for (i, b) in string.utf8.prefix(limit).enumerated() { h[offset + i] = b }
        }
        put(path, 0, 100); put("0000644", 100, 8); put("0000000", 108, 8); put("0000000", 116, 8)
        put(String(format: "%011o", size), 124, 12); put("00000000000", 136, 12)
        put("        ", 148, 8); h[156] = type
        if type == 50 { put("../../escape", 157, 100) }
        put("ustar", 257, 6); put("00", 263, 2)
        let sum = h.reduce(0) { $0 + Int($1) }
        put(String(format: "%06o", sum), 148, 7); h[154] = 0; h[155] = 32
        return Data(h) + Data(repeating: 0, count: 1024)
    }
    func testFileImportPreservesOriginalAndCreatesOwnedTemporaryCopy() async throws {
        let source = temporary("dylib")
        let binary = thin()
        try binary.write(to: source)
        defer { try? FileManager.default.removeItem(at: source) }
        let imported = try await ForgeDylibImporter.fromFile(source)
        defer { try? FileManager.default.removeItem(at: imported.dylib) }
        XCTAssertNotEqual(imported.dylib, source)
        XCTAssertEqual(try Data(contentsOf: source), binary)
        XCTAssertEqual(try Data(contentsOf: imported.dylib), binary)
        XCTAssertEqual(imported.info.arch, "arm64")
    }
    func testMagicNotExtensionSelectsParser() async throws {
        let renamed = temporary("deb")
        try thin().write(to: renamed)
        defer { try? FileManager.default.removeItem(at: renamed) }
        let result = try await ForgeDylibImporter.fromFile(renamed)
        defer { try? FileManager.default.removeItem(at: result.dylib) }
        XCTAssertEqual(result.info.arch, "arm64")
        let package = temporary("dylib")
        try ForgeDeb.build(name: "Test", bundleID: "com.test", dylib: thin()).write(to: package)
        defer { try? FileManager.default.removeItem(at: package) }
        let debResult = try await ForgeDylibImporter.fromFile(package)
        defer { try? FileManager.default.removeItem(at: debResult.dylib) }
        XCTAssertEqual(debResult.info.arch, "arm64")
    }
    func testNonBinaryWithDylibExtensionRejected() async throws {
        let source = temporary("dylib")
        try Data("<html>not a library</html>".utf8).write(to: source)
        defer { try? FileManager.default.removeItem(at: source) }
        do {
            let result = try await ForgeDylibImporter.fromFile(source)
            try? FileManager.default.removeItem(at: result.dylib)
            XCTFail("Non-binary accepted")
        } catch { XCTAssertTrue(error is ForgeDylibImportError) }
    }
    func testDebTraversalSymlinkAndExpansionRejectedWithoutResidue() throws {
        for tar in [maliciousTar(path: "../escape.dylib"), maliciousTar(path: "Library/link.dylib", type: 50),
                    maliciousTar(path: "large.dylib", size: ForgeDylibInspector.maximumBytes + 1)] {
            let workspace = temporary("workspace")
            try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: false)
            defer { try? FileManager.default.removeItem(at: workspace) }
            let package = workspace.appendingPathComponent("package.deb")
            try ar(tar).write(to: package)
            XCTAssertThrowsError(try ForgeDylibDebImport.extract(package, in: workspace))
            XCTAssertFalse(FileManager.default.fileExists(atPath: workspace.appendingPathComponent("extracted").path))
        }
    }
}
