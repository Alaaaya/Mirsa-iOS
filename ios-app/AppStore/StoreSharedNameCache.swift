import Foundation

/// Shared public version-name cache client. STAGED: default OFF, no endpoint is called until a reviewed
/// server is installed and `baseURL` is provided. Sends only appId + versionId + name, never user data.
enum StoreSharedNameCache {
    static var enabled = false
    static var baseURL: URL? = nil

    struct Lookup: Codable, Equatable { var version = 1; var names: [String: String]; var missing: [String]? }

    static func lookupBody(appID: String, ids: [String]) -> [String: Any] {
        ["appId": appID, "externalVersionIds": Array(ids.prefix(500))]
    }
    static func contributeBody(appID: String, names: [String: String]) -> [String: Any] {
        let clean = names.filter { !$0.value.isEmpty && $0.value.count <= 64 }
        return ["version": 1, "appId": appID, "names": Dictionary(uniqueKeysWithValues: Array(clean).prefix(100).map { ($0.key, $0.value) })]
    }
    /// One bulk lookup for the whole list. Fails closed: any problem returns [:].
    static func fetch(appID: String, ids: [String], send: (URL, [String: Any]) async throws -> Data) async -> [String: String] {
        guard enabled, let base = baseURL, !ids.isEmpty else { return [:] }
        guard let data = try? await send(base.appendingPathComponent("lookup"), lookupBody(appID: appID, ids: ids)),
              let r = try? JSONDecoder().decode(Lookup.self, from: data), r.version == 1 else { return [:] }
        return r.names.filter { ids.contains($0.key) && !$0.value.isEmpty && $0.value.count <= 64 }
    }
    static func contribute(appID: String, names: [String: String], send: (URL, [String: Any]) async throws -> Data) async {
        guard enabled, let base = baseURL, !names.isEmpty else { return }
        _ = try? await send(base.appendingPathComponent("contribute"), contributeBody(appID: appID, names: names))
    }
}
