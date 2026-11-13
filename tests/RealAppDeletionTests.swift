import Foundation
import XCTest
#if canImport(MirsaStoreKit)
@testable import MirsaStoreKit
#else
@testable import Mirsa
#endif

@MainActor
final class RealAppDeletionTests: XCTestCase {
    enum FixtureError: Error { case uninstallFailed }

    // The commit closure stands for the exact local record/files transaction.
    // Every failure checks an actual persisted fixture as well as list membership.
    private func failureCase(network: Bool = true, bundleID: String? = "app.husk",
                             outcome: Int = 0, expectedCalls: Int = 1) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let db = root.appendingPathComponent("apps.json")
        let ipa = root.appendingPathComponent("saved.ipa")
        let original = Data("app.husk,unrelated.app".utf8)
        try original.write(to: db)
        try Data("preserved IPA".utf8).write(to: ipa)
        var list = ["app.husk", "unrelated.app"]
        var calls = 0
        var committed = false
        do {
            try await RealAppDeletion.perform(networkReady: network, bundleID: bundleID,
                uninstall: { _ in
                    calls += 1
                    if outcome == 1 { throw FixtureError.uninstallFailed }
                    if outcome == 2 { throw CancellationError() }
                    return false
                },
                commit: {
                    committed = true
                    list.removeAll { $0 == "app.husk" }
                    try? Data(list.joined(separator: ",").utf8).write(to: db)
                    try? FileManager.default.removeItem(at: ipa)
                })
            XCTFail("Unconfirmed uninstall must throw")
        } catch {}
        XCTAssertFalse(committed)
        XCTAssertEqual(calls, expectedCalls)
        XCTAssertEqual(list, ["app.husk", "unrelated.app"])
        XCTAssertEqual(try Data(contentsOf: db), original)
        XCTAssertTrue(FileManager.default.fileExists(atPath: ipa.path))
    }

    func testVPNOffKeepsListDatabaseAndFilesWithoutCallingUninstall() async throws {
        try await failureCase(network: false, expectedCalls: 0)
    }
    func testInstallationProxyFailureKeepsListDatabaseAndFiles() async throws {
        try await failureCase(outcome: 1)
    }
    func testUnconfirmedResultKeepsListDatabaseAndFiles() async throws {
        try await failureCase()
    }
    func testMissingInstalledBundleKeepsListDatabaseAndFiles() async throws {
        try await failureCase(bundleID: nil, expectedCalls: 0)
    }
    func testEmptyInstalledBundleKeepsListDatabaseAndFiles() async throws {
        try await failureCase(bundleID: "  ", expectedCalls: 0)
    }
    func testCancelledUninstallKeepsListDatabaseAndFiles() async throws {
        try await failureCase(outcome: 2)
    }
    func testConfirmedVPNOnUninstallCommitsOnlyAfterDeviceCompletion() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let db = root.appendingPathComponent("apps.json")
        try Data("app.husk,unrelated.app".utf8).write(to: db)
        var list = ["app.husk", "unrelated.app"]
        var order: [String] = []
        try await RealAppDeletion.perform(networkReady: true, bundleID: "app.husk",
            uninstall: { bundleID in
                XCTAssertEqual(bundleID, "app.husk")
                XCTAssertEqual(list.count, 2)
                XCTAssertEqual(try Data(contentsOf: db), Data("app.husk,unrelated.app".utf8))
                order.append("confirmed")
                return true
            },
            commit: {
                order.append("commit")
                list.removeAll { $0 == "app.husk" }
                try? Data(list.joined(separator: ",").utf8).write(to: db)
            })
        XCTAssertEqual(order, ["confirmed", "commit"])
        XCTAssertEqual(list, ["unrelated.app"])
        XCTAssertEqual(try Data(contentsOf: db), Data("unrelated.app".utf8))
    }
}
