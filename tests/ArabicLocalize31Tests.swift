import XCTest
import CryptoKit
@testable import Mirsa

final class ArabicLocalize31Tests: XCTestCase {
    func testTokensMustMatch() {
        XCTAssertTrue(ArabicIPALocalizer.acceptable(source: "Hello %@, %d items", translated: "مرحبا %@، %d عناصر"))
        XCTAssertFalse(ArabicIPALocalizer.acceptable(source: "Hello %@", translated: "مرحبا"))
        XCTAssertFalse(ArabicIPALocalizer.acceptable(source: "Hi", translated: "  "))
    }
    func testWorthTranslating() {
        XCTAssertTrue(ArabicIPALocalizer.worthTranslating("Settings"))
        XCTAssertFalse(ArabicIPALocalizer.worthTranslating("https://example.com"))
        XCTAssertFalse(ArabicIPALocalizer.worthTranslating("%d"))
    }
    func testScanDetectsArabicAndStrings() throws {
        let fm = FileManager.default
        let app = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("T.app")
        let en = app.appendingPathComponent("en.lproj")
        try fm.createDirectory(at: en, withIntermediateDirectories: true)
        try "\"hello\" = \"Hello %@\";\n\"CFBundleName\" = \"T\";".write(to: en.appendingPathComponent("Localizable.strings"), atomically: true, encoding: .utf8)
        let s = try ArabicIPALocalizer.scan(app: app)
        XCTAssertFalse(s.hasArabic); XCTAssertEqual(s.items.count, 1)
        try fm.createDirectory(at: app.appendingPathComponent("ar.lproj"), withIntermediateDirectories: true)
        XCTAssertTrue(try ArabicIPALocalizer.scan(app: app).hasArabic)
    }
    private struct Translator: ArabicTranslating {
        var fail = false
        func translate(bundleID: String, version: String, contentHash: String, items: [ArabicIPALocalizer.Item]) async throws -> [String: String] {
            if fail { throw ArabicTranslationError(failure: .network) }
            return Dictionary(uniqueKeysWithValues: items.map { ($0.id, "عربي " + $0.text) })
        }
    }
    private func temp() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ar32-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return dir
    }
    private func plist(_ value: Any, to path: URL, format: PropertyListSerialization.PropertyListFormat = .binary) throws {
        try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
        try PropertyListSerialization.data(fromPropertyList: value, format: format, options: 0).write(to: path)
    }
    /// An owned English-only executable fixture, never executed. Real Rust ZIP pack/extract throughout.
    private func fixture(at dir: URL) throws -> (ipa: URL, app: URL) {
        let root = dir.appendingPathComponent("original"), app = root.appendingPathComponent("Payload/English.app")
        try plist(["CFBundleIdentifier": "org.mirsa.ar32.english", "CFBundleExecutable": "English",
                   "CFBundleName": "English", "CFBundleShortVersionString": "1.0", "CFBundleVersion": "1",
                   "MinimumOSVersion": "15.0", "CFBundleLocalizations": ["en"]], to: app.appendingPathComponent("Info.plist"))
        var binary = Data()
        let words: [UInt32] = [0xfeedfacf, 0x0100000c, 0, 2, 1, 24, 0, 0, 0x2c, 24, 0, 0, 0, 0]
        for word in words {
            var le = word.littleEndian; withUnsafeBytes(of: &le) { binary.append(contentsOf: $0) }
        }
        try binary.write(to: app.appendingPathComponent("English"))
        try plist(["greeting": "Hello %@", "settings": "Settings", "CFBundleDisplayName": "English"],
                  to: app.appendingPathComponent("en.lproj/Localizable.strings"))
        let output = dir.appendingPathComponent("English.ipa")
        try IPAEditorService.run("pack", input: root, output: output)
        return (output, app)
    }
    func testBinaryStringsAndPluralDictionaryPreserveTokensMetadataAndEnglish() async throws {
        let dir = try temp(), app = dir.appendingPathComponent("English.app")
        let en = app.appendingPathComponent("en.lproj")
        try plist(["CFBundleIdentifier": "org.mirsa.ar32", "CFBundleLocalizations": ["en"]], to: app.appendingPathComponent("Info.plist"))
        try plist(["greet": "Hello %1$@, %2$ld items", "CFBundleName": "Brand"], to: en.appendingPathComponent("Localizable.strings"))
        let plural: [String: Any] = ["items": ["NSStringLocalizedFormatKey": "%#@items@",
            "items": ["NSStringFormatSpecTypeKey": "NSStringPluralRuleType", "NSStringFormatValueTypeKey": "d",
                      "one": "%d item", "other": "%d items"]]]
        try plist(plural, to: en.appendingPathComponent("Localizable.stringsdict"))
        let originalStrings = try Data(contentsOf: en.appendingPathComponent("Localizable.strings"))
        let originalDict = try Data(contentsOf: en.appendingPathComponent("Localizable.stringsdict"))
        XCTAssertTrue(originalStrings.starts(with: Data("bplist00".utf8)))
        XCTAssertTrue(originalDict.starts(with: Data("bplist00".utf8)))
        let before = try ArabicIPALocalizer.scan(app: app)
        XCTAssertEqual(before.items.count, 3)
        XCTAssertEqual(before.contentHash.count, 64)
        let result = await ArabicIPALocalizer.localize(app: app, bundleID: "org.mirsa.ar32", version: "1", translator: Translator())
        XCTAssertEqual(result, .applied(3))
        let ar = app.appendingPathComponent("ar.lproj")
        let translated = try XCTUnwrap(try PropertyListSerialization.propertyList(from: Data(contentsOf: ar.appendingPathComponent("Localizable.strings")), options: [], format: nil) as? [String: String])
        XCTAssertEqual(translated["CFBundleName"], "Brand")
        XCTAssertEqual(translated["greet"], "عربي Hello %1$@, %2$ld items")
        let dict = try XCTUnwrap(try PropertyListSerialization.propertyList(from: Data(contentsOf: ar.appendingPathComponent("Localizable.stringsdict")), options: [], format: nil) as? [String: Any])
        let item = try XCTUnwrap(dict["items"] as? [String: Any]), forms = try XCTUnwrap(item["items"] as? [String: String])
        XCTAssertEqual(item["NSStringLocalizedFormatKey"] as? String, "%#@items@")
        XCTAssertEqual(forms["NSStringFormatSpecTypeKey"], "NSStringPluralRuleType")
        XCTAssertEqual(forms["NSStringFormatValueTypeKey"], "d")
        XCTAssertEqual(forms["one"], "عربي %d item"); XCTAssertEqual(forms["other"], "عربي %d items")
        XCTAssertEqual(try Data(contentsOf: en.appendingPathComponent("Localizable.strings")), originalStrings)
        XCTAssertEqual(try Data(contentsOf: en.appendingPathComponent("Localizable.stringsdict")), originalDict)
        var format = PropertyListSerialization.PropertyListFormat.xml
        let info = try XCTUnwrap(try PropertyListSerialization.propertyList(from: Data(contentsOf: app.appendingPathComponent("Info.plist")), options: [], format: &format) as? [String: Any])
        XCTAssertEqual(format, .binary); XCTAssertEqual(info["CFBundleLocalizations"] as? [String], ["en", "ar"])
    }
    func testPlaceholderMultisetsAndLowQualityFailOpenWithoutAnyChanges() async throws {
        for token in ["%@", "%1$@", "%02d", "%lld", "%.*f", "%%", "%#@count@", "{name}", "${value}", "{{name}}", "<b>", "</b>", #"\n"#] {
            XCTAssertTrue(ArabicIPALocalizer.acceptable(source: "Hello " + token, translated: "مرحبا " + token), token)
            XCTAssertFalse(ArabicIPALocalizer.acceptable(source: "Hello " + token, translated: "مرحبا"), token)
            XCTAssertFalse(ArabicIPALocalizer.acceptable(source: "Hello " + token + token, translated: "مرحبا " + token), token)
        }
        struct Broken: ArabicTranslating {
            func translate(bundleID: String, version: String, contentHash: String, items: [ArabicIPALocalizer.Item]) async throws -> [String: String] {
                Dictionary(uniqueKeysWithValues: items.map { ($0.id, "") })
            }
        }
        let dir = try temp(), fixture = try fixture(at: dir)
        let original = try Data(contentsOf: fixture.app.appendingPathComponent("Info.plist"))
        let result = await ArabicIPALocalizer.localize(app: fixture.app, bundleID: "org.mirsa.ar32.english", version: "1", translator: Broken())
        XCTAssertEqual(result, .failed(.invalid))
        XCTAssertEqual(try Data(contentsOf: fixture.app.appendingPathComponent("Info.plist")), original)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.app.appendingPathComponent("ar.lproj").path))
    }
    func testContentHashAndPreferencesCacheAreStableScopedAndInvalidateOnEnglishChanges() throws {
        let a = try temp(), b = try temp(), fa = try fixture(at: a), fb = try fixture(at: b)
        let first = try ArabicIPALocalizer.scan(app: fa.app).contentHash
        XCTAssertEqual(first, try ArabicIPALocalizer.scan(app: fb.app).contentHash)
        try plist(["greeting": "Hello %@ changed"], to: fb.app.appendingPathComponent("en.lproj/Localizable.strings"))
        XCTAssertNotEqual(first, try ArabicIPALocalizer.scan(app: fb.app).contentHash)
        let suite = "ar32-" + UUID().uuidString, defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        ArabicTranslatePrefs.set(true, bundleID: "org.one", defaults: defaults)
        ArabicTranslatePrefs.markHasArabic("org.one", defaults: defaults)
        let reopened = try XCTUnwrap(UserDefaults(suiteName: suite))
        XCTAssertTrue(ArabicTranslatePrefs.isOn("org.one", defaults: reopened))
        XCTAssertTrue(ArabicTranslatePrefs.hasArabicKnown("org.one", defaults: reopened))
        XCTAssertFalse(ArabicTranslatePrefs.isOn("org.two", defaults: reopened))
        XCTAssertFalse(ArabicTranslatePrefs.hasArabicKnown("org.two", defaults: reopened))
        ArabicTranslatePrefs.set(false, bundleID: "org.one", defaults: reopened)
        XCTAssertFalse(ArabicTranslatePrefs.isOn("org.one", defaults: reopened))
    }
    func testRealEnglishIPAInjectionBothDownloadAndPreSigningAndFailureKeepsOriginal() async throws {
        let fm = FileManager.default, dir = try temp(), original = try fixture(at: dir)
        let source = try Data(contentsOf: original.ipa), bid = "org.mirsa.ar32.english"
        ArabicTranslatePrefs.set(true, bundleID: bid)
        defer { ArabicTranslatePrefs.set(false, bundleID: bid) }
        let notice = await ArabicLocalizationPipeline.apply(workDir: dir, ipa: original.ipa, app: original.app,
            bundleID: bid, version: "1.0", translator: Translator())
        XCTAssertEqual(notice, ArabicTranslateText.applied)
        XCTAssertEqual(try Data(contentsOf: dir.appendingPathComponent("untranslated.ipa")), source)
        let extract = dir.appendingPathComponent("download-result")
        try IPAEditorService.run("extract", input: original.ipa, output: extract)
        let downloaded = try IPAEditorService.app(in: extract)
        XCTAssertTrue(fm.fileExists(atPath: downloaded.appendingPathComponent("ar.lproj/Localizable.strings").path))
        XCTAssertEqual(try Data(contentsOf: downloaded.appendingPathComponent("English")), try Data(contentsOf: original.app.appendingPathComponent("English")))
        // Exercise production prepare(), called directly before signer invocation. No mock ZIP, signing or native-code execution.
        let unsigned = dir.appendingPathComponent("before-sign.ipa"); try source.write(to: unsigned)
        var options = PersonalProjectOptions(); options.translateToArabic = true
        let prepared = try PersonalCertificateSigner.prepare(ipa: unsigned, stage: dir.appendingPathComponent("sign-stage"), options: options, arabicTranslator: Translator())
        XCTAssertEqual(ArabicLocalizationPipeline.lastNotice, ArabicTranslateText.applied)
        XCTAssertTrue(fm.fileExists(atPath: prepared.app.appendingPathComponent("ar.lproj/Localizable.strings").path))
        try IPAEditorService.run("validate", input: prepared.app.appendingPathComponent("English"))
        // Fail-open in both production paths. Original archive bytes and payload remain unchanged.
        let failDir = try temp(), failed = try fixture(at: failDir)
        let originalIPA = try Data(contentsOf: failed.ipa), originalInfo = try Data(contentsOf: failed.app.appendingPathComponent("Info.plist"))
        let failedNotice = await ArabicLocalizationPipeline.apply(workDir: failDir, ipa: failed.ipa, app: failed.app,
            bundleID: bid, version: "1.0", translator: Translator(fail: true))
        XCTAssertEqual(failedNotice, ArabicTranslateText.failed)
        XCTAssertEqual(try Data(contentsOf: failed.ipa), originalIPA)
        XCTAssertEqual(try Data(contentsOf: failed.app.appendingPathComponent("Info.plist")), originalInfo)
        XCTAssertFalse(fm.fileExists(atPath: failed.app.appendingPathComponent("ar.lproj").path))
        let failedPrepared = try PersonalCertificateSigner.prepare(ipa: failed.ipa, stage: failDir.appendingPathComponent("sign-stage"), options: options, arabicTranslator: Translator(fail: true))
        XCTAssertEqual(ArabicLocalizationPipeline.lastNotice, ArabicTranslateText.failed)
        let failedInfo = try IPAEditorService.info(in: failedPrepared.app)
        let beforeInfo = try XCTUnwrap(try PropertyListSerialization.propertyList(from: originalInfo, options: [], format: nil) as? [String: Any])
        XCTAssertTrue(NSDictionary(dictionary: failedInfo).isEqual(to: beforeInfo))
        XCTAssertFalse(fm.fileExists(atPath: failedPrepared.app.appendingPathComponent("ar.lproj").path))
        XCTAssertEqual(try Data(contentsOf: failed.ipa), originalIPA)
    }

    private final class LiveSessionStore: DiscoverySessionStore {
        var session: DiscoverySession?
        func load() -> DiscoverySession? { session }
        func save(_ value: DiscoverySession?) { session = value }
    }
    func testLiveEnglishIPAWithRealBackendIsInjectedBeforeSigning() async throws {
        let store = LiveSessionStore()
        let auth = DiscoveryAuthClient(projectURL: URL(string: WebBackendConfig.defaultProject)!,
            publishableKey: WebBackendConfig.defaultPublishableKey, store: store, http: SafeMetadataHTTP())
        let token = try await auth.token(forceRefresh: false)
        var component = String(token.split(separator: ".")[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while component.count % 4 != 0 { component += "=" }
        let claims = try XCTUnwrap(try JSONSerialization.jsonObject(with: XCTUnwrap(Data(base64Encoded: component))) as? [String: Any])
        let userID = try XCTUnwrap(claims["sub"] as? String)
        XCTAssertNotNil(UUID(uuidString: userID))
        // Collector deletes ONLY this test user's scoped cache/usage rows and anonymous Auth identity, even on failure.
        print("AR32_TEMP_AUTH_USER_UUID=" + userID)
        let dir = try temp(), original = try fixture(at: dir)
        let source = try Data(contentsOf: original.ipa)
        var options = PersonalProjectOptions(); options.translateToArabic = true
        let translator = ArabicBackendTranslator(tokenProvider: auth)
        let prepared = try PersonalCertificateSigner.prepare(ipa: original.ipa, stage: dir.appendingPathComponent("live-sign-stage"), options: options, arabicTranslator: translator)
        XCTAssertEqual(ArabicLocalizationPipeline.lastNotice, ArabicTranslateText.applied)
        let ar = try XCTUnwrap(try PropertyListSerialization.propertyList(from: Data(contentsOf: prepared.app.appendingPathComponent("ar.lproj/Localizable.strings")), options: [], format: nil) as? [String: String])
        let greeting = try XCTUnwrap(ar["greeting"]), settings = try XCTUnwrap(ar["settings"])
        XCTAssertNotNil(greeting.range(of: #"[\u0600-\u06ff]"#, options: .regularExpression))
        XCTAssertNotNil(settings.range(of: #"[\u0600-\u06ff]"#, options: .regularExpression))
        XCTAssertTrue(ArabicIPALocalizer.acceptable(source: "Hello %@", translated: greeting))
        XCTAssertNotEqual(settings, "Settings"); XCTAssertEqual(ar["CFBundleDisplayName"], "English")
        XCTAssertEqual(try Data(contentsOf: original.ipa), source)
        XCTAssertFalse(FileManager.default.fileExists(atPath: original.app.appendingPathComponent("ar.lproj").path))
        let packed = dir.appendingPathComponent("translated-before-sign.ipa")
        try IPAEditorService.run("pack", input: prepared.root, output: packed)
        let extracted = dir.appendingPathComponent("live-roundtrip")
        try IPAEditorService.run("extract", input: packed, output: extracted)
        let roundtrip = try IPAEditorService.app(in: extracted)
        XCTAssertEqual(try Data(contentsOf: roundtrip.appendingPathComponent("ar.lproj/Localizable.strings")), try Data(contentsOf: prepared.app.appendingPathComponent("ar.lproj/Localizable.strings")))
        try IPAEditorService.run("validate", input: roundtrip.appendingPathComponent("English"))
        let proof = XCTAttachment(string: "Real anonymous JWT, deployed Arabic backend, English-only owned IPA, Rust extract/pack, Arabic tokens verified in production prepare before signing. Original IPA unchanged.")
        proof.name = "ar32-real-backend-before-sign"; proof.lifetime = .keepAlways; add(proof)
    }

}
