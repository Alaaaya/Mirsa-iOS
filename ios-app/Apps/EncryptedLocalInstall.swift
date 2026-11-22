import Foundation
import UIKit

/// Cellular handoff for an App Store IPA. The original archive is served only
/// over loopback. Only public app metadata and a loopback URL reach the manifest
/// broker, never the IPA, SINF, purchase metadata or Apple account.
@MainActor
enum EncryptedLocalInstall {
    private static var active: LocalOTAServer?
    enum Failure: LocalizedError {
        case message(String)
        case pending(String)
        var errorDescription: String? {
            switch self {
            case .message(let text): return text
            case .pending(let text): return text
            }
        }
    }

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

    static var submitted: String {
        localized(
            "Sent to iOS for installation. Check the Home Screen for progress.",
            "انبعت لـiOS للتثبيت. تابع التقدم عالشاشة الرئيسية.",
            "Zur Installation an iOS übergeben. Prüfe den Fortschritt auf dem Home-Bildschirm.",
            "بۆ دامەزراندن نێردرا بۆ iOS. پێشکەوتن لە شاشەی سەرەکی ببینە.",
            "Ji bo sazkirinê ji iOS re hat şandin. Pêşveçûnê li ekrana sereke bibîne.")
    }

    static var unconfirmed: String {
        localized(
            "Installation is not confirmed yet. Check the Home Screen before trying again.",
            "التثبيت لسه مو مؤكّد. شوف الشاشة الرئيسية قبل ما تعيد المحاولة.",
            "Die Installation ist noch nicht bestätigt. Prüfe vor einem erneuten Versuch den Home-Bildschirm.",
            "دامەزراندن هێشتا پشتڕاست نەکراوەتەوە. پێش هەوڵدانەوە شاشەی سەرەکی بپشکنە.",
            "Sazkirin hîn nehat piştrastkirin. Berî dubarekirinê ekrana sereke kontrol bike.")
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
                        if ProcessInfo.processInfo.systemUptime - attempt.started >= 10 {
                            attempt.finish(.failure(Failure.pending(unconfirmed)))
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
                    do { try await Task.sleep(nanoseconds: 10_000_000_000) }
                    catch { return }
                    attempt.finish(.failure(Failure.pending(unconfirmed)))
                }
            }
        } onCancel: { Task { @MainActor in attempt.finish(.failure(CancellationError())) } }
    }

    private static func performHandoff(_ file: URL, attempt: Attempt) async throws {
        let info = try await Task.detached(priority: .userInitiated) { try identity(in: file) }.value
        try Task.checkCancellation()
        switch presence(bundleID: info.bundleID) {
        case .installed: throw Failure.message(replacementWarning)
        case .unknown:
            // An inconclusive presence query is not a failure or proof of absence.
            // Submit unchanged bytes to iOS, which retains all system prompts and
            // signature/license checks. Never delete an existing app or its data.
            break
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
            throw Failure.message(tr(
                "The local installation manifest is unavailable. Nothing was uploaded. Try again, or use Wi-Fi with LocalDevVPN.",
                "ملف التثبيت المحلي مو متاح. ما رفعنا شي. جرّب مرة تانية، أو استخدم الواي فاي مع LocalDevVPN."))
        }
        try Task.checkCancellation()
        let target = try OTAInstallLink.make(manifestURL: manifest)
        guard await UIApplication.shared.open(target) else {
            throw Failure.message(tr("iOS could not open the installer. Nothing was uploaded.",
                "iOS ما فتح المثبّت. ما رفعنا شي."))
        }
        // Keep the exact source file alive in its existing library. Do not
        // replace an earlier local server until iOS has accepted this handoff.
        let requested = await withTaskCancellationHandler {
            await server.awaitFirstRequest(timeout: 10)
        } onCancel: { server.stop() }
        try Task.checkCancellation()
        guard requested else { throw Failure.pending(unconfirmed) }
        active?.stop()
        active = server
        handedOff = true
    }
}

@_silgen_name("MirsaInstalledBundleState")
private func MirsaInstalledBundleState(_ bundleID: UnsafePointer<CChar>) -> Int32
