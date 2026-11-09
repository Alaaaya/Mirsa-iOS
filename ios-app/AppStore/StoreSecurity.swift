import Foundation
import Security

enum MirsaStoreError: Error, Equatable, LocalizedError {
    case busy, signedOut, verificationRequired, invalidInput, freeAppsOnly
    case keychain(Int32), invalidPackage, untrustedURL, serviceUnavailable
    case licenseRequired, operationCancelled
    var errorDescription: String? {
        switch self {
        case .busy: return "Another App Store operation is still running."
        case .signedOut: return "Sign in to your Apple Account first."
        case .verificationRequired: return "Enter the six-digit verification code from Apple."
        case .invalidInput: return "Check the email, country, app or version ID."
        case .freeAppsOnly: return "Only apps confirmed free in this account's store can be acquired."
        case .keychain: return "The device Keychain is unavailable. Unlock the device and try again."
        case .invalidPackage: return "Apple returned a package that does not match the requested app or version."
        case .untrustedURL: return "The download did not use a trusted Apple HTTPS address."
        case .serviceUnavailable: return "Apple could not complete the request. Check your connection, account region and App Store terms, then try again."
        case .licenseRequired: return "This Apple Account does not own this app. Acquire its free license first."
        case .operationCancelled: return "The App Store operation was cancelled."
        }
    }
}

protocol MirsaStoreVault {
    func read(_ key: String) throws -> Data?
    func write(_ data: Data, key: String) throws
    func remove(_ key: String) throws
}

/// Separate service from signing accounts. No shared group, synchronization or file fallback.
struct MirsaStoreKeychain: MirsaStoreVault {
    private let service = "com.alaa.mirsa.appstore.private"
    private func query(_ key: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service, kSecAttrAccount as String: key,
         kSecAttrSynchronizable as String: false]
    }
    func read(_ key: String) throws -> Data? {
        var q = query(key)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else {
            throw MirsaStoreError.keychain(status)
        }
        return data
    }
    func write(_ data: Data, key: String) throws {
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        let status = SecItemUpdate(query(key) as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var add = query(key)
            attributes.forEach { add[$0.key] = $0.value }
            let added = SecItemAdd(add as CFDictionary, nil)
            guard added == errSecSuccess else { throw MirsaStoreError.keychain(added) }
        } else if status != errSecSuccess { throw MirsaStoreError.keychain(status) }
    }
    func remove(_ key: String) throws {
        let status = SecItemDelete(query(key) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw MirsaStoreError.keychain(status)
        }
    }
}

enum MirsaStorePolicy {
    static func country(_ value: String) throws -> String {
        let value = value.uppercased()
        guard value.utf8.count == 2, value.utf8.allSatisfy({ (65...90).contains($0) }) else {
            throw MirsaStoreError.invalidInput
        }
        return value
    }
    static func version(_ value: String?) throws -> String? {
        guard let value, !value.isEmpty else { return nil }
        guard value.utf8.count <= 20, value.utf8.allSatisfy({ (48...57).contains($0) }),
              UInt64(value) != nil, UInt64(value) != 0 else { throw MirsaStoreError.invalidInput }
        return value
    }
    static func requireFree(_ price: Double?) throws {
        guard let price, price.isFinite, price == 0 else { throw MirsaStoreError.freeAppsOnly }
    }
    static func downloadURL(_ url: URL) throws {
        guard url.scheme?.lowercased() == "https", let host = url.host?.lowercased(),
              url.user == nil, url.password == nil, url.port == nil || url.port == 443,
              ["apple.com", "mzstatic.com", "cdn-apple.com"].contains(where: {
                  host == $0 || host.hasSuffix("." + $0)
              }) else { throw MirsaStoreError.untrustedURL }
    }
    static func archivePath(_ path: String) throws {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        guard !path.isEmpty, !path.hasPrefix("/"), !path.contains("\\"),
              !parts.contains(".."), !parts.contains("."), !path.contains("\0") else {
            throw MirsaStoreError.invalidPackage
        }
    }
}
