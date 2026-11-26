// Compiled only by the private same-payload diagnostic workflow.
// Current Swift preparation/export stays common. Exactly one Rust engine is linked per build.
import XCTest
@testable import Mirsa

final class SamePayloadAB26Tests: XCTestCase {
    func testFrozenOwnHostAndPinnedAlaaFeatureMatrix() async throws {
        let env = ProcessInfo.processInfo.environment
        let engine = try XCTUnwrap(env["MIRSA_AB_ENGINE"])
        XCTAssertTrue(["current", "released296"].contains(engine))
        let bundle = Bundle(for: Self.self), fm = FileManager.default
        let original = try XCTUnwrap(bundle.url(forResource: "ExactLaunch25Fixture", withExtension: "ipa"))
        let source = try XCTUnwrap(bundle.url(forResource: "Alaa", withExtension: "dylib"))
        let p12 = try XCTUnwrap(bundle.url(forResource: "LCSignSynthetic", withExtension: "p12"))
        let profile = try XCTUnwrap(bundle.url(forResource: "LCSignSynthetic", withExtension: "mobileprovision"))
        let inputSHA = try RuntimeOriginalIPA.hash(original)
        let componentSHA = try RuntimeOriginalIPA.hash(source)
        XCTAssertEqual(componentSHA, "04afc06b8a95d5ef1761bfa221bd1386f8762452970226d3c1ff64a4642d6565")
        let material = PersonalIdentityVault.Material(p12: try Data(contentsOf: p12), password: "mirsa-test", profile: try Data(contentsOf: profile))
        let root = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("SamePayloadAB26/" + engine)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        let store = KeychainSessionStore(), saved = store.load()
        defer { store.save(saved) }
        if engine == "current" {
            let token = try XCTUnwrap(env["MIRSA_RT_STAGING_TOKEN"])
            let expiry = try RuntimeStagingSession.validate(token: token, now: Date())
            try RuntimeStagingSessionStore.save(nil)
            XCTAssertFalse(RuntimeStagingSessionStore.importEnabled)
            let endpoint = try XCTUnwrap(RuntimeArabicBackendTranslator.defaultEndpoint())
            var ready = false
            for attempt in 1...3 {
                do {
                    _ = try await RuntimeTranslationHTTP().post(endpoint, token: "readiness-without-credentials", object: ["action": "readiness"])
                    XCTFail("Invalid readiness action unexpectedly succeeded")
                    throw RuntimeTranslationError.invalid
                } catch RuntimeTranslationError.httpStatus(400) {
                    ready = true
                    break
                } catch let error as URLError where Set<URLError.Code>([.timedOut, .networkConnectionLost, .cannotConnectToHost, .notConnectedToInternet]).contains(error.code) {
                    guard attempt < 3 else { throw error }
                    try await Task.sleep(nanoseconds: 500_000_000)
                }
            }
            XCTAssertTrue(ready)
            store.save(DiscoverySession(accessToken: token, refreshToken: "unused-fixture-refresh", expiresAt: expiry))
        }
        let cells: [(String, Bool, Bool)] = engine == "current"
            ? [("off", false, false), ("background", true, false), ("translation", false, true), ("combined", true, true)]
            : [("off", false, false)]
        var outcomes = [[String: Any]]()
        for (cell, background, translation) in cells {
            var options = PersonalProjectOptions()
            options.libraries = [source]
            options.selectedComponentIDs = ["exact:Alaa"]
            options.draftRevision = "frozen-same-payload26"
            options.injections = [InjectionPlanEntry(id: "exact:Alaa", library: source.path, target: "ExactLaunch25", method: .load_control)]
            options.backgroundNotifications = background
            options.backgroundMethods = background ? [.audio, .significantLocation] : []
            options.translateToArabic = translation
            let frozenOptions = options
            var outcome: [String: Any] = ["engine": engine, "cell": cell, "sourceIPA_SHA256": inputSHA, "AlaaSourceSHA256": componentSHA,
                "p12SHA256": try RuntimeOriginalIPA.hash(p12), "profileSHA256": try RuntimeOriginalIPA.hash(profile),
                "background": background, "translation": translation, "argument": "ALAA",
                "commonPipeline": "current Swift prepare, production sign, verify, pack, immutable attempt"]
            do {
                let signed = try await PersonalEncryptionWarning.signWithConsent { allowEncrypted in
                    XCTAssertFalse(Thread.isMainThread)
                    return try PersonalCertificateSigner.sign(ipa: original, material: material, pairingPath: "", options: frozenOptions, allowEncryptedSigning: allowEncrypted)
                }
                try PersonalInjectionProof.verifyRecord(signed.url)
                let attempt = try JSONDecoder().decode(PersonalInjectionProof.Attempt.self, from: Data(contentsOf: PersonalInjectionProof.sidecar(signed.url)))
                XCTAssertEqual(attempt.sourceSHA256, inputSHA)
                XCTAssertEqual(Array(attempt.componentSHA256.values), [componentSHA])
                XCTAssertEqual(attempt.selectedComponentIDs, ["exact:Alaa"])
                let destination = root.appendingPathComponent(cell + ".ipa")
                try? fm.removeItem(at: destination)
                try fm.copyItem(at: signed.url, to: destination)
                try Data(contentsOf: PersonalInjectionProof.sidecar(signed.url)).write(to: PersonalInjectionProof.sidecar(destination))
                outcome["signingPassed"] = true
                outcome["signedIPA_SHA256"] = try RuntimeOriginalIPA.hash(destination)
                outcome["attemptID"] = attempt.attemptID.uuidString
            } catch {
                outcome["signingPassed"] = false
                outcome["error"] = error.localizedDescription
                XCTFail("Same-payload cell \(engine)/\(cell) signing failed: \(error.localizedDescription)")
            }
            XCTAssertEqual(try RuntimeOriginalIPA.hash(original), inputSHA)
            XCTAssertEqual(try RuntimeOriginalIPA.hash(source), componentSHA)
            outcomes.append(outcome)
            try JSONSerialization.data(withJSONObject: outcomes, options: [.sortedKeys, .prettyPrinted]).write(to: root.appendingPathComponent("signing-outcomes.json"))
        }
        print("MIRSA_SAME_PAYLOAD26 exported immutable outputs engine=\(engine) cells=\(outcomes.count)")
    }
}
