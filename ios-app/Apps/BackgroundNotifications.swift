import Foundation

/// App-local opt-in methods. Empty selection observes events only, without keep-alive.
enum BackgroundNotificationMethod: String, Codable, CaseIterable, Sendable {
    case audio, significantLocation
}

enum BackgroundNotifications {
    static let configurationName = "MirsaBackgroundNotifications.plist"
    static let assetFolder = "BackgroundNotificationAssets"
    static var bundledDylib: URL? {
        Bundle.main.url(forResource: "MirsaBackground", withExtension: "dylib", subdirectory: assetFolder)
    }

    /// Pure metadata transform. Disabled means no added modes, permissions or config.
    static func configuredInfo(_ original: [String: Any], enabled: Bool,
                               methods: [BackgroundNotificationMethod]) -> [String: Any] {
        guard enabled else { return original }
        var info = original
        var modes = info["UIBackgroundModes"] as? [String] ?? []
        func add(_ value: String) { if !modes.contains(value) { modes.append(value) } }
        if methods.contains(.audio) { add("audio") }
        if methods.contains(.significantLocation) {
            add("location")
            let disclosure = "اخترت إشعارات بالخلفية عبر تغيّر الموقع الكبير. التطبيق بيستقبل أحداث الموقع لإعطاء فرص تشغيل بالخلفية، بدون تخزين أو إرسال الإحداثيات. مو ضمان لبقاء التطبيق شغّال."
            for key in ["NSLocationWhenInUseUsageDescription", "NSLocationAlwaysAndWhenInUseUsageDescription"] {
                let existing = (info[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                info[key] = existing.isEmpty ? disclosure : existing + "\n" + disclosure
            }
        }
        if !modes.isEmpty { info["UIBackgroundModes"] = modes }
        return info
    }

    static func configuration(enabled: Bool, methods: [BackgroundNotificationMethod]) -> [String: Any]? {
        guard enabled else { return nil }
        return ["schema": 1, "enabled": true, "methods": BackgroundNotificationMethod.allCases.filter { methods.contains($0) }.map(\.rawValue)]
    }

    private enum VerificationError: Error { case invalid }

    /// The same fail-closed boundary is used for the staged app and final signed archive.
    /// Check actual files, parsed load commands and selected opt-in methods, not a log notice.
    static func verifyInstalled(app: URL, methods: [BackgroundNotificationMethod]) throws {
        do {
            let fm = FileManager.default
            let frameworks = app.appendingPathComponent("Frameworks")
            let library = frameworks.appendingPathComponent("MirsaBackground.dylib")
            let config = app.appendingPathComponent(configurationName)
            let infoPath = app.appendingPathComponent("Info.plist")
            for path in [app, frameworks, library, config, infoPath] {
                guard (try? fm.destinationOfSymbolicLink(atPath: path.path)) == nil else {
                    throw VerificationError.invalid
                }
            }
            let attributes = try config.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            let libraryAttributes = try library.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard attributes.isRegularFile == true, let size = attributes.fileSize, size > 0, size < 16_384,
                  libraryAttributes.isRegularFile == true, let librarySize = libraryAttributes.fileSize,
                  librarySize > 0, librarySize < 4 * 1024 * 1024,
                  let actual = try PropertyListSerialization.propertyList(from: Data(contentsOf: config), format: nil) as? [String: Any],
                  let expected = configuration(enabled: true, methods: methods),
                  NSDictionary(dictionary: actual).isEqual(to: expected) else { throw VerificationError.invalid }
            let info = try IPAEditorService.info(in: app)
            guard let executable = info["CFBundleExecutable"] as? String, !executable.isEmpty,
                  !executable.contains("/"), !executable.contains("\\"), executable != ".", executable != ".." else {
                throw VerificationError.invalid
            }
            let main = app.appendingPathComponent(executable)
            guard (try? fm.destinationOfSymbolicLink(atPath: main.path)) == nil else { throw VerificationError.invalid }
            let loads = try IPAEditorService.dependencies(of: main)
            guard loads.filter({ $0 == "@loader_path/Frameworks/MirsaBackground.dylib" }).count == 1 else {
                throw VerificationError.invalid
            }
            let modes = info["UIBackgroundModes"] as? [String] ?? []
            if methods.contains(.audio), !modes.contains("audio") { throw VerificationError.invalid }
            if methods.contains(.significantLocation) {
                guard modes.contains("location") else { throw VerificationError.invalid }
                for key in ["NSLocationWhenInUseUsageDescription", "NSLocationAlwaysAndWhenInUseUsageDescription"] {
                    guard let value = info[key] as? String, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                        throw VerificationError.invalid
                    }
                }
            }
            try IPAEditorService.run("validate", input: library)
        } catch {
            throw SideloadError.message(personalText("The requested background notifications could not be verified. No IPA was exported.", "ما قدرت أتأكد من إشعارات الخلفية المطلوبة. ما تم تصدير IPA."))
        }
    }

    /// Transactional changes to the extracted COPY. The caller pins/verifies the retained IPA.
    /// Called once before the caller saves Info.plist. No translation state or backend access.
    static func apply(app: URL, info: inout [String: Any], options: PersonalProjectOptions,
                      dylib: URL? = bundledDylib) throws {
        guard options.backgroundNotifications else { return }
        let fm = FileManager.default
        guard let executable = info["CFBundleExecutable"] as? String, !executable.isEmpty,
              !executable.contains("/"), !executable.contains("\\"), executable != ".", executable != "..",
              let dylib else {
            throw SideloadError.message(personalText("Background notification support is missing from this build.", "دعم إشعارات الخلفية مو موجود بهالنسخة."))
        }
        let attributes = try dylib.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard attributes.isRegularFile == true, attributes.isSymbolicLink != true,
              let size = attributes.fileSize, size > 0, size < 4 * 1024 * 1024 else {
            throw SideloadError.message(personalText("Invalid background notification library.", "مكتبة إشعارات الخلفية مو صالحة."))
        }
        let frameworks = app.appendingPathComponent("Frameworks")
        let configPath = app.appendingPathComponent(configurationName)
        for path in [app, frameworks, configPath, frameworks.appendingPathComponent("MirsaBackground.dylib")] {
            guard (try? fm.destinationOfSymbolicLink(atPath: path.path)) == nil else {
                throw SideloadError.message(personalText("Unsafe background notification destination.", "مسار إشعارات الخلفية مو آمن."))
            }
        }
        guard !fm.fileExists(atPath: configPath.path),
              !fm.fileExists(atPath: frameworks.appendingPathComponent("MirsaBackground.dylib").path) else {
            throw SideloadError.message(personalText("Use the original app to change background notifications.", "استخدم التطبيق الأصلي لتغيّر إشعارات الخلفية."))
        }
        let updatedInfo = configuredInfo(info, enabled: true, methods: options.backgroundMethods)
        let config = configuration(enabled: true, methods: options.backgroundMethods)!
        let work = fm.temporaryDirectory.appendingPathComponent("background-notifications-" + UUID().uuidString)
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: work) }
        let copy = work.appendingPathComponent(app.lastPathComponent)
        try fm.copyItem(at: app, to: copy)
        try IPAEditorService.run("inject", input: copy, executable: executable, libraries: [dylib], newFirst: false)
        try PropertyListSerialization.data(fromPropertyList: config, format: .binary, options: 0)
            .write(to: copy.appendingPathComponent(configurationName), options: [.atomic, .completeFileProtection])
        try PropertyListSerialization.data(fromPropertyList: updatedInfo, format: .binary, options: 0)
            .write(to: copy.appendingPathComponent("Info.plist"), options: .atomic)
        try verifyInstalled(app: copy, methods: options.backgroundMethods)
        let backup = work.appendingPathComponent("original.app")
        try fm.moveItem(at: app, to: backup)
        do { try fm.moveItem(at: copy, to: app) }
        catch { try fm.moveItem(at: backup, to: app); throw error }
        info = updatedInfo
    }
}
