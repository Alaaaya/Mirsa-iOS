// Native Store (-1) provisioning. apple-auth core is MIT, see LICENSES.
import AsyncHTTPClient
import CStoreAMD
import CryptoKit
import Foundation
import NIOHTTP1
import Security

/// Device registration failed. Carries only the step that failed, never request
/// material, header values, challenge bytes or credentials.
public struct StoreAMDError: Error, LocalizedError, Sendable, Equatable {
    public enum Stage: Sendable, Equatable {
        case begin, request, finish, export
        case http(Int)
        case keychain(Int32)
        case headers, parse

        /// Stable, secret-free code for owner reports.
        public var code: String {
            switch self {
            case .begin: "begin"
            case .request: "request"
            case .finish: "finish"
            case .export: "export"
            case let .http(status): "http-\(status)"
            case let .keychain(status): "keychain-\(status)"
            case .headers: "headers"
            case .parse: "parse"
            }
        }
    }

    public let stage: Stage
    public init(_ stage: Stage) { self.stage = stage }

    public var diagnostic: String { "amd:" + stage.code }
    public var errorDescription: String? { "Device registration didn't finish [\(diagnostic)]. Please retry signing in." }
}

enum StoreAMDAction: Equatable, Sendable {
    case provision(Data)
    case reset

    /// The resolved action name, or nil when the response carries no AMD action at all.
    /// Header wins; otherwise a `customerMessage` such as `AMD-Action::SP` or `AMD-Action:RP`.
    static func actionName(fields: [String: Any], actionHeader: String?) -> String? {
        let header = (actionHeader ?? "").trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if !header.isEmpty { return header }
        let message = (fields["customerMessage"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard isActionMessage(message) else { return nil }
        guard let colon = message.lastIndex(of: ":") else { return "" }
        return message[message.index(after: colon)...].trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    static func isActionMessage(_ text: String?) -> Bool {
        guard let text else { return false }
        return text.trimmingCharacters(in: .whitespacesAndNewlines).uppercased().hasPrefix("AMD-ACTION")
    }

    static func parse(fields: [String: Any], actionHeader: String?, challenge: String?) throws -> Self? {
        guard let action = actionName(fields: fields, actionHeader: actionHeader) else { return nil }
        switch action {
        case "RP": return .reset
        case "SP":
            let challenge = (challenge ?? "").trimmingCharacters(in: .whitespaces)
            guard !challenge.isEmpty, challenge.utf8.count <= 16384,
                  let data = Data(base64Encoded: challenge), !data.isEmpty,
                  data.base64EncodedString() == challenge else { throw StoreAMDError(.parse) }
            return .provision(data)
        default: throw StoreAMDError(.parse)
        }
    }

    /// Plist first, then JSON; empty when the body is neither.
    static func fields(from body: Data) -> [String: Any] {
        guard !body.isEmpty, body.count <= 2 * 1024 * 1024 else { return [:] }
        if let plist = try? PropertyListSerialization.propertyList(from: body, format: nil) as? [String: Any] { return plist }
        if let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] { return json }
        return [:]
    }
}

struct StoreAMDBudget: Sendable {
    private(set) var provisions = 0
    private(set) var resets = 0
    private(set) var ignoredResets = 0
    private var provisionedSinceReset = false
    mutating func accept(_ action: StoreAMDAction) throws {
        switch action {
        case .provision:
            guard !provisionedSinceReset, provisions < 2 else { throw StoreAMDError(.parse) }
            provisions += 1
            provisionedSinceReset = true
        case .reset:
            guard resets == 0 else { throw StoreAMDError(.parse) }
            resets += 1
            provisionedSinceReset = false
        }
    }
    /// RP while no profile exists is not counted, but only one such retry is allowed.
    mutating func ignoreReset() throws {
        guard ignoredResets == 0 else { throw StoreAMDError(.parse) }
        ignoredResets += 1
    }
}

protocol StoreAMDProviding: Sendable {
    func headers() async throws -> [String: String]
    func provision(_ challenge: Data) async throws
    func reset() async throws
    func hasProfile() async -> Bool
    func observeServerDate(_ date: Date) async
}

/// Apple's clock, read from the HTTP `Date` header of bag/auth/store responses.
enum StoreAMDClock {
    /// Larger differences mean a broken header, not a skewed device.
    static let maximumOffset: TimeInterval = 7 * 24 * 3600

    static func serverDate(_ headers: HTTPHeaders) -> Date? {
        guard let value = headers.first(name: "Date") else { return nil }
        return parse(value)
    }

    static func parse(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return formatter.date(from: value.trimmingCharacters(in: .whitespaces))
    }

    static func offset(server: Date, local: Date = Date()) -> TimeInterval? {
        let delta = server.timeIntervalSince(local)
        guard delta.isFinite, abs(delta) <= maximumOffset else { return nil }
        return delta
    }

    static func seconds(now: Date = Date(), offset: TimeInterval) throws -> UInt32 {
        let value = now.timeIntervalSince1970 + offset
        guard value.isFinite, value >= 0, value < Double(UInt32.max) else { throw StoreAMDError(.headers) }
        return UInt32(value)
    }
}

/// Requests that may carry the machine OTP headers. Everything else gets them stripped.
/// The pod authenticate route (`p<N>-buy.itunes.apple.com/WebObjects/MZFinance.woa/wa/authenticate`)
/// is included: Apple redirects native sign-in there and ipatool re-sends the identical request,
/// AMD headers included, when only the destination changes.
enum StoreAMDHeaderPolicy {
    static let names = ["X-Apple-AMD", "X-Apple-AMD-M"]
    private static let nativeAuthPaths: Set = ["/auth/v1/native", "/auth/v1/native/", "/auth/v1/native/fast", "/auth/v1/native/fast/"]
    private static let storePaths: Set = [
        "/WebObjects/MZFinance.woa/wa/authenticate",
        "/WebObjects/MZFinance.woa/wa/authenticate/",
        "/WebObjects/MZFinance.woa/wa/buyProduct",
        "/WebObjects/MZFinance.woa/wa/volumeStoreDownloadProduct",
        "/WebObjects/MZFinance.woa/wa/redownloadProduct",
    ]
    private static let dispatchPaths: Set = ["/r/redownload", "/up/updateProduct"]

    static func allows(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https", url.user == nil, url.password == nil,
              url.port == nil || url.port == 443, let host = url.host?.lowercased() else { return false }
        // URL.path drops a trailing slash; use the raw path.
        let rawPath = URLComponents(url: url, resolvingAgainstBaseURL: true)?.percentEncodedPath ?? url.path
        if host == "auth.itunes.apple.com" { return nativeAuthPaths.contains(rawPath) }
        let buyHost = host == "buy.itunes.apple.com"
            || host.range(of: #"^p[0-9]+-buy\.itunes\.apple\.com$"#, options: .regularExpression) != nil
        if buyHost { return storePaths.contains(rawPath) }
        if host == "downloaddispatch.itunes.apple.com" { return dispatchPaths.contains(rawPath) }
        return false
    }

    /// Validated header pairs for `url`, or none when the path is not allowed.
    static func headers(_ amd: [String: String], for url: URL) throws -> [(String, String)] {
        guard allows(url) else { return [] }
        var result: [(String, String)] = []
        for name in names {
            guard let value = amd[name] else { continue }
            // Byte check: "\r\n" is one Character, so String.contains("\r") would miss it.
            guard !value.isEmpty, value.utf8.count <= 2048, !value.utf8.contains(where: { $0 == 13 || $0 == 10 || $0 == 0 }) else {
                throw StoreAMDError(.headers)
            }
            result.append((name, value))
        }
        return result
    }
}

// Pointers never leave this actor. Wrappers only allow deterministic RAII cleanup
// from Swift's nonisolated deinitializer; no native object is shared concurrently.
private final class AMDProfileHandle: @unchecked Sendable {
    let pointer: UnsafeMutableRawPointer
    init(_ pointer: UnsafeMutableRawPointer) { self.pointer = pointer }
    deinit { mirsa_store_profile_free(pointer) }
}

actor StoreAMDProof: StoreAMDProviding {
    private static let registry = LockedState<[String: StoreAMDProof]>([:])

    /// One instance per machine identifier, so the clock offset and the loaded
    /// profile are shared by sign-in, purchase and download.
    static func shared(deviceIdentifier: String) -> StoreAMDProof {
        registry.withLock { map in
            if let existing = map[deviceIdentifier] { return existing }
            let created = StoreAMDProof(deviceIdentifier: deviceIdentifier)
            map[deviceIdentifier] = created
            return created
        }
    }

    private let device: String
    private var hardware: [UInt8]?
    private var profile: AMDProfileHandle?
    private var loaded = false
    private var clockOffset: TimeInterval = 0

    init(deviceIdentifier: String) {
        device = deviceIdentifier
    }

    private var keyQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "com.mirsa.store-amd.v1",
         kSecAttrAccount as String: device]
    }

    private var saltQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "com.mirsa.store-amd.salt.v1",
         kSecAttrAccount as String: device]
    }

    private func checkDevice() throws {
        guard device.utf8.count == 12, device.utf8.allSatisfy({ (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) })
        else { throw StoreAMDError(.begin) }
    }

    func observeServerDate(_ date: Date) {
        if let offset = StoreAMDClock.offset(server: date) { clockOffset = offset }
    }

    func hasProfile() -> Bool {
        (try? load()) != nil && profile != nil
    }

    private func derive(_ salt: Data) -> [UInt8] {
        var input = Data("Mirsa:StoreAMD:v2:".utf8)
        input.append(salt)
        input.append(Data(device.utf8))
        return Array(Insecure.SHA1.hash(data: input))
    }

    private static func randomSalt() throws -> Data {
        var bytes = [UInt8](repeating: 0, count: 16)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { throw StoreAMDError(.begin) }
        return Data(bytes)
    }

    private func readItem(_ base: [String: Any]) -> Data? {
        var query = base
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        // Any status other than success is treated as "nothing stored".
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess else { return nil }
        return item as? Data
    }

    private func writeItem(_ base: [String: Any], _ data: Data) -> OSStatus {
        let status = SecItemUpdate(base as CFDictionary, [kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly] as CFDictionary)
        guard status == errSecItemNotFound else { return status }
        var attributes = base
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(attributes as CFDictionary, nil)
    }

    /// Fresh 16-byte salt, persisted when possible; an unwritable Keychain keeps it for this session only.
    private func rotateSalt() throws -> [UInt8] {
        let salt = try Self.randomSalt()
        _ = SecItemDelete(saltQuery as CFDictionary)
        _ = writeItem(saltQuery, salt)
        let derived = derive(salt)
        hardware = derived
        return derived
    }

    private func hardwareID() throws -> [UInt8] {
        if let hardware { return hardware }
        if let salt = readItem(saltQuery), salt.count == 16 {
            let derived = derive(salt)
            hardware = derived
            return derived
        }
        // No salt yet: any older profile was bound to another identity.
        _ = SecItemDelete(keyQuery as CFDictionary)
        return try rotateSalt()
    }

    private func load() throws {
        try checkDevice()
        guard !loaded else { return }
        let hw = try hardwareID()
        if let data = readItem(keyQuery) {
            let pointer = data.withUnsafeBytes { bytes in
                hw.withUnsafeBufferPointer { h in
                    mirsa_store_import(bytes.bindMemory(to: UInt8.self).baseAddress, data.count, h.baseAddress)
                }
            }
            if let pointer { profile = AMDProfileHandle(pointer) }
            else { try reset() }
        }
        loaded = true
    }

    /// RP: drop the provisioned profile only. The machine identity (hardware bytes, and the guid it is
    /// bound to) stays the same, as in ipatool, which re-provisions after RP with the unchanged hardware ID.
    func reset() throws {
        try checkDevice()
        _ = SecItemDelete(keyQuery as CFDictionary)
        profile = nil
        _ = try hardwareID()
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

    private func seconds() throws -> UInt32 {
        try StoreAMDClock.seconds(offset: clockOffset)
    }

    func provision(_ challenge: Data) async throws {
        try checkDevice()
        if !loaded { try load() }
        let hw = try hardwareID()
        let now = try seconds()
        let session = challenge.withUnsafeBytes { bytes in
            hw.withUnsafeBufferPointer { h in
                mirsa_store_begin(bytes.bindMemory(to: UInt8.self).baseAddress, challenge.count, h.baseAddress, now)
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
        } catch { throw StoreAMDError(.http(0)) }
        if let date = StoreAMDClock.serverDate(response.headers) { observeServerDate(date) }
        guard response.status == .ok else { throw StoreAMDError(.http(Int(response.status.code))) }
        guard let buffer = response.body,
              let root = try? PropertyListSerialization.propertyList(from: Data(buffer.readableBytesView), format: nil) as? [String: Any]
        else { throw StoreAMDError(.parse) }
        let fields = root["Protocol"] as? [String: Any] ?? root
        guard let setting = fields["settingInfo"] as? String, setting.utf8.count <= 87384,
              let ptm = Data(base64Encoded: setting), !ptm.isEmpty, ptm.count <= 65536,
              let transport = fields["transportKey"] as? String, transport.utf8.count <= 32,
              let key = Data(base64Encoded: transport), key.count == 16 else { throw StoreAMDError(.parse) }
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
        let result = hw.withUnsafeBufferPointer { h in
            mirsa_store_export(fresh.pointer, h.baseAddress, &encoded, encoded.count, &size)
        }
        guard result == 1 else { throw StoreAMDError(.export) }
        let status = writeItem(keyQuery, Data(encoded.prefix(size)))
        guard status == errSecSuccess else { throw StoreAMDError(.keychain(status)) }
        profile = fresh
        loaded = true
    }
}

// One transaction's bounded challenge state, also exercised with an offline provider.
struct StoreAMDHandshake: Sendable {
    let provider: any StoreAMDProviding
    private var budget = StoreAMDBudget()
    init(provider: any StoreAMDProviding) { self.provider = provider }

    /// True when the response was an AMD action that has been handled and the request should be retried.
    mutating func respond(fields: [String: Any], action: String?, challenge: String?, isolation: isolated (any Actor)? = #isolation) async throws -> Bool {
        guard let next = try StoreAMDAction.parse(fields: fields, actionHeader: action, challenge: challenge) else { return false }
        if case .reset = next {
            let hasProfile = await provider.hasProfile()
            if !hasProfile {
                try budget.ignoreReset()
                return true
            }
        }
        try budget.accept(next)
        switch next {
        case let .provision(data): try await provider.provision(data)
        case .reset: try await provider.reset()
        }
        return true
    }

    /// Same as above for a raw HTTP response of any status.
    mutating func respond(to response: HTTPClient.Response, isolation: isolated (any Actor)? = #isolation) async throws -> Bool {
        if let date = StoreAMDClock.serverDate(response.headers) { await provider.observeServerDate(date) }
        let body = response.body.map { Data($0.readableBytesView) } ?? Data()
        return try await respond(fields: StoreAMDAction.fields(from: body),
                                 action: response.headers.first(name: "X-Apple-AMD-Action"),
                                 challenge: response.headers.first(name: "X-Apple-AMD-Data"))
    }
}
