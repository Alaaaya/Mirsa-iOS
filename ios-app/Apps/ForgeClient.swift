import Foundation
import CryptoKit
import Security

/// Talks to the tweak-forge edge function with the signed-in Mirsa session. No secrets live in the app.
enum ForgeClient {
    static let endpoint = URL(string: WebBackendConfig.defaultProject + "/functions/v1/mirsa-forge")!

    enum Failure: LocalizedError {
        case message(String)
        /// Server refusal that needs inspector data; UI offers to open the existing Inspector for this app.
        case inspectorNeeded(String)
        /// 409 version_conflict: the community entry changed since the client last loaded it.
        case versionConflict(String)
        var errorDescription: String? { switch self { case .message(let m), .inspectorNeeded(let m), .versionConflict(let m): return m } }
        var isVersionConflict: Bool { if case .versionConflict = self { return true }; return false }
    }

    private static func token() async throws -> String {
        let auth = DiscoveryAuthClient(projectURL: URL(string: WebBackendConfig.defaultProject)!,
            publishableKey: WebBackendConfig.defaultPublishableKey, store: KeychainSessionStore(), http: SafeMetadataHTTP())
        return try await auth.token(forceRefresh: false)
    }

    /// Random per-install ID kept in the Keychain (this device only, no hardware fingerprint). Without App Attest the server cannot prove it
    /// belongs to a physical device; the server binds it to the signed-in account and limits new IDs per account and per IP instead.
    static func deviceID() -> String {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "com.alaa.mirsa.forge.device"]
        var out: AnyObject?
        var get = q; get[kSecReturnData as String] = true; get[kSecMatchLimit as String] = kSecMatchLimitOne
        if SecItemCopyMatching(get as CFDictionary, &out) == errSecSuccess, let d = out as? Data, let s = String(data: d, encoding: .utf8), UUID(uuidString: s) != nil { return s }
        let id = UUID().uuidString.lowercased()
        var add = q; add[kSecValueData as String] = Data(id.utf8); add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
        return id
    }

    static func failure(_ status: Int, _ data: Data) -> Failure {
        if status == 409, (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String == "version_conflict" {
            return .versionConflict(tr("This tweak was updated elsewhere. The list was reloaded, try again.", "التويك انحدث من مكان ثاني. حدّثنا القائمة، جرّب مرة ثانية.", ckb: "ئەم تویکە لە شوێنێکی تر نوێکراوەتەوە. لیستەکە نوێکرایەوە.", kmr: "Ev tweak li cihekî din hat nûkirin. Lîste nû bû."))
        }
        let m = message(status, data)
        return ForgeServerMessage.needsInspector(data) ? .inspectorNeeded(m) : .message(m)
    }

    private static func message(_ status: Int, _ data: Data) -> String {
        if let server = ForgeServerMessage.text(data, lang: ForgeServerMessage.lang()) { return server }
        let code = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String ?? ""
        switch (status, code) {
        case (429, "daily_limit"): return tr("Daily limit reached. Try again tomorrow.", "الحد اليومي خلص، جرّب بكرا", ckb: "سنووری ڕۆژانە تەواو بوو، سبەی تاقی بکەرەوە.", kmr: "Sînorê rojane qediya, sibê biceribîne.")
        case (429, "busy"): return tr("The AI is busy right now. Try again in a minute.", "الذكاء الاصطناعي مشغول هلأ. جرّب بعد دقيقة.", ckb: "زیرەکی دەستکرد ئێستا سەرقاڵە. دوای خولەکێک تاقی بکەرەوە.", kmr: "AI niha mijûl e. Piştî hûrdemekê biceribîne.")
        case (429, _): return tr("Hourly limit reached. Try again later.", "وصلت للحد بالساعة. جرّب بعدين.", ckb: "گەیشتیتە سنووری کاتژمێری. دواتر تاقی بکەرەوە.", kmr: "Sînorê demjimêrê tije bû. Paşê biceribîne.")
        case (503, "llm_not_configured"): return tr("The AI service is not set up on the server yet.", "خدمة الذكاء الاصطناعي مو مفعّلة على السيرفر بعد.", ckb: "خزمەتگوزاری زیرەکی دەستکرد هێشتا لەسەر سێرڤەر چالاک نەکراوە.", kmr: "Xizmeta AI hê li ser serverê ne çalak e.")
        case (503, "builder_not_configured"): return tr("The tweak build server is not connected yet.", "سيرفر بناء التويكس مو موصول بعد.", ckb: "سێرڤەری دروستکردنی تویک هێشتا پەیوەست نەکراوە.", kmr: "Servera çêkirina tweakê hê ne girêdayî ye.")
        case (422, "unsafe_or_invalid_code"): return tr("The generated code was rejected as unsafe. Rephrase the request.", "الكود المولّد انرفض لأنه مو آمن. أعد صياغة الطلب.", ckb: "کۆدی دروستکراو وەک نائەمن ڕەتکرایەوە. داواکاریەکە بنووسەرەوە.", kmr: "Koda hatî çêkirin wekî ne ewle hat redkirin. Daxwazê ji nû ve binivîse.")
        case (422, "build_failed"): return tr("The build failed.", "البناء فشل.", ckb: "دروستکردن شکستی هێنا.", kmr: "Çêkirin têk çû.")
        case (401, _): return tr("Sign-in expired. Reopen Mirsa and try again.", "انتهت الجلسة. افتح ميرسا من جديد.", ckb: "نشستەکە بەسەرچوو. میرسا دووبارە بکەرەوە.", kmr: "Danişîn qediya. Mirsa ji nû ve veke.")
        default: return tr("Server error. Try again.", "خطأ بالسيرفر. جرّب مرة ثانية.", ckb: "هەڵەی سێرڤەر. دووبارە تاقی بکەرەوە.", kmr: "Çewtiya serverê. Dîsa biceribîne.")
        }
    }

    static func post(_ body: [String: Any], timeout: TimeInterval = 120) async throws -> Data {
        var req = URLRequest(url: endpoint, timeoutInterval: timeout)
        req.httpMethod = "POST"
        req.setValue("Bearer " + (try await token()), forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(deviceID(), forHTTPHeaderField: "x-mirsa-device")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let cfg = URLSessionConfiguration.ephemeral; cfg.httpCookieStorage = nil
        let session = URLSession(configuration: cfg, delegate: OTANoRedirect(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (data, resp) = try await session.data(for: req)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw failure(status, data) }
        return data
    }

    static func get(_ query: [String: String]) async throws -> [String: Any] {
        var c = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)!
        c.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        var req = URLRequest(url: c.url!, timeoutInterval: 30)
        req.setValue("Bearer " + (try await token()), forHTTPHeaderField: "Authorization")
        req.setValue(deviceID(), forHTTPHeaderField: "x-mirsa-device")
        let (data, resp) = try await URLSession(configuration: .ephemeral).data(for: req)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw failure(status, data) }
        guard let o = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw Failure.message(message(status, data)) }
        return o
    }

    static func getData(_ query: [String: String]) async throws -> (Data, String, String) {
        var c = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)!
        c.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        var req = URLRequest(url: c.url!, timeoutInterval: 60)
        req.setValue("Bearer " + (try await token()), forHTTPHeaderField: "Authorization")
        let (data, resp) = try await URLSession(configuration: .ephemeral).data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw Failure.message(message((resp as? HTTPURLResponse)?.statusCode ?? 0, data)) }
        let h = resp as! HTTPURLResponse
        return (data, h.value(forHTTPHeaderField: "x-forge-key") ?? "", h.value(forHTTPHeaderField: "x-forge-kind") ?? "")
    }

    /// Explicit community download only. No redirects, bounded bytes, and a SHA-256 match before writing.
    static func communityDylib(id: String, sha256: String) async throws -> URL {
        guard UUID(uuidString: id) != nil, sha256.count == 64,
              sha256.allSatisfy({ $0.isHexDigit }) else { throw ForgeDylibImportError.invalidBinary }
        var c = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)!
        c.queryItems = [URLQueryItem(name: "action", value: "gallery-download"), URLQueryItem(name: "id", value: id)]
        var req = URLRequest(url: c.url!, timeoutInterval: 60)
        req.setValue("Bearer " + (try await token()), forHTTPHeaderField: "Authorization")
        req.setValue(deviceID(), forHTTPHeaderField: "x-mirsa-device")
        let cfg = URLSessionConfiguration.ephemeral; cfg.httpCookieStorage = nil
        let session = URLSession(configuration: cfg, delegate: OTANoRedirect(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (stream, response) = try await session.bytes(for: req)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw Failure.message(tr("The community download failed.", "تنزيل تويك المجتمع فشل.", ckb: "داگرتنی تویک شکستی هێنا.", kmr: "Daxistina tweakê têk çû."))
        }
        let maximum = 4 * 1024 * 1024
        guard response.expectedContentLength <= Int64(maximum) else { throw ForgeDylibImportError.tooLarge }
        var data = Data()
        for try await byte in stream {
            guard data.count < maximum else { throw ForgeDylibImportError.tooLarge }
            data.append(byte)
        }
        guard !data.isEmpty, ForgeFixItem.sha(data) == sha256.lowercased() else { throw ForgeDylibImportError.invalidBinary }
        _ = try ForgeDylibInspector.inspect(data)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("mirsa-community-" + UUID().uuidString + ".dylib")
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        return url
    }

    /// AES-256-GCM, per-job master key, HKDF-SHA256 per purpose, AAD = purpose|job|v1. Layout nonce||ciphertext||tag. Throws on any tampering.
    static func open(_ blob: Data, masterB64: String, job: String, purpose: String) throws -> Data {
        guard let m = Data(base64Encoded: masterB64), m.count == 32, blob.count >= 28 else { throw Failure.message("Invalid encrypted result") }
        let key = HKDF<SHA256>.deriveKey(inputKeyMaterial: SymmetricKey(data: m), salt: Data("cc-v1".utf8), info: Data((purpose + "|" + job).utf8), outputByteCount: 32)
        do { return try AES.GCM.open(try AES.GCM.SealedBox(combined: blob), using: key, authenticating: Data((purpose + "|" + job + "|v1").utf8)) }
        catch { throw Failure.message("The downloaded result failed verification and was discarded.") }
    }

    static func json(_ body: [String: Any]) async throws -> [String: Any] {
        guard let o = try JSONSerialization.jsonObject(with: try await post(body)) as? [String: Any] else { throw Failure.message(message(500, Data())) }
        return o
    }
}
