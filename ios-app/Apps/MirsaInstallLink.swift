import SwiftUI
import CoreImage.CIFilterBuiltins

/// Explicit opt-in upload of the signed IPA only. No keychain or signing material access.
@MainActor enum MirsaInstallLink {
    struct Link {
        let shareURL: URL
        let expiresAt: Date
    }
    static func create(signedIPA: URL) async throws -> Link {
        let metadata: [String: Any] = try await Task.detached {
            let staged = try CertificateInstall.stageSignedApp(ipa: signedIPA, in: FileManager.default.temporaryDirectory)
            defer { try? FileManager.default.removeItem(at: staged.stage) }
            guard FileManager.default.fileExists(atPath: staged.app.appendingPathComponent("_CodeSignature/CodeResources").path) else {
                throw SideloadError.message(linkText("Choose a signed IPA.", "اختار IPA موقّع.", "IPAی واژۆکراو هەڵبژێرە.", "IPA ya îmzekirî hilbijêre."))
            }
            let info = try IPAEditorService.info(in: staged.app)
            guard let id = info["CFBundleIdentifier"] as? String, let version = info["CFBundleVersion"] as? String else {
                throw SideloadError.message("Missing application identity.")
            }
            let bytes = try signedIPA.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            return ["bundleID": id, "version": version, "title": (info["CFBundleDisplayName"] as? String) ?? (info["CFBundleName"] as? String) ?? id, "bytes": bytes]
        }.value
        let bytes = try Data(contentsOf: signedIPA, options: .mappedIfSafe)
        guard bytes.count <= 30 * 1024 * 1024 else { throw SideloadError.message("OTA: 30 MB maximum.") }
        let auth = DiscoveryAuthClient(projectURL: URL(string: WebBackendConfig.defaultProject)!,
            publishableKey: WebBackendConfig.defaultPublishableKey, store: KeychainSessionStore(), http: SafeMetadataHTTP())
        let token = try await auth.token(forceRefresh: false)
        var request = URLRequest(url: CertificateOTA.endpoint, timeoutInterval: 120)
        request.httpMethod = "POST"
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        request.setValue(String(bytes.count), forHTTPHeaderField: "Content-Length")
        request.setValue("172800", forHTTPHeaderField: "x-mirsa-lifetime")
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        request.setValue(String(decoding: try JSONSerialization.data(withJSONObject: metadata), as: UTF8.self).addingPercentEncoding(withAllowedCharacters: allowed), forHTTPHeaderField: "x-mirsa-metadata")
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        let session = URLSession(configuration: config, delegate: OTANoRedirect(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (data, response) = try await session.upload(for: request, from: bytes)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let result = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let raw = result["shareURL"] as? String, let url = URL(string: raw),
              url.scheme == "https", url.host == "alaaaya.github.io",
              url.path == "/Mirsa-iOS/install.html", url.user == nil, url.password == nil, url.query == nil,
              let fragment = url.fragment,
              let parts = URLComponents(string: "https://local.invalid/?" + fragment),
              let bearer = parts.queryItems?.first(where: { $0.name == "token" })?.value,
              bearer.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil,
              let expiry = result["expiresAt"] as? String,
              let expires = parseDate(expiry), expires > Date(),
              expires.timeIntervalSinceNow <= 172860 else {
            throw SideloadError.message(linkText("Link unavailable. Check your session or upload quota.", "الرابط مو متاح. تأكد من تسجيل الدخول وحد الرفع.", "بەستەر بەردەست نییە. چوونەژوورەوە و سنووری بارکردن بپشکنە.", "Girêdan ne berdest e. Têketin û sînorê barkirinê kontrol bike."))
        }
        return Link(shareURL: url, expiresAt: expires)
    }
    private static func parseDate(_ value: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
}
private func linkText(_ en: String, _ ar: String, _ ckb: String, _ kmr: String) -> String {
    switch L.lang { case .english: return en; case .arabic: return ar; case .sorani: return ckb; case .kurmanji: return kmr }
}

/// Embed for an existing signed export, never for an unsigned configuration export.
struct MirsaInstallLinkView: View {
    let signedIPA: URL
    @State private var link: MirsaInstallLink.Link?
    @State private var busy = false
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(linkText("48-hour install link", "رابط تثبيت ٤٨ ساعة", "بەستەری دامەزراندنی ٤٨ کاتژمێر", "Girêdana sazkirinê ya 48 saetan"), systemImage: "qrcode").font(.headline)
            Text(linkText("Uploads the signed IPA, never your certificate or private key. Anyone with the link can download it until expiry. Device and certificate restrictions still apply.",
                          "بيرفع IPA الموقّع بس، مو شهادتك أو مفتاحك الخاص. أي حدا معه الرابط بيقدر ينزّله لحد انتهاء المدة. شروط الجهاز والشهادة بتضل مطبّقة.",
                          "تەنها IPAی واژۆکراو بار دەکرێت، نە بڕوانامە و کلیلی تایبەت. هەرکەس بەستەرەکەی هەبێت دەتوانێت تا بەسەرچوون دایبگرێت. سنووری ئامێر و بڕوانامە هەر دەمێنن.",
                          "Tenê IPA ya îmzekirî tê barkirin, ne sertîfîka an mifteya taybet. Kesê ku girêdan hebe dikare heta qedandinê daxîne. Sînorên amûr û sertîfîkayê dimînin.")).font(.caption).foregroundStyle(.secondary)
            if busy { ProgressView() }
            if let link {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    if link.expiresAt > context.date {
                        if let image = qr(link.shareURL) {
                            Image(uiImage: image).interpolation(.none).resizable().scaledToFit().frame(width: 220, height: 220).padding(12).background(.white)
                                .accessibilityLabel("QR")
                        }
                        ShareLink(item: link.shareURL) { Label(linkText("Share link", "مشاركة الرابط", "هاوبەشکردنی بەستەر", "Girêdanê parve bike"), systemImage: "square.and.arrow.up") }
                        Text(link.expiresAt, style: .date).font(.caption)
                        Text(link.expiresAt, style: .time).font(.caption)
                    } else {
                        Text(linkText("Link expired", "انتهت صلاحية الرابط", "بەستەر بەسەرچوو", "Girêdan qediya"))
                    }
                }
            }
            if let error { Text(error).font(.caption).foregroundStyle(.orange) }
            Button(linkText("Create link", "إنشاء رابط", "بەستەر دروست بکە", "Girêdanê çêke")) {
                busy = true; error = nil; link = nil
                Task {
                    do { link = try await MirsaInstallLink.create(signedIPA: signedIPA) }
                    catch { self.error = error.localizedDescription }
                    busy = false
                }
            }.buttonStyle(.borderedProminent).disabled(busy)
        }.padding(18).background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))
            .environment(\.layoutDirection, .leftToRight)
    }
    private func qr(_ url: URL) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(url.absoluteString.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage,
              let image = CIContext().createCGImage(output.transformed(by: CGAffineTransform(scaleX: 8, y: 8)), from: output.extent.applying(CGAffineTransform(scaleX: 8, y: 8))) else { return nil }
        return UIImage(cgImage: image)
    }
}

struct MirsaProjectInstallLink: View {
    let projectID: UUID
    let latest: URL?
    private var signed: URL? {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("MirsaSignedExports")
        if let latest, let safe = try? PersonalProjectFolder.validated(latest, in: root) { return safe }
        guard let relative = UserDefaults.standard.string(forKey: "mirsa.project.signed." + projectID.uuidString) else { return nil }
        return try? PersonalProjectFolder.validated(root.appendingPathComponent(relative), in: root)
    }
    var body: some View {
        if let signed { MirsaInstallLinkView(signedIPA: signed).id(signed.path) }
    }
}
