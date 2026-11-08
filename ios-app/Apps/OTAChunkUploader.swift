import Foundation

/// Reusable resumable file-chunk uploader. Reads one chunk at a time from disk
/// (never the whole file), reports byte progress through a URLSession delegate,
/// and refuses redirects. The wire format is supplied by `requestBuilder`.
enum OTAChunkError: LocalizedError, Equatable {
    case tooLarge, badHost, cancelled, server(Int), emptyFile, expired, badResponse
    var errorDescription: String? {
        switch self {
        case .tooLarge: return personalText("This app is larger than the 2 GB upload limit.", "التطبيق أكبر من حد الرفع 2 غيغا.")
        case .badHost: return personalText("Upload server is not allowed.", "سيرفر الرفع غير مسموح.")
        case .cancelled: return personalText("Upload cancelled.", "تم إلغاء الرفع.")
        case .server(let c): return personalText("Upload failed (code \(c)).", "فشل الرفع (رمز \(c)).")
        case .expired: return personalText("Upload session expired.", "انتهت جلسة الرفع.")
        case .badResponse: return personalText("Unexpected reply from the upload server.", "رد غير متوقع من سيرفر الرفع.")
        case .emptyFile: return personalText("The file is empty.", "الملف فاضي.")
        }
    }
}

struct OTAChunkPlan: Equatable {
    static let maxBytes: Int64 = 2 * 1024 * 1024 * 1024
    let total: Int64, chunkSize: Int64
    init(total: Int64, chunkSize: Int64 = 8 * 1024 * 1024) throws {
        guard total > 0 else { throw OTAChunkError.emptyFile }
        guard total <= Self.maxBytes else { throw OTAChunkError.tooLarge }
        self.total = total; self.chunkSize = max(1, chunkSize)
    }
    var count: Int { Int((total + chunkSize - 1) / chunkSize) }
    func range(_ index: Int) -> Range<Int64> {
        let s = Int64(index) * chunkSize
        return s..<min(total, s + chunkSize)
    }
}

enum OTAHostPolicy {
    static let allowed: Set<String> = ["mirsa-app.mooo.com"]
    static func acceptsManifest(_ url: URL) -> Bool {
        guard accepts(url), url.fragment == nil, url.path.hasPrefix("/ota/") else { return false }
        let q = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        return q.contains { $0.name == "kind" && $0.value == "manifest" } && q.contains { $0.name == "token" && !($0.value ?? "").isEmpty }
    }
    static func accepts(_ url: URL) -> Bool {
        url.scheme == "https" && url.user == nil && url.password == nil && url.port == nil
            && allowed.contains(url.host?.lowercased() ?? "")
    }
}

final class OTAProgressDelegate: NSObject, URLSessionTaskDelegate {
    private let lock = NSLock()
    private var handler: ((Int64) -> Void)?
    func set(_ h: ((Int64) -> Void)?) { lock.lock(); handler = h; lock.unlock() }
    func urlSession(_ s: URLSession, task: URLSessionTask, willPerformHTTPRedirection r: HTTPURLResponse, newRequest q: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
    func urlSession(_ s: URLSession, task: URLSessionTask, didSendBodyData b: Int64, totalBytesSent t: Int64, totalBytesExpectedToSend e: Int64) {
        lock.lock(); let h = handler; lock.unlock(); h?(t)
    }
}

struct OTASession { let url: URL; let token: String; let maxChunk: Int64 }

enum OTAOracleWire {
    static let basePrefix = "/ota/sessions/"
    /// Strict non-negative integral offset; rejects Bool, fractions, negatives.
    static func offset(from data: Data) -> Int64? {
        guard let o = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any], let n = o["offset"] as? NSNumber else { return nil }
        guard CFGetTypeID(n) != CFBooleanGetTypeID() else { return nil }
        let d = n.doubleValue
        guard d >= 0, d == d.rounded(), d <= 9_007_199_254_740_992 else { return nil }
        return n.int64Value
    }
    static func parseDate(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }
    static func session(from data: Data, now: Date = Date()) throws -> OTASession {
        guard let o = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let s = o["uploadURL"] as? String, let url = URL(string: s), OTAHostPolicy.accepts(url),
              url.path.hasPrefix(basePrefix), url.query == nil, url.fragment == nil,
              let token = o["uploadToken"] as? String, !token.isEmpty else { throw OTAChunkError.badHost }
        if let e = o["expiresAt"] {
            guard let es = e as? String, let date = parseDate(es), date > now else { throw OTAChunkError.expired }
        }
        var m: Int64 = 8 * 1024 * 1024
        if let raw = o["maxChunkBytes"] {
            guard let n = raw as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(), n.doubleValue >= 1, n.doubleValue == n.doubleValue.rounded() else { throw OTAChunkError.badHost }
            m = min(n.int64Value, m)
        }
        return OTASession(url: url, token: token, maxChunk: m)
    }
}

enum OTAFallbackPolicy {
    static let limit: Int64 = 30 * 1024 * 1024
    /// Only genuine network failure or VM-down gateway errors may use the Supabase path.
    static func allows(_ error: Error, size: Int64) -> Bool {
        guard size <= limit else { return false }
        if let u = error as? URLError {
            return [.cannotConnectToHost, .cannotFindHost, .dnsLookupFailed, .timedOut, .networkConnectionLost, .notConnectedToInternet].contains(u.code)
        }
        if case OTAChunkError.server(let c) = error { return [500, 502, 503, 504].contains(c) }
        return false
    }
}

final class OTAChunkUploader {
    private let session: URLSession
    private let delegate = OTAProgressDelegate()
    private let configuration: URLSessionConfiguration
    private let backoff: [TimeInterval]
    init(configuration: URLSessionConfiguration = .ephemeral, backoff: [TimeInterval] = [0.5, 1, 2, 4]) {
        configuration.httpCookieStorage = nil
        self.configuration = configuration
        self.backoff = backoff
        session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
    }
    func cancel() { session.invalidateAndCancel() }

    private func request(_ s: OTASession, _ url: URL, _ method: String) -> URLRequest {
        var r = URLRequest(url: url, timeoutInterval: 120)
        r.httpMethod = method
        r.setValue("Bearer " + s.token, forHTTPHeaderField: "Authorization")
        return r
    }
    private func map(_ e: Error) -> Error {
        if e is CancellationError { return OTAChunkError.cancelled }
        if let u = e as? URLError, u.code == .cancelled { return OTAChunkError.cancelled }
        return e
    }
    static func isTransient(_ e: Error) -> Bool {
        if let u = e as? URLError {
            return [.timedOut, .networkConnectionLost, .notConnectedToInternet, .cannotConnectToHost, .dnsLookupFailed, .cannotFindHost].contains(u.code)
        }
        if case OTAChunkError.server(let c) = e { return c == 408 || c == 429 || (500...599).contains(c) }
        return false
    }

    private func offsetCall(_ s: OTASession, _ method: String) async throws -> Int64 {
        guard OTAHostPolicy.accepts(s.url) else { throw OTAChunkError.badHost }
        do {
            let (d, resp) = try await session.data(for: request(s, s.url, method))
            let c = (resp as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(c) else { throw OTAChunkError.server(c) }
            guard let off = OTAOracleWire.offset(from: d) else { throw OTAChunkError.badResponse }
            return off
        } catch { throw map(error) }
    }
    /// Creates (idempotent) and returns the server's committed offset.
    func open(_ s: OTASession) async throws -> Int64 { try await offsetCall(s, "POST") }
    func status(_ s: OTASession) async throws -> Int64 { try await offsetCall(s, "GET") }

    /// Authoritative-offset status with bounded retries.
    private func statusWithRetry(_ s: OTASession) async throws -> Int64 {
        var attempt = 0
        while true {
            do { return try await status(s) }
            catch {
                guard Self.isTransient(error), attempt < backoff.count else { throw error }
                try await Task.sleep(nanoseconds: UInt64(backoff[attempt] * 1e9)); attempt += 1
            }
        }
    }

    /// Streams chunks from the acknowledged offset. Transient failures re-read the
    /// server offset (never re-append blindly); 409 trusts the server offset.
    func upload(file: URL, total: Int64, session s: OTASession, from startOffset: Int64, chunkSize: Int64? = nil,
                progress: @escaping (Double) -> Void) async throws {
        guard total > 0, startOffset >= 0, startOffset <= total else { throw OTAChunkError.badResponse }
        let plan = try OTAChunkPlan(total: total, chunkSize: min(chunkSize ?? s.maxChunk, s.maxChunk))
        guard let handle = try? FileHandle(forReadingFrom: file) else { throw OTAChunkError.emptyFile }
        defer { try? handle.close() }
        var offset = startOffset, conflicts = 0, retries = 0
        progress(Double(offset) / Double(total))
        while offset < total {
            try Task.checkCancellation()
            let len = min(plan.chunkSize, total - offset)
            try handle.seek(toOffset: UInt64(offset))
            guard let body = try handle.read(upToCount: Int(len)), Int64(body.count) == len else { throw OTAChunkError.emptyFile }
            var r = request(s, s.url, "PUT")
            r.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
            r.setValue(String(offset), forHTTPHeaderField: "X-Mirsa-Offset")
            let base = offset
            delegate.set { sent in progress(min(Double(base + min(sent, len)) / Double(total), 1)) }
            do {
                let (d, resp) = try await session.upload(for: r, from: body)
                let c = (resp as? HTTPURLResponse)?.statusCode ?? 0
                if c == 409 {
                    guard conflicts < 5, let auth = OTAOracleWire.offset(from: d), auth <= total else { throw OTAChunkError.server(409) }
                    conflicts += 1; offset = auth; continue
                }
                guard (200..<300).contains(c) else { throw OTAChunkError.server(c) }
                guard let next = OTAOracleWire.offset(from: d), next == offset + len else { throw OTAChunkError.badResponse }
                offset = next; retries = 0
            } catch {
                let e = map(error)
                guard Self.isTransient(e), retries < backoff.count else { throw e }
                try await Task.sleep(nanoseconds: UInt64(backoff[retries] * 1e9)); retries += 1
                let auth = try await statusWithRetry(s)
                guard auth <= total else { throw OTAChunkError.badResponse }
                offset = auth
            }
            progress(Double(offset) / Double(total))
        }
    }

    func finalize(_ s: OTASession) async throws -> URL {
        let url = s.url.appendingPathComponent("finalize")
        do {
            let (d, resp) = try await session.data(for: request(s, url, "POST"))
            let c = (resp as? HTTPURLResponse)?.statusCode ?? 0
            guard c == 200 else { throw OTAChunkError.server(c) }
            guard let o = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any],
                  let m = o["manifestURL"] as? String, let mu = URL(string: m), OTAHostPolicy.acceptsManifest(mu) else { throw OTAChunkError.badResponse }
            return mu
        } catch { throw map(error) }
    }

    /// DELETE on a fresh short-lived session, detached so a cancelled caller can still clean up.
    static func abort(_ s: OTASession, configuration: URLSessionConfiguration = .ephemeral) async {
        await Task.detached {
            configuration.httpCookieStorage = nil
            configuration.timeoutIntervalForRequest = 10
            let sess = URLSession(configuration: configuration, delegate: OTAProgressDelegate(), delegateQueue: nil)
            defer { sess.finishTasksAndInvalidate() }
            var r = URLRequest(url: s.url, timeoutInterval: 10)
            r.httpMethod = "DELETE"
            r.setValue("Bearer " + s.token, forHTTPHeaderField: "Authorization")
            _ = try? await sess.data(for: r)
        }.value
    }

    /// open -> upload -> finalize; aborts the server session on any non-finalized failure.
    static func run(file: URL, total: Int64, session s: OTASession, configuration: URLSessionConfiguration = .ephemeral,
                    backoff: [TimeInterval] = [0.5, 1, 2, 4], chunkSize: Int64? = nil,
                    progress: @escaping (Double) -> Void) async throws -> URL {
        let up = OTAChunkUploader(configuration: configuration, backoff: backoff)
        return try await withTaskCancellationHandler {
            do {
                let start = try await up.open(s)
                try await up.upload(file: file, total: total, session: s, from: start, chunkSize: chunkSize, progress: progress)
                return try await up.finalize(s)
            } catch {
                up.cancel()
                await abort(s, configuration: configuration)
                throw (error is CancellationError) ? OTAChunkError.cancelled : error
            }
        } onCancel: { up.cancel() }
    }
}
