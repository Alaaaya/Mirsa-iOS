import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Apple's dotted numeric marketing/OS versions are not SemVer. Foundation's
/// maintained numeric comparison avoids lexical 10 < 9 and integer overflow.
enum StoreVersionPolicy {
    static func newer(_ candidate: String, than installed: String) -> Bool? {
        func canonical(_ value: String) -> String? {
            guard !value.isEmpty, value.utf8.count <= 100 else { return nil }
            var parts = value.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
            guard parts.allSatisfy({ !$0.isEmpty && $0.utf8.allSatisfy { (48...57).contains($0) } }) else { return nil }
            parts = parts.map { part in
                let stripped = part.drop(while: { $0 == "0" })
                return stripped.isEmpty ? "0" : String(stripped)
            }
            while parts.count > 1 && parts.last == "0" { parts.removeLast() }
            return parts.joined(separator: ".")
        }
        guard let a = canonical(candidate), let b = canonical(installed) else { return nil }
        return a.compare(b, options: .numeric, locale: Locale(identifier: "en_US_POSIX")) == .orderedDescending
    }
}

struct StoreVersionPin: Codable, Equatable {
    let bundleID: String
    let country: String
    let externalVersionID: String
    let version: String
}

struct StoreWishItem: Codable, Identifiable, Equatable {
    let appID: Int64
    let bundleID: String
    let name: String
    let country: String
    var currency: String
    var price: Double
    var becameFree = false
    var notified = false
    var checkedAt: Date?
    var id: String { country.lowercased() + ":" + String(appID) }

    /// Only a fresh successful observation in the SAME country/currency can
    /// produce a transition. Unknown/error observations must not call this.
    mutating func observe(_ item: StoreCatalogItem, now: Date = Date()) -> Bool {
        guard item.app.id == appID, item.app.bundleID == bundleID,
              item.country.lowercased() == country.lowercased(),
              let next = item.app.price, next.isFinite, next >= 0,
              let code = item.currency, code == currency else { return false }
        let transition = price > 0 && next == 0
        if next > 0 { becameFree = false; notified = false }
        price = next; checkedAt = now
        if transition { becameFree = true }
        return becameFree && !notified && next == 0
    }
}

struct StoreCatalogItem: Sendable, Equatable {
    let app: MirsaStoreApp
    let country: String
    let currency: String?
    let releaseNotes: String?
    let minimumOSVersion: String?
    let screenshots: [URL]
    let rating: Double?
    let ratingCount: Int?
    let sizeBytes: Int64?
    // Public lookup has no reliable externalVersionID for older releases.
    func notes(forVersion externalVersionID: String?) -> String? {
        externalVersionID == nil ? releaseNotes : nil
    }
    func minimumOS(forVersion externalVersionID: String?) -> String? {
        externalVersionID == nil ? minimumOSVersion : nil
    }
}

enum StoreCatalog {
    enum Failure: Error { case unavailable, invalidMetadata }
    static func decode(_ data: Data, appID: Int64?, bundleID: String?, country: String) throws -> StoreCatalogItem {
        guard data.count <= 2_000_000 else { throw Failure.invalidMetadata }
        struct Reply: Decodable { let results: [Item] }
        struct Item: Decodable {
            let trackId: Int64; let bundleId: String; let trackName: String; let version: String
            let price: Double?; let currency: String?; let releaseNotes: String?; let minimumOsVersion: String?
            let artworkUrl100: String?; let screenshotUrls: [String]?
            let averageUserRating: Double?; let userRatingCount: Int?; let fileSizeBytes: String?
        }
        let results = try JSONDecoder().decode(Reply.self, from: data).results
        guard let item = results.first(where: { (appID == nil || $0.trackId == appID) && (bundleID == nil || $0.bundleId == bundleID) }),
              item.trackId > 0, !item.bundleId.isEmpty, !item.version.isEmpty,
              item.price.map({ $0.isFinite && $0 >= 0 }) ?? true else { throw Failure.unavailable }
        let screenshots = (item.screenshotUrls ?? []).prefix(20).compactMap { value -> URL? in
            guard let url = URL(string: value), url.scheme == "https", url.user == nil,
                  url.password == nil, url.port == nil, let host = url.host?.lowercased(),
                  host.hasSuffix(".mzstatic.com") else { return nil }
            return url
        }
        let currency = item.currency.flatMap { value in
            value.utf8.count == 3 && value.utf8.allSatisfy({ (65...90).contains($0) }) ? value : nil
        }
        return StoreCatalogItem(
            app: MirsaStoreApp(id: item.trackId, bundleID: item.bundleId, name: item.trackName,
                              version: item.version, price: item.price, artworkURL: item.artworkUrl100 ?? ""),
            country: try MirsaStorePolicy.country(country).lowercased(), currency: currency,
            releaseNotes: item.releaseNotes, minimumOSVersion: item.minimumOsVersion,
            screenshots: screenshots,
            rating: item.averageUserRating.flatMap { $0.isFinite && (0...5).contains($0) ? $0 : nil },
            ratingCount: item.userRatingCount.flatMap { $0 >= 0 ? $0 : nil },
            sizeBytes: item.fileSizeBytes.flatMap(Int64.init).flatMap { $0 >= 0 ? $0 : nil })
    }
    static func fetch(appID: Int64? = nil, bundleID: String? = nil, country: String) async throws -> StoreCatalogItem {
        try await StoreCatalogTransport.shared.fetch(appID: appID, bundleID: bundleID, country: country)
    }
}

/// One rate limiter across foreground/background callers, fresh successful data
/// only. No authenticated URLSession, account cookies, error/free caches.
private actor StoreCatalogTransport {
    static let shared = StoreCatalogTransport()
    private var nextRequest = Date.distantPast
    func fetch(appID: Int64?, bundleID: String?, country: String) async throws -> StoreCatalogItem {
        let cc = try MirsaStorePolicy.country(country).lowercased()
        guard (appID.map { $0 > 0 } ?? false) || (bundleID.map { !$0.isEmpty && $0.utf8.count < 256 } ?? false) else {
            throw StoreCatalog.Failure.invalidMetadata
        }
        let wait = max(0, nextRequest.timeIntervalSinceNow)
        nextRequest = Date(timeIntervalSinceNow: wait + 3.2)
        if wait > 0 { try await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000)) }
        try Task.checkCancellation()
        var components = URLComponents(string: "https://itunes.apple.com/lookup")!
        var query = [URLQueryItem(name: "country", value: cc), URLQueryItem(name: "entity", value: "software")]
        if let appID { query.append(URLQueryItem(name: "id", value: String(appID))) }
        else { query.append(URLQueryItem(name: "bundleId", value: bundleID)) }
        components.queryItems = query
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil; config.httpShouldSetCookies = false; config.urlCache = nil
        config.timeoutIntervalForRequest = 15; config.timeoutIntervalForResource = 20
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let (data, response) = try await session.data(from: components.url!)
        try Task.checkCancellation()
        guard let response = response as? HTTPURLResponse, response.statusCode == 200,
              response.url?.scheme == "https", response.url?.host == "itunes.apple.com" else {
            throw StoreCatalog.Failure.unavailable
        }
        return try StoreCatalog.decode(data, appID: appID, bundleID: bundleID, country: cc)
    }
}

enum StoreIPACleanupPolicy {
    static func mayDelete(enabled: Bool, confirmed: Bool, saved: Bool, active: Bool, pinned: Bool) -> Bool {
        enabled && confirmed && !saved && !active && !pinned
    }
}
