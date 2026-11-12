#!/usr/bin/env python3
"""Execute actual history fetch with URLProtocol fixtures. Never contacts Apple."""
from pathlib import Path
import subprocess, tempfile
r = Path(__file__).resolve().parents[2]
source = (r/'ios-app/AppStore/StorePurchaseHistory.swift').read_text().replace('@preconcurrency import ApplePackage', '')
# Only dependency-inject the private URLSession configuration, not request/parser logic.
source = source.replace('config.httpShouldSetCookies = false', 'config.protocolClasses = [FixtureProtocol.self]\n        config.httpShouldSetCookies = false')
redactor = (r/'vendor/ApplePackage/Sources/ApplePackage/Supplement/AuthenticationServiceError.swift').read_text()
redactor = 'enum AuthenticationServiceError {\n' + redactor[redactor.index('    public static func redact('):]
stubs = r'''
import Foundation
struct MirsaStoreApp { let id: Int64; let bundleID: String; let name: String; let version: String; let price: Double?; let artworkURL: String }
enum MirsaStoreError: Error { case serviceUnavailable }
enum Configuration { static let deviceIdentifier = "AABBCCDDEEFF" }
struct Account {
    let email = "private@example.invalid", password = "private-password", appleId = "private-id"
    let firstName = "PrivateFirst", lastName = "PrivateLast", passwordToken = "private-token"
    let directoryServicesIdentifier = "12345678901"
    var cookie = [Cookie(name: "commerce", value: "private-cookie", path: "/WebObjects/MZFinance.woa", domain: "p25-buy.itunes.apple.com", expiresAt: nil, httpOnly: true, secure: true)]
    func commerceStoreFront() throws -> String { "143480-1,29" }
}
struct Cookie {
    let name: String; let value: String; let path: String; let domain: String?
    let expiresAt: TimeInterval?; let httpOnly: Bool; let secure: Bool
}
extension Array where Element == Cookie {
    func buildCookieHeader(_ url: URL) -> [(String, String)] {
        let values = filter { $0.domain == url.host && url.path.hasPrefix($0.path) }.map { "\($0.name)=\($0.value)" }
        return values.isEmpty ? [] : [("Cookie", values.joined(separator: "; "))]
    }
}
struct SAPSigner {
    static func connect() async throws -> SAPSigner {
        if FixtureProtocol.mode == "setup" { throw URLError(.cannotConnectToHost) }
        return SAPSigner()
    }
    func sign(_ data: Data) async throws -> Data {
        if FixtureProtocol.mode == "signing" { throw URLError(.cannotDecodeContentData) }
        return data
    }
}
final class FixtureProtocol: URLProtocol {
    static var mode = "success"
    static var requests: [URLRequest] = []
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requests.append(request)
        guard request.url?.host == "pd.itunes.apple.com" else { fatalError("unexpected destination") }
        let path = request.url!.path
        if Self.mode == "timeout" { client?.urlProtocol(self, didFailWithError: URLError(.timedOut)); return }
        var bytes = Data()
        var headers: [String: String] = [:]
        if Self.mode == "plist" {
            bytes = try! PropertyListSerialization.data(fromPropertyList: ["failureType":"5020", "customerMessage":"private@example.invalid private-token private-cookie private-password"], format: .xml, options: 0)
        } else if path.hasSuffix("/login") {
            bytes = HistoryTags.encode("mlog", bytes: HistoryTags.encode("mstt", integer: 200) + HistoryTags.encode("mlid", integer: 42))
            headers["Set-Cookie"] = "history=private-session; Path=/; Secure; HttpOnly"
        } else if path.hasSuffix("/update") {
            bytes = HistoryTags.encode("mupd", bytes: HistoryTags.encode("mstt", integer: 200) + HistoryTags.encode("musr", integer: 7))
        } else {
            precondition(path.hasSuffix("/databases/7/items"))
            if Self.mode == "malformed" { bytes = HistoryTags.encode("mstt", integer: 200) }
            else {
                let row = HistoryTags.encode("mlit", bytes: HistoryTags.encode("aeSI", integer: 1234) + HistoryTags.encode("aeBI", bytes: Data("example.owned".utf8)) + HistoryTags.encode("aeLN", bytes: Data("Owned".utf8)))
                let count: UInt32 = Self.mode == "empty" ? 0 : 1
                bytes = HistoryTags.encode("adbs", bytes: HistoryTags.encode("mstt", integer: 200) + HistoryTags.encode("mtco", integer: count) + HistoryTags.encode("mrco", integer: count) + HistoryTags.encode("mlcl", bytes: count == 0 ? Data() : row))
            }
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: bytes)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
@main struct Tests {
    static func body(_ r: URLRequest) -> Data {
        if let data = r.httpBody { return data }
        guard let stream = r.httpBodyStream else { return Data() }
        stream.open(); defer { stream.close() }
        var result = Data(); var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let n = stream.read(&buffer, maxLength: buffer.count)
            if n <= 0 { break }; result.append(contentsOf: buffer.prefix(n))
        }
        return result
    }
    static func main() async throws {
        let account = Account()
        let result = try await MirsaStorePurchaseHistory.fetch(owner: account)
        precondition(result.count == 1 && result[0].id == 1234)
        precondition(FixtureProtocol.requests.count == 3)
        for (i, r) in FixtureProtocol.requests.enumerated() {
            precondition(r.httpMethod == "POST")
            precondition(r.value(forHTTPHeaderField: "X-Apple-Store-Front") == "143480-1,29")
            precondition(r.value(forHTTPHeaderField: "X-Token") == account.passwordToken)
            precondition(r.value(forHTTPHeaderField: "X-Dsid") == account.directoryServicesIdentifier)
            let cookie = r.value(forHTTPHeaderField: "Cookie") ?? ""
            precondition(cookie.contains("commerce=private-cookie"), "commerce cookie lost at DAAP boundary")
            if i > 0 {
                precondition(cookie.contains("history=private-session"), "DAAP login cookie lost")
                let bytes = body(r)
                precondition(r.value(forHTTPHeaderField: "X-Apple-ActionSignature") == bytes.base64EncodedString(), "signed bytes differ")
            }
        }
        let update = String(decoding: body(FixtureProtocol.requests[1]), as: UTF8.self)
        precondition(update == "session-id=42&revision-number=(null)&query=('com.apple.itunes.extended\\-media\\-kind:131072')")
        let items = body(FixtureProtocol.requests[2])
        precondition(String(decoding: items.prefix(4), as: UTF8.self) == "adsr")
        precondition(try HistoryTags.number("mlid", in: items) == 42)
        precondition(try HistoryTags.number("musr", in: items) == 7)
        FixtureProtocol.mode = "empty"
        precondition(try await MirsaStorePurchaseHistory.fetch(owner: account).isEmpty)
        for mode in ["plist", "malformed", "timeout", "setup", "signing"] {
            FixtureProtocol.mode = mode
            do { _ = try await MirsaStorePurchaseHistory.fetch(owner: account); fatalError("accepted \(mode)") }
            catch let diagnostic as PurchaseHistoryDiagnostic {
                let text = diagnostic.localizedDescription
                for secret in [account.email, account.password, account.passwordToken, "private-cookie"] { precondition(!text.contains(secret)) }
                if mode == "plist" { precondition(text.contains("failureType 5020") && text.contains("HTTP 200")) }
                if mode == "timeout" { precondition(text.contains("-1001")) }
                if mode == "setup" { precondition(text.contains("setup") && text.contains("-1004")) }
                if mode == "signing" { precondition(text.contains("update") && text.contains("-1016")) }
            }
        }
        let before = FixtureProtocol.requests.count
        let task = Task { () throws -> [MirsaStorePurchase] in
            // Give the parent a deterministic opportunity to cancel before fetch.
            try await Task.sleep(nanoseconds: 100_000_000)
            return try await MirsaStorePurchaseHistory.fetch(owner: account)
        }
        task.cancel()
        do { _ = try await task.value; fatalError("cancellation ignored") } catch is CancellationError {}
        precondition(FixtureProtocol.requests.count == before)
        print("PASS actual history fetch: exact signed bytes, full TR storefront, scoped commerce and session cookies, real empty, malformed schema, sanitized plist error, timeout and cancellation. No live network.")
    }
}
'''
# Evaluate throwing expressions outside precondition's nonthrowing autoclosure.
import re
stubs = re.sub(r'        precondition\(try (await )?([^\n]+)\)', lambda m: '        let check'+str(m.start())+' = try '+(m[1] or '')+m[2]+'\n        precondition(check'+str(m.start())+')', stubs)
with tempfile.TemporaryDirectory(prefix='history-protocol-tests-') as d:
    p=Path(d)/'main.swift'; p.write_text(source+redactor+stubs)
    subprocess.run(['swiftc','-swift-version','5','-parse-as-library',str(p),'-o',str(Path(d)/'tests')],check=True)
    subprocess.run([str(Path(d)/'tests')],check=True,timeout=45)
