import XCTest
@testable import Mirsa

final class MirsaRequestReadyTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func row(_ id: UUID, _ status: String, age: TimeInterval = 0) -> ForgeChatThread {
        ForgeChatThread(id: id, title: nil, status: status, createdAt: nil,
            updatedAt: ISO8601DateFormatter().string(from: now.addingTimeInterval(-age)))
    }
    func testFirstSnapshotNeverFloodsHistoricalReady() {
        var p = MirsaRequestReadyPolicy()
        XCTAssertTrue(p.observe([row(UUID(), "ready")], now: now).isEmpty)
    }
    func testKnownWorkingBecomesReadyExactlyOnce() {
        var p = MirsaRequestReadyPolicy(); let id = UUID()
        XCTAssertTrue(p.observe([row(id, "working")], now: now).isEmpty)
        XCTAssertEqual(p.observe([row(id, "ready")], now: now).map(\.id), [id])
        XCTAssertTrue(p.observe([row(id, "ready")], now: now).isEmpty)
    }
    func testReadySynonymsDoNotRetrigger() {
        for final in ["ready", "done", "completed", "delivered", "READY"] {
            var p = MirsaRequestReadyPolicy(); let id = UUID()
            _ = p.observe([row(id, "queued")], now: now)
            XCTAssertEqual(p.observe([row(id, final)], now: now).count, 1)
            XCTAssertTrue(p.observe([row(id, "delivered")], now: now).isEmpty)
        }
    }
    func testUnknownReadyAfterBaselineIsNotAnOldDeliveryFlood() {
        var p = MirsaRequestReadyPolicy()
        _ = p.observe([row(UUID(), "working")], now: now)
        XCTAssertTrue(p.observe([row(UUID(), "ready")], now: now).isEmpty)
    }
    func testStaleAndFutureReadySuppressed() {
        for age: TimeInterval in [86_401, -301] {
            var p = MirsaRequestReadyPolicy(); let id = UUID()
            _ = p.observe([row(id, "working")], now: now)
            XCTAssertTrue(p.observe([row(id, "ready", age: age)], now: now).isEmpty)
        }
    }
    func testMissingAndInvalidTimestampSuppressed() {
        for stamp: String? in [nil, "garbage"] {
            var p = MirsaRequestReadyPolicy(); let id = UUID()
            _ = p.observe([row(id, "working")], now: now)
            let ready = ForgeChatThread(id: id, title: nil, status: "ready", createdAt: nil, updatedAt: stamp)
            XCTAssertTrue(p.observe([ready], now: now).isEmpty)
        }
    }
    func testEmptyAndPartialReadRetainKnownRequest() {
        var p = MirsaRequestReadyPolicy(); let id = UUID()
        _ = p.observe([], now: now)
        XCTAssertFalse(p.initialized)
        _ = p.observe([row(id, "working")], now: now)
        _ = p.observe([row(UUID(), "open")], now: now)
        _ = p.observe([], now: now)
        XCTAssertEqual(p.observe([row(id, "ready")], now: now).map(\.id), [id])
    }
    func testRestartKeepsDeduplicationAndWorkingBaseline() throws {
        var p = MirsaRequestReadyPolicy(); let id = UUID()
        _ = p.observe([row(id, "working")], now: now)
        var restored = try JSONDecoder().decode(MirsaRequestReadyPolicy.self, from: JSONEncoder().encode(p))
        XCTAssertEqual(restored.observe([row(id, "ready")], now: now).count, 1)
        var again = try JSONDecoder().decode(MirsaRequestReadyPolicy.self, from: JSONEncoder().encode(restored))
        XCTAssertTrue(again.observe([row(id, "ready")], now: now).isEmpty)
    }
    func testFailureAndOrdinaryChatDoNotAlert() {
        var p = MirsaRequestReadyPolicy(); let id = UUID()
        _ = p.observe([row(id, "queued")], now: now)
        for status in ["working", "failed", "open"] {
            XCTAssertTrue(p.observe([row(id, status)], now: now).isEmpty)
        }
    }
    @MainActor
    @MainActor
    func testReadyBadgeClearsOnReadEvenWithoutTimestampChange() {
        let defaults = UserDefaults.standard
        let keys = ["mirsa.chat.seen.v1", "mirsa.chat.readyUnread.v1"]
        let saved = keys.map { defaults.object(forKey: $0) }
        defer {
            for (key, value) in zip(keys, saved) {
                if let value { defaults.set(value, forKey: key) }
                else { defaults.removeObject(forKey: key) }
            }
        }
        for key in keys { defaults.removeObject(forKey: key) }
        let local = ForgeChatLocal(); let id = UUID(); let thread = row(id, "working")
        local.baselineIfNeeded([thread])
        XCTAssertFalse(local.isUnread(thread))
        local.markReadyUnread([id])
        XCTAssertTrue(local.isUnread(thread))
        local.markSeen(id, updatedAt: thread.updatedAt)
        XCTAssertFalse(local.isUnread(thread))
    }
}
