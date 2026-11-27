import XCTest
import CryptoKit
@testable import Mirsa

/// Inert public-label fixtures exercise the real HTTP byte stream, never the network.
private final class RuntimeRefreshCapProtocol27: URLProtocol {
    static let bundleID = "com.mirsa.refresh.cap.fixture"
    static let revision = String(repeating: "a", count: 64)
    static func dictionary(count: Int = 910) throws -> Data {
        let entries: [[String: Any]] = (0..<count).map { index in
            ["source": "Menu item \(index) with more public interface context before confirming selection",
             "translation": "خيار من قائمة التطبيق لعرض تفاصيل العنصر المحدد",
             "version": 1, "provenance": "kat"]
        }
        return try JSONSerialization.data(withJSONObject: [
            "bundleId": bundleID, "revision": revision, "entries": entries
        ], options: [.sortedKeys])
    }
    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "runtime-cap.example.invalid"
    }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let path = request.url!.path
            let data: Data
            if path.contains("oversized") { data = Data(repeating: 32, count: 8 * 1_048_576 + 1) }
            else { data = try Self.dictionary(count: path.contains("ten-thousand") ? 10_000 : 910) }
            var headers: [String: String] = ["Content-Type": "application/json"]
            if path.contains("known") && !path.contains("unknown") {
                headers["Content-Length"] = String(data.count)
            } else if path.contains("understated") {
                headers["Content-Length"] = "1"
            }
            let response = HTTPURLResponse(url: request.url!, statusCode: 200,
                                           httpVersion: "HTTP/1.1", headerFields: headers)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            for start in stride(from: 0, to: data.count, by: 4096) {
                client?.urlProtocol(self, didLoad: data.subdata(in: start..<min(start + 4096, data.count)))
            }
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

final class RuntimeArabicTranslation25Tests: XCTestCase {
    private func capConfiguration27() -> URLSessionConfiguration {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [RuntimeRefreshCapProtocol27.self]
        return config
    }


    func testStageDiagnosticsDoNotLeakPathsTokensOrSourceLabels() {
        let privateMessage = "private-path/private-token/private-ui-label"
        for stage in RuntimeTranslationStage.allCases {
            let error = NSError(domain: privateMessage, code: 7,
                                userInfo: [NSLocalizedDescriptionKey: privateMessage])
            let notice = RuntimeArabicPipeline.failure(RuntimeTranslationStageError.at(error, stage)).localizedDescription
            XCTAssertEqual(notice, stage.notice + "\n[" + stage.code + "]")
            XCTAssertFalse(notice.contains(privateMessage))
            let nativeError = RuntimeArabicPipeline.failure(RuntimeTranslationStageError.at(
                SideloadError.message(privateMessage), stage)).localizedDescription
            XCTAssertEqual(nativeError, stage.notice + "\n[" + stage.code + "]")
            XCTAssertFalse(nativeError.contains(privateMessage))
        }
        let auth = RuntimeArabicPipeline.failure(RuntimeTranslationStageError.at(
            URLError(.timedOut), .auth)).localizedDescription
        XCTAssertTrue(auth.contains("[RT27-AUTH URL -1001]"))
        let throttled = RuntimeArabicPipeline.failure(RuntimeTranslationStageError.at(
            RuntimeTranslationError.httpStatus(429), .issue)).localizedDescription
        XCTAssertTrue(throttled.contains("[RT27-ISSUE HTTP 429]"))
        let authThrottle = RuntimeArabicPipeline.failure(RuntimeTranslationStageError.at(
            DiscoveryAuthError.httpStatus(429), .auth)).localizedDescription
        XCTAssertEqual(authThrottle, RuntimeTranslationStage.auth.notice + "\n[RT27-AUTH HTTP 429]")
        let nested = RuntimeTranslationStageError.at(
            RuntimeTranslationStageError.at(RuntimeTranslationError.invalid, .canonical), .dictionary)
        XCTAssertTrue(RuntimeArabicPipeline.failure(nested).localizedDescription.contains("[RT27-CANONICAL]"))
    }

    func testLocalScanFailureHasStageCodeAndNeverCallsTranslator() throws {
        let app = try synthetic(), before = try snapshot(app)
        var info = try IPAEditorService.info(in: app)
        info["CFBundleExecutable"] = "../outside-private-app"
        try PropertyListSerialization.data(fromPropertyList: info, format: .binary, options: 0)
            .write(to: app.appendingPathComponent("Info.plist"))
        let pinned = try snapshot(app)
        let translator = Translator(.failure(RuntimeTranslationError.network))
        let notice = try XCTUnwrap(RuntimeArabicPipeline.applyBlocking(app: app, translator: translator, dylib: nil))
        XCTAssertTrue(notice.contains("[RT27-SCAN APP]"))
        XCTAssertTrue(translator.calls.isEmpty)
        XCTAssertFalse(notice.contains("outside-private-app"))
        XCTAssertEqual(try snapshot(app), pinned)
        XCTAssertNotEqual(pinned, before)
    }

    func testFullCanonicalRefreshAccepts200KBDictionaryWithAndWithoutContentLength() async throws {
        let fixture = try RuntimeRefreshCapProtocol27.dictionary()
        XCTAssertGreaterThanOrEqual(fixture.count, 200_000)
        XCTAssertLessThan(fixture.count, 250_000)
        for path in ["known", "unknown", "understated"] {
            let response = try await RuntimeTranslationHTTP().post(
                URL(string: "https://runtime-cap.example.invalid/\(path)")!, token: "inert-fixture",
                object: ["action": "refresh"], configuration: capConfiguration27())
            let canonical = try RuntimeArabicBackendTranslator.canonicalDictionary(response,
                bundleID: RuntimeRefreshCapProtocol27.bundleID, revision: RuntimeRefreshCapProtocol27.revision)
            XCTAssertEqual(canonical.translations.count, 910)
            XCTAssertEqual(canonical.translations[
                "Menu item 909 with more public interface context before confirming selection"],
                "خيار من قائمة التطبيق لعرض تفاصيل العنصر المحدد")
        }
    }

    func testFullCanonicalRefreshAcceptsTenThousandEntriesAboveOneMiB() async throws {
        let fixture = try RuntimeRefreshCapProtocol27.dictionary(count: 10_000)
        XCTAssertGreaterThan(fixture.count, 1_048_576)
        XCTAssertLessThan(fixture.count, 8 * 1_048_576)
        for path in ["ten-thousand-known", "ten-thousand-unknown"] {
            let response = try await RuntimeTranslationHTTP().post(
                URL(string: "https://runtime-cap.example.invalid/\(path)")!, token: "inert-fixture",
                object: ["action": "refresh"], configuration: capConfiguration27())
            let canonical = try RuntimeArabicBackendTranslator.canonicalDictionary(response,
                bundleID: RuntimeRefreshCapProtocol27.bundleID, revision: RuntimeRefreshCapProtocol27.revision)
            XCTAssertEqual(canonical.translations.count, 10_000)
            XCTAssertEqual(canonical.translations[
                "Menu item 9999 with more public interface context before confirming selection"],
                "خيار من قائمة التطبيق لعرض تفاصيل العنصر المحدد")
        }
    }

    func testRefreshRejectsOverEightMiBByDeclaredAndActualStreamLength() async {
        for path in ["oversized-known", "oversized-unknown", "oversized-understated"] {
            do {
                _ = try await RuntimeTranslationHTTP().post(
                    URL(string: "https://runtime-cap.example.invalid/\(path)")!, token: "inert-fixture",
                    object: ["action": "refresh"], configuration: capConfiguration27())
                XCTFail("Refresh larger than 8 MiB must be rejected")
            } catch RuntimeTranslationError.invalid { }
            catch { XCTFail("Expected bounded response rejection, got \(error)") }
        }
    }

    func testNonRefreshResponsesKeep48KiBCap() async {
        for action in ["issue", "dictionary", "missing"] {
            for path in ["known", "unknown"] {
                do {
                    _ = try await RuntimeTranslationHTTP().post(
                        URL(string: "https://runtime-cap.example.invalid/\(path)")!, token: "inert-fixture",
                        object: ["action": action], configuration: capConfiguration27())
                    XCTFail("Non-refresh responses must retain the 48 KiB cap")
                } catch RuntimeTranslationError.invalid { }
                catch { XCTFail("Expected bounded response rejection, got \(error)") }
            }
        }
    }

    func testRefreshRequestsStillKeep48KiBCap() async {
        do {
            _ = try await RuntimeTranslationHTTP().post(
                URL(string: "https://runtime-cap.example.invalid/known")!, token: "inert-fixture",
                object: ["action": "refresh", "padding": String(repeating: "x", count: 49_152)],
                configuration: capConfiguration27())
            XCTFail("A refresh must not raise the request byte cap")
        } catch RuntimeTranslationError.invalid { }
        catch { XCTFail("Expected bounded request rejection, got \(error)") }
    }

    @MainActor
    func testConcurrentSigningWorkersLeaveAsyncDictionaryTasksRunnable() async {
        enum Completion: Error { case finished, timedOut }
        let outcomes = await withTaskGroup(of: Bool.self) { group in
            for _ in 0..<8 {
                group.addTask {
                    do {
                        _ = try await PersonalEncryptionWarning.signWithConsent { _ in
                            let ready = DispatchSemaphore(value: 0)
                            Task.detached {
                                try? await Task.sleep(nanoseconds: 50_000_000)
                                ready.signal()
                            }
                            guard ready.wait(timeout: .now() + 6) == .success else {
                                throw Completion.timedOut
                            }
                            throw Completion.finished
                        }
                        return false
                    } catch Completion.finished { return true }
                    catch { return false }
                }
            }
            var values: [Bool] = []
            for await outcome in group { values.append(outcome) }
            return values
        }
        XCTAssertEqual(outcomes.count, 8)
        XCTAssertTrue(outcomes.allSatisfy { $0 }, "Blocking signing workers must not starve async dictionary work")
    }

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

    @MainActor
    func testRealImporterBarrierBlocksImmediateSignAndMissingSelectedIDFails() async throws {
        let library = IPATweakLibrary.shared, intake = PersonalProjectIntake()
        let fixture = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "GenericMarker25", withExtension: "dylib"))
        let entered = expectation(description: "production importer suspended")
        var resume: CheckedContinuation<Void, Never>?
        library.importBarrierForTesting = {
            await withCheckedContinuation { continuation in resume = continuation; entered.fulfill() }
        }
        defer { library.importBarrierForTesting = nil }
        var imported: IPATweak?, failure: Error?
        let task = intake.beginImport(fixture, library: library) { result in
            switch result {
            case .success(let value): imported = value
            case .failure(let error): failure = error
            }
        }
        // No yield before this assertion: this is the original picker/sign race.
        XCTAssertThrowsError(try intake.requireReady(loaded: true, library: library))
        await fulfillment(of: [entered], timeout: 5)
        XCTAssertTrue(library.importing)
        XCTAssertThrowsError(try intake.requireReady(loaded: true, library: library))
        resume?.resume()
        await task.value
        XCTAssertNil(failure)
        XCTAssertNotNil(imported)
        XCTAssertNoThrow(try intake.requireReady(loaded: true, library: library))
        XCTAssertThrowsError(try intake.requireReady(loaded: false, library: library))
        XCTAssertThrowsError(try library.urls(for: Set([UUID()])))
    }

    /// All fixtures are Mirsa-owned, inert device Mach-O data, never launched here.
    /// Covers the exact prepare -> dispatch -> Rust signer -> pack -> retain chain.
    func testGenericDirectLoaderAndHookDependencyUseExactProductionAttempt() throws {
        let fixture = try realFixture(name: "GenericLaunch25Fixture"), bundle = Bundle(for: Self.self)
        let mainExecutable = try XCTUnwrap(IPAEditorService.info(in: fixture.app)["CFBundleExecutable"] as? String)
        let material = PersonalIdentityVault.Material(
            p12: try Data(contentsOf: XCTUnwrap(bundle.url(forResource: "LCSignSynthetic", withExtension: "p12"))),
            password: "mirsa-test",
            profile: try Data(contentsOf: XCTUnwrap(bundle.url(forResource: "LCSignSynthetic", withExtension: "mobileprovision"))))
        let marker = try XCTUnwrap(bundle.url(forResource: "GenericMarker25", withExtension: "dylib"))
        let hook = try XCTUnwrap(bundle.url(forResource: "GenericHookMarker25", withExtension: "dylib"))
        let original = try RuntimeOriginalIPA.hash(fixture.ipa)
        var attempts = Set<UUID>()
        for (source, method) in [(marker, InjectionMethod.direct), (marker, .load_control), (hook, .load_control)] {
            var options = PersonalProjectOptions()
            options.libraries = [source]
            options.selectedComponentIDs = ["fixture:" + source.lastPathComponent]
            options.draftRevision = "original-draft"
            options.injections = [InjectionPlanEntry(id: options.selectedComponentIDs[0], library: source.path, target: mainExecutable, method: method)]
            let result = try PersonalCertificateSigner.sign(ipa: fixture.ipa, material: material, pairingPath: "", options: options)
            try PersonalInjectionProof.verifyRecord(result.url)
            let proof = try JSONDecoder().decode(PersonalInjectionProof.Attempt.self,
                                                from: Data(contentsOf: PersonalInjectionProof.sidecar(result.url)))
            XCTAssertEqual(proof.attemptID, options.attemptID)
            XCTAssertTrue(attempts.insert(proof.attemptID).inserted)
            XCTAssertEqual(proof.sourceSHA256, original)
            XCTAssertEqual(proof.componentSHA256.values.first, try RuntimeOriginalIPA.hash(source))
            XCTAssertEqual(proof.selectedComponentIDs, options.selectedComponentIDs)
            XCTAssertFalse(proof.installed.dependencies.isEmpty)
            XCTAssertTrue(proof.installed.dependencies.keys.contains { $0.hasSuffix(source.lastPathComponent) })
            if method == .load_control {
                XCTAssertTrue(proof.installed.resources.keys.contains { $0.hasSuffix("MirsaLoadOrder.txt") })
                XCTAssertTrue(proof.installed.dependencies.values.contains { $0.contains("@loader_path/Frameworks/MirsaLoader.dylib") })
            }
            if source == hook {
                XCTAssertTrue(proof.installed.dependencies.keys.contains { $0.hasSuffix("CydiaSubstrate.framework/CydiaSubstrate") })
            }
            let mode = source == hook ? "HOOK" : (method == .load_control ? "LOADER" : "DIRECT")
            let proofDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("RuntimeSigningProof25")
            try FileManager.default.createDirectory(at: proofDir, withIntermediateDirectories: true)
            let proofIPA = proofDir.appendingPathComponent("GENERIC-" + mode + ".ipa")
            try? FileManager.default.removeItem(at: proofIPA)
            try FileManager.default.copyItem(at: result.url, to: proofIPA)
            try Data(contentsOf: PersonalInjectionProof.sidecar(result.url)).write(to: PersonalInjectionProof.sidecar(proofIPA))
            // Changing the next draft cannot relabel this output's immutable evidence.
            options.selectedComponentIDs = ["different-draft"]
            options.draftRevision = "different-draft"
            let retained = try CertificateInstall.retain(result.url)
            defer { try? FileManager.default.removeItem(at: retained.deletingLastPathComponent()) }
            try PersonalInjectionProof.verifyRecord(retained)
            let retainedProof = try JSONDecoder().decode(PersonalInjectionProof.Attempt.self,
                from: Data(contentsOf: PersonalInjectionProof.sidecar(retained)))
            XCTAssertEqual(retainedProof.selectedComponentIDs, proof.selectedComponentIDs)
            XCTAssertEqual(retainedProof.draftRevision, "original-draft")
            let extracted = fixture.root.appendingPathComponent(UUID().uuidString)
            try IPAEditorService.run("extract", input: retained, output: extracted)
            let app = try IPAEditorService.app(in: extracted)
            try PersonalInjectionProof.verify(proof.installed, app: app)
            let injected = app.appendingPathComponent("Frameworks/" + source.lastPathComponent)
            try FileManager.default.removeItem(at: injected)
            XCTAssertThrowsError(try PersonalInjectionProof.verify(proof.installed, app: app))
            // Archive mutation cannot pass retained/shared/OTA evidence validation.
            let handle = try FileHandle(forWritingTo: retained)
            try handle.seekToEnd(); try handle.write(contentsOf: Data([0])); try handle.close()
            XCTAssertThrowsError(try PersonalInjectionProof.verifyRecord(retained))
        }
        XCTAssertEqual(try RuntimeOriginalIPA.hash(fixture.ipa), original)
    }

    func testExactAlaaAndMirsaHookTestUseRealSigningAndPinnedPayloads() throws {
        let fixture = try realFixture(name: "ExactLaunch25Fixture"), bundle = Bundle(for: Self.self)
        let mainExecutable = try XCTUnwrap(IPAEditorService.info(in: fixture.app)["CFBundleExecutable"] as? String)
        let material = PersonalIdentityVault.Material(
            p12: try Data(contentsOf: XCTUnwrap(bundle.url(forResource: "LCSignSynthetic", withExtension: "p12"))),
            password: "mirsa-test",
            profile: try Data(contentsOf: XCTUnwrap(bundle.url(forResource: "LCSignSynthetic", withExtension: "mobileprovision"))))
        let proofDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("RuntimeSigningProof25")
        try FileManager.default.createDirectory(at: proofDir, withIntermediateDirectories: true)
        for (mode, name, expected) in [
            ("ALAA", "Alaa", "04afc06b8a95d5ef1761bfa221bd1386f8762452970226d3c1ff64a4642d6565"),
            ("HOOK", "MirsaHookTest", "58e1161b49abb5ff332d6d9a368ab2d04c83a67d904b4cd5e92360b807b88997")
        ] {
            let source = try XCTUnwrap(bundle.url(forResource: name, withExtension: "dylib"))
            XCTAssertEqual(try RuntimeOriginalIPA.hash(source), expected)
            var options = PersonalProjectOptions()
            options.libraries = [source]; options.selectedComponentIDs = ["exact:" + name]
            options.draftRevision = "exact-original-draft"
            options.injections = [InjectionPlanEntry(id: options.selectedComponentIDs[0], library: source.path, target: mainExecutable, method: .load_control)]
            let result = try PersonalCertificateSigner.sign(ipa: fixture.ipa, material: material, pairingPath: "", options: options)
            try PersonalInjectionProof.verifyRecord(result.url)
            let attempt = try JSONDecoder().decode(PersonalInjectionProof.Attempt.self,
                from: Data(contentsOf: PersonalInjectionProof.sidecar(result.url)))
            XCTAssertEqual(Array(attempt.componentSHA256.values), [expected])
            XCTAssertTrue(attempt.installed.dependencies.keys.contains { $0.hasSuffix(name + ".dylib") })
            if mode == "HOOK" {
                XCTAssertTrue(attempt.installed.dependencies.keys.contains { $0.hasSuffix("CydiaSubstrate.framework/CydiaSubstrate") })
            }
            let output = proofDir.appendingPathComponent("EXACT-" + mode + ".ipa")
            try? FileManager.default.removeItem(at: output)
            try FileManager.default.copyItem(at: result.url, to: output)
            try Data(contentsOf: PersonalInjectionProof.sidecar(result.url)).write(to: PersonalInjectionProof.sidecar(output))
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
    private func realFixture(name: String = "SignedFolder24Fixture") throws -> (ipa: URL, app: URL, root: URL) {
        // Generated as own-code signed arm64 fixture by native CI, not checked into this tree.
        let fixture = try XCTUnwrap(Bundle(for: Self.self).url(forResource: name, withExtension: "ipa"))
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
         "activation": "fixture.payload.signature", "installationId": "11111111-1111-4111-8111-111111111111",
         "endpoint": "https://runtime.example.com/translate",
         "expiresAt": ISO8601DateFormatter().string(from: Date().addingTimeInterval(3600))]
    }

    func testKatOnlyQueuedSigningResponseRequiresExactPersistedScopedReceipt() {
        let bundle = "org.mirsa.test.kat-only", revision = String(repeating: "a", count: 64)
        let sources = ["Settings", "Save %@"]
        let entries: [[String: Any]] = sources.map { source in
            ["source": source, "labelId": UUID().uuidString, "reviewId": UUID().uuidString,
             "version": 1, "kind": "missing"]
        }
        let good: [String: Any] = ["bundleId": bundle, "revision": revision,
            "translations": [String: String](), "deferred": "kat_review_required",
            "queue": ["persisted": true, "entries": entries]]
        func accepted(_ value: [String: Any]) -> Bool {
            RuntimeArabicBackendTranslator.acceptedDeferredReceipt(value, bundleID: bundle,
                revision: revision, sources: sources) != nil
        }
        XCTAssertTrue(accepted(good))
        for key in ["queue", "deferred", "bundleId", "revision", "translations"] {
            var missing = good; missing.removeValue(forKey: key)
            XCTAssertFalse(accepted(missing), key)
        }
        for (key, value) in [("bundleId", "org.other.app"), ("revision", "other-revision"),
                             ("deferred", "unreviewed_fallback")] {
            var bad = good; bad[key] = value
            XCTAssertFalse(accepted(bad), key)
        }
        var unpersisted = good; unpersisted["queue"] = ["persisted": false, "entries": entries]
        XCTAssertFalse(accepted(unpersisted))
        var wrongSources = entries; wrongSources[0]["source"] = "Private unrelated source"
        var mismatched = good; mismatched["queue"] = ["persisted": true, "entries": wrongSources]
        XCTAssertFalse(accepted(mismatched))
        var missingEntry = good; missingEntry["queue"] = ["persisted": true, "entries": [entries[0]]]
        XCTAssertFalse(accepted(missingEntry))
        for key in ["labelId", "reviewId", "version", "kind"] {
            var invalidEntries = entries; invalidEntries[0].removeValue(forKey: key)
            var invalid = good; invalid["queue"] = ["persisted": true, "entries": invalidEntries]
            XCTAssertFalse(accepted(invalid), key)
        }
        // This helper is the SAME guard used by dictionary() before the signing
        // pipeline can package an empty online table. Full live staging signing
        // remains covered by testRealProductionSigningAutoActivatesFromCurrentAccountAndOffDoesNotInject.
    }

    func testActivationClaimsUseTheirOwnRealmAndKeepAccountBinding() throws {
        let account = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
        let capability = "mrt1." + String(repeating: "a", count: 64)
        let hash = SHA256.hash(data: Data(capability.utf8)).map { String(format: "%02x", $0) }.joined()
        var claims: [String: String] = ["sub": account.uuidString.lowercased(),
            "iss": "urn:mirsa:translation25", "aud": "mirsa-translated-app",
            "bundleId": "org.mirsa.test", "revision": String(repeating: "a", count: 64),
            "installationId": "installation", "capHash": hash]
        func accepted() throws -> Bool {
            let body = try JSONSerialization.data(withJSONObject: claims).base64EncodedString()
                .replacingOccurrences(of: "=", with: "").replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            return RuntimeArabicBackendTranslator().activationScope("header." + body + ".signature",
                account: account, bundle: "org.mirsa.test", revision: String(repeating: "a", count: 64),
                installation: "installation", capability: capability)
        }
        XCTAssertTrue(try accepted(), "Activation is not an authenticated user JWT")
        for key in ["sub", "iss", "aud", "bundleId", "revision", "installationId", "capHash"] {
            let saved = claims[key]; claims[key] = "wrong"
            XCTAssertFalse(try accepted(), key)
            claims[key] = saved
        }
    }

    /// CI readiness only: the cold simulator/edge connection must reach request validation.
    /// The deliberately invalid action is rejected before auth, quota or capability writes.
    /// Never retry the real signing operation or weaken its required first issue assertion.
    private func awaitStagingTransportReadiness(_ endpoint: URL) async throws {
        for attempt in 1...3 {
            do {
                _ = try await RuntimeTranslationHTTP().post(endpoint,
                    token: "readiness-without-credentials", object: ["action": "readiness"])
                XCTFail("Invalid readiness action unexpectedly succeeded")
                throw RuntimeTranslationError.invalid
            } catch RuntimeTranslationError.httpStatus(400) {
                print("Simulator staging transport readiness reached validation on attempt \(attempt)")
                return
            } catch let error as URLError where
                Set<URLError.Code>([.timedOut, .networkConnectionLost, .cannotConnectToHost, .notConnectedToInternet]).contains(error.code) {
                guard attempt < 3 else { throw error }
                print("Simulator staging transport readiness retry \(attempt), transport code \(error.code.rawValue)")
                try await Task.sleep(nanoseconds: 500_000_000)
            }
        }
        throw RuntimeTranslationError.network
    }

    /// Kat-only staging intentionally queues unknown source revisions. Prepare the
    /// own-code fixture through the real public protocol, then wait for the private
    /// operator to save Kat-authored canonical entries. No translation/test override
    /// is injected into the production signer below.
    private func awaitCanonicalSigningFixture(_ fixture: (ipa: URL, app: URL, root: URL),
                                              revision: String, endpoint: URL) async throws {
        let info = try IPAEditorService.info(in: fixture.app)
        let id = try XCTUnwrap(info["CFBundleIdentifier"] as? String)
        guard id == "com.alaa.mirsa.ci.signedfolder" else { throw RuntimeTranslationError.invalid }
        let scan = try RuntimeTranslationScanner.scan(app: fixture.app)
        let items = scan.items.filter { RuntimeTranslationScanner.safeText($0.text) }
        let scannedSources = Set(["Settings", "Save %@", "%d items"])
        guard Set(items.map(\.text)) == scannedSources else { throw RuntimeTranslationError.invalid }
        // This entry is intentionally absent from the IPA scan, as if discovered by
        // an earlier runtime session. Production signing must embed it as well.
        let runtimeItem = ArabicIPALocalizer.Item(id: "runtime-menu", text: "Runtime menu")
        let expected = scannedSources.union([runtimeItem.text])
        let queued = try await RuntimeArabicBackendTranslator().dictionary(bundleID: id, revision: revision, items: items + [runtimeItem])
        let online = try XCTUnwrap(queued.online)
        let capability = try XCTUnwrap(online["token"])
        let activation = try XCTUnwrap(online["activation"])
        for _ in 0..<6 {
            try await Task.sleep(nanoseconds: 10_000_000_000)
            let response = try await RuntimeTranslationHTTP().post(endpoint, token: capability, activation: activation,
                object: ["action": "refresh", "consent": true, "bundleId": id, "revision": revision])
            guard response["bundleId"] as? String == id, response["revision"] as? String == revision,
                  let entries = response["entries"] as? [[String: Any]] else { throw RuntimeTranslationError.invalid }
            var canonical: [String: String] = [:]
            for entry in entries {
                guard let source = entry["source"] as? String, let value = entry["translation"] as? String,
                      expected.contains(source),
                      ArabicIPALocalizer.acceptable(source: source, translated: value) else {
                    XCTFail("Scoped signing fixture refresh has invalid source/value schema or placeholders")
                    throw RuntimeTranslationError.invalid
                }
                // Historical provider entries are not Kat approval. Wait for the
                // canonical CAS review instead of treating pending review as corruption.
                guard entry["provenance"] as? String == "kat" else { continue }
                canonical[source] = value
            }
            if Set(canonical.keys) == expected {
                // Fixture setup has its own quota window. Keep the real per-minute
                // service limits unchanged for the subsequent production/network tests.
                try await Task.sleep(nanoseconds: 61_000_000_000)
                print("Exact Kat-only scoped signing fixture is canonical and ready")
                return
            }
        }
        XCTFail("Kat-only signing fixture was not canonically reviewed before production signing")
        throw RuntimeTranslationError.timeout
    }

    /// No injected translator, endpoint or manual staging session. The same app account,
    /// prepare -> Rust personal_sign -> post-sign verification -> pack path as the UI.
    func testRealProductionSigningAutoActivatesFromCurrentAccountAndOffDoesNotInject() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let token = env["MIRSA_RT_STAGING_TOKEN"], !token.isEmpty else {
            if env["MIRSA_RT_REQUIRED_STAGING"] == "1" { XCTFail("Required private account fixture missing"); return }
            throw XCTSkip("private account fixture not provided")
        }
        let expiry = try RuntimeStagingSession.validate(token: token, now: Date())
        let store = KeychainSessionStore(), saved = store.load()
        defer { store.save(saved) }
        try RuntimeStagingSessionStore.save(nil)
        XCTAssertFalse(RuntimeStagingSessionStore.importEnabled)
        XCTAssertNil(RuntimeStagingSessionStore.load())
        let endpoint = try XCTUnwrap(RuntimeArabicBackendTranslator.defaultEndpoint())
        try await awaitStagingTransportReadiness(endpoint)
        store.save(DiscoverySession(accessToken: token, refreshToken: "unused-fixture-refresh", expiresAt: expiry))
        let fixture = try realFixture(), original = try RuntimeOriginalIPA.hash(fixture.ipa)
        try await awaitCanonicalSigningFixture(fixture, revision: original, endpoint: endpoint)
        let bundle = Bundle(for: Self.self)
        let material = PersonalIdentityVault.Material(
            p12: try Data(contentsOf: XCTUnwrap(bundle.url(forResource: "LCSignSynthetic", withExtension: "p12"))),
            password: "mirsa-test",
            profile: try Data(contentsOf: XCTUnwrap(bundle.url(forResource: "LCSignSynthetic", withExtension: "mobileprovision"))))
        var options = PersonalProjectOptions()
        options.translateToArabic = true
        options.backgroundNotifications = true
        options.backgroundMethods = [.audio, .significantLocation]
        // Match the UI worker boundary. Blocking the host application's main thread
        // here starves simulator networking while applyRequired waits on its semaphore.
        let enabledOptions = options
        let on = try await PersonalEncryptionWarning.signWithConsent { allowEncrypted in
            XCTAssertFalse(Thread.isMainThread, "Signing must use the same off-main worker as the UI")
            return try PersonalCertificateSigner.sign(ipa: fixture.ipa, material: material, pairingPath: "",
                options: enabledOptions, allowEncryptedSigning: allowEncrypted)
        }
        let unpacked = fixture.root.appendingPathComponent("signed-on")
        try IPAEditorService.run("extract", input: on.url, output: unpacked)
        let app = try IPAEditorService.app(in: unpacked)
        let info = try IPAEditorService.info(in: app), executable = try XCTUnwrap(info["CFBundleExecutable"] as? String)
        let loads = try IPAEditorService.dependencies(of: app.appendingPathComponent(executable))
        XCTAssertTrue(loads.contains("@loader_path/Frameworks/MirsaTranslate.dylib"))
        XCTAssertTrue(loads.contains("@loader_path/Frameworks/MirsaBackground.dylib"))
        let id = try XCTUnwrap(info["CFBundleIdentifier"] as? String)
        try RuntimeArabicPipeline.verifyInstalled(app: app, revision: original, bundleID: id)
        let config = app.appendingPathComponent("Frameworks/MirsaTranslations.json")
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: config)) as? [String: Any])
        let embedded = try XCTUnwrap(object["translations"] as? [String: String])
        XCTAssertFalse(embedded.isEmpty, "Full scoped dictionary must be embedded at signing")
        XCTAssertTrue(embedded.values.allSatisfy { $0.range(of: "[\\u0600-\\u06ff]", options: .regularExpression) != nil })
        XCTAssertNotNil(object["online"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: app.appendingPathComponent("_CodeSignature/CodeResources").path))
        let proofRoot = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("RuntimeSigningProof25")
        try FileManager.default.createDirectory(at: proofRoot, withIntermediateDirectories: true)
        // Independently fetch the FULL canonical scope, including previously learned
        // runtime strings that cannot be found by the binary/localization scanner.
        let online = try XCTUnwrap(object["online"] as? [String: String])
        let activation = try XCTUnwrap(online["activation"])
        let capability = try XCTUnwrap(online["token"])
        let response = try await RuntimeTranslationHTTP().post(endpoint, token: capability, activation: activation,
            object: ["action": "refresh", "consent": true, "bundleId": id, "revision": original])
        XCTAssertEqual(response["bundleId"] as? String, id)
        XCTAssertEqual(response["revision"] as? String, original)
        let entries = try XCTUnwrap(response["entries"] as? [[String: Any]])
        var canonical: [String: String] = [:]
        for entry in entries {
            let source = try XCTUnwrap(entry["source"] as? String)
            let value = try XCTUnwrap(entry["translation"] as? String)
            XCTAssertEqual(entry["provenance"] as? String, "kat")
            XCTAssertTrue(ArabicIPALocalizer.acceptable(source: source, translated: value))
            XCTAssertNil(canonical.updateValue(value, forKey: source), "Duplicate scoped source")
        }
        XCTAssertEqual(canonical, ["Settings": "الإعدادات", "Save %@": "حفظ %@",
                                   "%d items": "%d عنصر", "Runtime menu": "قائمة التطبيق"])
        XCTAssertEqual(embedded, canonical, "Signed dictionary must equal ALL canonical scoped entries, not just scanned strings")
        let scopeProof: [String: Any] = ["bundleId": id, "revision": original, "translations": canonical]
        try JSONSerialization.data(withJSONObject: scopeProof, options: [.sortedKeys])
            .write(to: proofRoot.appendingPathComponent("ON-dictionary-proof.json"), options: .atomic)
        let onProofURL = proofRoot.appendingPathComponent("ON.ipa")
        try? FileManager.default.removeItem(at: onProofURL)
        try FileManager.default.copyItem(at: on.url, to: onProofURL)
        let proof = XCTAttachment(contentsOfFile: on.url)
        proof.name = "production-sign-auto-account-arm64.ipa"; proof.lifetime = .keepAlways; add(proof)
        // Post-sign/export cannot report success if any translation side effect went missing.
        try FileManager.default.removeItem(at: config)
        XCTAssertThrowsError(try RuntimeArabicPipeline.verifyInstalled(app: app, revision: original, bundleID: id))
        XCTAssertEqual(try RuntimeOriginalIPA.hash(fixture.ipa), original)
        let off = try await PersonalEncryptionWarning.signWithConsent { allowEncrypted in
            XCTAssertFalse(Thread.isMainThread)
            return try PersonalCertificateSigner.sign(ipa: fixture.ipa, material: material, pairingPath: "",
                options: .init(), allowEncryptedSigning: allowEncrypted)
        }
        let offRoot = fixture.root.appendingPathComponent("signed-off")
        try IPAEditorService.run("extract", input: off.url, output: offRoot)
        try assertNoRuntime(IPAEditorService.app(in: offRoot))
        XCTAssertEqual(try RuntimeOriginalIPA.hash(fixture.ipa), original)
        let offProofURL = proofRoot.appendingPathComponent("OFF.ipa")
        try? FileManager.default.removeItem(at: offProofURL)
        try FileManager.default.copyItem(at: off.url, to: offProofURL)
        let offProof = XCTAttachment(contentsOfFile: off.url)
        offProof.name = "production-sign-toggle-off-arm64.ipa"; offProof.lifetime = .keepAlways; add(offProof)
    }

    func testRealSigningMissingAccountStopsWithActionableArabicErrorBeforeExport() throws {
        let oldLanguage = AppLanguageStore.shared.current
        AppLanguageStore.shared.set(.arabic)
        defer { AppLanguageStore.shared.set(oldLanguage) }
        let store = KeychainSessionStore(), saved = store.load()
        store.save(nil); defer { store.save(saved) }
        let fixture = try realFixture(), original = try RuntimeOriginalIPA.hash(fixture.ipa)
        var options = PersonalProjectOptions(); options.translateToArabic = true
        let stage = fixture.root.appendingPathComponent("missing-session")
        try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: true)
        XCTAssertThrowsError(try PersonalCertificateSigner.prepare(ipa: fixture.ipa, stage: stage, options: options)) { error in
            XCTAssertTrue(error.localizedDescription.contains(RuntimeArabicText.signIn))
            XCTAssertTrue(error.localizedDescription.contains("RT27-AUTH"))
            XCTAssertTrue(error.localizedDescription.contains("حسابك"))
        }
        XCTAssertEqual(try RuntimeOriginalIPA.hash(fixture.ipa), original)
    }

    func testEncryptedSkipsDictionaryAndPreservesAllBytes() throws {
        let app = try synthetic(encrypted: true), before = try snapshot(app)
        let translator = Translator(.failure(RuntimeTranslationError.network))
        XCTAssertEqual(RuntimeArabicPipeline.applyBlocking(app: app, translator: translator, dylib: nil), RuntimeArabicText.encrypted + "\n[RT27-SCAN ENCRYPTED]")
        XCTAssertTrue(translator.calls.isEmpty)
        XCTAssertEqual(try snapshot(app), before)
        try assertNoRuntime(app)
    }
    func testUnavailableAndFailureNeverMutateOriginal() throws {
        for (error, notice) in [(RuntimeTranslationError.notConfigured, RuntimeArabicText.unavailable),
                                (.network, RuntimeArabicText.failed), (.invalid, RuntimeArabicText.failed)] {
            let app = try synthetic(), before = try snapshot(app)
            let translator = Translator(.failure(error))
            let actual = RuntimeArabicPipeline.applyBlocking(app: app, translator: translator, dylib: nil)
            let expected = notice == RuntimeArabicText.failed ? RuntimeTranslationStage.dictionary.notice : notice
            XCTAssertEqual(actual, expected + "\n[RT27-DICTIONARY]")
            XCTAssertEqual(translator.calls.count, 1)
            XCTAssertEqual(try snapshot(app), before)
            try assertNoRuntime(app)
        }
        let app = try synthetic(), before = try snapshot(app)
        let translator = Translator(.success(RuntimeTranslationPackage(translations: ["Settings": "الإعدادات"])))
        XCTAssertEqual(RuntimeArabicPipeline.applyBlocking(app: app, translator: translator, dylib: nil), RuntimeArabicText.unavailable + "\n[RT27-INJECTION]")
        XCTAssertEqual(try snapshot(app), before)
    }
    func testFullCanonicalRefreshBindsScopeAndRejectsUnsafeEntries() throws {
        let bundle = "com.mirsa.fixture", revision = String(repeating: "a", count: 64)
        let kat: [String: Any] = ["source": "Runtime menu", "translation": "قائمة التطبيق", "provenance": "kat", "version": 2]
        let old: [String: Any] = ["source": "Settings", "translation": "الإعدادات", "provenance": "gemini", "version": 1]
        let good: [String: Any] = ["bundleId": bundle, "revision": revision, "entries": [kat, old]]
        func parse(_ value: [String: Any]) throws -> RuntimeCanonicalDictionary {
            try RuntimeArabicBackendTranslator.canonicalDictionary(value, bundleID: bundle, revision: revision)
        }
        XCTAssertEqual(try parse(good).translations, ["Runtime menu": "قائمة التطبيق"])
        for (key, value) in [("bundleId", "com.other.app"), ("revision", String(repeating: "b", count: 64))] {
            var bad = good; bad[key] = value
            XCTAssertThrowsError(try parse(bad))
        }
        for (key, value) in [("source", "secret=user@example.com" as Any),
                             ("translation", "قائمة %@" as Any), ("translation", "菜单" as Any),
                             ("version", true as Any), ("version", 1.5 as Any), ("version", 0 as Any)] {
            var item = kat; item[key] = value
            var bad = good; bad["entries"] = [item]
            XCTAssertThrowsError(try parse(bad), key)
        }
        var duplicate = good; duplicate["entries"] = [kat, kat]
        XCTAssertThrowsError(try parse(duplicate))
    }

    func testCanonicalRefreshStillRejectsEntryCountAboveTwentyThousand() throws {
        let data = try RuntimeRefreshCapProtocol27.dictionary(count: 20_001)
        let response = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertThrowsError(try RuntimeArabicBackendTranslator.canonicalDictionary(response,
            bundleID: RuntimeRefreshCapProtocol27.bundleID, revision: RuntimeRefreshCapProtocol27.revision))
    }

    func testRealSigningPipelineEmbedsTenThousandCanonicalTranslations() throws {
        let fixture = try realFixture(), scan = try RuntimeTranslationScanner.scan(app: fixture.app)
        let bundle = try XCTUnwrap(IPAEditorService.info(in: fixture.app)["CFBundleIdentifier"] as? String)
        let response = try XCTUnwrap(JSONSerialization.jsonObject(
            with: RuntimeRefreshCapProtocol27.dictionary(count: 10_000)) as? [String: Any])
        let parsed = try RuntimeArabicBackendTranslator.canonicalDictionary(response,
            bundleID: RuntimeRefreshCapProtocol27.bundleID, revision: RuntimeRefreshCapProtocol27.revision)
        let canonical = RuntimeCanonicalDictionary(bundleID: bundle, revision: scan.revision,
            translations: parsed.translations)
        let translator = Translator(.success(RuntimeTranslationPackage(translations: [:],
            online: grant(bundle: bundle, revision: scan.revision), canonicalDictionary: canonical)))
        try RuntimeArabicPipeline.applyRequired(app: fixture.app, translator: translator)
        let path = fixture.app.appendingPathComponent("Frameworks/MirsaTranslations.json")
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: path)) as? [String: Any])
        XCTAssertEqual(object["translations"] as? [String: String], canonical.translations)
        XCTAssertEqual((object["translations"] as? [String: String])?.count, 10_000)
        XCTAssertNoThrow(try RuntimeArabicPipeline.verifyInstalled(app: fixture.app,
            revision: scan.revision, bundleID: bundle))
    }

    func testRealSigningPipelineEmbedsPreviouslyLearnedCanonicalRuntimeSource() throws {
        let fixture = try realFixture(), scan = try RuntimeTranslationScanner.scan(app: fixture.app)
        let bundle = try XCTUnwrap(IPAEditorService.info(in: fixture.app)["CFBundleIdentifier"] as? String)
        XCTAssertFalse(scan.items.contains { $0.text == "Runtime menu" })
        let canonical = RuntimeCanonicalDictionary(bundleID: bundle, revision: scan.revision,
            translations: ["Runtime menu": "قائمة التطبيق", "Settings": "الإعدادات"])
        let translator = Translator(.success(RuntimeTranslationPackage(translations: ["Settings": "الإعدادات"],
            online: grant(bundle: bundle, revision: scan.revision), canonicalDictionary: canonical)))
        try RuntimeArabicPipeline.applyRequired(app: fixture.app, translator: translator)
        let config = fixture.app.appendingPathComponent("Frameworks/MirsaTranslations.json")
        let data = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: config)) as? [String: Any])
        XCTAssertEqual(data["translations"] as? [String: String], canonical.translations)
    }

    func testDynamicSourcesAndPlaceholderMismatchCannotCreateDictionary() throws {
        let app = try synthetic(), before = try snapshot(app)
        let translator = Translator(.success(RuntimeTranslationPackage(translations: [
            "Save %@": "حفظ", "%d items": "عناصر %n", "Not in this app": "دخيل"
        ])))
        XCTAssertEqual(RuntimeArabicPipeline.applyBlocking(app: app, translator: translator, dylib: nil), RuntimeTranslationStage.merge.notice + "\n[RT27-MERGE]")
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
        XCTAssertEqual(notice, RuntimeTranslationStage.wait.notice + "\n[RT27-WAIT]")
        XCTAssertEqual(try snapshot(app), before)
        await fulfillment(of: [finished], timeout: 3)
        // Synchronize after the value-only task has resumed; no staging edits may occur.
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(try snapshot(app), before)
        try assertNoRuntime(app)
    }
    func testOnlineScopeAndExpiryAreValidated() throws {
        let bundle = "org.mirsa.runtime25.generic", revision = String(repeating: "a", count: 64)
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
        XCTAssertEqual(RuntimeArabicPipeline.applyBlocking(app: app, translator: translator, dylib: nil), RuntimeTranslationStage.merge.notice + "\n[RT27-MERGE]")
        XCTAssertEqual(try snapshot(app), before)
    }
    func testGenericRuntimeInjectionWritesOnlyPerAppSafeDictionaryAndKeepsSourceIPA() throws {
        try assertGenericRuntimeInjection(onlineEnabled: true)
    }
    func testOfflineRuntimeInjectionWritesSafeDictionaryAndKeepsSourceIPA() throws {
        try assertGenericRuntimeInjection(onlineEnabled: false)
    }
    private func assertGenericRuntimeInjection(onlineEnabled: Bool) throws {
        let fixture = try realFixture(), original = try Data(contentsOf: fixture.ipa)
        let sha = try RuntimeOriginalIPA.pin(fixture.ipa)
        let scan = try RuntimeTranslationScanner.scan(app: fixture.app)
        let info = try IPAEditorService.info(in: fixture.app)
        let bundle = try XCTUnwrap(info["CFBundleIdentifier"] as? String)
        let online = onlineEnabled ? grant(bundle: bundle, revision: scan.revision) : nil
        let translator = Translator(.success(RuntimeTranslationPackage(translations: [
            "Save %@": "حفظ %@", "Settings": "الإعدادات", "%d items": "عناصر",
            "Not in this app": "دخيل"
        ], online: online)))
        let dylib = try XCTUnwrap(RuntimeArabicPipeline.bundledDylib, "Native app resource RuntimeTranslationAssets/MirsaTranslate.dylib is required")
        let executable = try XCTUnwrap(info["CFBundleExecutable"] as? String)
        let originalDependencies = try IPAEditorService.dependencies(of: fixture.app.appendingPathComponent(executable))
        XCTAssertFalse(originalDependencies.isEmpty, "Real linked fixture must have ordinal-bearing dependencies")
        let en = try Data(contentsOf: fixture.app.appendingPathComponent("en.lproj/Localizable.strings"))
        XCTAssertEqual(RuntimeArabicPipeline.applyBlocking(app: fixture.app, translator: translator, dylib: dylib),
                       onlineEnabled ? ArabicTranslateText.applied : RuntimeArabicText.offline)
        let config = fixture.app.appendingPathComponent("Frameworks/MirsaTranslations.json")
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: config)) as? [String: Any])
        let table = try XCTUnwrap(json["translations"] as? [String: String])
        // Full CURRENT scoped dictionary is embedded for first-frame Arabic; online activation stays for OTA.
        XCTAssertEqual(table, ["Save %@": "حفظ %@", "Settings": "الإعدادات"])
        XCTAssertEqual(json["online"] != nil, onlineEnabled)
        XCTAssertNil(table["%d items"]); XCTAssertNil(table["Not in this app"])
        XCTAssertEqual(json["revision"] as? String, scan.revision)
        XCTAssertEqual(json["online"] as? [String: String], online)
        XCTAssertEqual(translator.calls.first?.0, bundle)
        XCTAssertEqual(translator.calls.first?.1, scan.revision)
        XCTAssertEqual(try Data(contentsOf: fixture.app.appendingPathComponent("Frameworks/MirsaTranslate.dylib")), try Data(contentsOf: dylib))
        XCTAssertEqual(try IPAEditorService.dependencies(of: fixture.app.appendingPathComponent(executable)),
                       originalDependencies + ["@loader_path/Frameworks/MirsaTranslate.dylib"],
                       "Translation must append without shifting any existing dyld library ordinal")
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
