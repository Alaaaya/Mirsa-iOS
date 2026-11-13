import XCTest
@testable import Mirsa

final class ForgePortUploaderTests: XCTestCase {
    let base = URL(string: "https://port.example.com/mirsa-port")!
    func testSameOriginRelativeAccepted() {
        XCTAssertNotNil(ForgePortUploader.resolve("?action=port-upload&uploadID=11111111-1111-1111-1111-111111111111", base: base))
    }
    func testExternalOrPathChangeRejected() {
        XCTAssertNil(ForgePortUploader.resolve("https://evil.example.com/x", base: base))
        XCTAssertNil(ForgePortUploader.resolve("//evil.example.com/mirsa-port?x=1", base: base))
        XCTAssertNil(ForgePortUploader.resolve("/other?x=1", base: base))
    }
    func testSHA256OfFile() throws {
        let f = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("abc".utf8).write(to: f); defer { try? FileManager.default.removeItem(at: f) }
        let (h, n) = try ForgePortUploader.sha256(file: f)
        XCTAssertEqual(n, 3)
        XCTAssertEqual(h, "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }
    func testNoBaseConfiguredMeansUnavailable() { XCTAssertNil(ForgePortUploader.base) }
}
