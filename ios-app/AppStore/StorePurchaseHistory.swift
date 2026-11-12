import Foundation
@preconcurrency import ApplePackage

struct MirsaStorePurchase: Identifiable, Sendable {
    let id: Int64
    let bundleID: String
    let name: String
    let version: String
    let date: Date?
    var app: MirsaStoreApp {
        MirsaStoreApp(id: id, bundleID: bundleID, name: name, version: version,
                      price: nil, artworkURL: "")
    }
}

/// Read-only own-account DAAP history. Does not acquire licenses or change login state.
struct PurchaseHistoryDiagnostic: Error, LocalizedError, Sendable {
    enum Stage: String, Sendable { case setup, login, update, items }
    let stage: Stage
    let httpStatus: Int?
    let dmapStatus: UInt32?
    let failureType: String?
    let customerMessage: String?
    let detail: String

    init(stage: Stage, httpStatus: Int? = nil, dmapStatus: UInt32? = nil,
         failureType: Any? = nil, customerMessage: String? = nil,
         detail: String, secrets: [String] = []) {
        self.stage = stage; self.httpStatus = httpStatus; self.dmapStatus = dmapStatus
        let raw = (failureType as? String) ?? (failureType as? NSNumber)?.stringValue
        self.failureType = raw.flatMap { $0.range(of: "^-?[0-9]{1,8}$", options: .regularExpression) != nil ? $0 : nil }
        self.customerMessage = AuthenticationServiceError.redact(customerMessage, secrets: secrets)
        self.detail = detail
    }
    var errorDescription: String? {
        var fields = ["Apple history", stage.rawValue]
        if let httpStatus { fields.append("HTTP \(httpStatus)") }
        if let dmapStatus { fields.append("DMAP \(dmapStatus)") }
        if let failureType { fields.append("failureType \(failureType)") }
        fields.append(detail)
        if let customerMessage { fields.append(customerMessage) }
        return fields.joined(separator: " · ")
    }
}

enum MirsaStorePurchaseHistory {
    static func fetch(owner: Account) async throws -> [MirsaStorePurchase] {
        try Task.checkCancellation()
        // Validate the exact shared session before attempting SAP/network work.
        // Field names only, never account values or cookie contents.
        guard !owner.directoryServicesIdentifier.isEmpty else {
            throw PurchaseHistoryDiagnostic(stage: .setup, detail: "missing field dsid")
        }
        guard !owner.passwordToken.isEmpty else {
            throw PurchaseHistoryDiagnostic(stage: .setup, detail: "missing field passwordToken")
        }
        let guid = Configuration.deviceIdentifier
        guard guid.utf8.count == 12, guid.utf8.allSatisfy({ (48...57).contains($0) || (65...70).contains($0) }) else {
            throw PurchaseHistoryDiagnostic(stage: .setup, detail: "invalid or missing field guid")
        }
        let storeFront: String
        do { storeFront = try owner.commerceStoreFront() }
        catch {
            throw PurchaseHistoryDiagnostic(stage: .setup, detail: "invalid or missing field fullStorefront; sign in again from Account tab")
        }
        var cookies = HistorySessionCookies.historyCookies(owner.cookie)
        guard !cookies.isEmpty else {
            throw PurchaseHistoryDiagnostic(stage: .setup, detail: "missing field Apple session cookies; sign in again from Account tab")
        }
        let signer: SAPSigner
        do { signer = try await SAPSigner.connect() }
        catch {
            try Task.checkCancellation()
            throw PurchaseHistoryDiagnostic(stage: .setup, detail: "signer setup error \((error as NSError).code)")
        }
        let secrets = [owner.email, owner.password, owner.appleId, owner.firstName, owner.lastName,
                       owner.passwordToken, owner.directoryServicesIdentifier, Configuration.deviceIdentifier]
                       + owner.cookie.map(\.value)
        // Keep the DAAP session cookies returned by login/update, scoped to their origin.
        // Do not change or persist the commerce/login engine's cookie state.
        try Task.checkCancellation()
        let root = "https://pd.itunes.apple.com/WebObjects/MZPurchaseDaap.woa/purchase"
        let query = "('com.apple.itunes.extended\\-media\\-kind:131072')"
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false
        config.urlCache = nil
        config.timeoutIntervalForResource = 60
        let session = URLSession(configuration: config, delegate: HistoryRedirectPolicy(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        func request(_ path: String, stage: PurchaseHistoryDiagnostic.Stage, body: Data?, binary: Bool = false) async throws -> Data {
            try Task.checkCancellation()
            let url = URL(string: root + path)!
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.httpBody = body
            req.timeoutInterval = 45
            let now = Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970))
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
            let headers = [
                "Content-Type": binary ? "application/x-dmap-tagged" : "application/x-www-form-urlencoded",
                "User-Agent": "Configurator/2.21 (Macintosh; OS X 15.2; 24C5089c) AppleWebKit/0620.1.16.11.6",
                "X-Dsid": owner.directoryServicesIdentifier,
                "iCloud-DSID": owner.directoryServicesIdentifier,
                "X-Apple-Store-Front": storeFront,
                "X-Token": owner.passwordToken,
                "Accept": "*/*", "Accept-Language": "en-us",
                "Client-Cloud-DAAP-Request-Reason": "5",
                "Client-Cloud-Purchase-Daap-Version": "1.1/Configurator-2.0",
                "Client-DAAP-Version": "3.12",
                "Date": formatter.string(from: now),
                "X-Apple-I-Client-Time": ISO8601DateFormatter().string(from: now),
                "X-Apple-I-Locale": "en_US", "X-Apple-I-TimeZone": "Local",
                "X-Apple-TZ": String(TimeZone.current.secondsFromGMT(for: now) / 60),
                "X-Guid": Configuration.deviceIdentifier
            ]
            for (key, value) in headers { req.setValue(value, forHTTPHeaderField: key) }
            for (key, value) in cookies.buildCookieHeader(url) { req.setValue(value, forHTTPHeaderField: key) }
            if let body {
                do { req.setValue(try await signer.sign(body).base64EncodedString(), forHTTPHeaderField: "X-Apple-ActionSignature") }
                catch {
                    try Task.checkCancellation()
                    throw PurchaseHistoryDiagnostic(stage: stage, detail: "request signing error \((error as NSError).code)")
                }
            }
            let data: Data
            let response: URLResponse
            do { (data, response) = try await session.data(for: req) }
            catch {
                try Task.checkCancellation()
                let code = (error as NSError).code
                throw PurchaseHistoryDiagnostic(stage: stage, detail: "network \(code)")
            }
            try Task.checkCancellation()
            let status = (response as? HTTPURLResponse)?.statusCode
            guard data.count <= 32 * 1024 * 1024 else {
                throw PurchaseHistoryDiagnostic(stage: stage, httpStatus: status, detail: "response too large")
            }
            if let http = response as? HTTPURLResponse {
                cookies = HistorySessionCookies.merging(cookies, response: http)
            }
            // Apple can return a plist failure (also with HTTP 200), not DMAP.
            if let dict = (try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)) as? [String: Any] {
                throw PurchaseHistoryDiagnostic(stage: stage, httpStatus: status,
                    failureType: dict["failureType"], customerMessage: dict["customerMessage"] as? String,
                    detail: "Apple plist response", secrets: secrets + cookies.map(\.value))
            }
            guard status == 200 else {
                throw PurchaseHistoryDiagnostic(stage: stage, httpStatus: status, detail: "request rejected")
            }
            let dmapStatus: UInt32?
            do { dmapStatus = try HistoryTags.number("mstt", in: data) }
            catch { throw PurchaseHistoryDiagnostic(stage: stage, httpStatus: status, detail: "invalid DMAP framing") }
            guard dmapStatus == 200 else {
                throw PurchaseHistoryDiagnostic(stage: stage, httpStatus: status, dmapStatus: dmapStatus,
                                               detail: "missing or failed DMAP status")
            }
            return data
        }
        let login = try await request("/login", stage: .login, body: nil)
        guard let sid = try HistoryTags.number("mlid", in: login) else { throw PurchaseHistoryDiagnostic(stage: .login, httpStatus: 200, dmapStatus: 200, detail: "missing session ID") }
        let update = try await request("/update", stage: .update, body: Data("session-id=\(sid)&revision-number=(null)&query=\(query)".utf8))
        guard let revision = try HistoryTags.number("musr", in: update) else { throw PurchaseHistoryDiagnostic(stage: .update, httpStatus: 200, dmapStatus: 200, detail: "missing revision") }
        var content = HistoryTags.encode("mstc", integer: UInt32(Date().timeIntervalSince1970))
        content += HistoryTags.encode("mlid", integer: sid)
        content += HistoryTags.encode("mikd", bytes: Data([2]))
        content += HistoryTags.encode("musr", integer: revision)
        content += HistoryTags.encode("mder", integer: 0)
        content += HistoryTags.encode("mque", bytes: Data(query.utf8))
        content += HistoryTags.encode("aetl", bytes: Data())
        let listing = try await request("/databases/\(revision)/items", stage: .items, body: HistoryTags.encode("adsr", bytes: content), binary: true)
        return try HistoryTags.purchases(listing)
    }
}

/// Never forward account tokens/cookies automatically on a redirect.
private final class HistoryRedirectPolicy: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

enum HistorySessionCookies {
    // DAAP is hosted separately from buy/auth. It expects the account cookie
    // header, not just cookies whose original commerce path happens to match.
    // Re-scope only known Apple commerce cookies, only in this private session.
    static func historyCookies(_ saved: [Cookie]) -> [Cookie] {
        saved.compactMap { cookie in
            let domain = (cookie.domain ?? "itunes.apple.com").lowercased()
                .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            guard domain == "apple.com" || domain == "itunes.apple.com" ||
                  domain == "auth.itunes.apple.com" || domain == "buy.itunes.apple.com" || domain == "pd.itunes.apple.com" ||
                  domain.range(of: "^p[0-9]+-buy\\.itunes\\.apple\\.com$", options: .regularExpression) != nil,
                  !cookie.name.isEmpty, !cookie.value.isEmpty,
                  cookie.expiresAt.map({ $0 > Date().timeIntervalSince1970 }) ?? true else { return nil }
            return Cookie(name: cookie.name, value: cookie.value, path: "/", domain: "pd.itunes.apple.com",
                          expiresAt: cookie.expiresAt, httpOnly: cookie.httpOnly, secure: true)
        }
    }
    static func merging(_ saved: [Cookie], response: HTTPURLResponse) -> [Cookie] {
        guard let url = response.url, let host = url.host else { return saved }
        var headers: [String: String] = [:]
        for (key, value) in response.allHeaderFields {
            if let key = key as? String { headers[key] = String(describing: value) }
        }
        var result = saved
        for cookie in HTTPCookie.cookies(withResponseHeaderFields: headers, for: url) {
            let domain = cookie.domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
            guard !domain.isEmpty, host == domain || host.hasSuffix("." + domain) else { continue }
            // No broadening saved path/domain scope. Response may replace only its own key.
            result.removeAll { $0.name == cookie.name &&
                ($0.domain ?? host).lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".")) == domain && $0.path == cookie.path }
            guard !cookie.value.isEmpty, cookie.expiresDate.map({ $0 > Date() }) ?? true else { continue }
            result.append(Cookie(name: cookie.name, value: cookie.value, path: cookie.path,
                                 domain: cookie.domain, expiresAt: cookie.expiresDate?.timeIntervalSince1970,
                                 httpOnly: cookie.isHTTPOnly, secure: cookie.isSecure))
        }
        return result
    }
}

/// DMAP is a four-byte tag, big-endian uint32 size, then bytes.
enum HistoryTags {
    private static let groups: Set<String> = ["adbs","adsr","aply","avdb","mbcl","mccr","mcty","mdcl","mlcl","mlit","mlog","msrv","mupd"]
    static func encode(_ tag: String, integer: UInt32) -> Data {
        var n = integer.bigEndian
        return withUnsafeBytes(of: &n) { encode(tag, bytes: Data($0)) }
    }
    static func encode(_ tag: String, bytes: Data) -> Data {
        var output = Data(tag.utf8)
        var n = UInt32(bytes.count).bigEndian
        withUnsafeBytes(of: &n) { output.append(contentsOf: $0) }
        output.append(bytes)
        return output
    }
    static func scan(_ data: Data, depth: Int = 0, visit: (String, Data) throws -> Void) throws {
        guard depth < 16 else { throw MirsaStoreError.serviceUnavailable }
        var cursor = data.startIndex
        while cursor < data.endIndex {
            guard data.endIndex - cursor >= 8 else { throw MirsaStoreError.serviceUnavailable }
            let labelBytes = data[cursor..<cursor+4]
            guard labelBytes.allSatisfy({ (32...126).contains($0) }) else { throw MirsaStoreError.serviceUnavailable }
            let label = String(decoding: labelBytes, as: UTF8.self)
            let count = data[cursor+4..<cursor+8].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
            cursor += 8
            guard UInt64(count) <= UInt64(data.endIndex - cursor) else { throw MirsaStoreError.serviceUnavailable }
            let chunk = data[cursor..<cursor+Int(count)]
            try visit(label, chunk)
            if groups.contains(label) { try scan(chunk, depth: depth+1, visit: visit) }
            cursor += Int(count)
        }
    }
    static func integer(_ data: Data) throws -> UInt64 {
        guard [1,2,4,8].contains(data.count) else { throw MirsaStoreError.serviceUnavailable }
        return data.reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
    }
    static func number(_ tag: String, in data: Data) throws -> UInt32? {
        var result: UInt32?
        try scan(data) { label, bytes in
            if label == tag, result == nil {
                let n = try integer(bytes)
                guard n <= UInt32.max else { throw MirsaStoreError.serviceUnavailable }
                result = UInt32(n)
            }
        }
        return result
    }
    static func purchases(_ data: Data) throws -> [MirsaStorePurchase] {
        var result: [MirsaStorePurchase] = []
        var records = 0
        var validRecords = 0
        var hasListing = false
        var returned: UInt32?
        var total: UInt32?
        var seen = Set<Int64>()
        try scan(data) { label, chunk in
            if label == "mlcl" { hasListing = true }
            if label == "mrco" { returned = try number("mrco", in: encode("mrco", bytes: chunk)) }
            if label == "mtco" { total = try number("mtco", in: encode("mtco", bytes: chunk)) }
            guard label == "mlit" else { return }
            records += 1
            var id: Int64 = 0
            var bundle = "", title = "", fallback = "", version = ""
            var date: Date?
            try scan(chunk) { field, value in
                switch field {
                case "aeSI": let n = try integer(value); if n <= UInt64(Int64.max) { id = Int64(n) }
                case "aeBI": bundle = String(decoding: value, as: UTF8.self)
                case "aeLN": title = String(decoding: value, as: UTF8.self)
                case "minm": fallback = String(decoding: value, as: UTF8.self)
                case "aePd": version = String(decoding: value, as: UTF8.self)
                case "asdp": date = Date(timeIntervalSince1970: Double(try integer(value)))
                default: break
                }
            }
            if id > 0 { validRecords += 1 }
            if id > 0, seen.insert(id).inserted {
                result.append(.init(id: id, bundleID: bundle, name: title.isEmpty ? fallback : title, version: version, date: date))
            }
        }
        // A 200 status alone does not prove an empty history. Never hide unknown
        // schemas, rejected records, or incomplete listings behind a successful zero.
        let status = try number("mstt", in: data)
        let detail = "records \(records), IDs \(validRecords), returned \(returned.map(String.init) ?? "missing"), total \(total.map(String.init) ?? "missing")"
        guard status == 200, hasListing, records == validRecords,
              returned.map({ Int($0) == records }) ?? true,
              !(result.isEmpty && (total ?? 0) > 0),
              !result.isEmpty || returned == 0 || total == 0 else {
            throw PurchaseHistoryDiagnostic(stage: .items, httpStatus: 200, dmapStatus: status,
                                           detail: "unrecognized/incomplete listing · " + detail)
        }
        // The protocol requests the complete listing, not a page. A partial response
        // is not a complete history and must not quietly replace the owner's list.
        guard total.map({ Int($0) <= records }) ?? true else {
            throw PurchaseHistoryDiagnostic(stage: .items, httpStatus: 200, dmapStatus: status,
                                           detail: "partial listing · " + detail)
        }
        return result.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }
}
