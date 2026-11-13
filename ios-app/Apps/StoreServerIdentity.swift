import Foundation

/// Public builds never reach the App Store login. Backend stays owner-only.
enum MirsaStoreAvailability {
    static let publicLoginEnabled = false
}

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
            // At launch the saved device identity can still be loading. Re-read it (read-only, never enrolling)
            // for a bounded time before concluding this installation has no approved identity.
            let saved = try await MirsaStoreIdentityLoader.load {
                try ForgeClient.existingFixCredentials(bearer: bearer, user: user)
            }
            return MirsaStoreServerIdentity(bearer: saved.accessToken, userID: user,
                forgeDeviceID: saved.deviceID, forgeDeviceToken: saved.deviceToken)
        })
    }()
}

extension MirsaStoreOnDeviceClient {
    static let shared = MirsaStoreOnDeviceClient(gate: {
        await MirsaStoreServerClient.shared.loginAvailable()
    }, historyGate: {
        try await MirsaStoreServerClient.shared.authorizeHistory()
    })
}

/// Bounded, read-only wait for the already-enrolled device identity. Never creates, rotates or resets anything.
enum MirsaStoreIdentityLoader {
    static func load<T>(attempts: Int = 20, delayNanoseconds: UInt64 = 500_000_000,
                        sleep: (UInt64) async throws -> Void = { try await Task.sleep(nanoseconds: $0) },
                        read: () throws -> T) async throws -> T {
        var tried = 0
        while true {
            try Task.checkCancellation()
            do { return try read() }
            catch let error as MirsaStoreServerError {
                guard case .code(let code) = error, code == "staging_denied" else { throw error }
                tried += 1
                if tried >= max(1, attempts) { throw error }
                try await sleep(delayNanoseconds)
            }
        }
    }
}
