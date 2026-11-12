import Foundation

/// Separate namespace from the legacy/server migration cleanup. Otherwise the
/// server capability check on a new launch would delete the native Apple session.
struct MirsaStoreNativeVault: MirsaStoreVault {
    private let base = MirsaStoreKeychain()
    func read(_ key: String) throws -> Data? { try base.read("native." + key) }
    func write(_ data: Data, key: String) throws { try base.write(data, key: "native." + key) }
    func remove(_ key: String) throws { try base.remove("native." + key) }
}

/// The gate checks Mirsa's existing owner-device capability only. Apple credentials,
/// cookies, SAP exchange, searches and downloads never pass through that gate.
actor MirsaStoreOnDeviceClient {
    typealias Gate = () async -> Bool
    private let gate: Gate
    private let local: MirsaStoreClient
    init(local: MirsaStoreClient = MirsaStoreClient(vault: MirsaStoreNativeVault()), gate: @escaping Gate) {
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
    func verify(code: String, password: String? = nil) async throws -> MirsaStoreLogin {
        try await authorize()
        return try await local.verify(code: code, password: password)
    }
    func search(term: String, country: String? = nil, limit: Int = 25) async throws -> [MirsaStoreApp] {
        try await authorize()
        guard let account = try await local.currentAccount() else { throw MirsaStoreError.signedOut }
        return try await local.search(term: term, country: country ?? account.country, limit: limit)
    }
    /// Public lookup only. Never changes the commerce/account storefront.
    func availableInStore(_ apps: [MirsaStoreApp], country: String) async throws -> Set<Int64> {
        try await authorize()
        guard !apps.isEmpty else { return [] }
        var url = URLComponents(string: "https://itunes.apple.com/lookup")!
        url.queryItems = [
            URLQueryItem(name: "id", value: apps.map { String($0.id) }.joined(separator: ",")),
            URLQueryItem(name: "country", value: country),
            URLQueryItem(name: "entity", value: "software")
        ]
        var request = URLRequest(url: url.url!)
        request.timeoutInterval = 30
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw MirsaStoreError.invalidInput }
        struct Item: Decodable { let trackId: Int64 }
        struct Reply: Decodable { let results: [Item] }
        return Set(try JSONDecoder().decode(Reply.self, from: data).results.map { $0.trackId })
    }

    func purchaseHistory() async throws -> [MirsaStorePurchase] {
        try await authorize()
        return try await local.purchaseHistory()
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
