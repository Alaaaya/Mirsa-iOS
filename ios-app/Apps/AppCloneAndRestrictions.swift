import Foundation

/// Opt-in removal of device restrictions. Operates only on the extracted project COPY handed to prepare().
enum DeviceRestrictions {
    static let keys = ["UIDeviceFamily", "MinimumOSVersion", "UIRequiredDeviceCapabilities"]
    static func strip(_ info: inout [String: Any]) {
        for key in keys { info.removeValue(forKey: key) }
    }
    /// Same removal for embedded app extensions (PlugIns/*.appex) of the copy.
    static func stripExtensions(in app: URL) throws {
        let fm = FileManager.default
        let plugins = app.appendingPathComponent("PlugIns", isDirectory: true)
        guard let items = try? fm.contentsOfDirectory(at: plugins, includingPropertiesForKeys: nil) else { return }
        for appex in items where appex.pathExtension == "appex" {
            let plist = appex.appendingPathComponent("Info.plist")
            guard let data = try? Data(contentsOf: plist),
                  var info = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any] else { continue }
            strip(&info)
            try PropertyListSerialization.data(fromPropertyList: info, format: .binary, options: 0).write(to: plist, options: .atomic)
        }
    }
    static func removed(from info: [String: Any]) -> [String] { keys.filter { info[$0] != nil } }
}

/// Clone = same app under a NEW bundle identifier (and name) so both can be installed side by side.
enum AppClone {
    /// Wildcard-aware profile pattern match, e.g. "ABCDE12345.com.me.*" or "ABCDE12345.*".
    static func profileAllows(_ bundleID: String, pattern: String, teamID: String) -> Bool {
        var p = pattern
        if !teamID.isEmpty, p.hasPrefix(teamID + ".") { p = String(p.dropFirst(teamID.count + 1)) }
        if p == "*" { return true }
        if p.hasSuffix("*") { return bundleID.hasPrefix(String(p.dropLast())) }
        return p == bundleID
    }
    /// Builds a valid, different bundle identifier. `index` makes several clones distinct.
    static func cloneID(from original: String, index: Int = 1, existing: Set<String> = []) -> String {
        var n = max(1, index)
        while true {
            let candidate = original + ".clone" + (n == 1 ? "" : String(n))
            if !existing.contains(candidate), IPAEditorService.validBundleID(candidate) { return candidate }
            n += 1
            if n > 999 { return original + ".c" + String(UUID().uuidString.prefix(6)).lowercased() }
        }
    }
    enum Failure: LocalizedError {
        case sameID, invalid, profile(String)
        var errorDescription: String? {
            switch self {
            case .sameID: return sgText("The clone needs a different bundle ID.", "النسخة بدها معرّف مختلف.", "کلۆن پێویستی بە ناسنامەیەکی جیاواز هەیە.", "Klon pêdivî bi nasnameyeke cuda heye.")
            case .invalid: return sgText("Invalid bundle ID.", "معرّف غير صالح.", "ناسنامە دروست نییە.", "Nasname ne derbasdar e.")
            case .profile(let pattern): return sgText("The profile (\(pattern)) does not allow this ID.", "البروفايل (\(pattern)) ما بيسمح بهالمعرّف.", "پرۆفایل (\(pattern)) ئەم ناسنامەیە ڕێگە پێنادات.", "Profîl (\(pattern)) vê nasnameyê qebûl nake.")
            }
        }
    }
    /// Returns options configured as a clone. Refuses an ID the chosen profile cannot cover.
    static func options(base: PersonalProjectOptions, originalID: String, originalName: String,
                        newID: String, newName: String?, identity: PersonalIdentityVault.SavedIdentity?) throws -> PersonalProjectOptions {
        guard IPAEditorService.validBundleID(newID) else { throw Failure.invalid }
        guard newID != originalID else { throw Failure.sameID }
        if let identity, !identity.bundleID.isEmpty, !AppClone.profileAllows(newID, pattern: identity.bundleID, teamID: identity.teamID) {
            throw Failure.profile(identity.bundleID)
        }
        var o = base
        o.bundleID = newID
        let name = (newName?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 }
        o.displayName = name ?? originalName + " 2"
        return o
    }
}
