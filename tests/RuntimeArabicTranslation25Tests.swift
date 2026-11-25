import XCTest
@testable import Mirsa

final class RuntimeArabicTranslation25Tests: XCTestCase {
    private final class Translator: RuntimeDictionaryTranslating, @unchecked Sendable {
        private let lock = NSLock()
        private var recorded: [(String, String, [ArabicIPALocalizer.Item])] = []
        let output: Result<RuntimeTranslationPackage, Error>
        let delay: TimeInterval
        let completed: (() -> Void)?
        init(_ output: Result<RuntimeTranslationPackage, Error>, delay: TimeInterval = 0, completed: (() -> Void)? = nil) {
            self.output = output; self.delay = delay; self.completed = completed
        }
        private func record(_ bundle: String, _ revision: String, _ items: [ArabicIPALocalizer.Item]) {
            lock.lock(); defer { lock.unlock() }
            recorded.append((bundle, revision, items))
        }
        var calls: [(String, String, [ArabicIPALocalizer.Item])] {
            lock.lock(); defer { lock.unlock() }; return recorded
        }
        func dictionary(bundleID: String, revision: String, items: [ArabicIPALocalizer.Item]) async throws -> RuntimeTranslationPackage {
            record(bundleID, revision, items)
            // Intentionally ignores cancellation, exercising a late network completion.
            if delay > 0 {
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    DispatchQueue.global().asyncAfter(deadline: .now() + delay) { continuation.resume() }
                }
            }
            defer { completed?() }
            return try output.get()
        }
    }

    private func temp() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }
    private func plist(_ value: [String: Any], _ url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try PropertyListSerialization.data(fromPropertyList: value, format: .binary, options: 0).write(to: url)
    }
    private func synthetic(encrypted: Bool = false) throws -> URL {
        let app = try temp().appendingPathComponent("Generic.app")
        try plist(["CFBundleIdentifier": "org.mirsa.runtime25.generic", "CFBundleExecutable": "Main"],
                  app.appendingPathComponent("Info.plist"))
        var bytes = Data()
        let words: [UInt32] = [0xfeedfacf, 0x0100000c, 0, 2, 1, 24, 0, 0, 0x2c, 24, 0, 0, encrypted ? 1 : 0, 0]
        for word in words {
            var little = word.littleEndian
            withUnsafeBytes(of: &little) { bytes.append(contentsOf: $0) }
        }
        try bytes.write(to: app.appendingPathComponent("Main"))
        try addStrings(app)
        return app
    }
    private func addStrings(_ app: URL) throws {
        try plist(["save": "Save %@", "settings": "Settings", "count": "%d items"],
                  app.appendingPathComponent("en.lproj/Localizable.strings"))
    }
    private func snapshot(_ root: URL) throws -> [String: Data] {
        var result: [String: Data] = [:]
        let files = try XCTUnwrap(FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey]))
        for case let url as URL in files {
            if try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true {
                result[String(url.path.dropFirst(root.path.count))] = try Data(contentsOf: url)
            }
        }
        return result
    }
    private func assertNoRuntime(_ app: URL, file: StaticString = #filePath, line: UInt = #line) throws {
        let files = try snapshot(app)
        XCTAssertFalse(files.keys.contains { $0.contains("MirsaTranslate") || $0.contains("MirsaTranslations") }, file: file, line: line)
        let info = try IPAEditorService.info(in: app)
        let executable = try XCTUnwrap(info["CFBundleExecutable"] as? String)
        let bytes = try Data(contentsOf: app.appendingPathComponent(executable))
        XCTAssertNil(bytes.range(of: Data("MirsaTranslate.dylib".utf8)), file: file, line: line)
    }
    private func realFixture() throws -> (ipa: URL, app: URL, root: URL) {
        // Generated as own-code signed arm64 fixture by native CI, not checked into this tree.
        let fixture = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "SignedFolder24Fixture", withExtension: "ipa"))
        let root = try temp(), unpacked = root.appendingPathComponent("unpacked")
        try IPAEditorService.run("extract", input: fixture, output: unpacked)
        let app = try IPAEditorService.app(in: unpacked)
        try addStrings(app)
        let ipa = root.appendingPathComponent("Original.ipa")
        try IPAEditorService.run("pack", input: unpacked, output: ipa)
        return (ipa, app, root)
    }
    private func grant(bundle: String, revision: String) -> [String: String] {
        ["bundleId": bundle, "revision": revision,
         "token": "mrt1." + String(repeating: "a", count: 64),
         "endpoint": "https://runtime.example.com/translate",
         "expiresAt": ISO8601DateFormatter().string(from: Date().addingTimeInterval(3600))]
    }

    func testEncryptedSkipsDictionaryAndPreservesAllBytes() throws {
        let app = try synthetic(encrypted: true), before = try snapshot(app)
        let translator = Translator(.failure(RuntimeTranslationError.network))
        XCTAssertEqual(RuntimeArabicPipeline.applyBlocking(app: app, translator: translator, dylib: nil), RuntimeArabicText.encrypted)
        XCTAssertTrue(translator.calls.isEmpty)
        XCTAssertEqual(try snapshot(app), before)
        try assertNoRuntime(app)
    }
    func testUnavailableAndFailureNeverMutateOriginal() throws {
        for (error, notice) in [(RuntimeTranslationError.notConfigured, RuntimeArabicText.unavailable),
                                (.network, RuntimeArabicText.failed), (.invalid, RuntimeArabicText.failed)] {
            let app = try synthetic(), before = try snapshot(app)
            let translator = Translator(.failure(error))
            XCTAssertEqual(RuntimeArabicPipeline.applyBlocking(app: app, translator: translator, dylib: nil), notice)
            XCTAssertEqual(translator.calls.count, 1)
            XCTAssertEqual(try snapshot(app), before)
            try assertNoRuntime(app)
        }
        let app = try synthetic(), before = try snapshot(app)
        let translator = Translator(.success(RuntimeTranslationPackage(translations: ["Settings": "الإعدادات"])))
        XCTAssertEqual(RuntimeArabicPipeline.applyBlocking(app: app, translator: translator, dylib: nil), RuntimeArabicText.unavailable)
        XCTAssertEqual(try snapshot(app), before)
    }
    func testDynamicSourcesAndPlaceholderMismatchCannotCreateDictionary() throws {
        let app = try synthetic(), before = try snapshot(app)
        let translator = Translator(.success(RuntimeTranslationPackage(translations: [
            "Save %@": "حفظ", "%d items": "عناصر %n", "Not in this app": "دخيل"
        ])))
        XCTAssertEqual(RuntimeArabicPipeline.applyBlocking(app: app, translator: translator, dylib: nil), RuntimeArabicText.failed)
        XCTAssertEqual(try snapshot(app), before)
        let call = try XCTUnwrap(translator.calls.first)
        XCTAssertEqual(Set(call.2.map(\.text)), Set(["Save %@", "Settings", "%d items"]))
    }
    func testTimeoutLateAsyncResultCannotMutateFilesystem() async throws {
        let app = try synthetic(), before = try snapshot(app)
        let finished = expectation(description: "cancel-insensitive translator returned")
        let translator = Translator(.success(RuntimeTranslationPackage(translations: ["Settings": "الإعدادات"])),
                                    delay: 0.25, completed: { finished.fulfill() })
        let notice = await Task.detached {
            RuntimeArabicPipeline.applyBlocking(app: app, translator: translator, dylib: nil, timeout: 0.01)
        }.value
        XCTAssertEqual(notice, RuntimeArabicText.failed)
        XCTAssertEqual(try snapshot(app), before)
        await fulfillment(of: [finished], timeout: 3)
        // Synchronize after the value-only task has resumed; no staging edits may occur.
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(try snapshot(app), before)
        try assertNoRuntime(app)
    }
    func testOnlineScopeAndExpiryAreValidated() throws {
        let bundle = "org.mirsa.runtime25.generic", revision = "revision-a"
        let valid = grant(bundle: bundle, revision: revision)
        XCTAssertNotNil(RuntimeArabicBackendTranslator.validOnline(valid, bundleID: bundle, revision: revision))
        for (key, value) in [("bundleId", "org.other.app"), ("revision", "revision-b"),
                             ("token", "bootstrap-jwt"), ("endpoint", "http://runtime.example.com"),
                             ("endpoint", "https://127.0.0.1/api"),
                             ("expiresAt", "2000-01-01T00:00:00Z")] {
            var invalid = valid; invalid[key] = value
            XCTAssertNil(RuntimeArabicBackendTranslator.validOnline(invalid, bundleID: bundle, revision: revision), key)
        }
        let app = try synthetic(), before = try snapshot(app)
        let translator = Translator(.success(RuntimeTranslationPackage(translations: [:], online: valid)))
        XCTAssertEqual(RuntimeArabicPipeline.applyBlocking(app: app, translator: translator, dylib: nil), RuntimeArabicText.failed)
        XCTAssertEqual(try snapshot(app), before)
    }
    func testGenericRuntimeInjectionWritesOnlyPerAppSafeDictionaryAndKeepsSourceIPA() throws {
        let fixture = try realFixture(), original = try Data(contentsOf: fixture.ipa)
        let sha = try RuntimeOriginalIPA.pin(fixture.ipa)
        let scan = try RuntimeTranslationScanner.scan(app: fixture.app)
        let info = try IPAEditorService.info(in: fixture.app)
        let bundle = try XCTUnwrap(info["CFBundleIdentifier"] as? String)
        let online = grant(bundle: bundle, revision: scan.revision)
        let translator = Translator(.success(RuntimeTranslationPackage(translations: [
            "Save %@": "حفظ %@", "Settings": "الإعدادات", "%d items": "عناصر",
            "Not in this app": "دخيل"
        ], online: online)))
        let dylib = try XCTUnwrap(RuntimeArabicPipeline.bundledDylib, "Native app resource RuntimeTranslationAssets/MirsaTranslate.dylib is required")
        let en = try Data(contentsOf: fixture.app.appendingPathComponent("en.lproj/Localizable.strings"))
        XCTAssertEqual(RuntimeArabicPipeline.applyBlocking(app: fixture.app, translator: translator, dylib: dylib), ArabicTranslateText.applied)
        let config = fixture.app.appendingPathComponent("Frameworks/MirsaTranslations.json")
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: config)) as? [String: Any])
        let table = try XCTUnwrap(json["translations"] as? [String: String])
        XCTAssertEqual(table["Save %@"], "حفظ %@")
        XCTAssertEqual(table["Settings"], "الإعدادات")
        XCTAssertNil(table["%d items"]); XCTAssertNil(table["Not in this app"])
        XCTAssertEqual(json["revision"] as? String, scan.revision)
        XCTAssertEqual(json["online"] as? [String: String], online)
        XCTAssertEqual(translator.calls.first?.0, bundle)
        XCTAssertEqual(translator.calls.first?.1, scan.revision)
        XCTAssertEqual(try Data(contentsOf: fixture.app.appendingPathComponent("Frameworks/MirsaTranslate.dylib")), try Data(contentsOf: dylib))
        let executable = try XCTUnwrap(info["CFBundleExecutable"] as? String)
        XCTAssertNotNil(try Data(contentsOf: fixture.app.appendingPathComponent(executable)).range(of: Data("MirsaTranslate.dylib".utf8)))
        XCTAssertEqual(try Data(contentsOf: fixture.app.appendingPathComponent("en.lproj/Localizable.strings")), en)
        XCTAssertEqual(try Data(contentsOf: fixture.ipa), original)
        try RuntimeOriginalIPA.verify(fixture.ipa, expected: sha)

        // Toggle off must prepare from immutable library IPA, never the translated staging app.
        var options = PersonalProjectOptions(); options.translateToArabic = false
        let unused = Translator(.failure(RuntimeTranslationError.network))
        let prepared = try PersonalCertificateSigner.prepare(ipa: fixture.ipa, stage: fixture.root.appendingPathComponent("off"),
                                                              options: options, runtimeTranslator: unused)
        XCTAssertTrue(unused.calls.isEmpty)
        XCTAssertNil(ArabicLocalizationPipeline.lastNotice)
        try assertNoRuntime(prepared.app)
        XCTAssertFalse(FileManager.default.fileExists(atPath: prepared.app.appendingPathComponent("Frameworks").path))
        XCTAssertEqual(try Data(contentsOf: fixture.ipa), original)
    }
    func testOriginalSHAAndManifestTamperingFailBeforePrepare() throws {
        let fixture = try realFixture()
        let original = try Data(contentsOf: fixture.ipa)
        let sha = try RuntimeOriginalIPA.pin(fixture.ipa)
        XCTAssertEqual(try RuntimeOriginalIPA.pin(fixture.ipa), sha)
        let manifest = RuntimeOriginalIPA.manifest(for: fixture.ipa)
        let manifestBytes = try Data(contentsOf: manifest)
        try Data((String(repeating: "0", count: 64) + "\n").utf8).write(to: manifest)
        let translator = Translator(.failure(RuntimeTranslationError.network))
        XCTAssertThrowsError(try PersonalCertificateSigner.prepare(ipa: fixture.ipa,
            stage: fixture.root.appendingPathComponent("bad-manifest"), options: .init(), runtimeTranslator: translator)) {
            guard case RuntimeTranslationError.changedOriginal = $0 else { return XCTFail("Unexpected error \($0)") }
        }
        try manifestBytes.write(to: manifest)
        try (original + Data([0])).write(to: fixture.ipa)
        XCTAssertThrowsError(try RuntimeOriginalIPA.verify(fixture.ipa, expected: sha))
        XCTAssertThrowsError(try PersonalCertificateSigner.prepare(ipa: fixture.ipa,
            stage: fixture.root.appendingPathComponent("bad-sha"), options: .init(), runtimeTranslator: translator))
        XCTAssertTrue(translator.calls.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.root.appendingPathComponent("bad-manifest/archive").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.root.appendingPathComponent("bad-sha/archive").path))
    }
}
