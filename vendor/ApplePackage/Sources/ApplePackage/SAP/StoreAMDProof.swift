// Native Store (-1) provisioning. apple-auth core is MIT, see LICENSES.
import AsyncHTTPClient
import CStoreAMD
import CryptoKit
import Foundation
import Security

struct StoreAMDError: Error, LocalizedError {
    var errorDescription: String? { "App Store device provisioning failed. Please retry signing in." }
}

enum StoreAMDAction: Equatable, Sendable {
    case provision(Data)
    case reset

    static func parse(fields: [String: Any], actionHeader: String?, challenge: String?) throws -> Self? {
        let message = fields["customerMessage"] as? String ?? ""
        let action: String
        if let header = actionHeader, !header.isEmpty { action = header }
        else if message == "AMD-Action::SP" { action = "SP" }
        else if message == "AMD-Action::RP" { action = "RP" }
        else { return nil }
        switch action {
        case "RP": return .reset
        case "SP":
            guard let challenge, !challenge.isEmpty, challenge.utf8.count <= 16384,
                  let data = Data(base64Encoded: challenge), !data.isEmpty,
                  data.base64EncodedString() == challenge else { throw StoreAMDError() }
            return .provision(data)
        default: throw StoreAMDError()
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
            guard !provisionedSinceReset, provisions < 2 else { throw StoreAMDError() }
            provisions += 1
            provisionedSinceReset = true
        case .reset:
            guard resets == 0 else { throw StoreAMDError() }
            resets += 1
            provisionedSinceReset = false
        }
    }
}

protocol StoreAMDProviding: Sendable {
    func headers() async throws -> [String: String]
    func provision(_ challenge: Data) async throws
    func reset() async throws
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
    private let hardware: [UInt8]
    private var profile: AMDProfileHandle?
    private var loaded = false

    init(deviceIdentifier: String) {
        device = deviceIdentifier
        hardware = Array(Insecure.SHA1.hash(data: Data(("Mirsa:StoreAMD:v1:" + deviceIdentifier).utf8)))
    }

    private var keyQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "com.mirsa.store-amd.v1",
         kSecAttrAccount as String: device]
    }

    private func checkDevice() throws {
        guard device.utf8.count == 12, device.utf8.allSatisfy({ (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) })
        else { throw StoreAMDError() }
    }

    private func load() throws {
        try checkDevice()
        guard !loaded else { return }
        var query = keyQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw StoreAMDError() }
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
        guard status == errSecSuccess || status == errSecItemNotFound else { throw StoreAMDError() }
        profile = nil
        loaded = true
    }

    func headers() throws -> [String: String] {
        try load()
        guard let profile else { return [:] }
        var amd = [CChar](repeating: 0, count: 2048)
        var machine = [CChar](repeating: 0, count: 256)
        guard mirsa_store_headers(profile.pointer, try seconds(), &amd, amd.count, &machine, machine.count) == 1 else {
            throw StoreAMDError()
        }
        return ["X-Apple-AMD": String(cString: amd), "X-Apple-AMD-M": String(cString: machine)]
    }

    private func seconds() throws -> UInt32 {
        let value = Date().timeIntervalSince1970
        guard value >= 0, value < Double(UInt32.max) else { throw StoreAMDError() }
        return UInt32(value)
    }

    func provision(_ challenge: Data) async throws {
        try checkDevice()
        let now = try seconds()
        let session = challenge.withUnsafeBytes { bytes in
            hardware.withUnsafeBufferPointer { hw in
                mirsa_store_begin(bytes.bindMemory(to: UInt8.self).baseAddress, challenge.count, hw.baseAddress, now)
            }
        }
        guard let session else { throw StoreAMDError() }
        defer { mirsa_store_session_free(session) }
        var packet = [UInt8](repeating: 0, count: 4096)
        var count = 0
        guard mirsa_store_request(session, &packet, packet.count, &count) == 1, count == 260 else { throw StoreAMDError() }
        let body = try PropertyListSerialization.data(fromPropertyList: [
            "clientData": Data(packet.prefix(count)).base64EncodedString(), "guid": device,
        ], format: .xml, options: 0)
        // Fixed Apple endpoint, no credentials, no proxy, no redirects.
        let request = try HTTPClient.Request(url: "https://auth.itunes.apple.com/auth/v1/otp/1.5/finish", method: .POST,
            headers: ["Content-Type": "application/x-apple-plist", "User-Agent": Configuration.userAgent], body: .data(body))
        let client = Configuration.makeHTTPClient(redirectConfiguration: .disallow)
        defer { _ = client.shutdown() }
        let response = try await client.execute(request: request,
            delegate: ResponseAccumulator(request: request, maxBodySize: 1024 * 1024)).futureResult.get()
        guard response.status == .ok, let buffer = response.body,
              let root = try PropertyListSerialization.propertyList(from: Data(buffer.readableBytesView), format: nil) as? [String: Any]
        else { throw StoreAMDError() }
        let fields = root["Protocol"] as? [String: Any] ?? root
        guard let setting = fields["settingInfo"] as? String, setting.utf8.count <= 87384,
              let ptm = Data(base64Encoded: setting), !ptm.isEmpty, ptm.count <= 65536,
              let transport = fields["transportKey"] as? String, transport.utf8.count <= 32,
              let key = Data(base64Encoded: transport), key.count == 16 else { throw StoreAMDError() }
        let pointer = ptm.withUnsafeBytes { bytes in
            key.withUnsafeBytes { trust in
                mirsa_store_finish(session, bytes.bindMemory(to: UInt8.self).baseAddress, ptm.count,
                                   trust.bindMemory(to: UInt8.self).baseAddress)
            }
        }
        guard let pointer else { throw StoreAMDError() }
        let fresh = AMDProfileHandle(pointer)
        var encoded = [UInt8](repeating: 0, count: 65536)
        var size = 0
        let result = hardware.withUnsafeBufferPointer { hw in
            mirsa_store_export(fresh.pointer, hw.baseAddress, &encoded, encoded.count, &size)
        }
        guard result == 1 else { throw StoreAMDError() }
        var attributes = keyQuery
        attributes[kSecValueData as String] = Data(encoded.prefix(size))
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemUpdate(keyQuery as CFDictionary, [kSecValueData as String: Data(encoded.prefix(size))] as CFDictionary)
        guard status == errSecSuccess || (status == errSecItemNotFound && SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess)
        else { throw StoreAMDError() }
        profile = fresh
        loaded = true
    }
}

// One transaction's bounded challenge state, also exercised with an offline provider.
struct StoreAMDHandshake: Sendable {
    let provider: any StoreAMDProviding
    private var budget = StoreAMDBudget()
    init(provider: any StoreAMDProviding) { self.provider = provider }
    mutating func respond(fields: [String: Any], action: String?, challenge: String?, isolation: isolated (any Actor)? = #isolation) async throws -> Bool {
        guard let next = try StoreAMDAction.parse(fields: fields, actionHeader: action, challenge: challenge) else { return false }
        try budget.accept(next)
        switch next {
        case let .provision(data): try await provider.provision(data)
        case .reset: try await provider.reset()
        }
        return true
    }
}
