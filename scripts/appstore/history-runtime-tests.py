#!/usr/bin/env python3
"""Compile actual DMAP parser and history reload/client methods with synthetic, network-free collaborators."""
from pathlib import Path
import subprocess, tempfile
r=Path(__file__).resolve().parents[2]
h=(r/'ios-app/AppStore/StorePurchaseHistory.swift').read_text()
u=(r/'ios-app/Apps/AppStoreSection.swift').read_text()
c=(r/'ios-app/AppStore/StoreClient.swift').read_text()
purchase=h[h.index('struct MirsaStorePurchase:'):h.index('/// Read-only own-account')]
parser=h[h.index('struct PurchaseHistoryDiagnostic:'):h.index('enum MirsaStorePurchaseHistory {')]+h[h.index('enum HistorySessionCookies {'):]
redactor=(r/'vendor/ApplePackage/Sources/ApplePackage/Supplement/AuthenticationServiceError.swift').read_text()
redactor='enum AuthenticationServiceError {\n'+redactor[redactor.index('    public static func redact('):]
parser=redactor+parser
reload=u[u.index('    @MainActor private func reload() async {'):u.index('    @MainActor private func download(')].replace('private func','func')
client=c[c.index('    func purchaseHistory() async throws'):c.index('    private func loadAccount()')]
preamble='''import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
struct MirsaStoreApp: Sendable { let id: Int64; let bundleID: String; let name: String; let version: String; let price: Double?; let artworkURL: String }
enum MirsaStoreError: Error { case serviceUnavailable, busy, signedOut, operationCancelled, keychain
 var errorDescription: String? { "named local session error" }
}
struct MirsaStoreAccount: Equatable, Sendable { let email: String; let country: String; let name: String }
struct Account: Sendable { let directoryServicesIdentifier: String }
struct Cookie { let name: String; let value: String; let path: String; let domain: String?; let expiresAt: TimeInterval?; let httpOnly: Bool; let secure: Bool }
struct StorefrontMetadataMissing: Error, LocalizedError { var errorDescription: String? { "Storefront missing" } }
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
    func occupy() { busy = true }
    func release() { busy = false }
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
        let rows = HistoryTags.encode("mlcl", bytes: item(2, 1_700_000_000) + item(2, 1_700_000_001) + item(3, 1_710_000_000, name: "") + item(4, nil))
        let listing = HistoryTags.encode("adbs", bytes: HistoryTags.encode("mstt", integer: 200) + rows)
        let parsed = try HistoryTags.purchases(listing)
        precondition(parsed.map { $0.id } == [3, 2, 4], "sort/dedup/invalid ID")
        precondition(parsed[0].name == "Fallback" && parsed[0].version == "2.3" && parsed[0].bundleID == "example.owned")
        precondition(parsed[1].date?.timeIntervalSince1970 == 1_700_000_000 && parsed[2].date == nil, "Unix date or missing date")
        precondition(try HistoryTags.number("mstt", in: listing) == 200)
        precondition(try HistoryTags.number("mlid", in: listing) == nil)
        precondition(try HistoryTags.integer(Data([0,0,0,1,0,0,0,0])) == 4_294_967_296)
        fails("empty response is not empty history") { _ = try HistoryTags.purchases(Data()) }
        let empty = HistoryTags.encode("adbs", bytes: HistoryTags.encode("mstt", integer: 200) + HistoryTags.encode("mtco", integer: 0) + HistoryTags.encode("mrco", integer: 0) + HistoryTags.encode("mlcl", bytes: Data()))
        precondition(try HistoryTags.purchases(empty).isEmpty)
        fails("no recognized listing") { _ = try HistoryTags.purchases(HistoryTags.encode("mstt", integer: 200)) }
        fails("claimed records missing") { _ = try HistoryTags.purchases(HistoryTags.encode("adbs", bytes: HistoryTags.encode("mstt", integer: 200) + HistoryTags.encode("mtco", integer: 1027) + HistoryTags.encode("mlcl", bytes: Data()))) }
        fails("unrecognized record ID") { _ = try HistoryTags.purchases(HistoryTags.encode("adbs", bytes: HistoryTags.encode("mstt", integer: 200) + HistoryTags.encode("mlcl", bytes: item(0, 1)))) }
        fails("partial listing") { _ = try HistoryTags.purchases(HistoryTags.encode("adbs", bytes: HistoryTags.encode("mstt", integer: 200) + HistoryTags.encode("mtco", integer: 1027) + rows)) }
        fails("wrong returned count") { _ = try HistoryTags.purchases(HistoryTags.encode("adbs", bytes: HistoryTags.encode("mstt", integer: 200) + HistoryTags.encode("mrco", integer: 99) + rows)) }
        let diag = PurchaseHistoryDiagnostic(stage: .items, httpStatus: 200, dmapStatus: 403, failureType: "5020", customerMessage: "Account a@example.invalid token=secretcookie TESTSECRET", detail: "rejected", secrets: ["TESTSECRET"])
        let message = diag.localizedDescription
        precondition(message.contains("HTTP 200") && message.contains("DMAP 403") && message.contains("failureType 5020"))
        precondition(!message.contains("a@example.invalid") && !message.contains("secretcookie") && !message.contains("TESTSECRET"))
        precondition(PurchaseHistoryDiagnostic(stage: .login, failureType: "token-secret", detail: "rejected").failureType == nil)
        let saved = [Cookie(name: "session", value: "owned", path: "/WebObjects/MZFinance.woa", domain: "p25-buy.itunes.apple.com", expiresAt: nil, httpOnly: true, secure: true),
                     Cookie(name: "foreign", value: "no", path: "/", domain: "evil.example", expiresAt: nil, httpOnly: true, secure: true),
                     Cookie(name: "expired", value: "no", path: "/", domain: ".apple.com", expiresAt: 1, httpOnly: true, secure: true)]
        let scoped = HistorySessionCookies.historyCookies(saved)
        precondition(scoped.count == 1 && scoped[0].domain == "pd.itunes.apple.com" && scoped[0].path == "/" && scoped[0].secure)
        let response = HTTPURLResponse(url: URL(string: "https://pd.itunes.apple.com/WebObjects/MZPurchaseDaap.woa/purchase/login")!, statusCode: 200, httpVersion: nil, headerFields: ["Set-Cookie": "history=new-session; Path=/; Secure; HttpOnly"])!
        let merged = HistorySessionCookies.merging(scoped, response: response)
        precondition(merged.count == 2 && merged.contains { $0.name == "history" && $0.value == "new-session" })
        let deletion = HTTPURLResponse(url: response.url!, statusCode: 200, httpVersion: nil, headerFields: ["Set-Cookie": "history=; Path=/; Max-Age=0"])!
        precondition(HistorySessionCookies.merging(merged, response: deletion).count == 1)
        print("PASS honest empty vs missing/malformed/partial schema, Apple diagnostic redaction, commerce cookie isolation and history-session merge/deletion")
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

        let contention = ClientHarness()
        await contention.occupy()
        let delayed = Task { try await contention.purchaseHistory() }
        try await Task.sleep(nanoseconds: 150_000_000)
        let premature = await FetchStub.shared.waiting()
        precondition(!premature, "history must wait before starting fetch")
        await contention.release()
        while !(await FetchStub.shared.waiting()) { await Task.yield() }
        await FetchStub.shared.finish()
        _ = try await delayed.value
        let cancelling = ClientHarness()
        await cancelling.occupy()
        let cancelledWait = Task { try await cancelling.purchaseHistory() }
        try await Task.sleep(nanoseconds: 20_000_000)
        cancelledWait.cancel()
        do { _ = try await cancelledWait.value; fatalError("busy wait ignored cancellation") } catch {}
        let stillReserved = await cancelling.isBusy()
        precondition(stillReserved, "cancelled history must not release someone else's reservation")
        await cancelling.release()
        print("PASS actual busy setup waits for commerce reservation, resumes without reset, preserves foreign reservation on cancellation")
        let client = ClientHarness()
        let fetch = Task { try await client.purchaseHistory() }
        while !(await FetchStub.shared.waiting()) { await Task.yield() }
        let queued = Task { try await client.purchaseHistory() }
        for _ in 0..<20 { await Task.yield() }
        await client.signOut()
        await FetchStub.shared.finish()
        do { _ = try await fetch.value; fatalError("history survived logout") } catch MirsaStoreError.operationCancelled {}
        do { _ = try await queued.value; fatalError("queued history survived logout") } catch MirsaStoreError.operationCancelled {}
        let busy = await client.isBusy(); precondition(!busy, "history must release busy after logout")
        let signedOut = ClientHarness(); await signedOut.signOut()
        do { _ = try await signedOut.purchaseHistory(); fatalError("signed out request accepted") } catch let error as PurchaseHistoryDiagnostic { precondition(error.localizedDescription.contains("missing account session")) }
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
