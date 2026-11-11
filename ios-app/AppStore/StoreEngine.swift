import Foundation
import Logging
@preconcurrency import ApplePackage

struct MirsaStoreApp: Sendable, Equatable, Identifiable {
    let id: Int64
    let bundleID: String
    let name: String
    let version: String
    let price: Double?
    let artworkURL: String
    init(id: Int64, bundleID: String, name: String, version: String, price: Double?, artworkURL: String) {
        self.id = id; self.bundleID = bundleID; self.name = name; self.version = version
        self.price = price; self.artworkURL = artworkURL
    }
    init(_ software: Software) {
        id = software.id; bundleID = software.bundleID; name = software.name
        version = software.version; price = software.price; artworkURL = software.artworkUrl
    }
}

struct MirsaStoreAccount: Sendable, Equatable {
    let email: String
    let country: String
    let name: String
}

enum MirsaStoreLogin: Sendable, Equatable {
    case signedIn(MirsaStoreAccount)
    case verificationRequired
}

protocol MirsaStoreAuthentication {
    func authenticate(email: String, password: String, code: String) async throws -> Account
}

private struct AppleStoreAuthentication: MirsaStoreAuthentication {
    let authenticator: Authenticator
    func authenticate(email: String, password: String, code: String) async throws -> Account {
        do { return try await authenticator.authenticate(email: email, password: password, code: code) }
        catch let error as AuthenticationError { throw error }
        catch let error as StoreAMDError { throw error }
        catch { throw MirsaStoreAuthDiagnostic(.wrapping(error, stage: .authentication)) }
    }
}

protocol MirsaStoreEngine {
    func configure(guid: String)
    func authentication() async throws -> any MirsaStoreAuthentication
    func search(term: String, country: String, limit: Int) async throws -> [Software]
    func lookup(bundleID: String, country: String) async throws -> Software
    func acquire(account: inout Account, app: Software) async throws
    func manifest(account: inout Account, app: Software, version: String?) async throws -> DownloadOutput
    func versions(account: inout Account, bundleID: String) async throws -> [String]
    func versionMetadata(account: inout Account, app: Software, version: String) async throws -> String
}

extension MirsaStoreEngine {
    func versionMetadata(account: inout Account, app: Software, version: String) async throws -> String {
        throw MirsaStoreError.serviceUnavailable
    }
}

struct ApplePackageStoreEngine: MirsaStoreEngine {
    func versionMetadata(account: inout Account, app: Software, version: String) async throws -> String {
        try await VersionLookup.getVersionMetadata(account: &account, app: app, versionID: version).displayVersion
    }
    func configure(guid: String) {
        Configuration.deviceIdentifier = guid
        APLogger.verbose = false
        APLogger.logger = Logger(label: "MirsaStore", factory: { _ in SwiftLogNoOpLogHandler() })
        // Do not call ApplePackage's file-backed account helpers.
    }
    func authentication() async throws -> any MirsaStoreAuthentication {
        do { return AppleStoreAuthentication(authenticator: try await Authenticator()) }
        catch { throw MirsaStoreAuthDiagnostic(.wrapping(error, stage: .sapValidation)) }
    }
    func search(term: String, country: String, limit: Int) async throws -> [Software] {
        try await Searcher.search(term: term, countryCode: country, limit: limit)
    }
    func lookup(bundleID: String, country: String) async throws -> Software {
        try await Lookup.lookup(bundleID: bundleID, countryCode: country)
    }
    func acquire(account: inout Account, app: Software) async throws {
        try MirsaStorePolicy.requireFree(app.price)
        try await Purchase.purchase(account: &account, app: app)
    }
    func manifest(account: inout Account, app: Software, version: String?) async throws -> DownloadOutput {
        try await Download.download(account: &account, app: app, externalVersionID: version)
    }
    func versions(account: inout Account, bundleID: String) async throws -> [String] {
        try await VersionFinder.list(account: &account, bundleIdentifier: bundleID, entityType: .iPhone)
    }
}
