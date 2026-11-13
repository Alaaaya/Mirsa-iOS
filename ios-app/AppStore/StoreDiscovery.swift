import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Public, unauthenticated Apple charts only. No shared Apple-account cookies/headers.
struct StoreChartApp: Identifiable, Equatable, Sendable {
    let id: Int64
    let name: String
    let artworkURL: URL?
}

enum StoreDiscovery {
    static let genres: Set<Int> = [6014, 6007, 6017, 6011, 6016, 6013]
    enum Failure: Error { case invalidCountry, invalidGenre, invalidFeed }

    static func url(country: String, genre: Int?) throws -> URL {
        let cc = country.lowercased()
        guard cc.count == 2, cc.utf8.allSatisfy({ (97...122).contains($0) }) else { throw Failure.invalidCountry }
        if let genre, !genres.contains(genre) { throw Failure.invalidGenre }
        let filter = genre.map { "/genre=\($0)" } ?? ""
        return URL(string: "https://itunes.apple.com/\(cc)/rss/topfreeapplications/limit=12\(filter)/json")!
    }

    static func decode(_ data: Data, country: String, genre: Int?) throws -> [StoreChartApp] {
        let expected = try url(country: country, genre: genre)
        guard data.count <= 2_000_000,
              let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let feed = root["feed"] as? [String: Any],
              let identity = feed["id"] as? [String: Any],
              let rawURL = identity["label"] as? String, let source = URL(string: rawURL),
              source.host == expected.host, source.path == expected.path else { throw Failure.invalidFeed }
        guard let rawEntries = feed["entry"] else { return [] }
        let entries: [[String: Any]]
        if let list = rawEntries as? [[String: Any]] { entries = list }
        else if let one = rawEntries as? [String: Any] { entries = [one] }
        else { throw Failure.invalidFeed }
        var seen = Set<Int64>()
        return entries.prefix(12).compactMap { entry in
            guard let identity = entry["id"] as? [String: Any],
                  let attributes = identity["attributes"] as? [String: Any],
                  let rawID = attributes["im:id"] as? String, let id = Int64(rawID), id > 0,
                  let label = entry["im:name"] as? [String: Any], let name = label["label"] as? String,
                  !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  seen.insert(id).inserted else { return nil }
            let images = entry["im:image"] as? [[String: Any]] ?? []
            let artwork = images.reversed().compactMap { image -> URL? in
                guard let s = image["label"] as? String, let u = URL(string: s), u.scheme == "https",
                      let host = u.host, host.hasSuffix(".mzstatic.com"), u.user == nil, u.password == nil else { return nil }
                return u
            }.first
            return StoreChartApp(id: id, name: String(name.prefix(200)), artworkURL: artwork)
        }
    }

    static func load(country: String, genre: Int?) async throws -> [StoreChartApp] {
        let endpoint = try url(country: country, genre: genre)
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil; config.httpShouldSetCookies = false
        config.urlCache = nil; config.timeoutIntervalForRequest = 20; config.timeoutIntervalForResource = 25
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let (data, response) = try await session.data(from: endpoint)
        try Task.checkCancellation()
        guard let response = response as? HTTPURLResponse, response.statusCode == 200,
              response.url?.host == endpoint.host else { throw Failure.invalidFeed }
        return try decode(data, country: country, genre: genre)
    }
}
