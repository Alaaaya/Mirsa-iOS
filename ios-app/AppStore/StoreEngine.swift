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
    /// Selected catalogue identity, reused for version lists without a redundant lookup.
    var software: Software {
        Software(id: id, bundleID: bundleID, name: name, version: version, price: price,
                 artistName: "", sellerName: "", description: "", averageUserRating: 0,
                 userRatingCount: 0, artworkUrl: artworkURL, screenshotUrls: [], minimumOsVersion: "",
                 releaseDate: "", primaryGenreName: "")
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
    let guid: String
    func authenticate(email: String, password: String, code: String) async throws -> Account {
        do {
            return try await MirsaStoreGUIDLease.shared.run(guid: guid) {
                try await authenticator.authenticate(email: email, password: password, code: code)
            }
        }
        catch AuthenticationError.verificationCodeRequired { throw AuthenticationError.verificationCodeRequired }
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
    func versions(account: inout Account, app: Software) async throws -> [String]
    func versionMetadata(account: inout Account, app: Software, version: String) async throws -> String
}

extension MirsaStoreEngine {
    func versionMetadata(account: inout Account, app: Software, version: String) async throws -> String {
        throw MirsaStoreError.serviceUnavailable
    }
}

/// ApplePackage still reads a process-wide GUID. Hold a cancellable lease for the
/// entire library call, including suspension, so another account cannot overwrite it.
actor MirsaStoreGUIDLease {
    static let shared = MirsaStoreGUIDLease()
    private var busy = false
    func run<T>(guid: String, operation: () async throws -> T) async throws -> T {
        while busy {
            try Task.checkCancellation()
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        try Task.checkCancellation()
        busy = true
        defer { busy = false }
        Configuration.deviceIdentifier = guid
        return try await operation()
    }
}

final class ApplePackageStoreEngine: MirsaStoreEngine {
    private var guid = ""
    private func isolated<T>(_ operation: () async throws -> T) async throws -> T {
        try await MirsaStoreGUIDLease.shared.run(guid: guid, operation: operation)
    }

    func versionMetadata(account: inout Account, app: Software, version: String) async throws -> String {
        try await isolated { try await VersionLookup.getVersionMetadata(account: &account, app: app, versionID: version).displayVersion }
    }
    func configure(guid: String) {
        self.guid = guid
        APLogger.verbose = false
        APLogger.logger = Logger(label: "MirsaStore", factory: { _ in SwiftLogNoOpLogHandler() })
        // Do not call ApplePackage's file-backed account helpers.
    }
    func authentication() async throws -> any MirsaStoreAuthentication {
        do { return try await isolated { AppleStoreAuthentication(authenticator: try await Authenticator(), guid: guid) } }
        catch { throw MirsaStoreAuthDiagnostic(.wrapping(error, stage: .sapValidation)) }
    }
    func search(term: String, country: String, limit: Int) async throws -> [Software] {
        try await isolated { try await Searcher.search(term: term, countryCode: country, limit: limit) }
    }
    func lookup(bundleID: String, country: String) async throws -> Software {
        try await isolated { try await Lookup.lookup(bundleID: bundleID, countryCode: country) }
    }
    func acquire(account: inout Account, app: Software) async throws {
        try MirsaStorePolicy.requireFree(app.price)
        try await isolated { try await Purchase.purchase(account: &account, app: app) }
    }
    func manifest(account: inout Account, app: Software, version: String?) async throws -> DownloadOutput {
        try await isolated { try await Download.download(account: &account, app: app, externalVersionID: version) }
    }
    func versions(account: inout Account, app: Software) async throws -> [String] {
        try await isolated { try await VersionFinder.list(account: &account, app: app) }
    }
}
