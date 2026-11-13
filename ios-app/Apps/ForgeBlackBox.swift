import SwiftUI

/// Opt-in, report-only termination reports. Contract: signal number + format version only.
/// Identity comes from an enrolled installation capability; the culprit is never claimed.
enum ForgeBlackBox {
    static let consentKey = "mirsa.blackbox.consent.v1"
    static let service = "com.alaa.mirsa.forge.blackbox"
    static var consent: Bool { UserDefaults.standard.bool(forKey: consentKey) }

    struct Enrollment: Codable, Equatable { let installationID: UUID; let tweakID: UUID; let reportToken: String; let expiresAt: String }
    private static var fileURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("blackbox-installations.json")
    }
    /// Report tokens are secrets: the file holds only installation IDs, tokens live in the Keychain.
    private static func ids() -> [UUID: UUID] {
        guard let d = try? Data(contentsOf: fileURL), let m = try? JSONDecoder().decode([String: String].self, from: d) else { return [:] }
        return Dictionary(uniqueKeysWithValues: m.compactMap { k, v in
            guard let a = UUID(uuidString: k), let b = UUID(uuidString: v) else { return nil }; return (a, b) })
    }
    private static func saveIDs(_ m: [UUID: UUID]) {
        let raw = Dictionary(uniqueKeysWithValues: m.map { ($0.key.uuidString, $0.value.uuidString) })
        try? JSONEncoder().encode(raw).write(to: fileURL, options: [.atomic, .completeFileProtection])
    }
    static var enrolledCount: Int { ids().count }

    @MainActor static func enable(store: ForgeStore) async throws {
        let caps = await ForgeRepairGate.fetch()
        guard caps.blackbox else { throw ForgeClient.Failure.message(ForgeBlackBoxText.unavailable) }
        let token = try await ForgeClient.fixToken()
        var map = ids()
        for p in store.projects {
            guard let v = p.currentVersion, map[v.tweakID] == nil else { continue }
            let app = String(((Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "").prefix(32))
            let data = try await ForgeClient.fixRequest(["action": "blackbox-enroll", "consent": true, "id": UUID().uuidString.lowercased(),
                "tweakID": v.tweakID.uuidString.lowercased(), "sourceSHA256": ForgeFixItem.sha(Data(v.code.utf8)), "bundleID": p.bundleID,
                "tweakVersion": String(v.id.uuidString.prefix(8)).lowercased(), "appVersion": app], deviceToken: token, maxBytes: 8192)
            guard let o = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let iid = (o["installationID"] as? String).flatMap(UUID.init(uuidString:)),
                  let secret = o["reportToken"] as? String, secret.range(of: "^[A-Za-z0-9_-]{32,128}$", options: .regularExpression) != nil
            else { throw ForgeClient.Failure.message("Enrollment response was invalid.") }
            _ = try ForgeFixSystemKeychain().add(service: service, account: iid.uuidString.lowercased(), data: Data(secret.utf8))
            map[v.tweakID] = iid; saveIDs(map)
        }
        UserDefaults.standard.set(true, forKey: consentKey)
    }

    /// Turning off always clears local consent first, then asks the server to revoke each capability.
    @MainActor static func disable() async {
        UserDefaults.standard.set(false, forKey: consentKey)
        let map = ids()
        guard !map.isEmpty, let token = try? await ForgeClient.fixToken() else { return }
        var left = map
        for (tweak, iid) in map {
            if (try? await ForgeClient.fixRequest(["action": "blackbox-revoke", "installationID": iid.uuidString.lowercased()], deviceToken: token, maxBytes: 4096)) != nil { left[tweak] = nil }
        }
        saveIDs(left)
    }
}

enum ForgeBlackBoxText {
    static var title: String { tr5("Black box", "الصندوق الأسود", de: "Blackbox", ckb: "سندوقی ڕەش", kmr: "Qutiya reş") }
    static var toggle: String { tr5("Send anonymous crash signals for my tweaks", "ابعت إشارات كراش مجهولة عن تويكاتي", de: "Anonyme Absturzsignale für meine Tweaks senden", ckb: "نیشانەی کڕاشی نەناسراو بۆ تویکەکانم بنێرە", kmr: "Nîşanên qelibînê yên nenas ji bo tweakên min bişîne") }
    static var privacy: String { tr5("Off by default. Only the termination signal number, your tweak ID, source hash, bundle ID and versions are sent. No stack, paths, logs, device name or app data. A signal shows that the process ended, not which tweak or hook caused it, and no fix is promised. Turning it off revokes the report permission.", "مطفي افتراضياً. بينبعت بس رقم إشارة الإنهاء ومعرّف التويك وبصمة الكود ومعرّف التطبيق والإصدارات. بدون ستاك ولا مسارات ولا سجلات ولا اسم الجهاز ولا بيانات التطبيق. الإشارة بتدل إنو العملية انتهت، مو أي تويك أو هوك سببها، وما في وعد بإصلاح. إطفاؤه بيلغي صلاحية الإرسال.", de: "Standardmäßig aus. Gesendet werden nur die Signalnummer des Abbruchs, Tweak-ID, Quellcode-Hash, Bundle-ID und Versionen. Kein Stack, keine Pfade, keine Logs, kein Gerätename, keine App-Daten. Ein Signal zeigt nur, dass der Prozess endete, nicht welcher Tweak oder Hook schuld ist, und eine Reparatur wird nicht versprochen. Beim Ausschalten wird die Sendeberechtigung widerrufen.", ckb: "بە شێوەی بنەڕەتی کوژاوەیە. تەنها ژمارەی نیشانەی کۆتایی، ناسنامەی تویک، پەنجەمۆری کۆد، bundle ID و وەشانەکان دەنێردرێن. نە ستاک و نە ڕێڕەو و نە لۆگ و نە ناوی ئامێر و نە داتای ئەپ. نیشانە تەنها دەڵێت پرۆسەکە کۆتایی هات، نەک کام تویک یان هووک هۆکارە، و چاککردن بەڵێن نادرێت. کوژاندنەوە مۆڵەتی ناردن هەڵدەوەشێنێتەوە.", kmr: "Bi default girtî ye. Tenê hejmara nîşana qedandinê, nasnameya tweakê, hashê kodê, bundle ID û guhertoyan tên şandin. Ne stack, ne rê, ne log, ne navê cîhazê, ne daneyên appê. Nîşan tenê nîşan dide ku pêvajo qediya, ne kîjan tweak an hook sedem e, û sererastkirin nayê soz dan. Girtin destûra şandinê betal dike.") }
    static var unavailable: String { tr5("The server side is not active yet, so nothing was enabled or sent.", "جهة السيرفر لسا مو شغّالة، فما تفعّل ولا انبعت شي.", de: "Die Serverseite ist noch nicht aktiv, daher wurde nichts aktiviert oder gesendet.", ckb: "لای سێرڤەر هێشتا چالاک نییە، بۆیە هیچ چالاک نەکرا و نەنێردرا.", kmr: "Aliyê serverê hê çalak nîne, ji ber vê tiştek nehat çalakkirin an şandin.") }
}

struct ForgeBlackBoxCard: View {
    @ObservedObject private var store = ForgeStore.shared
    @State private var on = ForgeBlackBox.consent
    @State private var caps = ForgeRepairCapabilities()
    @State private var busy = false
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(ForgeBlackBoxText.toggle, isOn: Binding(get: { on }, set: { change($0) })).font(.subheadline.bold()).disabled(busy || (!on && !caps.blackbox))
            ForgeFeatureGuide(.blackbox)
            Text(ForgeBlackBoxText.privacy).font(.caption2).foregroundStyle(.white.opacity(0.6)).fixedSize(horizontal: false, vertical: true)
            if !caps.blackbox && !on { Text(ForgeBlackBoxText.unavailable).font(.caption2).foregroundStyle(.orange) }
            if let error { Text(error).font(.caption2).foregroundStyle(.orange) }
        }
        .padding(14).foregroundStyle(.white).appsGlass(cornerRadius: MirsaRadius.l)
        .task { caps = await ForgeRepairGate.fetch() }
    }
    private func change(_ v: Bool) {
        guard !busy else { return }; busy = true; error = nil
        Task { @MainActor in
            defer { busy = false }
            if v { do { try await ForgeBlackBox.enable(store: store); on = true } catch { self.error = error.localizedDescription; on = false } }
            else { await ForgeBlackBox.disable(); on = false }
        }
    }
}
