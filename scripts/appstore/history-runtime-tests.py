#!/usr/bin/env python3
"""Compile actual DMAP parser and history reload/client methods with synthetic, network-free collaborators."""
from pathlib import Path
import subprocess, tempfile
r=Path(__file__).resolve().parents[2]
h=(r/'ios-app/AppStore/StorePurchaseHistory.swift').read_text()
u=(r/'ios-app/Apps/AppStoreSection.swift').read_text()
c=(r/'ios-app/AppStore/StoreClient.swift').read_text()
purchase=h[h.index('struct MirsaStorePurchase:'):h.index('/// Read-only own-account')]
parser=h[h.index('enum HistoryTags {'):]
reload=u[u.index('    @MainActor private func reload() async {'):u.index('    @MainActor private func download(')].replace('private func','func')
client=c[c.index('    func purchaseHistory() async throws'):c.index('    private func loadAccount()')]
preamble='''import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
struct MirsaStoreApp: Sendable { let id: Int64; let bundleID: String; let name: String; let version: String; let price: Double?; let artworkURL: String }
enum MirsaStoreError: Error { case serviceUnavailable, busy, signedOut, operationCancelled }
struct MirsaStoreAccount: Equatable, Sendable { let email: String; let country: String; let name: String }
struct Account: Sendable { let directoryServicesIdentifier: String }
func tr(_ en: String, _ ar: String, ckb: String, kmr: String) -> String { en }
'''
mocks='''
@MainActor final class MirsaStoreOnDeviceClient {
    static let shared = MirsaStoreOnDeviceClient()
    var requests = 0
    var pending: CheckedContinuation<[MirsaStorePurchase], Error>?
    func purchaseHistory() async throws -> [MirsaStorePurchase] {
        precondition(pending == nil, "history requests must not overlap")
        requests += 1
        return try await withCheckedThrowingContinuation { pending = $0 }
    }
    func finish() { let p = pending; pending = nil; p?.resume(returning: []) }
}
@MainActor final class Model {
    var account: MirsaStoreAccount? = .init(email: "a@example.invalid", country: "tr", name: "A")
    var sessionRevision = 0
}
@MainActor final class ReloadHarness {
    var model = Model()
    var isActive = true
    var reloadID = UUID()
    var reloadTask: Task<Void, Never>?
    var loading = false
    var error: String?
    var purchases: [MirsaStorePurchase] = []
    var artwork: [Int64: String] = [:]
'''
client_mocks='''
actor FetchStub {
    static let shared = FetchStub()
    var pending: CheckedContinuation<[MirsaStorePurchase], Error>?
    func fetch() async throws -> [MirsaStorePurchase] {
        precondition(pending == nil)
        return try await withCheckedThrowingContinuation { pending = $0 }
    }
    func waiting() -> Bool { pending != nil }
    func finish() { let p = pending; pending = nil; p?.resume(returning: []) }
}
enum MirsaStorePurchaseHistory {
    static func fetch(owner: Account) async throws -> [MirsaStorePurchase] { try await FetchStub.shared.fetch() }
}
actor ClientHarness {
    var busy = false
    var generation: UInt64 = 0
    var owner: Account? = Account(directoryServicesIdentifier: "synthetic")
    func begin() throws -> UInt64 { guard !busy else { throw MirsaStoreError.busy }; busy = true; return generation }
    func requiredAccount() throws -> Account { guard let owner else { throw MirsaStoreError.signedOut }; return owner }
    func check(_ run: UInt64) throws {
        guard run == generation, !Task.isCancelled else { throw MirsaStoreError.operationCancelled }
    }
    func signOut() { generation += 1; owner = nil }
    func isBusy() -> Bool { busy }
'''
tests=r'''
@main struct Tests {
    static func fails(_ label: String, _ op: () throws -> Void) {
        do { try op(); fatalError("accepted malformed input: \(label)") } catch {}
    }
    static func item(_ id: UInt32, _ date: UInt32?, name: String = "Owned app", fallback: String = "Fallback") -> Data {
        var body = HistoryTags.encode("aeSI", integer: id)
        body += HistoryTags.encode("aeBI", bytes: Data("example.owned".utf8))
        body += HistoryTags.encode("aeLN", bytes: Data(name.utf8))
        body += HistoryTags.encode("minm", bytes: Data(fallback.utf8))
        body += HistoryTags.encode("aePd", bytes: Data("2.3".utf8))
        if let date { body += HistoryTags.encode("asdp", integer: date) }
        return HistoryTags.encode("mlit", bytes: body)
    }
    @MainActor static func main() async throws {
        let rows = HistoryTags.encode("mlcl", bytes: item(2, 1_700_000_000) + item(2, 1_700_000_001) + item(3, 1_710_000_000, name: "") + item(4, nil) + item(0, 1))
        let listing = HistoryTags.encode("adbs", bytes: HistoryTags.encode("mstt", integer: 200) + rows)
        let parsed = try HistoryTags.purchases(listing)
        precondition(parsed.map { $0.id } == [3, 2, 4], "sort/dedup/invalid ID")
        precondition(parsed[0].name == "Fallback" && parsed[0].version == "2.3" && parsed[0].bundleID == "example.owned")
        precondition(parsed[1].date?.timeIntervalSince1970 == 1_700_000_000 && parsed[2].date == nil, "Unix date or missing date")
        precondition(try HistoryTags.number("mstt", in: listing) == 200)
        precondition(try HistoryTags.number("mlid", in: listing) == nil)
        precondition(try HistoryTags.integer(Data([0,0,0,1,0,0,0,0])) == 4_294_967_296)
        precondition(try HistoryTags.purchases(Data()).isEmpty)
        for count in 1..<listing.count { fails("truncation \(count)") { _ = try HistoryTags.purchases(Data(listing.prefix(count))) } }
        fails("oversized length") { _ = try HistoryTags.purchases(Data("mlit".utf8) + Data([255,255,255,255])) }
        fails("invalid scalar size") { _ = try HistoryTags.number("mstt", in: HistoryTags.encode("mstt", bytes: Data([0,0,1]))) }
        fails("UInt32 overflow") { _ = try HistoryTags.number("mstt", in: HistoryTags.encode("mstt", bytes: Data(repeating: 255, count: 8))) }
        fails("invalid purchase date") { _ = try HistoryTags.purchases(HistoryTags.encode("mlit", bytes: HistoryTags.encode("asdp", bytes: Data([1,2,3])))) }
        var deep = HistoryTags.encode("mstt", integer: 200)
        for _ in 0..<17 { deep = HistoryTags.encode("mlcl", bytes: deep) }
        fails("depth limit") { _ = try HistoryTags.purchases(deep) }
        print("PASS actual DMAP parser: truncation, invalid size/scalars, overflow/depth, Unix dates, missing date, name fallback, sorting and dedup")

        let view = ReloadHarness()
        view.isActive = false
        await view.reload()
        precondition(MirsaStoreOnDeviceClient.shared.requests == 0, "hidden history must not fetch")
        view.isActive = true
        let first = Task { await view.reload() }
        while MirsaStoreOnDeviceClient.shared.requests < 1 { await Task.yield() }
        view.model.account = .init(email: "b@example.invalid", country: "us", name: "B")
        view.model.sessionRevision += 1
        let second = Task { await view.reload() }
        for _ in 0..<30 { await Task.yield() }
        precondition(MirsaStoreOnDeviceClient.shared.requests == 1, "account reload must await cancelled predecessor")
        MirsaStoreOnDeviceClient.shared.finish()
        while MirsaStoreOnDeviceClient.shared.requests < 2 { await Task.yield() }
        precondition(view.loading && view.error == nil && view.purchases.isEmpty, "stale reload must not clobber new load")
        MirsaStoreOnDeviceClient.shared.finish()
        await first.value; await second.value
        precondition(!view.loading && view.error == nil)
        let third = Task { await view.reload() }
        while MirsaStoreOnDeviceClient.shared.requests < 3 { await Task.yield() }
        third.cancel()
        MirsaStoreOnDeviceClient.shared.finish()
        await third.value
        precondition(!view.loading && view.error == nil, "cancellation must release loading")
        print("PASS actual reload methods: hidden guard, serialized account switch, stale-result/defer isolation and cancellation")

        let client = ClientHarness()
        let fetch = Task { try await client.purchaseHistory() }
        while !(await FetchStub.shared.waiting()) { await Task.yield() }
        do { _ = try await client.purchaseHistory(); fatalError("history failed to reserve busy") } catch MirsaStoreError.busy {}
        await client.signOut()
        await FetchStub.shared.finish()
        do { _ = try await fetch.value; fatalError("history survived logout") } catch MirsaStoreError.operationCancelled {}
        let busy = await client.isBusy(); precondition(!busy, "history must release busy after logout")
        let signedOut = ClientHarness(); await signedOut.signOut()
        do { _ = try await signedOut.purchaseHistory(); fatalError("signed out request accepted") } catch MirsaStoreError.signedOut {}
        let signedOutBusy = await signedOut.isBusy(); precondition(!signedOutBusy)
        print("PASS actual purchaseHistory method: exclusive reservation, logout invalidation, release on success/error")
    }
}
'''
# Swift throwing expressions are evaluated outside precondition's nonthrowing autoclosure.
import re
tests=re.sub(r'        precondition\(try ([^\n]+)\)',lambda m:'        let check'+str(m.start())+' = try '+m[1]+'\n        precondition(check'+str(m.start())+')',tests)
with tempfile.TemporaryDirectory(prefix='mirsa-history-tests-') as d:
    p=Path(d)/'history-tests.swift'
    p.write_text(preamble+purchase+parser+mocks+reload+'\n}\n'+client_mocks+client+'\n}\n'+tests)
    subprocess.run(['swiftc','-swift-version','5','-parse-as-library',str(p),'-o',str(Path(d)/'history-tests')],check=True)
    subprocess.run([str(Path(d)/'history-tests')],check=True,timeout=45)
