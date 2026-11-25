import XCTest
@testable import Mirsa

final class BackgroundNotifications25Tests: XCTestCase {
    func testLegacyDraftDecodesMissingKeysAsOff() throws {
        let encoded = try JSONEncoder().encode(PersonalProjectDraft())
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        for key in ["backgroundNotifications", "backgroundAudio", "backgroundLocation"] { json.removeValue(forKey: key) }
        let old = try JSONSerialization.data(withJSONObject: json)
        let draft = try JSONDecoder().decode(PersonalProjectDraft.self, from: old)
        XCTAssertNil(draft.backgroundNotifications)
        XCTAssertNil(draft.backgroundAudio)
        XCTAssertNil(draft.backgroundLocation)
        XCTAssertFalse(PersonalProjectOptions().backgroundNotifications)
        XCTAssertTrue(PersonalProjectOptions().backgroundMethods.isEmpty)
    }

    func testPerProjectSettingsRoundTripDoesNotTouchTranslation() throws {
        var first = PersonalProjectDraft()
        first.translateArabic = true
        first.backgroundNotifications = true
        first.backgroundAudio = true
        first.backgroundLocation = false
        let restored = try JSONDecoder().decode(PersonalProjectDraft.self, from: JSONEncoder().encode(first))
        XCTAssertEqual(restored, first)
        XCTAssertTrue(restored.translateArabic == true)
        XCTAssertNil(PersonalProjectDraft().backgroundNotifications)
    }

    func testOffDoesNotAddModesOrPermissionAndPreservesExisting() throws {
        let original: [String: Any] = ["UIBackgroundModes": ["fetch"], "NSLocationWhenInUseUsageDescription": "Original"]
        let actual = BackgroundNotifications.configuredInfo(original, enabled: false, methods: [.audio, .significantLocation])
        XCTAssertTrue(NSDictionary(dictionary: actual).isEqual(to: original))
        XCTAssertNil(BackgroundNotifications.configuration(enabled: false, methods: [.audio]))
        let empty = BackgroundNotifications.configuredInfo([:], enabled: true, methods: [])
        XCTAssertNil(empty["UIBackgroundModes"])
        XCTAssertNil(empty["NSLocationWhenInUseUsageDescription"])
    }

    func testSelectedMethodsOnlyAndOriginalMetadataPreserved() throws {
        let original: [String: Any] = ["UIBackgroundModes": ["fetch", "audio"], "NSLocationWhenInUseUsageDescription": "Original purpose"]
        let audio = BackgroundNotifications.configuredInfo(original, enabled: true, methods: [.audio])
        XCTAssertEqual(audio["UIBackgroundModes"] as? [String], ["fetch", "audio"])
        XCTAssertEqual(audio["NSLocationWhenInUseUsageDescription"] as? String, "Original purpose")
        XCTAssertNil(audio["NSLocationAlwaysAndWhenInUseUsageDescription"])
        let location = BackgroundNotifications.configuredInfo(["UIBackgroundModes": ["fetch"]], enabled: true, methods: [.significantLocation])
        XCTAssertEqual(location["UIBackgroundModes"] as? [String], ["fetch", "location"])
        XCTAssertNotNil(location["NSLocationAlwaysAndWhenInUseUsageDescription"])
        let both = BackgroundNotifications.configuredInfo(original, enabled: true, methods: [.audio, .significantLocation])
        XCTAssertEqual(both["UIBackgroundModes"] as? [String], ["fetch", "audio", "location"])
        XCTAssertTrue((both["NSLocationWhenInUseUsageDescription"] as? String)?.hasPrefix("Original purpose\n") == true)
        XCTAssertEqual(BackgroundNotifications.configuration(enabled: true, methods: [.audio, .audio])?["methods"] as? [String], ["audio"])
    }

    func testDisabledSigningDoesNotReadLibraryOrMutateCopy() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let marker = root.appendingPathComponent("marker")
        try Data("unchanged".utf8).write(to: marker)
        var info: [String: Any] = ["CFBundleExecutable": "Main", "UIBackgroundModes": ["fetch"]]
        let before = info
        try BackgroundNotifications.apply(app: root, info: &info, options: .init(), dylib: nil)
        XCTAssertTrue(NSDictionary(dictionary: info).isEqual(to: before))
        XCTAssertEqual(try Data(contentsOf: marker), Data("unchanged".utf8))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(BackgroundNotifications.configurationName).path))
    }

    func testMissingLibraryFailsWithoutMutatingMetadata() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        var info: [String: Any] = ["CFBundleExecutable": "Main"]
        var options = PersonalProjectOptions()
        options.backgroundNotifications = true
        options.backgroundMethods = [.significantLocation]
        XCTAssertThrowsError(try BackgroundNotifications.apply(app: root, info: &info, options: options, dylib: nil))
        XCTAssertNil(info["UIBackgroundModes"])
        XCTAssertNil(info["NSLocationAlwaysAndWhenInUseUsageDescription"])
    }

    func testRequiredBackgroundProofRejectsMissingConfigLibraryAndLoadCommand() throws {
        let fixture = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "SignedFolder24Fixture", withExtension: "ipa"))
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        var options = PersonalProjectOptions()
        options.backgroundNotifications = true
        options.backgroundMethods = [.audio, .significantLocation]
        let stage = root.appendingPathComponent("enabled")
        try fm.createDirectory(at: stage, withIntermediateDirectories: true)
        let enabled = try PersonalCertificateSigner.prepare(ipa: fixture, stage: stage, options: options)
        try BackgroundNotifications.verifyInstalled(app: enabled.app, methods: options.backgroundMethods)
        XCTAssertThrowsError(try BackgroundNotifications.verifyInstalled(app: enabled.app, methods: [.audio]))
        let config = enabled.app.appendingPathComponent(BackgroundNotifications.configurationName)
        let originalConfig = try Data(contentsOf: config)
        try fm.removeItem(at: config)
        XCTAssertThrowsError(try BackgroundNotifications.verifyInstalled(app: enabled.app, methods: options.backgroundMethods))
        let external = root.appendingPathComponent("outside.plist")
        try originalConfig.write(to: external)
        try fm.createSymbolicLink(at: config, withDestinationURL: external)
        XCTAssertThrowsError(try BackgroundNotifications.verifyInstalled(app: enabled.app, methods: options.backgroundMethods))
        try fm.removeItem(at: config)
        try originalConfig.write(to: config)
        let library = enabled.app.appendingPathComponent("Frameworks/MirsaBackground.dylib")
        let originalLibrary = try Data(contentsOf: library)
        try fm.removeItem(at: library)
        XCTAssertThrowsError(try BackgroundNotifications.verifyInstalled(app: enabled.app, methods: options.backgroundMethods))
        try originalLibrary.write(to: library)
        let infoURL = enabled.app.appendingPathComponent("Info.plist")
        let originalInfo = try Data(contentsOf: infoURL)
        var incompleteInfo = enabled.info
        incompleteInfo.removeValue(forKey: "UIBackgroundModes")
        try PropertyListSerialization.data(fromPropertyList: incompleteInfo, format: .binary, options: 0).write(to: infoURL)
        XCTAssertThrowsError(try BackgroundNotifications.verifyInstalled(app: enabled.app, methods: options.backgroundMethods))
        try originalInfo.write(to: infoURL)
        try BackgroundNotifications.verifyInstalled(app: enabled.app, methods: options.backgroundMethods)
        let plainStage = root.appendingPathComponent("plain")
        try fm.createDirectory(at: plainStage, withIntermediateDirectories: true)
        let plain = try PersonalCertificateSigner.prepare(ipa: fixture, stage: plainStage, options: .init())
        try fm.createDirectory(at: plain.app.appendingPathComponent("Frameworks"), withIntermediateDirectories: true)
        try originalLibrary.write(to: plain.app.appendingPathComponent("Frameworks/MirsaBackground.dylib"))
        try originalConfig.write(to: plain.app.appendingPathComponent(BackgroundNotifications.configurationName))
        var plainInfo = BackgroundNotifications.configuredInfo(plain.info, enabled: true, methods: options.backgroundMethods)
        // Metadata and payload alone are insufficient without the executable load command.
        plainInfo["CFBundleExecutable"] = plain.info["CFBundleExecutable"]
        try PropertyListSerialization.data(fromPropertyList: plainInfo, format: .binary, options: 0)
            .write(to: plain.app.appendingPathComponent("Info.plist"))
        XCTAssertThrowsError(try BackgroundNotifications.verifyInstalled(app: plain.app, methods: options.backgroundMethods))
    }

    func testNativeSigningInjectionPreservesOriginalAndToggleOff() throws {
        let fixture = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "SignedFolder24Fixture", withExtension: "ipa"))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let input = root.appendingPathComponent("Original.ipa")
        try FileManager.default.copyItem(at: fixture, to: input)
        let original = try RuntimeOriginalIPA.hash(input)
        var options = PersonalProjectOptions()
        options.backgroundNotifications = true
        options.backgroundMethods = [.audio]
        let enabledStage = root.appendingPathComponent("enabled")
        try FileManager.default.createDirectory(at: enabledStage, withIntermediateDirectories: true)
        let enabled = try PersonalCertificateSigner.prepare(ipa: input, stage: enabledStage, options: options)
        let config = try Data(contentsOf: enabled.app.appendingPathComponent(BackgroundNotifications.configurationName))
        let plist = try XCTUnwrap(PropertyListSerialization.propertyList(from: config, format: nil) as? [String: Any])
        XCTAssertEqual(plist["methods"] as? [String], ["audio"])
        XCTAssertTrue((enabled.info["UIBackgroundModes"] as? [String])?.contains("audio") == true)
        XCTAssertNil(enabled.info["NSLocationAlwaysAndWhenInUseUsageDescription"])
        let binaryName = try XCTUnwrap(enabled.info["CFBundleExecutable"] as? String)
        let binary = try Data(contentsOf: enabled.app.appendingPathComponent(binaryName))
        XCTAssertNotNil(binary.range(of: Data("MirsaBackground.dylib".utf8)))
        XCTAssertTrue(FileManager.default.fileExists(atPath: enabled.app.appendingPathComponent("Frameworks/MirsaBackground.dylib").path))
        let disabledStage = root.appendingPathComponent("disabled")
        try FileManager.default.createDirectory(at: disabledStage, withIntermediateDirectories: true)
        let disabled = try PersonalCertificateSigner.prepare(ipa: input, stage: disabledStage, options: .init())
        XCTAssertFalse(FileManager.default.fileExists(atPath: disabled.app.appendingPathComponent(BackgroundNotifications.configurationName).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: disabled.app.appendingPathComponent("Frameworks/MirsaBackground.dylib").path))
        XCTAssertEqual(try RuntimeOriginalIPA.hash(input), original)
    }
}
