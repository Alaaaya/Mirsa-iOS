import Foundation
import Security

struct ForgeFixCredentials {
    let accessToken: String
    let deviceID: String
    let deviceToken: String
}

extension ForgeClient {
    /// Parses only the binding key, never treats decoded claims as authorization.
    /// Server getUser validates the actual user JWT on every request.
    static func fixUserID(_ jwt: String) throws -> UUID {
        let parts = jwt.split(separator: ".")
        guard parts.count == 3 else { throw Failure.message("Missing user session.") }
        var payload = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while payload.count % 4 != 0 { payload += "=" }
        guard let data = Data(base64Encoded: payload),
              let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sub = obj["sub"] as? String, let id = UUID(uuidString: sub),
              obj["role"] as? String == "authenticated" else { throw Failure.message("Missing authenticated user session.") }
        return id
    }

    static func fixToken() async throws -> ForgeFixCredentials {
        let auth = DiscoveryAuthClient(projectURL: URL(string: WebBackendConfig.defaultProject)!,
            publishableKey: WebBackendConfig.defaultPublishableKey, store: KeychainSessionStore(), http: SafeMetadataHTTP())
        let jwt = try await auth.token(forceRefresh: false)
        let user = try fixUserID(jwt)
        let device = deviceID()
        let token = try ForgeFixKeychain.token(user: user, device: device)
        let credentials = ForgeFixCredentials(accessToken: jwt, deviceID: device, deviceToken: token)
        // Repeat registration with the SAME saved token. Lost responses cannot strand the device.
        let response = try await fixRequest(["action": "fix-register", "deviceToken": token], deviceToken: credentials)
        guard let obj = try JSONSerialization.jsonObject(with: response) as? [String: Any],
              obj["version"] as? Int == 1, obj["deviceToken"] as? String == token else {
            throw Failure.message("Device registration could not be verified.")
        }
        return credentials
    }

    static func fixRequest(_ body: [String: Any], deviceToken credentials: ForgeFixCredentials, maxBytes: Int = 6 * 1024 * 1024) async throws -> Data {
        var request = URLRequest(url: endpoint, timeoutInterval: 60)
        request.httpMethod = "POST"
        request.setValue("Bearer " + credentials.accessToken, forHTTPHeaderField: "Authorization")
        request.setValue(credentials.deviceID, forHTTPHeaderField: "x-mirsa-device")
        request.setValue(credentials.deviceToken, forHTTPHeaderField: "x-mirsa-device-token")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil; config.urlCache = nil
        let session = URLSession(configuration: config, delegate: OTANoRedirect(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (stream, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              response.url == endpoint, response.expectedContentLength <= Int64(maxBytes) else {
            throw Failure.message("Fix sync request failed. Reopen Mirsa to retry.")
        }
        var result = Data()
        for try await byte in stream {
            guard result.count < maxBytes else { throw Failure.message("Fix response exceeds its limit.") }
            result.append(byte)
        }
        if body["action"] as? String == "fix-download" {
            guard http.mimeType == "application/octet-stream",
                  http.value(forHTTPHeaderField: "x-content-sha256") == ForgeFixItem.sha(result) else {
                throw Failure.message("Fix download verification failed.")
            }
        }
        return result
    }
}

enum ForgeFixKeychain {
    static func token(user: UUID, device: String) throws -> String {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.alaa.mirsa.forge.fix-inbox",
            kSecAttrAccount as String: user.uuidString.lowercased() + "." + device.lowercased()]
        func read() throws -> String? {
            var q = query; q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
            var value: AnyObject?
            let status = SecItemCopyMatching(q as CFDictionary, &value)
            if status == errSecItemNotFound { return nil }
            guard status == errSecSuccess, let data = value as? Data, let token = String(data: data, encoding: .utf8),
                  token.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil else {
                throw ForgeClient.Failure.message("Fix identity is unavailable. No token was reset.")
            }
            return token
        }
        if let token = try read() { return token }
        var random = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, random.count, &random) == errSecSuccess else {
            throw ForgeClient.Failure.message("Cannot create fix identity.")
        }
        let token = random.map { String(format: "%02x", $0) }.joined()
        var add = query; add[kSecValueData as String] = Data(token.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess || status == errSecDuplicateItem, let saved = try read() else {
            throw ForgeClient.Failure.message("Cannot save fix identity.")
        }
        return saved // Re-read handles concurrent callers. Never send before durable storage.
    }
}
