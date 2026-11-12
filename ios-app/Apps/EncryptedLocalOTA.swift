import Foundation
import SwiftUI
import Security
import UIKit

/// This certificate encrypts loopback transport only. It never signs an app,
/// changes an IPA, or grants the device another account's FairPlay licence.
@MainActor final class EncryptedLocalOTA: ObservableObject {
    static let shared = EncryptedLocalOTA()
    @Published var shown = false
    @Published var busy = false
    @Published var status = ""
    @Published private(set) var profileURL: URL?
    @Published private(set) var installURL: URL?
    private var https: LocalOTAServer?
    private var bootstrap: LocalOTAServer?
    private var background: OTABackgroundBox?
    private var preparing = false
    private struct Material: Codable {
        let p12: String
        let password: String
        let root: String
        let expires: UInt64
    }
    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "mirsa.local-https.v1",
         kSecAttrAccount as String: "device-identity",
         kSecAttrSynchronizable as String: false]
    }
    private static func material() async throws -> Material {
        var q = query; q[kSecReturnData as String] = true
        var item: CFTypeRef?
        if SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess,
           let data = item as? Data,
           let saved = try? JSONDecoder().decode(Material.self, from: data),
           saved.expires > UInt64(Date().timeIntervalSince1970) + 86400 {
            return saved
        }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.complete])
        defer { try? FileManager.default.removeItem(at: dir) }
        let out = dir.appendingPathComponent("identity.json")
        try await Task.detached {
            try IPAEditorService.run("local_tls_identity", input: dir, output: out)
        }.value
        let data = try Data(contentsOf: out)
        let result = try JSONDecoder().decode(Material.self, from: data)
        SecItemDelete(query as CFDictionary)
        var add = query; add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        guard SecItemAdd(add as CFDictionary, nil) == errSecSuccess else {
            throw SideloadError.message("Could not save the local HTTPS identity.")
        }
        return result
    }
    private static func identity(_ material: Material) throws -> SecIdentity {
        guard let bytes = Data(base64Encoded: material.p12) else { throw LocalOTAServer.Failure.start }
        var imported: CFArray?
        let opts = [kSecImportExportPassphrase as String: material.password]
        guard SecPKCS12Import(bytes as CFData, opts as CFDictionary, &imported) == errSecSuccess,
              let rows = imported as? [[String: Any]],
              let value = rows.first?[kSecImportItemIdentity as String] else {
            throw SideloadError.message("Could not load the local HTTPS identity.")
        }
        return value as! SecIdentity
    }
    private static func profile(root: Data) throws -> Data {
        let rootID = UUID().uuidString
        let payload: [String: Any] = [
            "PayloadType": "com.apple.security.root",
            "PayloadVersion": 1, "PayloadIdentifier": "com.mirsa.local.root." + rootID,
            "PayloadUUID": rootID, "PayloadDisplayName": "Mirsa Local Install",
            "PayloadDescription": "On-device HTTPS only. Does not sign apps or configure a proxy or VPN.",
            "PayloadContent": root
        ]
        return try PropertyListSerialization.data(fromPropertyList: [
            "PayloadType": "Configuration", "PayloadVersion": 1,
            "PayloadIdentifier": "com.mirsa.local.install", "PayloadUUID": UUID().uuidString,
            "PayloadDisplayName": "Mirsa Local Install",
            "PayloadDescription": "Trust only this device's local install server. Remove this profile in Settings when no longer needed.",
            "PayloadRemovalDisallowed": false, "PayloadContent": [payload]
        ], format: .xml, options: 0)
    }
    static func manifest(package: URL, entry: EncryptedIPAEntry) throws -> Data {
        try PropertyListSerialization.data(fromPropertyList: [
            "items": [[
                "assets": [["kind": "software-package", "url": package.absoluteString]],
                "metadata": ["bundle-identifier": entry.bundleID, "bundle-version": entry.buildVersion ?? entry.version,
                             "kind": "software", "title": entry.name]
            ]]
        ], format: .xml, options: 0)
    }
    func prepare(_ entry: EncryptedIPAEntry) async {
        guard !preparing else { return }
        preparing = true
        stop(); shown = true; busy = true
        status = personalText("Preparing on-device HTTPS…", "عم حضّر التثبيت المحلي…")
        defer { busy = false; preparing = false }
        do {
            let material = try await Self.material()
            guard let root = Data(base64Encoded: material.root) else { throw LocalOTAServer.Failure.start }
            let file = EncryptedAppsStore.ipaURL(entry.id)
            let server = try LocalOTAServer(file: file, identity: Self.identity(material))
            https = server
            let port = try await server.start()
            let base = "https://mirsa.localtest.me:\(port)/\(server.token)"
            guard let package = URL(string: base + "/Mirsa.ipa"),
                  let manifest = URL(string: base + "/manifest.plist"),
                  let landing = URL(string: base + "/install.html") else { throw LocalOTAServer.Failure.start }
            let target = try OTAInstallLink.make(manifestURL: manifest)
            let escaped = target.absoluteString.replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "\"", with: "&quot;").replacingOccurrences(of: "<", with: "&lt;")
            let html = """
            <!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Mirsa Local Install</title></head>
            <body style="background:#111;color:#eee;font:18px -apple-system;padding:32px">
            <h1>Mirsa</h1><p>Install the original App Store package. iOS checks your purchase.</p>
            <p dir="rtl">ثبّت النسخة الأصلية. iOS بيتأكد من ملكيتك للتطبيق.</p>
            <a style="color:#baf" href="\(escaped)">Install / تثبيت</a></body></html>
            """
            server.setResources([
                "/\(server.token)/manifest.plist": .init(data: try Self.manifest(package: package, entry: entry), contentType: "application/xml"),
                "/\(server.token)/install.html": .init(data: Data(html.utf8), contentType: "text/html; charset=utf-8")
            ])
            let setup = try LocalOTAServer(file: file)
            bootstrap = setup
            setup.setResources(["/\(setup.token)/Mirsa.mobileconfig": .init(data: try Self.profile(root: root), contentType: "application/x-apple-aspen-config")])
            let setupPort = try await setup.start()
            profileURL = URL(string: "http://127.0.0.1:\(setupPort)/\(setup.token)/Mirsa.mobileconfig")
            installURL = landing
            let bg = UIApplication.shared.beginBackgroundTask(withName: "Mirsa original IPA OTA") { [weak self] in
                Task { @MainActor in
                    self?.stop()
                    self?.status = personalText("iOS stopped the local server. Return to Mirsa and try again.", "iOS وقّف السيرفر المحلي. ارجع لمرسى وجرب مرة تانية.")
                }
            }
            let box = OTABackgroundBox(bg); background = box
            server.onStop = { box.end() }
            status = personalText("Ready. Set up local trust once, then open installation. This hands off to iOS; it does not confirm that the app installed.",
                                  "جاهز. فعّل الثقة المحلية أول مرة، بعدين افتح التثبيت. iOS بيقرر إذا بيقبل التطبيق، فتح الصفحة مو تأكيد إنه تثبّت.")
        } catch {
            stop()
            status = AppsStore.friendly(error)
        }
    }
    func openProfile() async {
        guard let profileURL else { return }
        if !(await UIApplication.shared.open(profileURL)) {
            status = personalText("Safari could not open the setup profile.", "ما قدرت افتح بروفايل الإعداد بسفاري.")
        }
    }
    func openInstaller() async {
        guard let installURL, let https, !https.isStopped else {
            status = personalText("The local session expired. Close and try again.", "انتهت الجلسة المحلية. سكّر وجرب من جديد.")
            return
        }
        // Never bypass certificate verification. A normal HTTPS request must
        // succeed with system trust after the user installs/enables the root.
        busy = true; defer { busy = false }
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil; config.urlCredentialStorage = nil
        let session = URLSession(configuration: config, delegate: OTANoRedirect(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        do {
            let (_, response) = try await session.data(for: URLRequest(url: installURL, timeoutInterval: 8))
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw LocalOTAServer.Failure.start }
            guard await UIApplication.shared.open(installURL) else { throw LocalOTAServer.Failure.start }
            status = personalText("Opened Safari. Tap Install. Return here if iOS stops the local server. Installation is not yet confirmed.",
                                  "فتحت سفاري. اضغط تثبيت. إذا iOS وقّف السيرفر ارجع لهون. التثبيت لسا مو مؤكّد.")
        } catch {
            status = personalText("Local HTTPS was not reachable or trusted. Install the profile and enable full trust in Settings, then try again. DNS or device policy may block loopback.",
                                  "الاتصال المحلي ما اشتغل أو الشهادة مو موثوقة. ثبّت البروفايل وفعّل الثقة الكاملة بالإعدادات وجرب. ممكن DNS أو إعدادات الجهاز تمنع الاتصال المحلي.")
        }
    }
    func stop() {
        https?.stop(); bootstrap?.stop()
        https = nil; bootstrap = nil
        background?.end(); background = nil
        profileURL = nil; installURL = nil
    }
}

struct EncryptedLocalOTAView: View {
    @ObservedObject var model = EncryptedLocalOTA.shared
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(personalText("Local install • no signing", "تثبيت محلي • بدون توقيع")).font(.title2.bold())
                    Text(personalText("No Wi-Fi or LocalDevVPN check. The original IPA stays unchanged. First-time setup requires a certificate profile and explicit full trust. iOS still validates your purchase.",
                                      "ما بيطلب Wi-Fi ولا LocalDevVPN. ملف التطبيق بيضل متل ما هو. أول مرة بدك تثبّت بروفايل شهادة وتفعّل الثقة الكاملة بإيدك. iOS بيضل بيتحقق من شرائك."))
                    Text(personalText("The certificate is generated on this device for mirsa.localtest.me only. Its private key never leaves Mirsa; it cannot decrypt the app. Remove Mirsa Local Install in Settings when you no longer need it.",
                                      "الشهادة بتنولد عهالجهاز لاتصال mirsa.localtest.me المحلي بس، ومفتاحها ما بيطلع من مرسى. ما بتفك تشفير التطبيق. احذف Mirsa Local Install من الإعدادات لما ما تعود تحتاجه."))
                        .font(.caption).foregroundStyle(.secondary)
                    Button(personalText("1. Download local certificate profile", "١. نزّل بروفايل الشهادة المحلية")) { Task { await model.openProfile() } }
                        .buttonStyle(.mirsaPrimary).disabled(model.profileURL == nil || model.busy)
                    Text(personalText("Settings > General > VPN & Device Management > Mirsa Local Install > Install. Then Settings > General > About > Certificate Trust Settings > enable full trust for Mirsa Local Install.",
                                      "الإعدادات > عام > VPN وإدارة الجهاز > Mirsa Local Install > تثبيت. بعدين عام > حول > إعدادات الثقة بالشهادات > فعّل الثقة الكاملة لـMirsa Local Install."))
                        .font(.callout)
                    Button(personalText("2. Open installation in Safari", "٢. افتح التثبيت بسفاري")) { Task { await model.openInstaller() } }
                        .buttonStyle(.mirsaPrimary).disabled(model.installURL == nil || model.busy)
                    if model.busy { ProgressView() }
                    Text(model.status).font(.callout).accessibilityIdentifier("encrypted-local-ota-status")
                }.padding(24)
            }
            .navigationTitle("Mirsa Local Install")
            .toolbar { ToolbarItem(placement: .confirmationAction) {
                Button(personalText("Close", "إغلاق")) { model.shown = false }
            }}
        }
        // Keep the bounded server alive when Safari opens; closing this sheet
        // is not an installation-success signal.
    }
}
