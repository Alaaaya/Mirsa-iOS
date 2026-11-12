import Foundation

/// Catalogue inputs only. Never fetch arbitrary pasted URLs or persist their query
/// strings (which can contain tracking or credentials).
enum StoreSearchQuery: Equatable {
    case name(String), appID(String)
    static func parse(_ input: String) throws -> Self {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.utf8.count <= 256,
              !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            throw MirsaStoreError.invalidInput
        }
        if value.allSatisfy({ $0.isASCII && $0.isNumber }) {
            guard let n = Int64(value), n > 0 else { throw MirsaStoreError.invalidInput }
            return .appID(String(n))
        }
        if value.contains("://") || value.lowercased().hasPrefix("apps.apple.com/") {
            let candidate = value.contains("://") ? value : "https://" + value
            guard let url = URLComponents(string: candidate), url.scheme == "https",
                  ["apps.apple.com", "itunes.apple.com"].contains(url.host?.lowercased() ?? ""),
                  url.user == nil, url.password == nil, url.port == nil,
                  let part = url.path.split(separator: "/").last, part.hasPrefix("id") else {
                throw MirsaStoreError.invalidInput
            }
            let id = String(part.dropFirst(2))
            guard !id.isEmpty, id.allSatisfy({ $0.isASCII && $0.isNumber }),
                  let n = Int64(id), n > 0 else { throw MirsaStoreError.invalidInput }
            return .appID(String(n))
        }
        return .name(value)
    }
    var term: String { switch self { case .name(let s), .appID(let s): return s } }
}

enum StoreRecentSearches {
    static func read(_ data: Data) -> [String] {
        guard data.count <= 4096, let values = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return clean(values)
    }
    static func adding(_ term: String, to data: Data) -> Data {
        encode(clean([term] + read(data)))
    }
    static func removing(_ term: String, from data: Data) -> Data {
        encode(read(data).filter { $0 != term })
    }
    static func encode(_ values: [String]) -> Data { (try? JSONEncoder().encode(clean(values))) ?? Data() }
    private static func clean(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return Array(values.prefix(100).compactMap { value -> String? in
            guard let query = try? StoreSearchQuery.parse(value) else { return nil }
            let term = query.term
            guard seen.insert(term.lowercased()).inserted else { return nil }
            return term
        }.prefix(12))
    }
}
