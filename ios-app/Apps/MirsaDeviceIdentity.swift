import Foundation
import Security
import AirliftFFI

/// Stable Mirsa device identity.
/// - deviceID: the existing random lowercase UUID (format and header unchanged), stored in the Keychain with
///   kSecAttrAccessibleAfterFirstUnlock and never synced to iCloud. Keychain items survive app updates and
///   delete + reinstall as long as the app is signed with the same team (same keychain access group).
/// - UDID: read once from lockdown (UniqueDeviceID) over LocalDevVPN + pairing file, stored in the Keychain the same way.
///   Never shown in the UI; sent only as the optional device_udid field behind MirsaFeatures.stableDeviceLink.
enum MirsaDeviceIdentity {
    static let idService = "com.alaa.mirsa.forge.device"   // same service as before, so existing installs keep their ID
    static let udidService = "com.alaa.mirsa.device.udid"
    /// UserDefaults keys an older build may have used for the ID. No shipped Mirsa build stored the ID in
    /// UserDefaults (it has always been in the Keychain); keep the hook so a known legacy key can be added here.
    static let legacyDefaultsKeys: [String] = []

    private static let lock = NSLock()
    private static var cachedID: String?

    static func deviceID() -> String {
        lock.lock(); defer { lock.unlock() }
        if let c = cachedID { return c }
        // 1. Keychain first.
        if let s = read(idService), UUID(uuidString: s) != nil {
            ensureAttributes(idService)
            cachedID = s; return s
        }
        // 2. Legacy UserDefaults value: move it to the Keychain, then remove it from UserDefaults.
        for key in legacyDefaultsKeys {
            if let s = UserDefaults.standard.string(forKey: key), UUID(uuidString: s) != nil {
                let v = s.lowercased()
                if write(idService, v) { UserDefaults.standard.removeObject(forKey: key) }
                cachedID = v; return v
            }
        }
        // 3. Neither: create a new one.
        let id = UUID().uuidString.lowercased()
        _ = write(idService, id)
        cachedID = id
        return id
    }

    // MARK: UDID

    static func storedUDID() -> String? {
        guard let s = read(udidService), validUDID(s) else { return nil }
        return s
    }

    /// 25-char "00008130-001A2B3C4D5E6F7A" style or 40-hex legacy UDID.
    static func validUDID(_ s: String) -> Bool {
        let hex = Set("0123456789abcdefABCDEF-")
        return (s.count == 25 || s.count == 40) && s.allSatisfy { hex.contains($0) }
    }

    @MainActor private static var reading = false
    /// Reads UniqueDeviceID from lockdown once when LocalDevVPN is up and the pairing file exists. Silent on failure.
    @MainActor static func refreshUDIDIfPossible(_ vm: AppViewModel) {
        guard storedUDID() == nil, !reading else { return }
        let path = PairingController.pairingFilePath()
        guard FileManager.default.fileExists(atPath: path),
              DeviceConnectionPolicy.mayAttempt(tunnelRoute: NetworkStatus.summarize(deviceIP: vm.deviceIP).vpn, hasPairing: true) else { return }
        vm.syncTargetHostsToRust()
        reading = true
        DispatchQueue.global(qos: .utility).async {
            var out: UnsafeMutablePointer<CChar>?
            var err: UnsafeMutablePointer<CChar>?
            let rc = path.withCString { al_device_udid($0, &out, &err) }
            let udid = out.map { String(cString: $0) }
            if let p = out { al_string_free(p) }
            if let p = err { al_string_free(p) }
            if rc == 0, let u = udid, validUDID(u) { _ = write(udidService, u) }
            Task { @MainActor in reading = false }
        }
    }

    // MARK: Keychain

    private static func base(_ service: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrSynchronizable as String: kCFBooleanFalse as Any]
    }

    private static func read(_ service: String) -> String? {
        var q = base(service)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }

    @discardableResult
    private static func write(_ service: String, _ value: String) -> Bool {
        let attrs: [String: Any] = [kSecValueData as String: Data(value.utf8),
                                    kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock]
        let st = SecItemUpdate(base(service) as CFDictionary, attrs as CFDictionary)
        if st == errSecSuccess { return true }
        guard st == errSecItemNotFound else { return false }
        var add = base(service); attrs.forEach { add[$0.key] = $0.value }
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }

    /// Older builds wrote the ID with ...AfterFirstUnlockThisDeviceOnly; move it to AfterFirstUnlock (still not synced). Value untouched.
    private static func ensureAttributes(_ service: String) {
        let attrs: [String: Any] = [kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock]
        _ = SecItemUpdate(base(service) as CFDictionary, attrs as CFDictionary)
    }
}
