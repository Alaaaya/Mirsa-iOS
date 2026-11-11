import Foundation
import XCTest
import UIKit
import CryptoKit
@testable import Mirsa

/// Mirsa 2.1 attachments contract: client-side rules (URL validation, text files, image normalisation).
final class ChatAttachmentRulesTests: XCTestCase {
    private func problem(_ s: String) -> ChatAttachmentRules.LinkProblem? {
        if case .failure(let p) = ChatAttachmentRules.validateLink(s) { return p }
        return nil
    }

    func testAcceptsPublicHTTPSLinks() {
        XCTAssertNil(problem("https://example.com/docs/page"))
        XCTAssertNil(problem("https://github.com/Alaaaya/Mirsa-iOS/issues/1?x=1#y"))
        XCTAssertNil(problem("https://example.com:443/ok"))
    }

    func testRejectsNonHTTPSCredentialsHostsAndPorts() {
        XCTAssertEqual(problem("http://example.com"), .notHTTPS)
        XCTAssertEqual(problem("ftp://example.com/a"), .notHTTPS)
        XCTAssertEqual(problem("https://user:pw@example.com/"), .credentials)
        XCTAssertEqual(problem("https://127.0.0.1/"), .host)
        XCTAssertEqual(problem("https://[::1]/"), .host)
        XCTAssertEqual(problem("https://localhost/"), .host)
        XCTAssertEqual(problem("https://printer.local/"), .host)
        XCTAssertEqual(problem("https://intranet/"), .host)
        XCTAssertEqual(problem("https://example.com:8443/"), .port)
        XCTAssertEqual(problem(""), .empty)
        XCTAssertEqual(problem("https://example.com/" + String(repeating: "a", count: 2100)), .tooLong)
    }

    func testRejectsExecutableAndArchivePathsIncludingPercentEncoded() {
        for path in ["app.ipa", "App.IPA", "app%2Eipa", "app%252Eipa", "app%2eIPA", "a.apk", "a.zip", "a.deb",
                     "setup.exe", "x.tar.gz", "app.ipa.", "app.ipa;v=1", "dir.zip/readme"] {
            XCTAssertEqual(problem("https://example.com/" + path), .blockedFile, path)
        }
    }

    func testTextFiles() {
        XCTAssertNil(ChatAttachmentRules.textFileProblem(name: "a.json", data: Data("{\"a\":1}".utf8)))
        XCTAssertNil(ChatAttachmentRules.textFileProblem(name: "notes.TXT", data: Data("hello\nworld\t!".utf8)))
        XCTAssertEqual(ChatAttachmentRules.textFileProblem(name: "a.json", data: Data("{".utf8)), .json)
        XCTAssertEqual(ChatAttachmentRules.textFileProblem(name: "a.md", data: Data("x".utf8)), .type)
        XCTAssertEqual(ChatAttachmentRules.textFileProblem(name: "a.txt", data: Data([0x41, 0x01])), .control)
        XCTAssertEqual(ChatAttachmentRules.textFileProblem(name: "a.txt", data: Data([0xFF, 0xFE, 0x41])), .utf8)
        XCTAssertEqual(ChatAttachmentRules.textFileProblem(name: "a.txt", data: Data(repeating: 0x41, count: 262_145)), .size)
    }

    func testImageTargetSizeCapsSidesAndMegapixels() {
        let t = ChatAttachmentRules.imageTargetSize(width: 4032, height: 3024)
        XCTAssertLessThanOrEqual(max(t.width, t.height), 1600)
        XCTAssertLessThanOrEqual(t.width * t.height, 2_560_000)
        let s = ChatAttachmentRules.imageTargetSize(width: 800, height: 600)
        XCTAssertEqual(s.width, 800); XCTAssertEqual(s.height, 600)
        let q = ChatAttachmentRules.imageTargetSize(width: 1600, height: 1600)
        XCTAssertLessThanOrEqual(q.width * q.height, 2_560_000)
    }

    func testNormalizeProducesSmallJPEG() throws {
        let size = CGSize(width: 3000, height: 2400)
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
        let img = UIGraphicsImageRenderer(size: size, format: fmt).image { ctx in
            for i in 0..<300 {
                UIColor(hue: CGFloat(i % 100) / 100, saturation: 0.8, brightness: 0.9, alpha: 1).setFill()
                ctx.fill(CGRect(x: (i * 37) % 3000, y: (i * 53) % 2400, width: 160, height: 120))
            }
        }
        let out = try XCTUnwrap(ChatAttachmentImage.normalize(try XCTUnwrap(img.pngData())))
        let back = try XCTUnwrap(UIImage(data: out))
        let w = Int(back.size.width * back.scale), h = Int(back.size.height * back.scale)
        XCTAssertLessThanOrEqual(out.count, 1_048_576)
        XCTAssertLessThanOrEqual(max(w, h), 1600)
        XCTAssertLessThanOrEqual(w * h, 2_560_000)
        XCTAssertTrue(out.starts(with: [0xFF, 0xD8]))
    }

    func testBinaryFilesExtensionSizeAndSignature() {
        let zip = Data([0x50, 0x4B, 0x03, 0x04, 0, 0, 0, 0])
        let deb = Data("!<arch>\ndebian-binary".utf8)
        let dylib = Data([0xCF, 0xFA, 0xED, 0xFE, 7, 0, 0, 1])
        XCTAssertNil(ChatAttachmentRules.binaryFileProblem(name: "a.zip", data: zip))
        XCTAssertNil(ChatAttachmentRules.binaryFileProblem(name: "a.DEB", data: deb))
        XCTAssertNil(ChatAttachmentRules.binaryFileProblem(name: "libx.dylib", data: dylib))
        XCTAssertEqual(ChatAttachmentRules.binaryFileProblem(name: "a.zip", data: deb), .signature)
        XCTAssertEqual(ChatAttachmentRules.binaryFileProblem(name: "a.ipa", data: zip), .type)
        XCTAssertEqual(ChatAttachmentRules.binaryFileProblem(name: "a.zip", data: Data()), .binarySize)
        var big = zip; big.append(Data(count: 5_242_880 - zip.count))
        XCTAssertNil(ChatAttachmentRules.binaryFileProblem(name: "a.zip", data: big))
        big.append(0)
        XCTAssertEqual(ChatAttachmentRules.binaryFileProblem(name: "a.zip", data: big), .binarySize)
        XCTAssertEqual(ChatAttachmentRules.binaryMaxBytes, 5_242_880)
        XCTAssertEqual(ChatAttachmentRules.binaryMime(forName: "x.zip"), "application/zip")
        XCTAssertEqual(ChatAttachmentRules.binaryMime(forName: "x.deb"), "application/vnd.debian.binary-package")
        XCTAssertEqual(ChatAttachmentRules.binaryMime(forName: "x.dylib"), "application/x-mach-binary")
        XCTAssertEqual(ChatAttachmentRules.textMaxBytes, 262_144)
        XCTAssertEqual(ChatAttachmentRules.imageMaxBytes, 1_048_576)
        XCTAssertFalse(MirsaFeatures.binaryAttachmentsEnabled)
    }

    func testSendIDsAreUniqueAndAtMostThree() {
        let ids = (0..<5).map { _ in UUID() }
        XCTAssertEqual(ChatAttachmentRules.sendIDs(ids + ids), Array(ids.prefix(3)))
    }

    @MainActor func testFeatureUsesVerifiedProductionAndFixturesStayOffline() {
        XCTAssertTrue(MirsaFeatures.chatAttachments21)
        XCTAssertEqual(ChatAttachmentConfig.productionBaseURL, ForgeClient.endpoint)
        XCTAssertEqual(ChatAttachmentConfig.productionBaseURL.absoluteString,
                       "https://hirebeofomiyumwysppj.supabase.co/functions/v1/mirsa-forge")
        if ForgeChatStore.fixture {
            XCTAssertNil(ChatAttachmentConfig.endpoint)
        } else {
            XCTAssertEqual(ChatAttachmentConfig.endpoint, ChatAttachmentConfig.productionBaseURL)
        }
    }

    func testBinaryReadIsVerifiedBySizeHashMimeAndMagic() throws {
        let zip = Data([0x50, 0x4B, 0x03, 0x04]) + Data(repeating: 7, count: 60)
        let sha = SHA256.hash(data: zip).map { String(format: "%02x", $0) }.joined()
        func meta(size: Int64? = 64, sha256: String? = sha, mime: String? = "application/zip") -> ChatAttachmentMeta {
            ChatAttachmentMeta(id: UUID(), kind: "file", name: "a.zip", mime: mime, size: size, sha256: sha256, expiresAt: nil, available: true, url: nil)
        }
        XCTAssertNoThrow(try AttachmentUploader.verifyBinary(zip, mime: "application/zip", meta: meta()))
        XCTAssertThrowsError(try AttachmentUploader.verifyBinary(zip, mime: "application/zip", meta: nil))
        XCTAssertThrowsError(try AttachmentUploader.verifyBinary(zip, mime: "application/zip", meta: meta(size: 63)))
        XCTAssertThrowsError(try AttachmentUploader.verifyBinary(zip, mime: "application/zip", meta: meta(sha256: String(repeating: "0", count: 64))))
        XCTAssertThrowsError(try AttachmentUploader.verifyBinary(zip, mime: "application/zip", meta: meta(sha256: nil)))
        XCTAssertThrowsError(try AttachmentUploader.verifyBinary(zip, mime: "application/zip", meta: meta(mime: "application/x-mach-binary")))
        let fake = Data(repeating: 1, count: 64)
        let fsha = SHA256.hash(data: fake).map { String(format: "%02x", $0) }.joined()
        XCTAssertThrowsError(try AttachmentUploader.verifyBinary(fake, mime: "application/zip", meta: meta(sha256: fsha)))
        XCTAssertEqual(ChatAttachmentRules.binaryMime(forName: "x.ZIP"), "application/zip")
        XCTAssertEqual(ChatAttachmentRules.binaryMime(forName: "x.deb"), "application/vnd.debian.binary-package")
        XCTAssertEqual(ChatAttachmentRules.binaryMime(forName: "x.dylib"), "application/x-mach-binary")
        XCTAssertEqual(ChatAttachmentRules.binaryFileProblem(name: "a.zip", data: Data([0x50, 0x4B, 0x03, 0x04]) + Data(count: ChatAttachmentRules.binaryMaxBytes)), .binarySize)
    }
}
