import Foundation
import Security
@preconcurrency import ApplePackage

/// Own-account only. All Apple traffic is on-device; no Mirsa backend is involved.
actor MirsaStoreClient {
    static let shared = MirsaStoreClient()
    private let vault: any MirsaStoreVault
    private let engine: any MirsaStoreEngine
    private let packages: any MirsaStorePackages
    private var prepared = false
    private var busy = false
    private var generation: UInt64 = 0
    private struct Challenge {
        let session: any MirsaStoreAuthentication
        let email: String
        // Memory-only, discarded with this five-minute challenge. Never persisted.
        let password: String
        var submittedCodes: Set<String> = []
        let id: UUID
        let expires: Date
        var attempts: Int
    }
    private var challenge: Challenge?

    init(vault: any MirsaStoreVault = MirsaStoreKeychain(),
         engine: any MirsaStoreEngine = ApplePackageStoreEngine(),
         packages: any MirsaStorePackages = AppleStorePackages()) {
        self.vault = vault; self.engine = engine; self.packages = packages
    }

    func currentAccount() throws -> MirsaStoreAccount? {
        try prepare()
        return try loadAccount().map(summary)
    }

    func search(term: String, country: String, limit: Int = 25) async throws -> [MirsaStoreApp] {
        let run = try begin()
        defer { busy = false }
        let country = try MirsaStorePolicy.country(country)
        guard Configuration.storeId(for: country) != nil, !term.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              term.utf8.count <= 256 else { throw MirsaStoreError.invalidInput }
        do {
            let apps = try await engine.search(term: term, country: country, limit: min(50, max(1, limit)))
            try check(run)
            return apps.map(MirsaStoreApp.init)
        } catch { throw safe(error) }
    }

    func signIn(email: String, password: String) async throws -> MirsaStoreLogin {
        let run = try begin()
        defer { busy = false }
        challenge = nil
        try vault.remove("challenge")
        let email = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard email.contains("@"), email.utf8.count <= 254, !password.isEmpty,
              password.utf8.count <= 1024 else { throw MirsaStoreError.invalidInput }
        do {
            let session = try await engine.authentication()
            try check(run)
            let id = UUID()
            challenge = Challenge(session: session, email: email, password: password, id: id,
                                  expires: Date().addingTimeInterval(300), attempts: 0)
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: 300_000_000_000)
                await self?.expireChallenge(id)
            }
            return try await authenticate(code: "", run: run)
        } catch {
            try check(run)
            if let auth = error as? AuthenticationError, case .verificationCodeRequired = auth {
                return .verificationRequired
            }
            challenge = nil
            try? vault.remove("challenge")
            throw safe(error)
        }
    }

    /// Retains the *same* SAP signer, routing and cookies for a bounded 2FA continuation.
    func verify(code: String, password: String) async throws -> MirsaStoreLogin {
        let run = try begin()
        defer { busy = false }
        guard var pending = challenge, pending.expires > Date(), pending.attempts < 3 else {
            challenge = nil
            try vault.remove("challenge")
            throw MirsaStoreError.signedOut
        }
        guard let code = MirsaStoreCode.valid(code), password == pending.password,
              !pending.submittedCodes.contains(code) else {
            throw MirsaStoreError.invalidInput
        }
        pending.attempts += 1
        pending.submittedCodes.insert(code)
        challenge = pending
        do { return try await authenticate(code: code, run: run) }
        catch {
            // Keep the same session for a corrected code, but never beyond three submissions.
            let diagnostic = safe(error) as? MirsaStoreAuthDiagnostic
            if diagnostic?.appleCode == "5020" || (challenge?.attempts ?? 3) >= 3 {
                challenge = nil
                try? vault.remove("challenge")
            }
            throw safe(error)
        }
    }

    func signOut() throws {
        generation &+= 1
        challenge = nil
        packages.cancel()
        // Keep the stable machine identifier; deleting it on each logout changes identity.
        var deletionError: Error?
        do { try vault.remove("account") } catch { deletionError = error }
        do { try vault.remove("challenge") } catch { deletionError = deletionError ?? error }
        if let deletionError { throw deletionError }
    }

    /// Explicit free-license action only. Download never silently acquires or purchases.
    func acquireFreeApp(_ app: MirsaStoreApp) async throws {
        let run = try begin()
        defer { busy = false }
        var owner = try requiredAccount()
        do {
            let fresh = try await engine.lookup(bundleID: app.bundleID, country: try country(owner))
            try check(run)
            guard fresh.id == app.id else { throw MirsaStoreError.invalidPackage }
            try MirsaStorePolicy.requireFree(fresh.price)
            try await engine.acquire(account: &owner, app: fresh)
            try check(run)
            try persist(owner)
        } catch { throw safe(error) }
    }

    func availableVersions(_ app: MirsaStoreApp) async throws -> [String] {
        let run = try begin()
        defer { busy = false }
        var owner = try requiredAccount()
        do {
            let versions = try await engine.versions(account: &owner, bundleID: app.bundleID)
            try check(run)
            try persist(owner)
            return try versions.map {
                guard let version = try MirsaStorePolicy.version($0) else { throw MirsaStoreError.invalidPackage }
                return version
            }
        } catch { throw safe(error) }
    }

    func versionMetadata(_ app: MirsaStoreApp, externalVersionIDs ids: [String]) async throws -> [MirsaStoreServerClient.VersionMetadata] {
        guard !ids.isEmpty, ids.count <= 20, Set(ids).count == ids.count,
              ids.allSatisfy(MirsaStoreServerClient.numericVersion) else { throw MirsaStoreError.invalidInput }
        let run = try begin(); defer { busy = false }
        var owner = try requiredAccount()
        let fresh = try await engine.lookup(bundleID: app.bundleID, country: try country(owner))
        try check(run)
        guard fresh.id == app.id else { throw MirsaStoreError.invalidPackage }
        var entries: [MirsaStoreServerClient.VersionMetadata] = []
        for id in ids {
            do {
                let version = try await engine.versionMetadata(account: &owner, app: fresh, version: id)
                try check(run)
                guard !version.isEmpty, version.utf8.count <= 128,
                      !version.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
                    throw MirsaStoreError.invalidPackage
                }
                entries.append(.init(externalVersionID: id, status: "ready", version: version))
            } catch {
                try check(run)
                entries.append(.init(externalVersionID: id, status: "unavailable", version: nil))
            }
        }
        try persist(owner)
        return entries
    }

    /// Returns a local encrypted IPA with the account's original SINF, not a decrypted/re-signed app.
    /// Caller may hand this URL to the local importer. No automatic install or sharing.
    func downloadOwnedApp(_ app: MirsaStoreApp, externalVersionID: String? = nil) async throws -> URL {
        let run = try begin()
        defer { busy = false }
        var owner = try requiredAccount()
        let version = try MirsaStorePolicy.version(externalVersionID)
        var completed: URL?
        do {
            let fresh = try await engine.lookup(bundleID: app.bundleID, country: try country(owner))
            try check(run)
            guard fresh.id == app.id else { throw MirsaStoreError.invalidPackage }
            let output = try await engine.manifest(account: &owner, app: fresh, version: version)
            try check(run)
            try validate(output: output, app: app, version: version)
            try persist(owner)
            let url = try await packages.fetch(output: output, bundleID: app.bundleID)
            completed = url
            try check(run)
            return url
        } catch {
            if let completed { MirsaManagedTmp.end(completed.deletingLastPathComponent()) }
            throw safe(error)
        }
    }

    private func authenticate(code: String, run: UInt64) async throws -> MirsaStoreLogin {
        guard let pending = challenge else { throw MirsaStoreError.signedOut }
        let owner = try await pending.session.authenticate(email: pending.email, password: pending.password, code: code)
        try check(run)
        guard challenge?.id == pending.id, pending.expires > Date() else {
            throw MirsaStoreError.operationCancelled
        }
        let result = try summary(owner)
        try persist(owner)
        challenge = nil
        try vault.remove("challenge")
        return .signedIn(result)
    }

    private func expireChallenge(_ id: UUID) {
        guard challenge?.id == id else { return }
        challenge = nil
        try? vault.remove("challenge")
    }

    private func prepare() throws {
        guard !prepared else { return }
        let guid: String
        if let bytes = try vault.read("machine"), let saved = String(data: bytes, encoding: .utf8),
           saved.utf8.count == 12, saved.utf8.allSatisfy({ (48...57).contains($0) || (65...70).contains($0) }) {
            guid = saved
        } else {
            var random = [UInt8](repeating: 0, count: 6)
            guard SecRandomCopyBytes(kSecRandomDefault, random.count, &random) == errSecSuccess else {
                throw MirsaStoreError.serviceUnavailable
            }
            guid = random.map { String(format: "%02X", $0) }.joined()
            try vault.write(Data(guid.utf8), key: "machine")
        }
        try vault.remove("challenge")
        if let account = try loadAccount(), !account.password.isEmpty { try persist(account) }
        engine.configure(guid: guid)
        prepared = true
    }
    private func begin() throws -> UInt64 {
        guard !busy else { throw MirsaStoreError.busy }
        try prepare()
        busy = true
        return generation
    }
    private func check(_ run: UInt64) throws {
        guard run == generation, !Task.isCancelled else { throw MirsaStoreError.operationCancelled }
    }
    private func loadAccount() throws -> Account? {
        guard let data = try vault.read("account") else { return nil }
        return try JSONDecoder().decode(Account.self, from: data)
    }
    private func requiredAccount() throws -> Account {
        guard let account = try loadAccount() else { throw MirsaStoreError.signedOut }
        return account
    }
    private func country(_ owner: Account) throws -> String {
        guard let value = Configuration.countryCode(for: owner.store) else { throw MirsaStoreError.invalidInput }
        return value
    }
    private func summary(_ owner: Account) throws -> MirsaStoreAccount {
        MirsaStoreAccount(email: owner.email, country: try country(owner), name: owner.firstName)
    }
    private func persist(_ owner: Account) throws {
        var session = owner
        session.password = ""
        try vault.write(try JSONEncoder().encode(session), key: "account")
    }
    private func validate(output: DownloadOutput, app: MirsaStoreApp, version: String?) throws {
        guard let url = URL(string: output.downloadURL) else { throw MirsaStoreError.untrustedURL }
        try MirsaStorePolicy.downloadURL(url)
        guard !output.sinfs.isEmpty, output.sinfs.count <= 128,
              output.sinfs.allSatisfy({ !$0.sinf.isEmpty && $0.sinf.count <= 4 * 1024 * 1024 }),
              output.iTunesMetadata.count <= 2 * 1024 * 1024,
              let metadata = try PropertyListSerialization.propertyList(from: output.iTunesMetadata, format: nil) as? [String: Any],
              metadata["softwareVersionBundleId"] as? String == app.bundleID,
              metadata["itemId"].map({ String(describing: $0) }) == String(app.id),
              version == nil || metadata["softwareVersionExternalIdentifier"].map({ String(describing: $0) }) == version else {
            throw MirsaStoreError.invalidPackage
        }
    }
    private func safe(_ error: Error) -> Error {
        if let diagnostic = error as? MirsaStoreAuthDiagnostic { return diagnostic }
        if let diagnostic = error as? AuthenticationServiceError { return MirsaStoreAuthDiagnostic(diagnostic) }
        if let error = error as? MirsaStoreError { return error }
        if error is CancellationError { return MirsaStoreError.operationCancelled }
        if let auth = error as? AuthenticationError, case .verificationCodeRequired = auth {
            return MirsaStoreError.verificationRequired
        }
        if case ApplePackageError.licenseRequired = error { return MirsaStoreError.licenseRequired }
        // Do not surface arbitrary URL/body/account descriptions to telemetry or UI.
        return MirsaStoreError.serviceUnavailable
    }
}
