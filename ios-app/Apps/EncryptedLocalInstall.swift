import Foundation
import UIKit

/// Cellular handoff for an App Store IPA. The original archive is served only
/// over loopback. Only public app metadata and a loopback URL reach the manifest
/// broker, never the IPA, SINF, purchase metadata or Apple account.
@MainActor
enum EncryptedLocalInstall {
    private static var active: LocalOTAServer?

    enum Presence { case installed, unknown }
    static func presence(bundleID: String) -> Presence {
        bundleID.withCString { MirsaInstalledBundleState($0) == 1 ? .installed : .unknown }
    }

    static func localized(_ en: String, _ ar: String, _ de: String, _ ckb: String, _ kmr: String) -> String {
        // Mirsa has four explicit app locales. English fallback on a German
        // device uses German here; Kurdish selection always keeps its script.
        if L.lang == .english, Locale.preferredLanguages.first?.hasPrefix("de") == true { return de }
        return tr(en, ar, ckb: ckb, kmr: kmr)
    }

    static var replacementWarning: String {
        localized(
            "This cellular install method cannot replace an existing copy here. Use Wi-Fi + LocalDevVPN to replace it while keeping its data. Alternatively, delete the app yourself first, but deleting it removes its local data. Mirsa will not delete anything.",
            "طريقة التثبيت عبيانات الموبايل ما بتستبدل النسخة الموجودة هون. استخدم الواي فاي مع LocalDevVPN لتستبدلها وتحافظ على بياناتها. أو احذف التطبيق بنفسك أولاً، بس الحذف بيمسح بياناته المحلية. مرسى ما بيحذف شي.",
            "Diese Installation über mobile Daten kann eine vorhandene Kopie hier nicht ersetzen. Nutze WLAN + LocalDevVPN, um sie unter Beibehaltung ihrer Daten zu ersetzen. Alternativ kannst du die App zuerst selbst löschen; dabei gehen ihre lokalen Daten verloren. Mirsa löscht nichts.",
            "ئەم شێوازە بە داتای مۆبایل ناتوانێت لێرە جێی کۆپییەکی هەبوو بگرێتەوە. Wi-Fi + LocalDevVPN بەکاربهێنە بۆ جێگرتنەوە بە پاراستنی داتاکانی. یان سەرەتا خۆت ئەپەکە بسڕەوە، بەڵام داتای ناوخۆیی دەسڕێتەوە. Mirsa هیچ شتێک ناسڕێتەوە.",
            "Ev awayê sazkirinê bi daneyên mobîl li vir nikare cihê kopiyeke heyî bigire. Ji bo guherandinê bi parastina daneyan Wi-Fi + LocalDevVPN bikar bîne. An pêşî sepanê bixwe jê bibe, lê ev daneyên wê yên herêmî jê dibe. Mirsa tiştekî jê nabe.")
    }

    static var unknownWarning: String {
        localized(
            "Mirsa could not reliably check whether this app is already installed. A fresh install can continue; an existing copy may be rejected by iOS. ",
            "مرسى ما قدر يتأكد إذا التطبيق مثبت من قبل. فيك تكمّل لتثبيت جديد؛ إذا في نسخة موجودة ممكن iOS يرفض. ",
            "Mirsa konnte nicht zuverlässig prüfen, ob diese App bereits installiert ist. Eine Neuinstallation kann fortgesetzt werden; eine vorhandene Kopie kann von iOS abgelehnt werden. ",
            "Mirsa نەیتوانی بە دڵنیایی بزانێت ئەم ئەپە پێشتر دامەزراوە یان نا. دەتوانیت بە دامەزراندنی نوێ بەردەوام بیت؛ iOS لەوانەیە کۆپییەکی هەبوو ڕەت بکاتەوە. ",
            "Mirsa nikarî bi bawerî kontrol bike ka ev sepan berê hatiye sazkirin. Sazkirineke nû dikare bidome; iOS dibe ku kopiyeke heyî red bike. ") + replacementWarning
    }

    static func confirmUnknown() async -> Bool {
        #if canImport(UIKit)
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first(where: { $0.activationState == .foregroundActive }),
              var controller = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController else { return false }
        while let presented = controller.presentedViewController { controller = presented }
        guard !controller.isBeingDismissed, !(controller is UIAlertController) else { return false }
        return await withCheckedContinuation { continuation in
            let alert = UIAlertController(title: "Mirsa", message: unknownWarning, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: localized("Cancel", "إلغاء", "Abbrechen", "پاشگەزبوونەوە", "Betal bike"), style: .cancel) { _ in continuation.resume(returning: false) })
            alert.addAction(UIAlertAction(title: localized("Continue fresh install", "كمّل تثبيت جديد", "Neuinstallation fortsetzen", "بەردەوام بە لە دامەزراندنی نوێ", "Sazkirina nû bidomîne"), style: .default) { _ in continuation.resume(returning: true) })
            controller.present(alert, animated: true)
        }
        #else
        return await CellularConsentFixture.confirm()
        #endif
    }

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
        switch presence(bundleID: info.bundleID) {
        case .installed: throw SideloadError.message(replacementWarning)
        case .unknown:
            guard await confirmUnknown() else { throw CancellationError() }
        }
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

@_silgen_name("MirsaInstalledBundleState")
private func MirsaInstalledBundleState(_ bundleID: UnsafePointer<CChar>) -> Int32
