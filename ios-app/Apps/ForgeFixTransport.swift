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

protocol ForgeFixSecretStore {
    /// nil = not found. Throws on any other failure (fail closed).
    func read(service: String, account: String) throws -> Data?
    /// Returns false when the item already exists (concurrent creator).
    func add(service: String, account: String, data: Data) throws -> Bool
}

struct ForgeFixStoreError: Error { let status: Int32 }

struct ForgeFixSystemKeychain: ForgeFixSecretStore {
    private func query(_ service: String, _ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
    }
    func read(service: String, account: String) throws -> Data? {
        var q = query(service, account); q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var value: AnyObject?
        let status = SecItemCopyMatching(q as CFDictionary, &value)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = value as? Data else { throw ForgeFixStoreError(status: status) }
        return data
    }
    func add(service: String, account: String, data: Data) throws -> Bool {
        var q = query(service, account); q[kSecValueData as String] = data
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(q as CFDictionary, nil)
        if status == errSecDuplicateItem { return false }
        guard status == errSecSuccess else { throw ForgeFixStoreError(status: status) }
        return true
    }
}

enum ForgeFixKeychain {
    static let service = "com.alaa.mirsa.forge.fix-inbox"
    static func token(user: UUID, device: String, store: ForgeFixSecretStore = ForgeFixSystemKeychain(),
                      random: () -> Data? = { var b = [UInt8](repeating: 0, count: 32); return SecRandomCopyBytes(kSecRandomDefault, 32, &b) == errSecSuccess ? Data(b) : nil }) throws -> String {
        let account = user.uuidString.lowercased() + "." + device.lowercased()
        func valid(_ data: Data?) throws -> String? {
            guard let data else { return nil }
            guard let token = String(data: data, encoding: .utf8),
                  token.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil else {
                throw ForgeClient.Failure.message("Fix identity is unavailable. No token was reset.")
            }
            return token
        }
        func read() throws -> String? {
            do { return try valid(store.read(service: service, account: account)) }
            catch let e as ForgeFixStoreError { throw ForgeClient.Failure.message("Fix identity is unavailable. No token was reset. (\(e.status))") }
        }
        if let token = try read() { return token }
        guard let bytes = random(), bytes.count == 32 else { throw ForgeClient.Failure.message("Cannot create fix identity.") }
        let token = bytes.map { String(format: "%02x", $0) }.joined()
        do { _ = try store.add(service: service, account: account, data: Data(token.utf8)) }
        catch let e as ForgeFixStoreError { throw ForgeClient.Failure.message("Cannot save fix identity. (\(e.status))") }
        guard let saved = try read() else { throw ForgeClient.Failure.message("Cannot save fix identity.") }
        return saved // Re-read handles concurrent callers. Never send before durable storage.
    }
}
