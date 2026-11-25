import Foundation
import SwiftUI
import Security

/// Owner test-build only. A short-lived, staging-scoped JWT plus the staging endpoint, imported
/// explicitly by the owner and kept in the Keychain. No provider key, signing secret or prod session
/// is ever accepted, and nothing from here is embedded in an app or IPA.
struct RuntimeStagingSession: Codable, Equatable {
    var endpoint: String
    var token: String
    var expiresAt: Date

    static let allowedHost = "willingly-dejectedly-superb-neanderthal.kitten.space"
    static let pathPrefix = "/runtime-translate-"
    static let issuer = "urn:mirsa:runtime-staging25"
    static let audience = "mirsa-runtime-staging25"
    static let maxLifetime: TimeInterval = 3600

    enum Failure: Error, Equatable { case format, endpoint, token, expired }

    /// Import text is either JSON {"endpoint","accessToken"|"token"} or "endpoint token".
    static func parse(_ text: String, now: Date = Date()) throws -> RuntimeStagingSession {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var endpoint: String?, token: String?
        if let data = trimmed.data(using: .utf8), let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
            endpoint = obj["endpoint"] as? String
            token = (obj["accessToken"] as? String) ?? (obj["token"] as? String)
        } else {
            let parts = trimmed.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" }).map(String.init)
            if parts.count == 2 { endpoint = parts[0]; token = parts[1] }
        }
        guard let endpoint, let token else { throw Failure.format }
        guard let url = URL(string: endpoint), url.scheme == "https", url.host?.lowercased() == allowedHost, url.port == nil,
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
              url.path.hasPrefix(pathPrefix), url.path.count > pathPrefix.count + 8 else { throw Failure.endpoint }
        let exp = try validate(token: token, now: now)
        return RuntimeStagingSession(endpoint: endpoint, token: token, expiresAt: exp)
    }

    /// Structural check only (the server verifies the signature): staging issuer and audience, bounded exp.
    static func validate(token: String, now: Date) throws -> Date {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3, token.count < 4096 else { throw Failure.token }
        var b64 = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while b64.count % 4 != 0 { b64 += "=" }
        guard let data = Data(base64Encoded: b64), let claims = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              claims["iss"] as? String == issuer, let exp = (claims["exp"] as? NSNumber)?.doubleValue else { throw Failure.token }
        let aud = claims["aud"]
        guard (aud as? String) == audience || ((aud as? [String])?.contains(audience) == true) else { throw Failure.token }
        guard let iat = (claims["iat"] as? NSNumber)?.doubleValue, iat <= now.timeIntervalSince1970 + 60, exp - iat > 0, exp - iat <= maxLifetime else { throw Failure.token }
        let date = Date(timeIntervalSince1970: exp)
        guard date > now else { throw Failure.expired }
        guard date.timeIntervalSince(now) <= maxLifetime else { throw Failure.token }
        return date
    }

    var isValid: Bool { expiresAt > Date().addingTimeInterval(30) }
}

enum RuntimeStagingSessionStore {
    private static let service = "com.alaa.mirsa.runtime.staging.session"
    struct KeychainFailure: LocalizedError, Equatable {
        let status: OSStatus
        var errorDescription: String? { "Translation session Keychain error (\(status))." }
    }
    private static var base: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
         kSecAttrAccount as String: "owner-staging"]
    }
    /// Fail closed for automatic use; explicit operator imports surface the native OSStatus.
    static func load(now: Date = Date()) -> RuntimeStagingSession? { try? read(now: now) }
    static func read(now: Date = Date()) throws -> RuntimeStagingSession? {
        var q = base; q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: AnyObject?
        let status = SecItemCopyMatching(q as CFDictionary, &out)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainFailure(status: status) }
        guard let d = out as? Data else { throw KeychainFailure(status: errSecDecode) }
        let s = try JSONDecoder().decode(RuntimeStagingSession.self, from: d)
        guard s.expiresAt > now else { return nil }
        return s
    }
    static func save(_ s: RuntimeStagingSession?) throws {
        guard let s else {
            let status = SecItemDelete(base as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainFailure(status: status) }
            return
        }
        let d = try JSONEncoder().encode(s)
        // Update atomically. Never delete a working credential before a write succeeds.
        let attrs: [String: Any] = [kSecValueData as String: d,
                                  kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        var status = SecItemUpdate(base as CFDictionary, attrs as CFDictionary)
        if status == errSecItemNotFound {
            var add = base; attrs.forEach { add[$0.key] = $0.value }
            status = SecItemAdd(add as CFDictionary, nil)
            if status == errSecDuplicateItem { status = SecItemUpdate(base as CFDictionary, attrs as CFDictionary) }
        }
        guard status == errSecSuccess else { throw KeychainFailure(status: status) }
        guard try read() == s else { throw KeychainFailure(status: errSecDecode) }
    }
    /// The owner import UI is only offered when this build opts in via Info.plist.
    static var importEnabled: Bool { false }
}

struct RuntimeStagingTokenProvider: DiscoveryTokenProvider {
    let session: RuntimeStagingSession
    func token(forceRefresh: Bool) async throws -> String {
        guard session.isValid else { throw RuntimeTranslationError.notConfigured }
        return session.token
    }
}
