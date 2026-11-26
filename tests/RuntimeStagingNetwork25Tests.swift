import XCTest
@testable import Mirsa

/// Real network gate against the branch-only staging endpoint. Credentials come only from the
/// CI launch environment (ephemeral, staging-scoped, 1h). Nothing is stored in the app or IPA.
final class RuntimeStagingNetwork25Tests: XCTestCase {
    private struct EnvAuth: DiscoveryTokenProvider {
        let value: String
        func token(forceRefresh: Bool) async throws -> String { value }
    }
    func testQueuedFallbackRejectsMissingForgedAndPartialReceipts() {
        let source = "设置 %d"
        let entry: [String: Any] = ["source": source, "labelId": UUID().uuidString, "reviewId": UUID().uuidString, "version": 1, "kind": "missing"]
        let good: [String: Any] = ["queue": ["persisted": true, "entries": [entry]]]
        XCTAssertNotNil(RuntimeArabicBackendTranslator.queueReceipt(good, sources: [source]))
        let badReceipts: [[String: Any]] = [
            [:], ["error": "unavailable"], ["queue": ["persisted": false, "entries": [entry]]],
            ["queue": ["persisted": true, "entries": []]],
            ["queue": ["persisted": true, "entries": [entry, entry]]],
            ["queue": ["persisted": true, "entries": [["source": source, "labelId": "fake"]]]]
        ]
        for bad in badReceipts { XCTAssertNil(RuntimeArabicBackendTranslator.queueReceipt(bad, sources: [source])) }
        XCTAssertNil(RuntimeArabicBackendTranslator.queueReceipt(good, sources: [source, "说明"]))
    }
    func testStagingDictionaryPreservesSpecifiersAndIssuesScopedGrant() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let raw = env["MIRSA_RT_STAGING_ENDPOINT"], let token = env["MIRSA_RT_STAGING_TOKEN"], !raw.isEmpty, !token.isEmpty else {
            if env["MIRSA_RT_REQUIRED_STAGING"] == "1" { XCTFail("REQUIRED staging endpoint/token missing"); return }
            throw XCTSkip("staging env not provided")
        }
        // Diagnose expired operator setup before any generic network error, never log the JWT.
        let expiry = try RuntimeStagingSession.validate(token: token, now: Date())
        guard expiry.timeIntervalSinceNow > 60 else {
            XCTFail("Staging fixture expired or too close to expiry; refresh before dispatch.")
            return
        }
        let endpoint = try XCTUnwrap(URL(string: raw))
        let translator = RuntimeArabicBackendTranslator(endpoint: endpoint, tokenProvider: EnvAuth(value: token))
        let items = [
            ArabicIPALocalizer.Item(id: "a", text: "Cancel"),
            ArabicIPALocalizer.Item(id: "b", text: "%d items selected"),
            ArabicIPALocalizer.Item(id: "c", text: "Open %@ settings"),
            ArabicIPALocalizer.Item(id: "d", text: "Save changes")
        ]
        let revision = String(repeating: "ab", count: 32)
        let package = try await translator.dictionary(bundleID: "com.example.stagingprobe", revision: revision, items: items)
        let arabic = { (s: String) in s.unicodeScalars.contains { (0x0600...0x06FF).contains($0.value) } }
        XCTAssertEqual(package.queueReceipts.count, items.count, "Every source must have a committed label and review outbox receipt")
        if package.deferredReasons.isEmpty {
            XCTAssertFalse(package.translations.isEmpty, "Successful provider returned no translations")
        } else {
            XCTAssertTrue(package.deferredReasons.allSatisfy { ["provider_429", "provider_503", "provider_throttled", "kat_review_required"].contains($0) })
            // Missing values render verbatim. No error, fabricated Arabic or crash.
            for item in items where package.translations[item.text] == nil {
                XCTAssertEqual(package.translations[item.text] ?? item.text, item.text)
            }
            print("Live native provider fallback verified committed queue receipt and original text")
        }
        for (source, translated) in package.translations {
            XCTAssertTrue(arabic(translated), "not Arabic: \(source)")
            for spec in ["%d", "%@"] where source.contains(spec) { XCTAssertTrue(translated.contains(spec), "specifier lost in \(source)") }
        }
        if package.deferredReasons.isEmpty {
            XCTAssertNotNil(package.translations["%d items selected"], "specifier string missing from dictionary")
            XCTAssertNotNil(package.translations["Open %@ settings"])
        }
        // Missing/unknown ids must fail open (no throw, no bogus entries).
        let missing = try await translator.dictionary(bundleID: "com.example.stagingprobe", revision: revision,
            items: [ArabicIPALocalizer.Item(id: "zz", text: "Zzqx unlikelyword")])
        XCTAssertTrue(missing.translations.values.allSatisfy { arabic($0) })
        // The issued runtime capability must exist and drive a real 'missing' request exactly as the injected dylib does.
        let online = try XCTUnwrap(package.online, "staging issued no runtime capability")
        XCTAssertNotNil(RuntimeArabicBackendTranslator.validOnline(online, bundleID: "com.example.stagingprobe", revision: revision))
        let grant = try XCTUnwrap(online["token"])
        let grantEndpoint = try XCTUnwrap(URL(string: try XCTUnwrap(online["endpoint"])))
        let reply = try await RuntimeTranslationHTTP().post(grantEndpoint, token: grant, activation: online["activation"], object: [
            "action": "missing", "consent": true, "bundleId": "com.example.stagingprobe", "revision": revision,
            "items": [["id": "s0", "text": "删除 %d 张照片"]]])
        let map = try XCTUnwrap(reply["translations"] as? [String: String])
        XCTAssertNotNil(RuntimeArabicBackendTranslator.queueReceipt(reply, sources: ["删除 %d 张照片"]))
        if let value = map["s0"] {
            XCTAssertTrue(arabic(value)); XCTAssertTrue(value.contains("%d"))
        } else {
            XCTAssertTrue(["provider_429", "provider_503", "provider_throttled", "kat_review_required"].contains(reply["deferred"] as? String ?? ""))
            XCTAssertEqual(map["s0"] ?? "删除 %d 张照片", "删除 %d 张照片")
            // A second authenticated refresh proves durable server state remains available.
            let refresh = try await RuntimeTranslationHTTP().post(grantEndpoint, token: grant, activation: online["activation"], object: [
                "action": "refresh", "consent": true, "bundleId": "com.example.stagingprobe", "revision": revision])
            XCTAssertNotNil(refresh["entries"] as? [[String: Any]])
            print("Live native missing fallback verified committed queue receipt and original text")
        }
        // A user session token must NOT be accepted as a runtime capability.
        do {
            _ = try await RuntimeTranslationHTTP().post(grantEndpoint, token: token, object: ["action": "missing", "consent": true,
                "bundleId": "com.example.stagingprobe", "revision": revision, "items": [["id": "s0", "text": "删除 %d 张照片"]]])
            XCTFail("user JWT accepted for missing")
        } catch RuntimeTranslationError.httpStatus(let status) {
            XCTAssertEqual(status, 401, "valid missing request must be rejected by auth, not input validation")
        }
    }
}
