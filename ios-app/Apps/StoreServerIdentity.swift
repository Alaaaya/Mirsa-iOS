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
            // The app's own idempotent registration (same saved token) must have succeeded once for this user
            // before the first gate check; concurrent searches share one in-flight registration.
            let saved = try await MirsaStoreRegistration.shared.credentials(user: user) {
                try await ForgeClient.fixToken()
            }
            return MirsaStoreServerIdentity(bearer: saved.accessToken, userID: user,
                forgeDeviceID: saved.deviceID, forgeDeviceToken: saved.deviceToken)
        })
    }()
}

extension MirsaStoreOnDeviceClient {
    static let shared = MirsaStoreOnDeviceClient(gate: {
        await MirsaStoreServerClient.shared.loginAvailable()
    }, stateGate: {
        await MirsaStoreServerClient.shared.gateState()
    }, historyGate: {
        try await MirsaStoreServerClient.shared.authorizeHistory()
    })
}

/// Bounded, read-only wait for the already-enrolled device identity. Never creates, rotates or resets anything.
enum MirsaStoreIdentityLoader {
    /// Posted once the saved device identity is loaded/verified; the Store re-evaluates availability then.
    static let readyNotification = Notification.Name("mirsa.device.identity.ready")
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

    /// Read the saved identity; if it is not there yet, await one real registration/refresh and read again.
    /// A transient refresh failure surfaces as upstream_unavailable (unknown), never as an identity denial.
    /// Only a missing identity after a successful refresh is the definitive staging_denied.
    static func loadRefreshing<T>(refresh: () async throws -> Void, read: () throws -> T) async throws -> T {
        do { return try read() }
        catch let error as MirsaStoreServerError {
            guard case .code(let code) = error, code == "staging_denied" else { throw error }
        }
        try Task.checkCancellation()
        try await refresh()
        try Task.checkCancellation()
        return try read()
    }
}

/// Shares one in-flight registration per user and remembers success, so a cold start with a stored token but a
/// pending registration is never judged by a local read alone. Only a verified registration result is used.
actor MirsaStoreRegistration {
    static let shared = MirsaStoreRegistration()
    private var ready: [UUID: ForgeFixCredentials] = [:]
    private var inflight: [UUID: Task<ForgeFixCredentials, Error>] = [:]

    func credentials(user: UUID, register: @escaping @Sendable () async throws -> ForgeFixCredentials) async throws -> ForgeFixCredentials {
        if let done = ready[user] { return done }
        let task: Task<ForgeFixCredentials, Error>
        if let running = inflight[user] { task = running } else {
            task = Task {
                let c: ForgeFixCredentials
                do { c = try await register() }
                catch let e as MirsaStoreServerError { throw e }
                catch is CancellationError { throw CancellationError() }
                catch { throw MirsaStoreServerError(code: "upstream_unavailable") }
                // The returned bearer must belong to the same user; otherwise the result is unknown, not a denial.
                guard (try? ForgeClient.fixUserID(c.accessToken)) == user else { throw MirsaStoreServerError(code: "upstream_unavailable") }
                return c
            }
            inflight[user] = task
        }
        do {
            let c = try await task.value
            ready[user] = c; inflight[user] = nil
            return c
        } catch {
            inflight[user] = nil
            throw error
        }
    }
}
