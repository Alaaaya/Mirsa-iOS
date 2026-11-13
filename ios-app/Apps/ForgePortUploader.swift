import Foundation
import CryptoKit

/// Streaming IPA uploader for the staged port backend (schema 2). Raw octet-stream, no base64.
/// Inactive unless an approved HTTPS base is configured in Info.plist (MirsaPortBaseURL) AND capabilities allow it.
enum ForgePortUploader {
    static let maxBytes = 536_870_912
    static var base: URL? {
        guard let s = Bundle.main.object(forInfoDictionaryKey: "MirsaPortBaseURL") as? String, let u = URL(string: s),
              u.scheme == "https", u.host != nil, u.user == nil, u.query == nil, u.fragment == nil else { return nil }
        return u
    }
    struct Ready: Equatable { let uploadID: UUID; let sha256: String }

    static func sha256(file: URL) throws -> (String, Int) {
        let h = try FileHandle(forReadingFrom: file); defer { try? h.close() }
        var hasher = SHA256(); var n = 0
        while let chunk = try h.read(upToCount: 1 << 20), !chunk.isEmpty { hasher.update(data: chunk); n += chunk.count }
        return (hasher.finalize().map { String(format: "%02x", $0) }.joined(), n)
    }

    /// Same-origin only: the server-provided upload URL is resolved against the configured base and rejected otherwise.
    static func resolve(_ relative: String, base: URL) -> URL? {
        guard relative.hasPrefix("?"), let u = URL(string: relative, relativeTo: base)?.absoluteURL,
              u.scheme == base.scheme, u.host == base.host, u.port == base.port, u.path == base.path else { return nil }
        return u
    }

    private static func session() -> URLSession {
        let c = URLSessionConfiguration.ephemeral; c.httpCookieStorage = nil; c.urlCache = nil; c.timeoutIntervalForRequest = 15; c.timeoutIntervalForResource = 330
        return URLSession(configuration: c, delegate: OTANoRedirect(), delegateQueue: nil)
    }
    private static func headers(_ r: inout URLRequest, _ cr: ForgeFixCredentials) {
        r.setValue("Bearer " + cr.accessToken, forHTTPHeaderField: "Authorization")
        r.setValue(cr.deviceID, forHTTPHeaderField: "x-mirsa-device")
        r.setValue(cr.deviceToken, forHTTPHeaderField: "x-mirsa-device-token")
    }
    private static func json(_ body: [String: Any], to url: URL, _ cr: ForgeFixCredentials, _ s: URLSession) async throws -> [String: Any] {
        var r = URLRequest(url: url, timeoutInterval: 30); r.httpMethod = "POST"; headers(&r, cr)
        r.setValue("application/json", forHTTPHeaderField: "Content-Type"); r.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (d, resp) = try await s.data(for: r)
        guard let h = resp as? HTTPURLResponse, h.statusCode == 200, d.count <= 16384,
              let o = try JSONSerialization.jsonObject(with: d) as? [String: Any] else { throw ForgeClient.Failure.message(ForgePortText.unavailable) }
        return o
    }

    /// One-shot: a failed stream is never retried silently (server answers 409 on replay).
    static func upload(file: URL, role: String, credentials cr: ForgeFixCredentials, progress: @escaping (Double) -> Void = { _ in }) async throws -> Ready {
        guard let base else { throw ForgeClient.Failure.message(ForgePortText.unavailable) }
        let (digest, size) = try sha256(file: file)
        guard (32...maxBytes).contains(size), ["old", "new"].contains(role) else { throw ForgePortError.tooLarge }
        let s = session(); defer { s.finishTasksAndInvalidate() }
        let id = UUID()
        let c = try await json(["action": "port-upload-create", "id": id.uuidString.lowercased(), "role": role, "bytes": size, "sha256": digest], to: base, cr, s)
        guard (c["uploadID"] as? String)?.lowercased() == id.uuidString.lowercased(), c["method"] as? String == "POST",
              c["bytes"] as? Int == size, let rel = c["uploadURL"] as? String, let url = resolve(rel, base: base)
        else { throw ForgeClient.Failure.message("Upload permission was invalid.") }
        var r = URLRequest(url: url, timeoutInterval: 300); r.httpMethod = "POST"; headers(&r, cr)
        r.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type"); r.setValue(String(size), forHTTPHeaderField: "Content-Length")
        let (d, resp) = try await s.upload(for: r, fromFile: file)
        progress(1)
        guard let h = resp as? HTTPURLResponse, h.statusCode == 200, d.count <= 4096,
              let o = try JSONSerialization.jsonObject(with: d) as? [String: Any],
              o["state"] as? String == "ready", o["sha256"] as? String == digest, o["bytes"] as? Int == size,
              (o["uploadID"] as? String)?.lowercased() == id.uuidString.lowercased()
        else { throw ForgeClient.Failure.message("Upload was not confirmed by the server.") }
        return Ready(uploadID: id, sha256: digest)
    }

    static func request(id: UUID, tweakID: UUID, bundleID: String, name: String, sourceSHA256: String, code: String, old: Ready, new: Ready, credentials cr: ForgeFixCredentials) async throws -> [String: Any] {
        guard let base else { throw ForgeClient.Failure.message(ForgePortText.unavailable) }
        let s = session(); defer { s.finishTasksAndInvalidate() }
        return try await json(["action": "port-request", "id": id.uuidString.lowercased(), "tweakID": tweakID.uuidString.lowercased(), "bundleID": bundleID,
            "name": name, "sourceSHA256": sourceSHA256, "consent": true, "code": code,
            "oldIPA": ["uploadID": old.uploadID.uuidString.lowercased(), "sha256": old.sha256],
            "newIPA": ["uploadID": new.uploadID.uuidString.lowercased(), "sha256": new.sha256]], to: base, cr, s)
    }
    static func status(id: UUID, credentials cr: ForgeFixCredentials) async throws -> [String: Any] {
        guard let base else { throw ForgeClient.Failure.message(ForgePortText.unavailable) }
        let s = session(); defer { s.finishTasksAndInvalidate() }
        return try await json(["action": "port-status", "id": id.uuidString.lowercased()], to: base, cr, s)
    }
}
