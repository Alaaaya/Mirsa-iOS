import Foundation

/// Talks to the tweak-forge edge function with the signed-in Mirsa session. No secrets live in the app.
enum ForgeClient {
    static let endpoint = URL(string: WebBackendConfig.defaultProject + "/functions/v1/mirsa-forge")!

    enum Failure: LocalizedError {
        case message(String)
        var errorDescription: String? { if case .message(let m) = self { return m }; return nil }
    }

    private static func token() async throws -> String {
        let auth = DiscoveryAuthClient(projectURL: URL(string: WebBackendConfig.defaultProject)!,
            publishableKey: WebBackendConfig.defaultPublishableKey, store: KeychainSessionStore(), http: SafeMetadataHTTP())
        return try await auth.token(forceRefresh: false)
    }

    private static func message(_ status: Int, _ data: Data) -> String {
        let code = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String ?? ""
        switch (status, code) {
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
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let cfg = URLSessionConfiguration.ephemeral; cfg.httpCookieStorage = nil
        let session = URLSession(configuration: cfg, delegate: OTANoRedirect(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (data, resp) = try await session.data(for: req)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw Failure.message(message(status, data)) }
        return data
    }

    static func get(_ query: [String: String]) async throws -> [String: Any] {
        var c = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)!
        c.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        var req = URLRequest(url: c.url!, timeoutInterval: 30)
        req.setValue("Bearer " + (try await token()), forHTTPHeaderField: "Authorization")
        let (data, resp) = try await URLSession(configuration: .ephemeral).data(for: req)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200, let o = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw Failure.message(message(status, data)) }
        return o
    }

    static func getData(_ query: [String: String]) async throws -> Data {
        var c = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)!
        c.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        var req = URLRequest(url: c.url!, timeoutInterval: 60)
        req.setValue("Bearer " + (try await token()), forHTTPHeaderField: "Authorization")
        let (data, resp) = try await URLSession(configuration: .ephemeral).data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw Failure.message(message((resp as? HTTPURLResponse)?.statusCode ?? 0, data)) }
        return data
    }

    static func json(_ body: [String: Any]) async throws -> [String: Any] {
        guard let o = try JSONSerialization.jsonObject(with: try await post(body)) as? [String: Any] else { throw Failure.message(message(500, Data())) }
        return o
    }
}
