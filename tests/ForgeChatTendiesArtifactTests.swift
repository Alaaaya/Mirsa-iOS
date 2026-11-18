import XCTest
import CryptoKit
@testable import Mirsa

private final class ForgeWallpaperURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "wallpaper.example.com" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            guard request.value(forHTTPHeaderField: "Authorization") == nil else { throw URLError(.userAuthenticationRequired) }
            let body: Data
            if request.url!.path.contains("invalid") {
                body = Data("not a ZIP archive".utf8)
            } else {
                let url = Bundle(for: ForgeWallpaperURLProtocol.self).url(forResource: "Naruto-Space", withExtension: "tendies")!
                body = try Data(contentsOf: url)
            }
            let status = request.url!.path.contains("expired") ? 410 : 200
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1",
                                           headerFields: ["Content-Length": String(body.count)])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

@MainActor
final class ForgeChatTendiesArtifactTests: XCTestCase {
    private let fixtureHash = "8720c01d9d5f486e03500441b9b75bf202c8147573c45367625143ef1370acf1"
    private func artifact(name: String? = nil, size: Int64? = 1_349_699, hash: String? = nil, kind: String = "tendies") -> ForgeChatArtifact {
        ForgeChatArtifact(id: UUID(), kind: kind, name: name ?? "Chat-\(UUID().uuidString).tendies",
                          size: size, sha256: hash ?? fixtureHash, expiresAt: nil)
    }
    private func configuration() -> URLSessionConfiguration {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ForgeWallpaperURLProtocol.self]
        return config
    }
    private func store(path: String = "real") -> ForgeChatStore {
        ForgeChatStore(testRequest: { body in
            XCTAssertEqual(body["action"] as? String, "chat-artifact-download")
            XCTAssertNotNil(body["threadID"]); XCTAssertNotNil(body["id"])
            return Data("{\"url\":\"https://wallpaper.example.com/\(path)\"}".utf8)
        })
    }
    private func download(_ a: ForgeChatArtifact, path: String = "real") async throws -> URL {
        try await store(path: path).downloadArtifact(threadID: UUID(), artifact: a, progress: { _ in }, configuration: configuration())
    }

    func testActualBackendArtifactDownloadsVerifiesImportsAndPersistsInExistingWallpaperList() async throws {
        let fixture = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "Naruto-Space", withExtension: "tendies"))
        let bytes = try Data(contentsOf: fixture)
        XCTAssertEqual(bytes.count, 1_349_699)
        XCTAssertEqual(SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined(), fixtureHash)
        let oldSaved = UserDefaults.standard.data(forKey: "aircard.saved_tendies")
        defer { UserDefaults.standard.set(oldSaved, forKey: "aircard.saved_tendies") }
        let model = AppViewModel()
        let a = artifact()
        let file = try await download(a)
        XCTAssertEqual(file.lastPathComponent, a.name)
        XCTAssertEqual(try Data(contentsOf: file), bytes)
        let managedDirectory = file.deletingLastPathComponent()
        try await ForgeChatStore.importDownloadedTendies(file, model: model)
        XCTAssertFalse(FileManager.default.fileExists(atPath: managedDirectory.path))
        let item = try XCTUnwrap(model.tendieItems.first { $0.fileName == a.name })
        defer { try? FileManager.default.removeItem(at: item.fileURL) }
        XCTAssertTrue(FileManager.default.fileExists(atPath: item.fileURL.path))
        XCTAssertEqual(try Data(contentsOf: item.fileURL), bytes)
        let saved = try XCTUnwrap(UserDefaults.standard.data(forKey: "aircard.saved_tendies"))
        XCTAssertTrue(try JSONDecoder().decode([TendieItem].self, from: saved).contains { $0.id == item.id })
        model.tendieItems = []
        model.loadSavedTendies()
        XCTAssertTrue(model.tendieItems.contains { $0.id == item.id })
    }

    func testCorruptSizeHashAndExpiredDownloadNeverReachLibraryImport() async throws {
        for (a, path) in [(artifact(size: 1), "real"), (artifact(hash: String(repeating: "0", count: 64)), "real"),
                          (artifact(), "expired")] {
            do {
                let file = try await download(a, path: path)
                MirsaManagedTmp.end(file.deletingLastPathComponent())
                XCTFail("Invalid or expired wallpaper was accepted")
            } catch {}
        }
    }

    func testMissingIntegrityMetadataFailsBeforeRequest() async {
        var calls = 0
        let s = ForgeChatStore(testRequest: { _ in calls += 1; return Data() })
        let noHash = ForgeChatArtifact(id: UUID(), kind: "tendies", name: "x.tendies", size: 42, sha256: nil, expiresAt: nil)
        for a in [noHash, artifact(size: nil), artifact(size: 0), artifact(hash: "not-a-sha256")] {
            do {
                _ = try await s.downloadArtifact(threadID: UUID(), artifact: a, progress: { _ in }, configuration: configuration())
                XCTFail("Unverifiable wallpaper accepted")
            } catch {}
        }
        XCTAssertEqual(calls, 0)
    }

    func testImportWithoutModelFailsAndCleansDownloadedFile() async throws {
        let file = try await download(artifact())
        let dir = file.deletingLastPathComponent()
        do { try await ForgeChatStore.importDownloadedTendies(file, model: nil); XCTFail("Missing model silently succeeded") } catch {}
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.path))
    }

    func testInvalidArchiveDoesNotAddWallpaperAndCleansDownload() async throws {
        let body = Data("not a ZIP archive".utf8)
        let hash = SHA256.hash(data: body).map { String(format: "%02x", $0) }.joined()
        let oldSaved = UserDefaults.standard.data(forKey: "aircard.saved_tendies")
        defer { UserDefaults.standard.set(oldSaved, forKey: "aircard.saved_tendies") }
        let model = AppViewModel()
        let before = model.tendieItems.map(\.id)
        let file = try await download(artifact(size: Int64(body.count), hash: hash), path: "invalid")
        let dir = file.deletingLastPathComponent()
        do { try await ForgeChatStore.importDownloadedTendies(file, model: model); XCTFail("Invalid ZIP imported") } catch {}
        XCTAssertEqual(model.tendieItems.map(\.id), before)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.path))
    }

    func testSafeFilenameKeepsWallpaperNameWithoutDirectoryTraversal() {
        for name in ["../../Outside.tendies", "C:\\tmp\\Outside.tendies", "/absolute/Outside.tendies"] {
            XCTAssertEqual(ForgeChatStore.safeTendiesName(artifact(name: name)), "Outside.tendies")
        }
        let hidden = artifact(name: ".hidden.tendies")
        XCTAssertTrue(ForgeChatStore.safeTendiesName(hidden).hasPrefix("Wallpaper-"))
        XCTAssertEqual(ForgeChatStore.safeTendiesName(artifact(name: "name.zip")), "name.tendies")
        XCTAssertLessThanOrEqual(ForgeChatStore.safeTendiesName(artifact(name: String(repeating: "x", count: 200))).count, 88)
    }

    func testAddWallpaperLabelInAllFiveAppLanguages() {
        let old = AppLanguageStore.shared.current
        defer { AppLanguageStore.shared.set(old) }
        let labels: [(AppLanguage, String)] = [
            (.arabic, "أضف للخلفيات"), (.english, "Add to wallpapers"), (.german, "Zu Hintergründen hinzufügen"),
            (.sorani, "زیادکردن بۆ وەڵپەیپەرەکان"), (.kurmanji, "Li wallpaperan zêde bike")
        ]
        for (language, label) in labels {
            AppLanguageStore.shared.set(language)
            XCTAssertEqual(ForgeChatText.addWallpaper, label)
        }
    }
}
