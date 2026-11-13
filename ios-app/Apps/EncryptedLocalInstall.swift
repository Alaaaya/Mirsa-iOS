import Foundation
import UIKit

/// Cellular handoff for an App Store IPA. The original archive is served only
/// over loopback. Only public app metadata and a loopback URL reach the manifest
/// broker, never the IPA, SINF, purchase metadata or Apple account.
@MainActor
enum EncryptedLocalInstall {
    private static var active: LocalOTAServer?

    /// One bounded attempt. Detached callbacks can only finish their own gate.
    @MainActor private final class Attempt {
        var continuation: CheckedContinuation<Void, Error>?
        var worker: Task<Void, Never>?
        var timer: Task<Void, Never>?
        var stop: (() -> Void)?
        var finished = false
        var foreground: NSObjectProtocol?
        let started = ProcessInfo.processInfo.systemUptime
        func finish(_ result: Result<Void, Error>) {
            guard !finished else { return }
            finished = true
            timer?.cancel()
            if let foreground { NotificationCenter.default.removeObserver(foreground) }
            foreground = nil
            if case .failure = result { worker?.cancel(); stop?() }
            let pending = continuation
            continuation = nil
            pending?.resume(with: result)
        }
    }

    static var unconfirmed: String {
        localized(
            "Installation could not be confirmed. The install button is available again. Check the Home Screen; if the app is already installed, use Wi-Fi + LocalDevVPN to replace it without deleting its data.",
            "ما قدرنا نتأكد من التثبيت. زر التثبيت رجع اشتغل. شوف الشاشة الرئيسية؛ إذا التطبيق موجود، استخدم الواي فاي مع LocalDevVPN لتستبدله بدون حذف بياناته.",
            "Die Installation konnte nicht bestätigt werden. Die Installationstaste ist wieder verfügbar. Prüfe den Home-Bildschirm; nutze bei einer vorhandenen App WLAN + LocalDevVPN, um ihre Daten zu behalten.",
            "دامەزراندن پشتڕاست نەکرایەوە. دوگمەی دامەزراندن دووبارە بەردەستە. شاشەی سەرەکی بپشکنە؛ بۆ ئەپی هەبوو Wi-Fi + LocalDevVPN بەکاربهێنە بۆ پاراستنی داتا.",
            "Sazkirin nehat piştrastkirin. Bişkojka sazkirinê dîsa amade ye. Ekrana sereke kontrol bike; ji bo sepana heyî Wi-Fi + LocalDevVPN bikar bîne da dane neyên jêbirin.")
    }

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
        let consent = Consent()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                consent.continuation = continuation
                guard !Task.isCancelled else { consent.finish(false); return }
                let alert = UIAlertController(title: "Mirsa", message: unknownWarning, preferredStyle: .alert)
                consent.alert = alert
                alert.addAction(UIAlertAction(title: localized("Cancel", "إلغاء", "Abbrechen", "پاشگەزبوونەوە", "Betal bike"), style: .cancel) { _ in consent.finish(false) })
                alert.addAction(UIAlertAction(title: localized("Continue fresh install", "كمّل تثبيت جديد", "Neuinstallation fortsetzen", "بەردەوام بە لە دامەزراندنی نوێ", "Sazkirina nû bidomîne"), style: .default) { _ in consent.finish(true) })
                controller.present(alert, animated: true)
            }
        } onCancel: { Task { @MainActor in consent.finish(false) } }
        #else
        return await CellularConsentFixture.confirm()
        #endif
    }

    #if canImport(UIKit)
    @MainActor private final class Consent {
        var continuation: CheckedContinuation<Bool, Never>?
        weak var alert: UIAlertController?
        func finish(_ allow: Bool) {
            guard let pending = continuation else { return }
            continuation = nil
            alert?.dismiss(animated: true)
            pending.resume(returning: allow)
        }
    }
    #endif

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
        let attempt = Attempt()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                attempt.continuation = continuation
                guard !Task.isCancelled else { attempt.finish(.failure(CancellationError())); return }
                #if canImport(UIKit)
                attempt.foreground = NotificationCenter.default.addObserver(
                    forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
                ) { _ in
                    Task { @MainActor in
                        if ProcessInfo.processInfo.systemUptime - attempt.started >= 30 {
                            attempt.finish(.failure(SideloadError.message(unconfirmed)))
                        }
                    }
                }
                #endif
                attempt.worker = Task {
                    do {
                        try await performHandoff(file, attempt: attempt)
                        attempt.finish(.success(()))
                    } catch { attempt.finish(.failure(error)) }
                }
                attempt.timer = Task {
                    do { try await Task.sleep(nanoseconds: 30_000_000_000) }
                    catch { return }
                    attempt.finish(.failure(SideloadError.message(unconfirmed)))
                }
            }
        } onCancel: { Task { @MainActor in attempt.finish(.failure(CancellationError())) } }
    }

    private static func performHandoff(_ file: URL, attempt: Attempt) async throws {
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
        attempt.stop = { server.stop() }
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
            await server.awaitFirstRequest(timeout: 30)
        } onCancel: { server.stop() }
        try Task.checkCancellation()
        guard requested else { throw SideloadError.message(unconfirmed) }
        active?.stop()
        active = server
        handedOff = true
    }
}

@_silgen_name("MirsaInstalledBundleState")
private func MirsaInstalledBundleState(_ bundleID: UnsafePointer<CChar>) -> Int32
