// Native Store (-1) provisioning. apple-auth core is MIT, see LICENSES.
import AsyncHTTPClient
import CStoreAMD
import CryptoKit
import Foundation
import Security

struct StoreAMDError: Error, LocalizedError, Sendable {
    enum Step: String, Sendable { case challenge, budget, device, begin, request, finish, http, keychain, headers, clock }
    let step: Step
    let httpStatus: Int?
    let keychainStatus: Int32?
    let actionHeaderPresent: Bool?
    let amdDataLength: Int?
    init(_ step: Step = .challenge, httpStatus: Int? = nil, keychainStatus: Int32? = nil, actionHeaderPresent: Bool? = nil, amdDataLength: Int? = nil) {
        self.step = step
        self.httpStatus = httpStatus
        self.actionHeaderPresent = actionHeaderPresent
        self.amdDataLength = amdDataLength
        self.keychainStatus = keychainStatus
    }
    var errorDescription: String? {
        var text = "تسجيل الجهاز ما كمل [AMD " + step.rawValue + "]"
        if let httpStatus { text += " HTTP " + String(httpStatus) }
        if let keychainStatus { text += " Keychain " + String(keychainStatus) }
        if step == .clock { text += ". Could not synchronize Apple time. Check automatic date and time, then retry." }
        if let actionHeaderPresent { text += " header=" + String(actionHeaderPresent) }
        if let amdDataLength { text += " AMDDataLength=" + String(amdDataLength) }
        return text
    }
}

// RFC 7231 IMF-fixdate. Never interpolate the header into errors.
struct StoreAMDClock: Sendable {
    private(set) var offset: TimeInterval = 0
    mutating func synchronize(_ header: String?, now: Date = Date()) throws {
        guard let header, header.utf8.count <= 64 else { throw StoreAMDError(.clock) }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
        formatter.isLenient = false
        guard let server = formatter.date(from: header) else { throw StoreAMDError(.clock) }
        offset = server.timeIntervalSince(now)
    }
    func seconds(now: Date = Date()) throws -> UInt32 {
        let value = now.timeIntervalSince1970 + offset
        guard value >= 0, value < Double(UInt32.max) else { throw StoreAMDError(.clock) }
        return UInt32(value)
    }
}

enum StoreAMDAction: Equatable, Sendable {
    case provision(Data)
    case reset

    static func parse(fields: [String: Any], actionHeader: String?, challenge: String?) throws -> Self? {
        let message = (fields["customerMessage"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let header = actionHeader?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? ""
        let action: String
        if !header.isEmpty { action = header }
        else if message.hasPrefix("AMD-Action"), let last = message.lastIndex(of: ":") {
            action = String(message[message.index(after: last)...]).trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        } else if message.hasPrefix("AMD-Action") {
            throw StoreAMDError(.challenge, actionHeaderPresent: actionHeader != nil, amdDataLength: challenge?.utf8.count ?? 0)
        } else { return nil }
        func invalid() -> StoreAMDError {
            StoreAMDError(.challenge, actionHeaderPresent: actionHeader != nil, amdDataLength: challenge?.utf8.count ?? 0)
        }
        switch action {
        case "RP": return .reset
        case "SP":
            guard let challenge, !challenge.isEmpty, challenge.utf8.count <= 16384,
                  let data = Data(base64Encoded: challenge), !data.isEmpty,
                  data.base64EncodedString() == challenge else { throw invalid() }
            return .provision(data)
        default: throw invalid()
        }
    }
}

struct StoreAMDBudget: Sendable {
    private(set) var provisions = 0
    private(set) var resets = 0
    private var provisionedSinceReset = false
    mutating func accept(_ action: StoreAMDAction) throws {
        switch action {
        case .provision:
            guard !provisionedSinceReset, provisions < 2 else { throw StoreAMDError(.budget) }
            provisions += 1
            provisionedSinceReset = true
        case .reset:
            guard resets == 0 else { throw StoreAMDError(.budget) }
            resets += 1
            provisionedSinceReset = false
        }
    }
}

protocol StoreAMDProviding: Sendable {
    func headers() async throws -> [String: String]
    func provision(_ challenge: Data) async throws
    func reset() async throws
    func synchronize(dateHeader: String?) async throws
}

// Pointers never leave this actor. Wrappers only allow deterministic RAII cleanup
// from Swift's nonisolated deinitializer; no native object is shared concurrently.
private final class AMDProfileHandle: @unchecked Sendable {
    let pointer: UnsafeMutableRawPointer
    init(_ pointer: UnsafeMutableRawPointer) { self.pointer = pointer }
    deinit { mirsa_store_profile_free(pointer) }
}

actor StoreAMDProof: StoreAMDProviding {
    private let device: String
    private var hardware: [UInt8] = []
    private var profile: AMDProfileHandle?
    private var loaded = false
    private var clock = StoreAMDClock()

    init(deviceIdentifier: String) {
        device = deviceIdentifier

    }

    private var keyQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "com.mirsa.store-amd.v1",
         kSecAttrAccount as String: device]
    }

    private var saltQuery: [String: Any] {
        var query = keyQuery
        query[kSecAttrService as String] = "com.mirsa.store-amd.salt.v1"
        return query
    }

    private func selectHardware(rotating: Bool = false) throws {
        var query = saltQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        let salt: Data
        if !rotating, status == errSecSuccess, let stored = item as? Data, stored.count == 32 {
            salt = stored
        } else {
            var bytes = [UInt8](repeating: 0, count: 32)
            let randomStatus = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
            guard randomStatus == errSecSuccess else { throw StoreAMDError(.device) }
            salt = Data(bytes)
            var attributes = saltQuery
            attributes[kSecValueData as String] = salt
            attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let updated = SecItemUpdate(saltQuery as CFDictionary, [kSecValueData as String: salt] as CFDictionary)
            let saved = updated == errSecItemNotFound ? SecItemAdd(attributes as CFDictionary, nil) : updated
            guard saved == errSecSuccess else { throw StoreAMDError(.keychain, keychainStatus: saved) }
        }
        hardware = Array(Insecure.SHA1.hash(data: Data(("Mirsa:StoreAMD:v2:" + device).utf8) + salt))
    }

    private func checkDevice() throws {
        guard device.utf8.count == 12, device.utf8.allSatisfy({ (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) })
        else { throw StoreAMDError(.device) }
    }

    private func load() throws {
        try checkDevice()
        guard !loaded else { return }
        var query = keyQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        // A locked/unreadable Keychain must never be interpreted as a usable profile.
        guard status == errSecSuccess || status == errSecItemNotFound else {
            profile = nil
            loaded = true
            return
        }
        try selectHardware()
        if let data = item as? Data {
            let pointer = data.withUnsafeBytes { bytes in
                hardware.withUnsafeBufferPointer { hw in
                    mirsa_store_import(bytes.bindMemory(to: UInt8.self).baseAddress, data.count, hw.baseAddress)
                }
            }
            if let pointer { profile = AMDProfileHandle(pointer) }
            else { try reset() }
        }
        loaded = true
    }

    func reset() throws {
        let status = SecItemDelete(keyQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw StoreAMDError(.keychain, keychainStatus: status) }
        profile = nil
        try selectHardware(rotating: true)
        loaded = true
    }

    func headers() throws -> [String: String] {
        try load()
        guard let profile else { return [:] }
        var amd = [CChar](repeating: 0, count: 2048)
        var machine = [CChar](repeating: 0, count: 256)
        guard mirsa_store_headers(profile.pointer, try seconds(), &amd, amd.count, &machine, machine.count) == 1 else {
            throw StoreAMDError(.headers)
        }
        return ["X-Apple-AMD": String(cString: amd), "X-Apple-AMD-M": String(cString: machine)]
    }

    func synchronize(dateHeader: String?) throws {
        try clock.synchronize(dateHeader)
    }

    private func seconds() throws -> UInt32 { try clock.seconds() }

    func provision(_ challenge: Data) async throws {
        try load()
        if hardware.isEmpty { try selectHardware() }
        let now = try seconds()
        let session = challenge.withUnsafeBytes { bytes in
            hardware.withUnsafeBufferPointer { hw in
                mirsa_store_begin(bytes.bindMemory(to: UInt8.self).baseAddress, challenge.count, hw.baseAddress, now)
            }
        }
        guard let session else { throw StoreAMDError(.begin) }
        defer { mirsa_store_session_free(session) }
        var packet = [UInt8](repeating: 0, count: 4096)
        var count = 0
        guard mirsa_store_request(session, &packet, packet.count, &count) == 1, count == 260 else { throw StoreAMDError(.request) }
        let body = try PropertyListSerialization.data(fromPropertyList: [
            "clientData": Data(packet.prefix(count)).base64EncodedString(), "guid": device,
        ], format: .xml, options: 0)
        // Fixed Apple endpoint, no credentials, no proxy, no redirects.
        let request = try HTTPClient.Request(url: "https://auth.itunes.apple.com/auth/v1/otp/1.5/finish", method: .POST,
            headers: ["Content-Type": "application/x-apple-plist", "User-Agent": Configuration.userAgent], body: .data(body))
        let client = Configuration.makeHTTPClient(redirectConfiguration: .disallow)
        defer { _ = client.shutdown() }
        let response: HTTPClient.Response
        do {
            response = try await client.execute(request: request,
                delegate: ResponseAccumulator(request: request, maxBodySize: 1024 * 1024)).futureResult.get()
        } catch { throw StoreAMDError(.http) }
        guard response.status == .ok else { throw StoreAMDError(.http, httpStatus: Int(response.status.code)) }
        try synchronize(dateHeader: response.headers.first(name: "Date"))
        guard let buffer = response.body,
              let root = try PropertyListSerialization.propertyList(from: Data(buffer.readableBytesView), format: nil) as? [String: Any]
        else { throw StoreAMDError(.finish) }
        let fields = root["Protocol"] as? [String: Any] ?? root
        guard let setting = fields["settingInfo"] as? String, setting.utf8.count <= 87384,
              let ptm = Data(base64Encoded: setting), !ptm.isEmpty, ptm.count <= 65536,
              let transport = fields["transportKey"] as? String, transport.utf8.count <= 32,
              let key = Data(base64Encoded: transport), key.count == 16 else { throw StoreAMDError(.finish) }
        let pointer = ptm.withUnsafeBytes { bytes in
            key.withUnsafeBytes { trust in
                mirsa_store_finish(session, bytes.bindMemory(to: UInt8.self).baseAddress, ptm.count,
                                   trust.bindMemory(to: UInt8.self).baseAddress)
            }
        }
        guard let pointer else { throw StoreAMDError(.finish) }
        let fresh = AMDProfileHandle(pointer)
        var encoded = [UInt8](repeating: 0, count: 65536)
        var size = 0
        let result = hardware.withUnsafeBufferPointer { hw in
            mirsa_store_export(fresh.pointer, hw.baseAddress, &encoded, encoded.count, &size)
        }
        guard result == 1 else { throw StoreAMDError(.keychain) }
        var attributes = keyQuery
        attributes[kSecValueData as String] = Data(encoded.prefix(size))
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemUpdate(keyQuery as CFDictionary, [kSecValueData as String: Data(encoded.prefix(size))] as CFDictionary)
        let finalStatus = status == errSecItemNotFound ? SecItemAdd(attributes as CFDictionary, nil) : status
        guard finalStatus == errSecSuccess else { throw StoreAMDError(.keychain, keychainStatus: finalStatus) }
        profile = fresh
        loaded = true
    }
}

// One transaction's bounded challenge state, also exercised with an offline provider.
struct StoreAMDHandshake: Sendable {
    let provider: any StoreAMDProviding
    private var budget = StoreAMDBudget()
    init(provider: any StoreAMDProviding) { self.provider = provider }
    mutating func respond(to response: HTTPClient.Response, isolation: isolated (any Actor)? = #isolation) async throws -> Bool {
        let data = response.body.map { Data($0.readableBytesView) } ?? Data()
        let fields = (try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
            ?? (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        let action = response.headers.first(name: "X-Apple-AMD-Action")
        let challenge = response.headers.first(name: "X-Apple-AMD-Data")
        guard try StoreAMDAction.parse(fields: fields, actionHeader: action, challenge: challenge) != nil else { return false }
        // Do not require a clock or mutate state for ignored RP.
        if try StoreAMDAction.parse(fields: fields, actionHeader: action, challenge: challenge) == .reset,
           try await provider.headers().isEmpty { return false }
        try await provider.synchronize(dateHeader: response.headers.first(name: "Date"))
        return try await respond(fields: fields, action: action, challenge: challenge)
    }

    mutating func respond(fields: [String: Any], action: String?, challenge: String?, isolation: isolated (any Actor)? = #isolation) async throws -> Bool {
        guard let next = try StoreAMDAction.parse(fields: fields, actionHeader: action, challenge: challenge) else { return false }
        // An RP without an existing profile is a no-op, not a device reset.
        if next == .reset, try await provider.headers().isEmpty { return false }
        try budget.accept(next)
        switch next {
        case let .provision(data): try await provider.provision(data)
        case .reset: try await provider.reset()
        }
        return true
    }
}


// Proofs are never sent to arbitrary Apple routes, dispatch URLs, CDN or redirects.
enum StoreAMDHeaderScope {
    static func permits(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https", url.user == nil, url.password == nil,
              url.port == nil || url.port == 443, let host = url.host?.lowercased() else { return false }
        let path = url.path.hasSuffix("/") ? String(url.path.dropLast()) : url.path
        if host == "auth.itunes.apple.com" {
            return path == "/auth/v1/native" || path == "/auth/v1/native/fast"
        }
        let purchaseHost = host == "buy.itunes.apple.com" ||
            host.range(of: "^p[0-9]+-buy\\.itunes\\.apple\\.com$", options: .regularExpression) != nil
        // A pod redirect can challenge the legacy authentication endpoint too.
        // Keep proof scoped to these exact commerce paths, never all Apple URLs.
        return purchaseHost && ["/WebObjects/MZFinance.woa/wa/buyProduct",
                                "/WebObjects/MZFinance.woa/wa/authenticate"].contains(path)
    }

    static func append(_ proof: [String: String], to headers: inout [(String, String)], url: URL) throws {
        guard permits(url) else { return }
        for name in ["X-Apple-AMD", "X-Apple-AMD-M"] {
            if let value = proof[name] {
                guard !value.isEmpty, value.utf8.count <= 2048, !value.contains("\r"), !value.contains("\n") else { throw StoreAMDError(.headers) }
                headers.append((name, value))
            }
        }
    }
}
