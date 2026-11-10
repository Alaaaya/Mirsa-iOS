import Foundation

extension MirsaStoreServerClient {
    static let shared: MirsaStoreServerClient = {
        let auth = DiscoveryAuthClient(projectURL: URL(string: WebBackendConfig.defaultProject)!,
            publishableKey: WebBackendConfig.defaultPublishableKey,
            store: KeychainSessionStore(), http: SafeMetadataHTTP())
        return MirsaStoreServerClient(identity: {
            let bearer = try await auth.token(forceRefresh: false)
            // This claim only chooses a local Keychain slot. The backend verifies the JWT and
            // independently binds its signed user UUID to the hashed opaque device credential.
            let parts = bearer.split(separator: ".")
            guard parts.count == 3 else { throw MirsaStoreServerError(code: "unauthorized") }
            var encoded = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
            while encoded.count % 4 != 0 { encoded += "=" }
            guard let bytes = Data(base64Encoded: encoded),
                  let object = try JSONSerialization.jsonObject(with: bytes) as? [String: Any],
                  let subject = object["sub"] as? String, let user = UUID(uuidString: subject) else {
                throw MirsaStoreServerError(code: "unauthorized")
            }
            return MirsaStoreServerIdentity(bearer: bearer, userID: user)
        })
    }()
}
