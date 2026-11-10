import Foundation

struct MirsaStoreServerIdentity {
    let bearer: String
    let userID: UUID
}

enum MirsaStoreServerError: Error, Equatable {
    case code(String)
    static let allowed = Set(["unauthorized", "device_required", "rate_limited", "challenge_expired",
        "invalid_code", "credentials_rejected", "session_expired", "not_authenticated",
        "paid_app_forbidden", "license_required", "not_found", "artifact_expired", "too_large", "busy", "upstream_unavailable"])
    init(code: String) { self = .code(Self.allowed.contains(code) ? code : "upstream_unavailable") }
}

/// The server is the sole Apple protocol adapter. No password or challenge secret is persisted.
/// Only an opaque device token bound to the fixed Supabase user is stored in this-device Keychain.
actor MirsaStoreServerClient {
    typealias Identity = () async throws -> MirsaStoreServerIdentity
    typealias HTTP = (URLRequest) async throws -> (Data, Int)
    private let identity: Identity
    private let vault: any MirsaStoreVault
    private let transport: MirsaStoreServerTransport
    private let http: HTTP
    private let pause: () async throws -> Void
    static let maximumPolls = 300
    private var busy = false
    private var removedLegacySecrets = false
    private var generation: UInt64 = 0
    private var pending: (id: String, expires: Date, attempts: Int)?
    private var artifact: MirsaStoreServerArtifact?
    private var lastIdentity: MirsaStoreServerIdentity?

    init(identity: @escaping Identity, vault: any MirsaStoreVault = MirsaStoreKeychain(),
         transport: MirsaStoreServerTransport = try! MirsaStoreServerTransport(
            origin: URL(string: "https://mirsa-app.mooo.com")!),
         http: HTTP? = nil,
         pause: @escaping () async throws -> Void = { try await Task.sleep(nanoseconds: 2_000_000_000) }) {
        self.identity = identity; self.vault = vault; self.transport = transport; self.pause = pause
        self.http = http ?? { try await transport.json($0) }
    }

    private struct Account: Decodable {
        let email: String
        let name: String?
        let storefront: String
        var summary: MirsaStoreAccount { MirsaStoreAccount(email: email, country: storefront, name: name ?? "") }
    }
    private struct State: Decodable {
        let status: String
        let account: Account?
        let challengeID: String?
        let expiresAt: String?
        let passwordRequired: Bool?
    }
    private struct Device: Decodable { let deviceToken: String }
    private struct Failure: Decodable { struct Detail: Decodable { let code: String }; let error: Detail }
    private struct Apps: Decodable { let apps: [App] }
    private struct App: Decodable {
        let id: Int64; let bundleID: String; let name: String; let version: String; let price: Double?
        var summary: MirsaStoreApp { MirsaStoreApp(id: id, bundleID: bundleID, name: name,
                                                  version: version, price: price, artworkURL: "") }
    }
    private struct Job: Decodable {
        let jobID: String; let status: String; let appID: Int64
        let externalVersionID: String?; let artifact: Artifact?
    }
    private struct Versions: Decodable {
        let appID: Int64; let latestExternalVersionID: String; let versions: [String]
    }
    struct Artifact: Decodable {
        let url: String; let size: Int64; let sha256: String; let expiresAt: String
        let appID: Int64; let externalVersionID: String?
    }

    static func date(_ value: String) -> Date? {
        let f = ISO8601DateFormatter()
        if let date = f.date(from: value) { return date }
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: value)
    }

    private func begin() throws -> UInt64 {
        guard !busy else { throw MirsaStoreError.busy }
        busy = true
        return generation
    }
    private func check(_ run: UInt64) throws {
        guard generation == run, !Task.isCancelled else { throw MirsaStoreError.operationCancelled }
    }
    private func key(_ identity: MirsaStoreServerIdentity) -> String {
        "server-device." + identity.userID.uuidString.lowercased()
    }
    private func request(_ path: String, method: String = "POST", body: [String: Any]? = [:],
                         owner: MirsaStoreServerIdentity, device: String? = nil) throws -> URLRequest {
        var request = URLRequest(url: try transport.url("/store/v1" + path), timeoutInterval: 180)
        request.httpMethod = method
        request.setValue("Bearer " + owner.bearer, forHTTPHeaderField: "Authorization")
        if let device { request.setValue(device, forHTTPHeaderField: "X-Mirsa-Store-Device") }
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if method != "GET", let body { request.httpBody = try JSONSerialization.data(withJSONObject: body) }
        return request
    }
    private func perform<T: Decodable>(_ request: URLRequest, as type: T.Type) async throws -> T {
        let (data, status) = try await http(request)
        guard (200..<300).contains(status) else {
            let code = (try? JSONDecoder().decode(Failure.self, from: data))?.error.code
                ?? (status == 401 ? "unauthorized" : "upstream_unavailable")
            throw MirsaStoreServerError(code: code)
        }
        do { return try JSONDecoder().decode(T.self, from: data) }
        catch { throw MirsaStoreServerError(code: "upstream_unavailable") }
    }
    private func credentials(_ run: UInt64) async throws -> (MirsaStoreServerIdentity, String) {
        if !removedLegacySecrets {
            try vault.remove("account")
            try vault.remove("challenge")
            removedLegacySecrets = true
        }
        let owner = try await identity()
        try check(run)
        if let previous = lastIdentity, previous.userID != owner.userID { pending = nil }
        lastIdentity = owner
        if let data = try vault.read(key(owner)) {
            guard let token = String(data: data, encoding: .utf8), Self.validToken(token) else {
                throw MirsaStoreServerError(code: "device_required")
            }
            return (owner, token)
        }
        let device = try await perform(request("/devices", owner: owner), as: Device.self)
        try check(run)
        guard Self.validToken(device.deviceToken) else { throw MirsaStoreServerError(code: "device_required") }
        try vault.write(Data(device.deviceToken.utf8), key: key(owner))
        return (owner, device.deviceToken)
    }
    private static func validToken(_ value: String) -> Bool {
        value.utf8.count >= 32 && value.utf8.count <= 256 &&
            value.utf8.allSatisfy { (48...57).contains($0) || (65...90).contains($0) ||
                (97...122).contains($0) || $0 == 45 || $0 == 95 }
    }

    func currentAccount() async throws -> MirsaStoreAccount? {
        let run = try begin(); defer { busy = false }
        let (owner, token) = try await credentials(run)
        let state = try await perform(request("/account", method: "GET", body: nil, owner: owner, device: token), as: State.self)
        try check(run)
        if state.status == "signed_out" { return nil }
        guard state.status == "authenticated", let account = state.account else {
            throw MirsaStoreServerError(code: "upstream_unavailable")
        }
        return account.summary
    }

    func signIn(email: String, password: String) async throws -> MirsaStoreLogin {
        let run = try begin(); defer { busy = false }
        pending = nil
        let mail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard mail.contains("@"), mail.utf8.count <= 254, !password.isEmpty, password.utf8.count <= 1024 else {
            throw MirsaStoreError.invalidInput
        }
        let (owner, token) = try await credentials(run)
        let state = try await perform(request("/login", body: ["email": mail, "password": password],
                                              owner: owner, device: token), as: State.self)
        try check(run)
        return try login(state)
    }

    func verify(code: String, password: String) async throws -> MirsaStoreLogin {
        let run = try begin(); defer { busy = false }
        guard let challenge = pending, challenge.expires > Date(), challenge.attempts < 2 else {
            pending = nil; throw MirsaStoreServerError(code: "challenge_expired")
        }
        guard code.utf8.count == 6, code.utf8.allSatisfy({ (48...57).contains($0) }),
              !password.isEmpty, password.utf8.count <= 1024 else { throw MirsaStoreError.invalidInput }
        let (owner, token) = try await credentials(run)
        guard pending?.id == challenge.id else { throw MirsaStoreServerError(code: "challenge_expired") }
        pending = (challenge.id, challenge.expires, challenge.attempts + 1)
        do {
            let state = try await perform(request("/verify",
                body: ["challengeID": challenge.id, "password": password, "code": code],
                owner: owner, device: token), as: State.self)
            try check(run)
            return try login(state)
        } catch {
            if (pending?.attempts ?? 2) >= 2 { pending = nil }
            throw error
        }
    }

    private func login(_ state: State) throws -> MirsaStoreLogin {
        if state.status == "authenticated", let account = state.account {
            pending = nil; return .signedIn(account.summary)
        }
        if state.status == "challenge", state.passwordRequired == true, let id = state.challengeID,
           !id.isEmpty, id.utf8.count <= 256, let stamp = state.expiresAt, let expires = Self.date(stamp), expires > Date() {
            let attempts = pending?.id == id ? pending?.attempts ?? 0 : 0
            pending = (id, min(expires, Date().addingTimeInterval(300)), attempts)
            return .verificationRequired
        }
        throw MirsaStoreServerError(code: "upstream_unavailable")
    }

    func search(term: String, limit: Int = 25) async throws -> [MirsaStoreApp] {
        let run = try begin(); defer { busy = false }
        let q = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, q.utf8.count <= 256 else { throw MirsaStoreError.invalidInput }
        let (owner, token) = try await credentials(run)
        let result = try await perform(request("/search", body: ["term": q, "limit": min(50, max(1, limit))],
                                              owner: owner, device: token), as: Apps.self)
        try check(run)
        guard result.apps.count <= 50 else { throw MirsaStoreError.invalidPackage }
        return result.apps.map(\.summary)
    }

    func acquireFreeApp(_ app: MirsaStoreApp) async throws {
        let run = try begin(); defer { busy = false }
        try MirsaStorePolicy.requireFree(app.price)
        let (owner, token) = try await credentials(run)
        // Purchase response carries no contract-required fields.
        let (data, status) = try await http(request("/purchase", body: ["appID": app.id], owner: owner, device: token))
        try check(run)
        guard (200..<300).contains(status) else {
            throw MirsaStoreServerError(code: (try? JSONDecoder().decode(Failure.self, from: data))?.error.code ?? "upstream_unavailable")
        }
    }

    func availableVersions(_ app: MirsaStoreApp) async throws -> [String] {
        let run = try begin(); defer { busy = false }
        let (owner, token) = try await credentials(run)
        let result = try await perform(request("/versions", body: ["appID": app.id], owner: owner, device: token), as: Versions.self)
        try check(run)
        guard result.appID == app.id, Self.numericVersion(result.latestExternalVersionID),
              result.versions.count <= 10_000 else { throw MirsaStoreError.invalidPackage }
        let ids = result.versions
        guard ids.allSatisfy(Self.numericVersion), Set(ids).count == ids.count,
              ids.contains(result.latestExternalVersionID) else { throw MirsaStoreError.invalidPackage }
        return ids
    }

    static func numericVersion(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 20 && value.utf8.allSatisfy { (48...57).contains($0) }
    }

    static func verifySelection(appID: Int64, externalVersionID: String?,
                                expectedAppID: Int64, expectedVersionID: String?) throws {
        guard appID == expectedAppID, externalVersionID == expectedVersionID else {
            throw MirsaStoreError.invalidPackage
        }
    }

    func downloadOwnedApp(_ app: MirsaStoreApp, externalVersionID: String? = nil) async throws -> URL {
        let run = try begin(); defer { busy = false; artifact = nil }
        let (owner, token) = try await credentials(run)
        var body: [String: Any] = ["appID": app.id]
        if let externalVersionID {
            guard Self.numericVersion(externalVersionID) else { throw MirsaStoreError.invalidInput }
            body["externalVersionID"] = externalVersionID
        }
        var job = try await perform(request("/downloads", body: body, owner: owner, device: token), as: Job.self)
        try check(run)
        try Self.verifySelection(appID: job.appID, externalVersionID: job.externalVersionID,
                                 expectedAppID: app.id, expectedVersionID: externalVersionID)
        let jobID = job.jobID
        guard Self.identifier(jobID) else { throw MirsaStoreError.invalidPackage }
        // Poll only during this explicit foreground operation, bounded to ten minutes.
        for _ in 0..<Self.maximumPolls {
            try check(run)
            if job.status == "ready", let item = job.artifact {
                try Self.verifySelection(appID: item.appID, externalVersionID: item.externalVersionID,
                                         expectedAppID: app.id, expectedVersionID: externalVersionID)
                let url = try Self.artifactURL(item, transport: transport)
                let fetch = MirsaStoreServerArtifact()
                artifact = fetch
                var req = try request("/artifacts/" + url.lastPathComponent, method: "GET", body: nil, owner: owner, device: token)
                // Refresh the Supabase JWT, never replay the Apple password.
                let refreshed = try await identity()
                try check(run)
                guard refreshed.userID == owner.userID else { throw MirsaStoreError.operationCancelled }
                req.setValue("Bearer " + refreshed.bearer, forHTTPHeaderField: "Authorization")
                let file = try await fetch.fetch(transport: transport, request: req, expectedBytes: item.size,
                                                 sha256: item.sha256, expires: Self.date(item.expiresAt)!)
                do { try check(run); return file }
                catch { MirsaManagedTmp.end(file.deletingLastPathComponent()); throw error }
            }
            guard job.status == "queued" || job.status == "running" else {
                throw MirsaStoreServerError(code: "upstream_unavailable")
            }
            try await pause()
            let refreshed = try await identity()
            try check(run)
            guard refreshed.userID == owner.userID else { throw MirsaStoreError.operationCancelled }
            job = try await perform(request("/downloads/" + jobID, method: "GET", body: nil,
                                            owner: refreshed, device: token), as: Job.self)
            guard job.jobID == jobID else { throw MirsaStoreError.invalidPackage }
            try Self.verifySelection(appID: job.appID, externalVersionID: job.externalVersionID,
                                     expectedAppID: app.id, expectedVersionID: externalVersionID)
        }
        throw MirsaStoreServerError(code: "busy")
    }

    static func identifier(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 256 &&
            value.utf8.allSatisfy { (48...57).contains($0) || (65...90).contains($0) ||
                (97...122).contains($0) || $0 == 45 || $0 == 95 }
    }
    static func artifactURL(_ item: Artifact, transport: MirsaStoreServerTransport) throws -> URL {
        guard let url = URL(string: item.url), url.query == nil, url.fragment == nil,
              url.path.hasPrefix("/store/v1/artifacts/"), identifier(url.lastPathComponent),
              url.path == "/store/v1/artifacts/" + url.lastPathComponent,
              try transport.url(url.path) == url,
              item.size > 0, item.size <= MirsaStoreServerTransport.maximumIPABytes,
              item.sha256.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil,
              let expires = date(item.expiresAt), expires > Date(),
              expires.timeIntervalSinceNow <= 15 * 60 + 60 else { throw MirsaStoreError.invalidPackage }
        return url
    }

    func signOut() async throws {
        generation &+= 1
        pending = nil
        artifact?.cancel()
        // Do not discard the token before server acknowledgement. A failed logout can be retried.
        let (owner, token) = try await credentials(generation)
        let state = try await perform(request("/logout", owner: owner, device: token), as: State.self)
        guard state.status == "signed_out" else { throw MirsaStoreServerError(code: "upstream_unavailable") }
    }
}
