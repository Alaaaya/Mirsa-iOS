import Foundation
import UIKit

/// Cellular handoff for an App Store IPA. The original archive is served only
/// over loopback. Only public app metadata and a loopback URL reach the manifest
/// broker, never the IPA, SINF, purchase metadata or Apple account.
@MainActor
enum EncryptedLocalInstall {
    private static var active: LocalOTAServer?

    struct Identity: Equatable {
        let bundleID: String
        let version: String
        let title: String
    }

    nonisolated static func identity(in file: URL) throws -> Identity {
        let bytes = try Data(contentsOf: file, options: .mappedIfSafe)
        let zip = try ZipReader(data: bytes)
        let candidates = zip.entries.filter {
            let parts = $0.name.split(separator: "/", omittingEmptySubsequences: false)
            return parts.count == 3 && parts[0] == "Payload" &&
                parts[1].hasSuffix(".app") && parts[2] == "Info.plist"
        }
        guard candidates.count == 1, let entry = candidates.first,
              entry.uncompressedSize <= 2 * 1024 * 1024,
              let info = try PropertyListSerialization.propertyList(
                from: zip.read(entry, length: entry.uncompressedSize), format: nil) as? [String: Any],
              let id = info["CFBundleIdentifier"] as? String, !id.isEmpty,
              let version = info["CFBundleVersion"] as? String, !version.isEmpty else {
            throw EncryptedIPAError.noInfo
        }
        return Identity(bundleID: id, version: version,
            title: (info["CFBundleDisplayName"] as? String) ?? (info["CFBundleName"] as? String) ?? id)
    }

    /// Success means iOS started fetching the untouched archive, not that it
    /// installed or accepted its FairPlay license. There is NO upload fallback.
    static func handoff(_ file: URL) async throws {
        let info = try await Task.detached(priority: .userInitiated) { try identity(in: file) }.value
        try Task.checkCancellation()
        let size = Int64(try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0)
        let server = try LocalOTAServer(file: file)
        var handedOff = false
        defer { if !handedOff { server.stop(); if active === server { active = nil } } }
        let background = UIApplication.shared.beginBackgroundTask(withName: "Mirsa App Store local install") { server.stop() }
        let backgroundBox = OTABackgroundBox(background)
        server.onStop = { backgroundBox.end() }
        let port = try await server.start()
        guard let base = CertificateOTA.localManifestEndpoint,
              let manifest = LocalOTAManifest.url(base: base, port: port, token: server.token,
                bundleID: info.bundleID, version: info.version, title: info.title, bytes: size),
              await LocalOTAManifest.preflight(manifest, port: port) else {
            throw SideloadError.message(tr(
                "The local installation manifest is unavailable. Nothing was uploaded. Try again, or use Wi-Fi with LocalDevVPN.",
                "ملف التثبيت المحلي مو متاح. ما رفعنا شي. جرّب مرة تانية، أو استخدم الواي فاي مع LocalDevVPN."))
        }
        try Task.checkCancellation()
        let target = try OTAInstallLink.make(manifestURL: manifest)
        guard await UIApplication.shared.open(target) else {
            throw SideloadError.message(tr("iOS could not open the installer. Nothing was uploaded.",
                "iOS ما فتح المثبّت. ما رفعنا شي."))
        }
        // Keep the exact source file alive in its existing library. Do not
        // replace an earlier local server until iOS has accepted this handoff.
        let requested = await withTaskCancellationHandler {
            await server.awaitFirstRequest(timeout: 60)
        } onCancel: { server.stop() }
        try Task.checkCancellation()
        guard requested else {
            throw SideloadError.message(tr(
                "iOS did not request the app. Keep Mirsa open, confirm Install, and try again. Nothing was uploaded. This method cannot replace an App Store-installed copy; use Wi-Fi with LocalDevVPN to keep its data.",
                "iOS ما طلب التطبيق. خلّي مرسى مفتوح وأكّد التثبيت وجرّب تاني. ما رفعنا شي. هالطريقة ما بتستبدل نسخة مثبتة من المتجر؛ استخدم الواي فاي مع LocalDevVPN لتحافظ على بياناتها."))
        }
        active?.stop()
        active = server
        handedOff = true
    }
}
