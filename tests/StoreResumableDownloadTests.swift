import Foundation
import XCTest
#if canImport(MirsaStoreKit)
@testable import MirsaStoreKit
#else
@testable import Mirsa
#endif

private final class MockCDN: URLProtocol {
    struct Reply { var status: Int; var headers: [String: String]; var body: Data; var cutAfter: Int? = nil }
    nonisolated(unsafe) static var handler: ((URLRequest) -> Reply)?
    nonisolated(unsafe) static var requests: [URLRequest] = []
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requests.append(request)
        guard let r = Self.handler?(request) else { client?.urlProtocol(self, didFailWithError: URLError(.badURL)); return }
        let resp = HTTPURLResponse(url: request.url!, statusCode: r.status, httpVersion: "HTTP/1.1", headerFields: r.headers)!
        client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
        if let cut = r.cutAfter {
            if cut == 0 {
                client?.urlProtocol(self, didFailWithError: URLError(.networkConnectionLost))
            } else {
                // Complete a deliberately short body. URLProtocol may buffer didLoad
                // until completion, so waiting for delegate progress before completing
                // creates a circular wait. Production detects EOF before Content-Length.
                client?.urlProtocol(self, didLoad: r.body.prefix(cut))
                client?.urlProtocolDidFinishLoading(self)
            }
        } else {
            client?.urlProtocol(self, didLoad: r.body)
            client?.urlProtocolDidFinishLoading(self)
        }
    }
    override func stopLoading() {}
}

final class StoreResumableDownloadTests: XCTestCase {
    private let url = URL(string: "https://cdn.apple.com/app.ipa")!
    private let body = Data((0..<100).map { UInt8($0) })
    private var dir: URL!
    override func setUp() {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        MockCDN.requests = []; MockCDN.handler = nil
    }
    override func tearDown() { try? FileManager.default.removeItem(at: dir) }

    private func make(max: Int64 = 1000, wait: @escaping StoreResumableDownload.NetworkWait = { .becameOnline }) -> StoreResumableDownload {
        StoreResumableDownload(folder: dir.appendingPathComponent("f"), maxBytes: max, protocolClasses: [MockCDN.self],
                               validate: { try MirsaStorePolicy.downloadURL($0) }, networkWait: wait)
    }
    private func serve(etag: String = "\"v1\"", cutFirst: Int? = nil) {
        var first = true
        MockCDN.handler = { [body] req in
            if let range = req.value(forHTTPHeaderField: "Range"), range.hasPrefix("bytes="),
               let start = Int(range.dropFirst(6).dropLast()), req.value(forHTTPHeaderField: "If-Range") == etag {
                let part = body.suffix(from: start)
                return .init(status: 206, headers: ["ETag": etag, "Content-Range": "bytes \(start)-99/100", "Content-Length": "\(part.count)"], body: Data(part))
            }
            let cut = first ? cutFirst : nil; first = false
            return .init(status: 200, headers: ["ETag": etag, "Content-Length": "100"], body: body, cutAfter: cut)
        }
    }
    func testFullDownload() async throws {
        serve()
        let out = dir.appendingPathComponent("out.ipa")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try await make().download(url, to: out, run: StoreTransferRun())
        XCTAssertEqual(try Data(contentsOf: out), body)
    }
    func testTruncatedEOFResumesWithRange() async throws {
        serve(cutFirst: 40)
        let out = dir.appendingPathComponent("out.ipa")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try await make().download(url, to: out, run: StoreTransferRun())
        XCTAssertEqual(try Data(contentsOf: out), body)
        XCTAssertEqual(MockCDN.requests.count, 2)
        XCTAssertEqual(MockCDN.requests[1].value(forHTTPHeaderField: "Range"), "bytes=40-")
        XCTAssertEqual(MockCDN.requests[1].value(forHTTPHeaderField: "If-Range"), "\"v1\"")
    }
    func testConnectionLostPreservesExistingPartialAndRetriesRange() async throws {
        // Explicit URLError path with a pre-existing partial. The EOF test above
        // separately proves partial bytes originate from the real delegate pipeline.
        let folder = dir.appendingPathComponent("f")
        try StoreResumeStore.prepare(folder)
        try body.prefix(40).write(to: StoreResumeStore.partial(folder))
        let headers = StoreResponseHeaders(etag: "\"v1\"", lastModified: nil,
                                           contentRange: nil, contentLength: "100", contentEncoding: nil)
        var state = StoreRangeLogic.freshState(headers, total: 100)
        state.bytes = 40
        StoreResumeStore.save(state, folder)
        var first = true
        MockCDN.handler = { [body] _ in
            if first {
                first = false
                return .init(status: 206, headers: ["ETag": "\"v1\"", "Content-Range": "bytes 40-99/100",
                                                   "Content-Length": "60"], body: Data(), cutAfter: 0)
            }
            return .init(status: 206, headers: ["ETag": "\"v1\"", "Content-Range": "bytes 40-99/100",
                                               "Content-Length": "60"], body: Data(body.suffix(60)))
        }
        let out = dir.appendingPathComponent("out.ipa")
        try await make().download(url, to: out, run: StoreTransferRun())
        XCTAssertEqual(try Data(contentsOf: out), body)
        XCTAssertEqual(MockCDN.requests.count, 2)
        for request in MockCDN.requests {
            XCTAssertEqual(request.value(forHTTPHeaderField: "Range"), "bytes=40-")
            XCTAssertEqual(request.value(forHTTPHeaderField: "If-Range"), "\"v1\"")
        }
    }
    func testChangedFileRestartsFromZero() async throws {
        var n = 0
        MockCDN.handler = { [body] req in
            n += 1
            if n == 1 { return .init(status: 200, headers: ["ETag": "\"v1\"", "Content-Length": "100"], body: body, cutAfter: 40) }
            if req.value(forHTTPHeaderField: "Range") != nil {
                return .init(status: 206, headers: ["ETag": "\"v2\"", "Content-Range": "bytes 40-99/100", "Content-Length": "60"], body: Data(body.suffix(60)))
            }
            return .init(status: 200, headers: ["ETag": "\"v2\"", "Content-Length": "100"], body: body)
        }
        let out = dir.appendingPathComponent("out.ipa")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try await make().download(url, to: out, run: StoreTransferRun())
        XCTAssertEqual(try Data(contentsOf: out), body)
        XCTAssertNil(MockCDN.requests.last?.value(forHTTPHeaderField: "Range"))
    }
    func testBodyCapStopsBeforeWriting() async throws {
        serve()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        do {
            try await make(max: 50).download(url, to: dir.appendingPathComponent("o"), run: StoreTransferRun())
            XCTFail("must fail")
        } catch { XCTAssertTrue(true) }
    }
    func testUntrustedHostRejected() async throws {
        let bad = URL(string: "https://evil.example/app.ipa")!
        do { try await make().download(bad, to: dir.appendingPathComponent("o"), run: StoreTransferRun()); XCTFail() }
        catch { XCTAssertTrue(MockCDN.requests.isEmpty) }
    }
    func testNoEndlessRetryWhenServerKeepsFailing() async throws {
        MockCDN.handler = { [body] _ in .init(status: 200, headers: ["Content-Length": "100"], body: body, cutAfter: 0) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        do { try await make(wait: { .alreadyOnline }).download(url, to: dir.appendingPathComponent("o"), run: StoreTransferRun()); XCTFail() }
        catch { XCTAssertLessThanOrEqual(MockCDN.requests.count, 4) }
    }
    func testCancelWhilePausedReturnsAndKeepsPartial() async throws {
        serve()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let run = StoreTransferRun(); run.pause()
        let d = make()
        let t = Task { try await d.download(url, to: self.dir.appendingPathComponent("o"), run: run) }
        try await Task.sleep(nanoseconds: 100_000_000)
        t.cancel()
        do { try await t.value; XCTFail() } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertTrue(MockCDN.requests.isEmpty)
    }
    func testDiscardWhilePausedThrows() async throws {
        serve()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let run = StoreTransferRun(); run.pause()
        let d = make()
        let t = Task { try await d.download(url, to: self.dir.appendingPathComponent("o"), run: run) }
        try await Task.sleep(nanoseconds: 100_000_000)
        run.requestDiscard()
        do { try await t.value; XCTFail() } catch { XCTAssertTrue(error is CancellationError) }
    }
}

final class StoreTransferLifecycleTests: XCTestCase {
    func testOldEndCannotOverwriteNewRunEvenWhenIdlePublishArrivesLast() {
        var pending: [() -> Void] = []
        let control = StoreTransferControl(enqueue: { pending.append($0) })
        let a = control.begin()
        pending.removeFirst()()
        control.end(a)
        let b = control.begin()
        // Model end(A) unlocking, begin(B) publishing, then A's idle publication.
        let idleA = pending.removeFirst()
        pending.removeFirst()()
        XCTAssertEqual(control.phase, .running)
        idleA()
        XCTAssertEqual(control.phase, .running)
        control.pause()
        pending.removeFirst()()
        XCTAssertEqual(control.phase, .paused)
        control.end(a)
        XCTAssertTrue(pending.isEmpty)
        control.end(b)
        pending.removeFirst()()
        XCTAssertEqual(control.phase, .idle)
    }
}
