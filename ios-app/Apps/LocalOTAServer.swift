import Foundation
import Network

/// Route chosen for the signed IPA handoff. Only `.local` means bytes are served from this device.
enum OTARoute: Equatable {
    case local
    case upload(reason: OTAUploadReason)
}
enum OTAUploadReason: String, Equatable {
    case disabledByUser, fileUnavailable, serverStartFailed, manifestUnreachable, noInstallerRequest
    var english: String {
        switch self {
        case .disabledByUser: return "Local install is turned off."
        case .fileUnavailable: return "The signed IPA is not readable for local serving."
        case .serverStartFailed: return "The on-device server could not start."
        case .manifestUnreachable: return "The HTTPS install manifest was not reachable."
        case .noInstallerRequest: return "iOS did not request the app from this device in time."
        }
    }
    var arabic: String {
        switch self {
        case .disabledByUser: return "التثبيت المحلي مطفي."
        case .fileUnavailable: return "ما قدرت اقرأ الـ IPA الموقّع للتشغيل المحلي."
        case .serverStartFailed: return "السيرفر المحلي ما اشتغل."
        case .manifestUnreachable: return "ملف التثبيت HTTPS ما انوصل."
        case .noInstallerRequest: return "iOS ما طلب التطبيق من هالجهاز بالوقت المحدد."
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
    /// Real HTTPS GET so an undeployed/broken broker is caught before iOS silently shows nothing.
    static func preflight(_ url: URL, port: UInt16, timeout: TimeInterval = 8) async -> Bool {
        var req = URLRequest(url: url, timeoutInterval: timeout)
        req.cachePolicy = .reloadIgnoringLocalCacheData
        let cfg = URLSessionConfiguration.ephemeral; cfg.httpCookieStorage = nil
        let s = URLSession(configuration: cfg, delegate: OTANoRedirect(), delegateQueue: nil)
        defer { s.invalidateAndCancel() }
        guard let (d, r) = try? await s.data(for: req), (r as? HTTPURLResponse)?.statusCode == 200,
              d.count < 64 * 1024, let body = String(data: d, encoding: .utf8) else { return false }
        return body.contains("http://127.0.0.1:\(port)/") && body.contains("software-package")
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
/// Serves exactly one file on 127.0.0.1 under an unguessable token path. All mutable state is guarded by `lock`
/// and all network callbacks run on one serial queue. Not reachable from the network.
final class LocalOTAServer: @unchecked Sendable {
    static let maxConnections = 8
    static let maxHeaderBytes = 16 * 1024
    /// Injectable for tests. Applies to receiving the request header only.
    nonisolated(unsafe) static var headerTimeout: TimeInterval = 30
    let token = (0..<2).map { _ in String(format: "%016llx", UInt64.random(in: .min ... .max)) }.joined()
    private let file: URL
    private let size: Int64
    private let queue = DispatchQueue(label: "mirsa.local-ota")
    private let lock = NSLock()
    private var listener: NWListener?
    private var connections: [ObjectIdentifier: NWConnection] = [:]
    private var headerDone = Set<ObjectIdentifier>()
    private var stopped = false
    private var _servedBytes: Int64 = 0
    private var _port: UInt16 = 0
    private var requested = false
    private var waiter: CheckedContinuation<Bool, Never>?
    var onStop: (@Sendable () -> Void)?
    var servedBytes: Int64 { lock.lock(); defer { lock.unlock() }; return _servedBytes }
    var port: UInt16 { lock.lock(); defer { lock.unlock() }; return _port }
    var isStopped: Bool { lock.lock(); defer { lock.unlock() }; return stopped }
    enum Failure: Error { case unreadable, start, timeout }
    init(file: URL) throws {
        self.file = file
        guard let s = (try file.resourceValues(forKeys: [.fileSizeKey])).fileSize, s > 0 else { throw Failure.unreadable }
        size = Int64(s)
    }
    func start(lifetime: TimeInterval = 600, timeout: TimeInterval = 5) async throws -> UInt16 {
        let params = NWParameters.tcp
        params.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        let l = try NWListener(using: params)
        lock.lock(); listener = l; lock.unlock()
        l.newConnectionHandler = { [weak self] c in self?.accept(c) }
        let ready: UInt16
        do { ready = try await withCheckedThrowingContinuation { cont in
            let box = OnceBox<UInt16>(cont)
            l.stateUpdateHandler = { st in
                switch st {
                case .ready: if let p = l.port?.rawValue { box.resume(.success(p)) }
                case .failed(let e): box.resume(.failure(e))
                case .cancelled: box.resume(.failure(Failure.start))
                default: break
                }
            }
            queue.asyncAfter(deadline: .now() + timeout) { box.resume(.failure(Failure.timeout)); }
            l.start(queue: queue)
        } } catch { stop(); throw error }
        lock.lock(); _port = ready; let already = stopped; lock.unlock()
        if already { l.cancel(); throw Failure.start }
        queue.asyncAfter(deadline: .now() + lifetime) { [weak self] in self?.stop() }
        return ready
    }
    /// True once a valid-token GET delivered its first body chunk (HEAD never counts). False on timeout or stop. Single bounded wait.
    func awaitFirstRequest(timeout: TimeInterval) async -> Bool {
        await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            lock.lock()
            if requested { lock.unlock(); cont.resume(returning: true); return }
            if stopped { lock.unlock(); cont.resume(returning: false); return }
            waiter = cont
            lock.unlock()
            queue.asyncAfter(deadline: .now() + timeout) { [weak self] in self?.resolveWaiter(false) }
        }
    }
    private func resolveWaiter(_ value: Bool) {
        lock.lock(); let w = waiter; waiter = nil; lock.unlock()
        w?.resume(returning: value)
    }
    func stop() {
        lock.lock()
        let was = stopped; stopped = true
        let l = listener; listener = nil
        let conns = Array(connections.values); connections.removeAll()
        lock.unlock()
        l?.cancel(); conns.forEach { $0.cancel() }
        resolveWaiter(false)
        if !was { onStop?() }
    }
    private func accept(_ conn: NWConnection) {
        let id = ObjectIdentifier(conn)
        lock.lock()
        guard !stopped, connections.count < Self.maxConnections else { lock.unlock(); conn.cancel(); return }
        connections[id] = conn
        lock.unlock()
        conn.stateUpdateHandler = { [weak self] st in
            switch st { case .failed, .cancelled: self?.drop(id); default: break }
        }
        conn.start(queue: queue)
        // Header deadline only: a connection that has not delivered a full request header is cut.
        // Active transfers are never killed by this timer.
        queue.asyncAfter(deadline: .now() + Self.headerTimeout) { [weak self] in
            guard let self else { return }
            self.lock.lock(); let pending = self.connections[id] != nil && !self.headerDone.contains(id); self.lock.unlock()
            if pending { conn.cancel() }
        }
        readHeader(conn, buffer: Data())
    }
    private func drop(_ id: ObjectIdentifier) { lock.lock(); connections[id] = nil; headerDone.remove(id); lock.unlock() }
    private func readHeader(_ conn: NWConnection, buffer: Data) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, complete, err in
            guard let self, err == nil else { conn.cancel(); return }
            var buf = buffer; if let data { buf.append(data) }
            if buf.count > Self.maxHeaderBytes { return self.fail(conn, 431, "Request Header Fields Too Large") }
            if let end = buf.range(of: Data("\r\n\r\n".utf8)) {
                guard let req = String(data: buf[..<end.lowerBound], encoding: .utf8) else { return self.fail(conn, 400, "Bad Request") }
                self.lock.lock(); self.headerDone.insert(ObjectIdentifier(conn)); self.lock.unlock()
                self.respond(conn, request: req)
            } else if complete { conn.cancel() } else { self.readHeader(conn, buffer: buf) }
        }
    }
    private func header(_ req: String, _ name: String) -> String? {
        req.components(separatedBy: "\r\n").first { $0.lowercased().hasPrefix(name.lowercased() + ":") }
            .map { String($0.dropFirst(name.count + 1)).trimmingCharacters(in: .whitespaces) }
    }
    private func fail(_ conn: NWConnection, _ code: Int, _ text: String) {
        conn.send(content: Data("HTTP/1.1 \(code) \(text)\r\nCache-Control: no-store\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".utf8), completion: .contentProcessed { _ in conn.cancel() })
    }
    private func respond(_ conn: NWConnection, request: String) {
        let line = request.components(separatedBy: "\r\n").first?.split(separator: " ").map(String.init) ?? []
        guard line.count >= 2, ["GET", "HEAD"].contains(line[0]) else { return fail(conn, 405, "Method Not Allowed") }
        guard line[1] == "/\(token)/Mirsa.ipa" else { return fail(conn, 404, "Not Found") }
        let range: ClosedRange<Int64>?
        do { range = try LocalOTARange.parse(header(request, "Range"), size: size) } catch { return fail(conn, 416, "Range Not Satisfiable") }
        let lo = range?.lowerBound ?? 0, hi = range?.upperBound ?? size - 1
        let status = range == nil ? "200 OK" : "206 Partial Content"
        var head = "HTTP/1.1 \(status)\r\nContent-Type: application/octet-stream\r\nCache-Control: no-store\r\nAccept-Ranges: bytes\r\nContent-Length: \(hi - lo + 1)\r\nConnection: close\r\n"
        if range != nil { head += "Content-Range: bytes \(lo)-\(hi)/\(size)\r\n" }
        head += "\r\n"
        let isGet = line[0] == "GET"
        conn.send(content: Data(head.utf8), completion: .contentProcessed { [weak self] e in
            guard let self, e == nil else { conn.cancel(); return }
            guard isGet, let fh = try? FileHandle(forReadingFrom: self.file) else { conn.cancel(); return }
            try? fh.seek(toOffset: UInt64(lo))
            self.stream(conn, fh, remaining: hi - lo + 1)
        })
    }
    private func stream(_ conn: NWConnection, _ fh: FileHandle, remaining: Int64) {
        guard !isStopped, remaining > 0, let chunk = try? fh.read(upToCount: Int(min(256 * 1024, remaining))), !chunk.isEmpty else {
            try? fh.close(); conn.cancel(); return
        }
        conn.send(content: chunk, completion: .contentProcessed { [weak self] e in
            if e != nil { try? fh.close(); conn.cancel(); return }
            guard let self else { try? fh.close(); return }
            self.lock.lock(); self._servedBytes += Int64(chunk.count); let first = !self.requested; self.requested = true; self.lock.unlock()  // after successful send
            if first { self.resolveWaiter(true) }  // real GET, first body chunk delivered
            self.stream(conn, fh, remaining: remaining - Int64(chunk.count))
        })
    }
}
/// Resumes a throwing continuation exactly once.
final class OnceBox<T>: @unchecked Sendable {
    private let lock = NSLock(); private var cont: CheckedContinuation<T, Error>?
    init(_ c: CheckedContinuation<T, Error>) { cont = c }
    func resume(_ r: Result<T, Error>) {
        lock.lock(); let c = cont; cont = nil; lock.unlock()
        c?.resume(with: r)
    }
}
