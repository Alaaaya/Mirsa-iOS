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

final class OTAChunkUploader {
    private let session: URLSession
    private let delegate = OTAProgressDelegate()
    init() {
        let c = URLSessionConfiguration.ephemeral
        c.httpCookieStorage = nil
        session = URLSession(configuration: c, delegate: delegate, delegateQueue: nil)
    }
    func cancel() { session.invalidateAndCancel() }
    /// Sends chunks from `start` (resume point). Progress is 0...1 of total bytes.
    func upload(file: URL, plan: OTAChunkPlan, startingAt start: Int = 0,
                requestBuilder: (Int, Range<Int64>) throws -> URLRequest,
                progress: @escaping (Double) -> Void) async throws {
        guard let handle = try? FileHandle(forReadingFrom: file) else { throw OTAChunkError.emptyFile }
        defer { try? handle.close() }
        for i in start..<plan.count {
            try Task.checkCancellation()
            let r = plan.range(i)
            let request = try requestBuilder(i, r)
            guard let url = request.url, OTAHostPolicy.accepts(url) else { throw OTAChunkError.badHost }
            try handle.seek(toOffset: UInt64(r.lowerBound))
            guard let body = try handle.read(upToCount: Int(r.count)), Int64(body.count) == r.count else { throw OTAChunkError.emptyFile }
            delegate.onBytes = { sent in progress(Double(r.lowerBound + sent) / Double(plan.total)) }
            do {
                let (_, resp) = try await session.upload(for: request, from: body)
                let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
                guard (200..<300).contains(code) else { throw OTAChunkError.server(code) }
            } catch is CancellationError { throw OTAChunkError.cancelled }
            catch let e as URLError where e.code == .cancelled { throw OTAChunkError.cancelled }
            progress(Double(r.upperBound) / Double(plan.total))
        }
    }
}
