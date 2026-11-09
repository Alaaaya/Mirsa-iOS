import Foundation
import Network
import UIKit

/// Route chosen for the signed IPA handoff. Only `.local` means bytes are served from this device.
enum OTARoute: Equatable {
    case local
    case upload(reason: OTAUploadReason)
}
enum OTAUploadReason: String, Equatable {
    case disabledByUser, fileUnavailable, serverStartFailed, manifestUnreachable, installerRefused
    var english: String {
        switch self {
        case .disabledByUser: return "Local install is turned off."
        case .fileUnavailable: return "The signed IPA is not readable for local serving."
        case .serverStartFailed: return "The on-device server could not start."
        case .manifestUnreachable: return "The HTTPS install manifest could not be created."
        case .installerRefused: return "iOS refused the local install link."
        }
    }
    var arabic: String {
        switch self {
        case .disabledByUser: return "التثبيت المحلي مطفي."
        case .fileUnavailable: return "ما قدرت اقرأ الـ IPA الموقّع للتشغيل المحلي."
        case .serverStartFailed: return "السيرفر المحلي ما اشتغل."
        case .manifestUnreachable: return "ما انعمل ملف التثبيت HTTPS."
        case .installerRefused: return "iOS رفض رابط التثبيت المحلي."
        }
    }
}
enum OTARouteSelector {
    static let defaultsKey = "mirsa.ota.local.enabled"
    static func select(fileReadable: Bool, enabled: Bool = (UserDefaults.standard.object(forKey: defaultsKey) as? Bool) ?? true) -> OTARoute {
        guard enabled else { return .upload(reason: .disabledByUser) }
        guard fileReadable else { return .upload(reason: .fileUnavailable) }
        return .local
    }
}
enum LocalOTAManifest {
    /// HTTPS manifest URL; the broker only emits a loopback http URL with this port and token.
    static func url(base: URL, port: UInt16, token: String, bundleID: String, version: String, title: String, bytes: Int64) -> URL? {
        guard port >= 1024, token.range(of: "^[a-f0-9]{32,64}$", options: .regularExpression) != nil,
              var c = URLComponents(url: base, resolvingAgainstBaseURL: false), c.scheme == "https" else { return nil }
        c.queryItems = [.init(name: "action", value: "local-manifest"), .init(name: "port", value: String(port)),
            .init(name: "token", value: token), .init(name: "bundleID", value: bundleID), .init(name: "version", value: version),
            .init(name: "title", value: title), .init(name: "bytes", value: String(bytes))]
        return c.url
    }
}
/// Parses a single "bytes=a-b" range. nil = whole file; throws = unsatisfiable.
enum LocalOTARange {
    struct Unsatisfiable: Error {}
    static func parse(_ header: String?, size: Int64) throws -> ClosedRange<Int64>? {
        guard let header, !header.isEmpty else { return nil }
        guard header.hasPrefix("bytes="), !header.contains(","), size > 0 else { throw Unsatisfiable() }
        let parts = header.dropFirst(6).split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 2 else { throw Unsatisfiable() }
        if parts[0].isEmpty {
            guard let n = Int64(parts[1]), n > 0 else { throw Unsatisfiable() }
            return max(0, size - n)...(size - 1)
        }
        guard let a = Int64(parts[0]), a >= 0, a < size else { throw Unsatisfiable() }
        let b = parts[1].isEmpty ? size - 1 : (Int64(parts[1]) ?? -1)
        guard b >= a else { throw Unsatisfiable() }
        return a...min(b, size - 1)
    }
}
/// Serves exactly one file on 127.0.0.1 under an unguessable token path. Not reachable from the network.
final class LocalOTAServer: @unchecked Sendable {
    let token = (0..<2).map { _ in String(format: "%016llx", UInt64.random(in: .min ... .max)) }.joined()
    private let file: URL
    private let size: Int64
    private let queue = DispatchQueue(label: "mirsa.local-ota")
    private var listener: NWListener?
    private var connections = Set<ObjectIdentifier>()
    private var bg: UIBackgroundTaskIdentifier = .invalid
    private(set) var servedBytes: Int64 = 0
    private(set) var port: UInt16 = 0
    init(file: URL) throws {
        self.file = file
        guard let s = (try file.resourceValues(forKeys: [.fileSizeKey])).fileSize, s > 0 else { throw OTAUploadError.unreadable }
        size = Int64(s)
    }
    enum OTAUploadError: Error { case unreadable, start }
    func start(lifetime: TimeInterval = 600) async throws -> UInt16 {
        let params = NWParameters.tcp
        params.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        let l = try NWListener(using: params)
        l.newConnectionHandler = { [weak self] c in self?.serve(c) }
        let ready: UInt16 = try await withCheckedThrowingContinuation { cont in
            var done = false
            l.stateUpdateHandler = { st in
                guard !done else { return }
                switch st {
                case .ready: if let p = l.port?.rawValue { done = true; cont.resume(returning: p) }
                case .failed(let e): done = true; cont.resume(throwing: e)
                case .cancelled: done = true; cont.resume(throwing: OTAUploadError.start)
                default: break
                }
            }
            l.start(queue: queue)
        }
        listener = l; port = ready
        await MainActor.run { bg = UIApplication.shared.beginBackgroundTask { [weak self] in self?.stop() } }
        queue.asyncAfter(deadline: .now() + lifetime) { [weak self] in self?.stop() }
        return ready
    }
    func stop() {
        listener?.cancel(); listener = nil
        let id = bg; bg = .invalid
        if id != .invalid { DispatchQueue.main.async { UIApplication.shared.endBackgroundTask(id) } }
    }
    private func serve(_ conn: NWConnection) {
        conn.start(queue: queue)
        conn.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { [weak self] data, _, _, err in
            guard let self, err == nil, let data, let req = String(data: data, encoding: .utf8) else { conn.cancel(); return }
            self.respond(conn, request: req)
        }
    }
    private func header(_ req: String, _ name: String) -> String? {
        req.components(separatedBy: "\r\n").first { $0.lowercased().hasPrefix(name.lowercased() + ":") }
            .map { String($0.dropFirst(name.count + 1)).trimmingCharacters(in: .whitespaces) }
    }
    private func respond(_ conn: NWConnection, request: String) {
        let line = request.components(separatedBy: "\r\n").first?.split(separator: " ").map(String.init) ?? []
        func fail(_ code: Int, _ text: String) {
            conn.send(content: Data("HTTP/1.1 \(code) \(text)\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".utf8), completion: .contentProcessed { _ in conn.cancel() })
        }
        guard line.count >= 2, ["GET", "HEAD"].contains(line[0]) else { return fail(405, "Method Not Allowed") }
        guard line[1] == "/\(token)/Mirsa.ipa" else { return fail(404, "Not Found") }
        let range: ClosedRange<Int64>?
        do { range = try LocalOTARange.parse(header(request, "Range"), size: size) } catch { return fail(416, "Range Not Satisfiable") }
        let lo = range?.lowerBound ?? 0, hi = range?.upperBound ?? size - 1
        let status = range == nil ? "200 OK" : "206 Partial Content"
        var head = "HTTP/1.1 \(status)\r\nContent-Type: application/octet-stream\r\nAccept-Ranges: bytes\r\nContent-Length: \(hi - lo + 1)\r\nConnection: close\r\n"
        if range != nil { head += "Content-Range: bytes \(lo)-\(hi)/\(size)\r\n" }
        head += "\r\n"
        conn.send(content: Data(head.utf8), completion: .contentProcessed { [weak self] e in
            guard let self, e == nil, line[0] == "GET", let fh = try? FileHandle(forReadingFrom: self.file) else { conn.cancel(); return }
            try? fh.seek(toOffset: UInt64(lo))
            self.stream(conn, fh, remaining: hi - lo + 1)
        })
    }
    private func stream(_ conn: NWConnection, _ fh: FileHandle, remaining: Int64) {
        guard remaining > 0, let chunk = try? fh.read(upToCount: Int(min(256 * 1024, remaining))), !chunk.isEmpty else {
            try? fh.close(); conn.cancel(); return
        }
        servedBytes += Int64(chunk.count)
        conn.send(content: chunk, completion: .contentProcessed { [weak self] e in
            if e != nil { try? fh.close(); conn.cancel(); return }
            self?.stream(conn, fh, remaining: remaining - Int64(chunk.count))
        })
    }
}
