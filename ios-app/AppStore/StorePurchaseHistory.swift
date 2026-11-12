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
enum MirsaStorePurchaseHistory {
    static func fetch(owner: Account) async throws -> [MirsaStorePurchase] {
        let signer = try await SAPSigner.connect()
        let root = "https://pd.itunes.apple.com/WebObjects/MZPurchaseDaap.woa/purchase"
        let query = "('com.apple.itunes.extended\\-media\\-kind:131072')"
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false
        config.urlCache = nil
        let session = URLSession(configuration: config, delegate: HistoryRedirectPolicy(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        func request(_ path: String, body: Data?, binary: Bool = false) async throws -> Data {
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
                "X-Apple-Store-Front": owner.storeFront ?? owner.store,
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
            for (key, value) in owner.cookie.buildCookieHeader(url) { req.setValue(value, forHTTPHeaderField: key) }
            if let body {
                req.setValue(try await signer.sign(body).base64EncodedString(), forHTTPHeaderField: "X-Apple-ActionSignature")
            }
            let (data, response) = try await session.data(for: req)
            guard (response as? HTTPURLResponse)?.statusCode == 200, data.count <= 32 * 1024 * 1024 else {
                throw MirsaStoreError.serviceUnavailable
            }
            guard try HistoryTags.number("mstt", in: data) == 200 else { throw MirsaStoreError.serviceUnavailable }
            return data
        }
        let login = try await request("/login", body: nil)
        guard let sid = try HistoryTags.number("mlid", in: login) else { throw MirsaStoreError.serviceUnavailable }
        let update = try await request("/update", body: Data("session-id=\(sid)&revision-number=(null)&query=\(query)".utf8))
        guard let revision = try HistoryTags.number("musr", in: update) else { throw MirsaStoreError.serviceUnavailable }
        var content = HistoryTags.encode("mstc", integer: UInt32(Date().timeIntervalSince1970))
        content += HistoryTags.encode("mlid", integer: sid)
        content += HistoryTags.encode("mikd", bytes: Data([2]))
        content += HistoryTags.encode("musr", integer: revision)
        content += HistoryTags.encode("mder", integer: 0)
        content += HistoryTags.encode("mque", bytes: Data(query.utf8))
        content += HistoryTags.encode("aetl", bytes: Data())
        let listing = try await request("/databases/\(revision)/items", body: HistoryTags.encode("adsr", bytes: content), binary: true)
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
            let label = String(decoding: data[cursor..<cursor+4], as: UTF8.self)
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
        var seen = Set<Int64>()
        try scan(data) { label, chunk in
            guard label == "mlit" else { return }
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
            if id > 0, seen.insert(id).inserted {
                result.append(.init(id: id, bundleID: bundle, name: title.isEmpty ? fallback : title, version: version, date: date))
            }
        }
        return result.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }
}
