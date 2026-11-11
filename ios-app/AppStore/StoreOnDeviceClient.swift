import Foundation

/// The gate checks Mirsa's existing owner-device capability only. Apple credentials,
/// cookies, SAP exchange, searches and downloads never pass through that gate.
actor MirsaStoreOnDeviceClient {
    typealias Gate = () async -> Bool
    private let gate: Gate
    private let local: MirsaStoreClient
    init(local: MirsaStoreClient = MirsaStoreClient(), gate: @escaping Gate) {
        self.local = local; self.gate = gate
    }
    private func authorize() async throws {
        guard await gate() else { throw MirsaStoreServerError(code: "staging_denied") }
        try Task.checkCancellation()
    }
    func currentAccount() async throws -> MirsaStoreAccount? {
        try await authorize()
        return try await local.currentAccount()
    }
    func signIn(email: String, password: String) async throws -> MirsaStoreLogin {
        try await authorize()
        return try await local.signIn(email: email, password: password)
    }
    func verify(code: String, password: String) async throws -> MirsaStoreLogin {
        try await authorize()
        return try await local.verify(code: code, password: password)
    }
    func search(term: String, limit: Int = 25) async throws -> [MirsaStoreApp] {
        try await authorize()
        guard let account = try await local.currentAccount() else { throw MirsaStoreError.signedOut }
        return try await local.search(term: term, country: account.country, limit: limit)
    }
    func acquireFreeApp(_ app: MirsaStoreApp) async throws {
        try await authorize()
        try await local.acquireFreeApp(app)
    }
    func availableVersions(_ app: MirsaStoreApp) async throws -> [String] {
        try await authorize()
        return try await local.availableVersions(app)
    }
    func versionMetadata(_ app: MirsaStoreApp, externalVersionIDs ids: [String]) async throws -> [MirsaStoreServerClient.VersionMetadata] {
        try await authorize()
        return try await local.versionMetadata(app, externalVersionIDs: ids)
    }
    func downloadOwnedApp(_ app: MirsaStoreApp, externalVersionID: String? = nil) async throws -> URL {
        try await authorize()
        return try await local.downloadOwnedApp(app, externalVersionID: externalVersionID)
    }
    func signOut() async throws {
        // Removing a local session must still work when the gate is offline or revoked.
        try await local.signOut()
    }
}
