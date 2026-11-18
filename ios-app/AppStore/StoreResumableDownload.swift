import Foundation

/// One HTTP request, with its own session and delegate. A new instance is made for every attempt, so a
/// late callback of an old attempt can never touch the state of a newer one.
final class StoreAttempt: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    enum Outcome: Equatable { case finished, paused, networkLost, restartFromZero }
    struct Result { var outcome: Outcome; var state: StoreResumeState; var progressed: Bool; var discardedBytes: Bool }
    enum Reason { case none, pause, user }

    private let lock = NSLock()
    private let url: URL
    private let folder: URL
    private let validate: (URL) throws -> Void
    private let maxBytes: Int64
    private let protocolClasses: [AnyClass]?
    private let report: @Sendable (Int64, Int64, Bool) -> Void
    private let offset: Int64
    private var state: StoreResumeState
    private var handle: FileHandle?
    private var task: URLSessionDataTask?
    private var cont: CheckedContinuation<Result, Error>?
    private var reason = Reason.none
    private var failure: Error?
    private var decision: StoreRangeDecision?
    private var wantsRestart = false
    private var redirects = 0
    private var bodyReceived: Int64 = 0
    private var bodyExpected: Int64?
    private var sinceSave: Int64 = 0
    private var progressed = false
    private var discardedBytes = false

    init(url: URL, folder: URL, state: StoreResumeState, validate: @escaping (URL) throws -> Void, maxBytes: Int64,
         protocolClasses: [AnyClass]?, report: @escaping @Sendable (Int64, Int64, Bool) -> Void) {
        self.url = url; self.folder = folder; self.state = state; self.validate = validate
        self.maxBytes = maxBytes; self.protocolClasses = protocolClasses; self.report = report
        self.offset = state.bytes
        super.init()
    }

    func cancel(_ why: Reason) {
        lock.lock()
        if reason == .none || why == .user { reason = why }
        let t = task
        lock.unlock()
        t?.cancel()
    }

    private func request(for url: URL) -> URLRequest {
        var req = URLRequest(url: url)
        req.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        if offset > 0, let validator = state.ifRangeValue {
            req.setValue("bytes=\(offset)-", forHTTPHeaderField: "Range")
            req.setValue(validator, forHTTPHeaderField: "If-Range")
        }
        return req
    }

    func run(run: StoreTransferRun) async throws -> Result {
        let handle = try FileHandle(forWritingTo: StoreResumeStore.partial(folder))
        try handle.seek(toOffset: UInt64(offset))
        self.handle = handle
        let cfg = URLSessionConfiguration.ephemeral
        cfg.httpShouldSetCookies = false; cfg.httpCookieStorage = nil; cfg.urlCredentialStorage = nil; cfg.urlCache = nil
        cfg.timeoutIntervalForRequest = 60; cfg.timeoutIntervalForResource = 24 * 3600
        if let protocolClasses { cfg.protocolClasses = protocolClasses }
        let session = URLSession(configuration: cfg, delegate: self, delegateQueue: nil)
        defer {
            session.invalidateAndCancel()
            run.unregister()
            try? handle.synchronize(); try? handle.close(); self.handle = nil
            StoreResumeStore.save(state, folder)
        }
        report(state.bytes, state.total ?? 0, false)
        return try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { (c: CheckedContinuation<Result, Error>) in
                let t = session.dataTask(with: request(for: url))
                lock.lock(); cont = c; task = t; let why = reason; lock.unlock()
                guard why == .none, run.register({ [weak self] in self?.cancel(.pause) }) else {
                    // Paused or discarded before the request even started.
                    lock.lock(); cont = nil; lock.unlock()
                    c.resume(returning: Result(outcome: .paused, state: state, progressed: false, discardedBytes: false))
                    return
                }
                t.resume()
            }
        }, onCancel: { self.cancel(.user) })
    }

    // MARK: delegate

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        do {
            guard let next = request.url, redirects < 5 else { throw MirsaStoreError.untrustedURL }
            try validate(next)
            redirects += 1
            // Rebuilt from scratch: only Range / If-Range survive, never credentials or cookies.
            completionHandler(self.request(for: next))
        } catch { failure = error; completionHandler(nil) }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let http = response as? HTTPURLResponse else { failure = MirsaStoreError.invalidPackage; completionHandler(.cancel); return }
        do { if let u = http.url { try validate(u) } } catch { failure = error; completionHandler(.cancel); return }
        let headers = StoreResponseHeaders(etag: http.value(forHTTPHeaderField: "ETag"),
                                           lastModified: http.value(forHTTPHeaderField: "Last-Modified"),
                                           contentRange: http.value(forHTTPHeaderField: "Content-Range"),
                                           contentLength: http.value(forHTTPHeaderField: "Content-Length"),
                                           contentEncoding: http.value(forHTTPHeaderField: "Content-Encoding"))
        let d = StoreRangeLogic.decide(status: http.statusCode, offset: offset, state: state, headers: headers, maxBytes: maxBytes)
        decision = d
        switch d {
        case .append(let length, let total):
            bodyExpected = length
            state.total = total
        case .fullBody(let total):
            if offset > 0 { discardedBytes = true }
            do {
                try handle?.truncate(atOffset: 0)
                try handle?.seek(toOffset: 0)
            } catch { failure = error; completionHandler(.cancel); return }
            state = StoreRangeLogic.freshState(headers, total: total)
            bodyExpected = total
            report(0, total ?? 0, offset > 0)
        case .restartFromZero:
            wantsRestart = true; completionHandler(.cancel); return
        case .fail:
            failure = MirsaStoreError.invalidPackage; completionHandler(.cancel); return
        }
        StoreResumeStore.save(state, folder)
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard failure == nil else { return }
        // Bounds are checked BEFORE the bytes touch the disk.
        let after = state.bytes + Int64(data.count)
        if after > maxBytes || (bodyExpected.map { bodyReceived + Int64(data.count) > $0 } ?? false) {
            failure = MirsaStoreError.invalidPackage; dataTask.cancel(); return
        }
        do {
            try handle?.write(contentsOf: data)
        } catch { failure = error; dataTask.cancel(); return }
        bodyReceived += Int64(data.count)
        state.bytes = after
        sinceSave += Int64(data.count)
        progressed = true
        if sinceSave >= 1_048_576 {
            sinceSave = 0
            try? handle?.synchronize()
            StoreResumeStore.save(state, folder)
        }
        report(state.bytes, state.total ?? 0, false)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock(); let c = cont; cont = nil; self.task = nil; let why = reason; lock.unlock()
        guard let c else { return }
        func done(_ o: Outcome) {
            c.resume(returning: Result(outcome: o, state: state, progressed: progressed, discardedBytes: discardedBytes))
        }
        if let failure { c.resume(throwing: failure); return }
        if why == .user { c.resume(throwing: CancellationError()); return }
        if wantsRestart { done(.restartFromZero); return }
        if why == .pause { done(.paused); return }
        if let error {
            let ns = error as NSError
            if ns.domain == NSURLErrorDomain, Self.transient.contains(ns.code) { done(.networkLost); return }
            c.resume(throwing: error); return
        }
        switch decision {
        case .append(let length, _):
            if bodyReceived == length, state.total == state.bytes { done(.finished) } else { done(.networkLost) }
        case .fullBody(let total):
            if let total {
                if state.bytes == total { done(.finished) } else { done(.networkLost) }
            } else if state.bytes > 0 {
                state.total = state.bytes; done(.finished)
            } else { c.resume(throwing: MirsaStoreError.invalidPackage) }
        default:
            c.resume(throwing: MirsaStoreError.invalidPackage)
        }
    }

    private static let transient: Set<Int> = [
        NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost, NSURLErrorTimedOut,
        NSURLErrorCannotConnectToHost, NSURLErrorDataNotAllowed, NSURLErrorInternationalRoamingOff,
        NSURLErrorCallIsActive, NSURLErrorDNSLookupFailed, NSURLErrorCannotFindHost
    ]
}

/// Resumes the same bytes of one app/version for one account. Pause, network loss and restart are all here.
final class StoreResumableDownload: @unchecked Sendable {
    typealias NetworkWait = @Sendable () async -> StoreNetworkWait.Result
    private let folder: URL
    private let validate: (URL) throws -> Void
    private let maxBytes: Int64
    private let protocolClasses: [AnyClass]?
    private let networkWait: NetworkWait
    private let report: @Sendable (Int64, Int64, Bool) -> Void
    private let phase: @Sendable (StoreTransferControl.Phase) -> Void

    init(folder: URL, maxBytes: Int64 = StoreRangeLogic.maxBytes,
         protocolClasses: [AnyClass]? = nil,
         validate: @escaping (URL) throws -> Void,
         networkWait: @escaping NetworkWait = { await StoreNetworkWait.untilOnline() },
         phase: @escaping @Sendable (StoreTransferControl.Phase) -> Void = { _ in },
         report: @escaping @Sendable (Int64, Int64, Bool) -> Void = { _, _, _ in }) {
        self.folder = folder; self.validate = validate; self.maxBytes = maxBytes
        self.protocolClasses = protocolClasses; self.networkWait = networkWait; self.phase = phase; self.report = report
    }

    func download(_ url: URL, to destination: URL, run: StoreTransferRun) async throws {
        try validate(url)
        try StoreResumeStore.prepare(folder)
        StoreResumeStore.prune(keep: folder)
        var restarts = 0, failures = 0
        var state = StoreResumeStore.load(folder)
        while true {
            try Task.checkCancellation()
            if run.discardRequested { throw CancellationError() }
            await run.waitWhilePaused()
            try Task.checkCancellation()
            if run.discardRequested { throw CancellationError() }
            let reconciled = StoreResumeStore.reconcile(state, folder: folder)
            state = reconciled.state
            if reconciled.discarded {
                restarts += 1
                if restarts > 3 { throw MirsaStoreError.invalidPackage }
                report(0, 0, true)
            }
            StoreResumeStore.save(state, folder)
            phase(.running)
            let attempt = StoreAttempt(url: url, folder: folder, state: state, validate: validate, maxBytes: maxBytes,
                                       protocolClasses: protocolClasses, report: report)
            let result = try await attempt.run(run: run)
            state = result.state
            if result.discardedBytes { report(state.bytes, state.total ?? 0, true) }
            switch result.outcome {
            case .finished:
                let fm = FileManager.default
                try? fm.removeItem(at: destination)
                try fm.moveItem(at: StoreResumeStore.partial(folder), to: destination)
                StoreResumeStore.clear(folder)
                return
            case .paused:
                phase(.paused)
            case .networkLost:
                if result.progressed { failures = 0 }
                phase(.waitingForNetwork)
                let net = await networkWait()
                try Task.checkCancellation()
                if run.discardRequested { throw CancellationError() }
                switch net {
                case .timedOut: throw URLError(.notConnectedToInternet)
                case .alreadyOnline:
                    // The network is fine but the server keeps failing: no endless loop.
                    if !result.progressed { failures += 1 }
                    if failures >= 3 { throw URLError(.timedOut) }
                case .becameOnline: break
                }
            case .restartFromZero:
                restarts += 1
                if restarts > 3 { StoreResumeStore.clear(folder); throw MirsaStoreError.invalidPackage }
                state = StoreResumeState()
                try? FileManager.default.removeItem(at: StoreResumeStore.partial(folder))
                StoreResumeStore.save(state, folder)
                report(0, 0, true)
            }
        }
    }
}
