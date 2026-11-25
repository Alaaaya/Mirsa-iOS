import Foundation
import SwiftUI
import Security

/// Owner test-build only. A short-lived, staging-scoped JWT plus the staging endpoint, imported
/// explicitly by the owner and kept in the Keychain. No provider key, signing secret or prod session
/// is ever accepted, and nothing from here is embedded in an app or IPA.
struct RuntimeStagingSession: Codable, Equatable {
    var endpoint: String
    var token: String
    var expiresAt: Date

    static let allowedHost = "willingly-dejectedly-superb-neanderthal.kitten.space"
    static let pathPrefix = "/runtime-translate-"
    static let issuer = "urn:mirsa:runtime-staging25"
    static let audience = "mirsa-runtime-staging25"
    static let maxLifetime: TimeInterval = 3600

    enum Failure: Error, Equatable { case format, endpoint, token, expired }

    /// Import text is either JSON {"endpoint","accessToken"|"token"} or "endpoint token".
    static func parse(_ text: String, now: Date = Date()) throws -> RuntimeStagingSession {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var endpoint: String?, token: String?
        if let data = trimmed.data(using: .utf8), let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
            endpoint = obj["endpoint"] as? String
            token = (obj["accessToken"] as? String) ?? (obj["token"] as? String)
        } else {
            let parts = trimmed.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" }).map(String.init)
            if parts.count == 2 { endpoint = parts[0]; token = parts[1] }
        }
        guard let endpoint, let token else { throw Failure.format }
        guard let url = URL(string: endpoint), url.scheme == "https", url.host?.lowercased() == allowedHost, url.port == nil,
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
              url.path.hasPrefix(pathPrefix), url.path.count > pathPrefix.count + 8 else { throw Failure.endpoint }
        let exp = try validate(token: token, now: now)
        return RuntimeStagingSession(endpoint: endpoint, token: token, expiresAt: exp)
    }

    /// Structural check only (the server verifies the signature): staging issuer and audience, bounded exp.
    static func validate(token: String, now: Date) throws -> Date {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3, token.count < 4096 else { throw Failure.token }
        var b64 = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while b64.count % 4 != 0 { b64 += "=" }
        guard let data = Data(base64Encoded: b64), let claims = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              claims["iss"] as? String == issuer, let exp = (claims["exp"] as? NSNumber)?.doubleValue else { throw Failure.token }
        let aud = claims["aud"]
        guard (aud as? String) == audience || ((aud as? [String])?.contains(audience) == true) else { throw Failure.token }
        guard let iat = (claims["iat"] as? NSNumber)?.doubleValue, iat <= now.timeIntervalSince1970 + 60, exp - iat > 0, exp - iat <= maxLifetime else { throw Failure.token }
        let date = Date(timeIntervalSince1970: exp)
        guard date > now else { throw Failure.expired }
        guard date.timeIntervalSince(now) <= maxLifetime else { throw Failure.token }
        return date
    }

    var isValid: Bool { expiresAt > Date().addingTimeInterval(30) }
}

enum RuntimeStagingSessionStore {
    private static let service = "com.alaa.mirsa.runtime.staging.session"
    private static var base: [String: Any] { [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service] }
    static func load(now: Date = Date()) -> RuntimeStagingSession? {
        var q = base; q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data,
              let s = try? JSONDecoder().decode(RuntimeStagingSession.self, from: d), s.expiresAt > now else { return nil }
        return s
    }
    static func save(_ s: RuntimeStagingSession?) {
        SecItemDelete(base as CFDictionary)
        guard let s, let d = try? JSONEncoder().encode(s) else { return }
        var add = base
        add[kSecValueData as String] = d
        add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
    }
    /// The owner import UI is only offered when this build opts in via Info.plist.
    static var importEnabled: Bool { (Bundle.main.object(forInfoDictionaryKey: "MirsaRuntimeStagingImport") as? Bool) == true }
}

struct RuntimeStagingTokenProvider: DiscoveryTokenProvider {
    let session: RuntimeStagingSession
    func token(forceRefresh: Bool) async throws -> String {
        guard session.isValid else { throw RuntimeTranslationError.notConfigured }
        return session.token
    }
}

/// Owner test-build row: imports a short-lived staging session so the translate toggle can reach the staging backend.
struct RuntimeStagingImportRow: View {
    @State private var sheet = false
    @State private var text = ""
    @State private var message: String?
    @State private var active = RuntimeStagingSessionStore.load() != nil
    var body: some View {
        if RuntimeStagingSessionStore.importEnabled {
            VStack(alignment: .leading, spacing: 4) {
                Button { sheet = true } label: {
                    Label(active ? personalText("Staging session active (replace)", "جلسة الاختبار فعّالة (استبدال)") : personalText("Import translation test session", "استيراد جلسة اختبار الترجمة"), systemImage: "key.fill").font(.caption)
                }.accessibilityIdentifier("project-sign-translate-ar-import")
                if let message { Text(message).font(.caption2).foregroundStyle(.secondary).accessibilityIdentifier("project-sign-translate-ar-import-status") }
            }
            .sheet(isPresented: $sheet) {
                NavigationView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(personalText("Paste the staging endpoint and short-lived token (JSON or 'endpoint token'). Only the staging host is accepted.", "الصق عنوان الاختبار والتوكن القصير (JSON أو 'العنوان التوكن'). بس سيرفر الاختبار مقبول.")).font(.footnote)
                        TextEditor(text: $text).font(.system(.footnote, design: .monospaced)).frame(minHeight: 160)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.4)))
                            .autocorrectionDisabled().textInputAutocapitalization(.never).accessibilityIdentifier("project-sign-translate-ar-import-field")
                        Button(personalText("Save", "حفظ")) { save() }.buttonStyle(.borderedProminent).accessibilityIdentifier("project-sign-translate-ar-import-save")
                        Spacer()
                    }.padding()
                    .navigationTitle(personalText("Test session", "جلسة الاختبار")).navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button(personalText("Close", "إغلاق")) { sheet = false } } }
                }
            }
        }
    }
    private func save() {
        do {
            RuntimeStagingSessionStore.save(try RuntimeStagingSession.parse(text))
            text = ""; active = true; sheet = false
            message = personalText("Session saved.", "انحفظت الجلسة.")
        } catch {
            message = personalText("Invalid or expired staging session.", "الجلسة غير صالحة أو منتهية.")
            sheet = false
        }
    }
}
