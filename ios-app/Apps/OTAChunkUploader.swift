import Foundation

/// Reusable resumable file-chunk uploader. Reads one chunk at a time from disk
/// (never the whole file), reports byte progress through a URLSession delegate,
/// and refuses redirects. The wire format is supplied by `requestBuilder`.
enum OTAChunkError: LocalizedError, Equatable {
    case tooLarge, badHost, cancelled, server(Int), emptyFile
    var errorDescription: String? {
        switch self {
        case .tooLarge: return personalText("This app is larger than the 2 GB upload limit.", "التطبيق أكبر من حد الرفع 2 غيغا.")
        case .badHost: return personalText("Upload server is not allowed.", "سيرفر الرفع غير مسموح.")
        case .cancelled: return personalText("Upload cancelled.", "تم إلغاء الرفع.")
        case .server(let c): return personalText("Upload failed (code \(c)).", "فشل الرفع (رمز \(c)).")
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
    static func accepts(_ url: URL) -> Bool {
        url.scheme == "https" && url.user == nil && url.password == nil && url.port == nil
            && allowed.contains(url.host?.lowercased() ?? "")
    }
}

final class OTAProgressDelegate: NSObject, URLSessionTaskDelegate {
    var onBytes: ((Int64) -> Void)?
    func urlSession(_ s: URLSession, task: URLSessionTask, willPerformHTTPRedirection r: HTTPURLResponse, newRequest q: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
    func urlSession(_ s: URLSession, task: URLSessionTask, didSendBodyData b: Int64, totalBytesSent t: Int64, totalBytesExpectedToSend e: Int64) { onBytes?(t) }
}

struct OTASession { let url: URL; let token: String; let maxChunk: Int64 }

enum OTAOracleWire {
    static let basePrefix = "/ota/sessions/"
    static func offset(from data: Data) -> Int64? {
        ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])?["offset"] as? Int64
            ?? (((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])?["offset"] as? Int).map(Int64.init)
    }
    static func session(from data: Data) throws -> OTASession {
        guard let o = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let s = o["uploadURL"] as? String, let url = URL(string: s), OTAHostPolicy.accepts(url),
              url.path.hasPrefix(basePrefix), url.query == nil,
              let token = o["uploadToken"] as? String, !token.isEmpty else { throw OTAChunkError.badHost }
        let m = (o["maxChunkBytes"] as? NSNumber)?.int64Value ?? 8 * 1024 * 1024
        return OTASession(url: url, token: token, maxChunk: min(max(m, 1), 8 * 1024 * 1024))
    }
}

final class OTAChunkUploader {
    private let session: URLSession
    private let delegate = OTAProgressDelegate()
    init() {
        let c = URLSessionConfiguration.ephemeral
        c.httpCookieStorage = nil
        session = URLSession(configuration: c, delegate: delegate, delegateQueue: nil)
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

    /// Creates (idempotent) and returns the server's committed offset.
    func open(_ s: OTASession) async throws -> Int64 {
        guard OTAHostPolicy.accepts(s.url) else { throw OTAChunkError.badHost }
        do {
            let (d, resp) = try await session.data(for: request(s, s.url, "POST"))
            let c = (resp as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(c), let off = OTAOracleWire.offset(from: d) else { throw OTAChunkError.server(c) }
            return off
        } catch { throw map(error) }
    }

    /// Streams chunks from the server-acknowledged offset, trusting 409 offsets.
    func upload(file: URL, total: Int64, session s: OTASession, from startOffset: Int64,
                progress: @escaping (Double) -> Void) async throws {
        let plan = try OTAChunkPlan(total: total, chunkSize: s.maxChunk)
        guard let handle = try? FileHandle(forReadingFrom: file) else { throw OTAChunkError.emptyFile }
        defer { try? handle.close() }
        var offset = startOffset, conflicts = 0
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
            delegate.onBytes = { sent in progress(Double(base + sent) / Double(total)) }
            do {
                let (d, resp) = try await session.upload(for: r, from: body)
                let c = (resp as? HTTPURLResponse)?.statusCode ?? 0
                if c == 409, let auth = OTAOracleWire.offset(from: d), auth >= 0, auth <= total, conflicts < 5 {
                    conflicts += 1; offset = auth; continue
                }
                guard (200..<300).contains(c), let next = OTAOracleWire.offset(from: d), next > offset, next <= total else { throw OTAChunkError.server(c) }
                offset = next
            } catch { throw map(error) }
            progress(Double(offset) / Double(total))
        }
    }

    func finalize(_ s: OTASession) async throws -> URL {
        let url = s.url.appendingPathComponent("finalize")
        do {
            let (d, resp) = try await session.data(for: request(s, url, "POST"))
            let c = (resp as? HTTPURLResponse)?.statusCode ?? 0
            guard c == 200, let o = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any],
                  let m = o["manifestURL"] as? String, let mu = URL(string: m), OTAHostPolicy.accepts(mu) else { throw OTAChunkError.server(c) }
            return mu
        } catch { throw map(error) }
    }

    func abort(_ s: OTASession) async { _ = try? await session.data(for: request(s, s.url, "DELETE")) }
}
