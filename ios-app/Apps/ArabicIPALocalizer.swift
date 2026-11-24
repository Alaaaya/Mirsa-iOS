import Foundation
import CryptoKit

// "ترجم للعربي": translates an English-only app's UI strings to Arabic and injects ar.lproj before signing.
// Pure Foundation. Only bounded string values leave the device (never the IPA or file paths).

enum ArabicLocalizationFailure: String, Equatable { case network, busy, rateLimited, invalid, tooLarge, notConfigured, io }

enum ArabicLocalizationOutcome: Equatable {
    case applied(Int)
    case alreadyArabic
    case nothingToTranslate
    case failed(ArabicLocalizationFailure)
}

protocol ArabicTranslating {
    func translate(bundleID: String, version: String, contentHash: String, items: [ArabicIPALocalizer.Item]) async throws -> [String: String]
}

enum ArabicIPALocalizer {
    struct Item: Equatable { let id: String; let text: String }
    struct Slot { let file: Int; let path: [String] }
    struct FilePlan { let bundleDir: URL; let name: String; let root: [String: Any]; let isDict: Bool }
    struct Scan { var files: [FilePlan] = []; var items: [Item] = []; var slots: [String: Slot] = [:]; var hasArabic = false; var contentHash = "" }

    static let maxItems = 1500, maxText = 2000, maxTotal = 150_000, maxFileBytes = 1_048_576, maxDirs = 300, maxEntries = 200_000
    static let skipKeys: Set<String> = ["CFBundleName", "CFBundleDisplayName", "CFBundleSpokenName"]
    static let pluralKeys: Set<String> = ["NSStringLocalizedFormatKey", "zero", "one", "two", "few", "many", "other"]
    static let sourceDirs = ["en.lproj", "English.lproj", "Base.lproj"]

    // Keep in sync with backend/ar-localize/logic.mjs.
    static let tokenRegex = try! NSRegularExpression(pattern: #"%#@\w+@|%(?:\d+\$)?[-+ 0#']*(?:\d+|\*(?:\d+\$)?)?(?:\.(?:\d+|\*(?:\d+\$)?))?(?:hh|h|ll|l|q|L|z|t|j)?[@diouxXeEfFgGaAcCsSp]|%%|\$\{[^}]*\}|\{\{[^}]*\}\}|\{[^{}]*\}|</?[A-Za-z][^<>]*>|\\[nrt]"#)

    static func tokens(_ s: String) -> [String] {
        let ns = s as NSString
        return tokenRegex.matches(in: s, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range) }
    }

    static func acceptable(source: String, translated: String) -> Bool {
        let t = translated.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, t.count <= maxText * 2 else { return false }
        if translated.unicodeScalars.contains(where: { $0.value < 0x20 && $0.value != 0x09 && $0.value != 0x0A && $0.value != 0x0D }) { return false }
        let original = tokens(source), replacement = tokens(translated)
        guard original.sorted() == replacement.sorted() else { return false }
        let consumesArgument: (String) -> Bool = { $0.hasPrefix("%") && $0 != "%%" }
        let args = original.filter(consumesArgument)
        let allExplicit = args.allSatisfy {
            $0.range(of: #"^%[1-9][0-9]*\$"#, options: .regularExpression) != nil &&
            $0.range(of: #"\*(?![1-9][0-9]*\$)"#, options: .regularExpression) == nil
        }
        return allExplicit || args == replacement.filter(consumesArgument)
    }

    static func worthTranslating(_ s: String) -> Bool {
        guard s.count <= maxText, !s.isEmpty else { return false }
        if s.range(of: #"^[a-z][a-z0-9+.\-]*://"#, options: .regularExpression) != nil { return false }
        let stripped = tokenRegex.stringByReplacingMatches(in: s, range: NSRange(location: 0, length: (s as NSString).length), withTemplate: "")
        return stripped.range(of: #"[A-Za-z]{2,}"#, options: .regularExpression) != nil
    }

    static func isArabicDir(_ name: String) -> Bool {
        let n = name.lowercased()
        return n == "ar.lproj" || n == "arabic.lproj" || (n.hasPrefix("ar-") && n.hasSuffix(".lproj")) || (n.hasPrefix("ar_") && n.hasSuffix(".lproj"))
    }

    // MARK: Scan

    static func scan(app: URL) throws -> Scan {
        let fm = FileManager.default
        let appPath = app.standardizedFileURL.path
        var found: [URL: [String]] = [:]   // bundle dir -> source lproj names
        var arabicIn: Set<URL> = []
        var entries = 0, dirs = 0
        guard let en = fm.enumerator(at: app, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey], options: []) else { throw CocoaError(.fileReadUnknown) }
        for case let u as URL in en {
            entries += 1
            guard entries <= maxEntries else { throw CocoaError(.fileReadTooLarge) }
            let v = try u.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            if v.isSymbolicLink == true { en.skipDescendants(); continue }
            guard v.isDirectory == true else { continue }
            let name = u.lastPathComponent
            guard name.hasSuffix(".lproj") else { continue }
            en.skipDescendants()
            let parent = u.deletingLastPathComponent().standardizedFileURL
            guard parent.path == appPath || parent.path.hasPrefix(appPath + "/") else { continue }
            if isArabicDir(name) { arabicIn.insert(parent); continue }
            if sourceDirs.contains(name) { dirs += 1; guard dirs <= maxDirs else { throw CocoaError(.fileReadTooLarge) }; found[parent, default: []].append(name) }
        }
        var scan = Scan()
        scan.hasArabic = arabicIn.contains(app.standardizedFileURL)
        if scan.hasArabic { return scan }
        var total = 0
        for parent in found.keys.sorted(by: { $0.path < $1.path }) {
            if arabicIn.contains(parent) { continue }
            guard let chosen = sourceDirs.first(where: { found[parent]!.contains($0) }) else { continue }
            let dir = parent.appendingPathComponent(chosen, isDirectory: true)
            let names = ((try? fm.contentsOfDirectory(atPath: dir.path)) ?? []).sorted()
            for file in names where file.hasSuffix(".strings") || file.hasSuffix(".stringsdict") {
                let url = dir.appendingPathComponent(file)
                let rv = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .isSymbolicLinkKey])
                guard rv?.isRegularFile == true, rv?.isSymbolicLink != true, (rv?.fileSize ?? Int.max) <= maxFileBytes,
                      let data = try? Data(contentsOf: url),
                      let plist = (try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)) as? [String: Any] else { continue }
                let isDict = file.hasSuffix(".stringsdict")
                let fileIndex = scan.files.count
                var local: [(String, [String])] = []
                if isDict { collect(plist, path: [], into: &local) }
                else { for (k, v) in plist where v is String && !skipKeys.contains(k) { local.append((v as! String, [k])) } }
                local = local.filter { worthTranslating($0.0) }.sorted { $0.1.joined(separator: "\u{1}") < $1.1.joined(separator: "\u{1}") }
                guard !local.isEmpty else { continue }
                scan.files.append(FilePlan(bundleDir: parent, name: file, root: plist, isDict: isDict))
                for (n, entry) in local.enumerated() {
                    total += entry.0.count
                    guard scan.items.count < maxItems, total <= maxTotal else { throw CocoaError(.fileReadTooLarge) }
                    let id = "\(fileIndex).\(n)"
                    scan.items.append(Item(id: id, text: entry.0))
                    scan.slots[id] = Slot(file: fileIndex, path: entry.1)
                }
            }
        }
        var hasher = SHA256()
        for f in scan.files { hasher.update(data: Data((f.bundleDir.path.replacingOccurrences(of: appPath, with: "") + "|" + f.name + "\n").utf8)) }
        for i in scan.items { hasher.update(data: Data((i.id + "\u{0}" + i.text + "\u{1}").utf8)) }
        scan.contentHash = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        return scan
    }

    private static func collect(_ node: Any, path: [String], into out: inout [(String, [String])]) {
        guard let dict = node as? [String: Any] else { return }
        for (k, v) in dict {
            if let s = v as? String { if pluralKeys.contains(k) { out.append((s, path + [k])) } }
            else { collect(v, path: path + [k], into: &out) }
        }
    }

    private static func setting(_ node: Any, path: ArraySlice<String>, value: String) -> Any? {
        guard var dict = node as? [String: Any], let head = path.first, let child = dict[head] else { return nil }
        if path.count == 1 { guard child is String else { return nil }; dict[head] = value; return dict }
        guard let updated = setting(child, path: path.dropFirst(), value: value) else { return nil }
        dict[head] = updated
        return dict
    }

    // MARK: Apply

    static func localize(app: URL, bundleID: String, version: String, translator: ArabicTranslating) async -> ArabicLocalizationOutcome {
        let scan: Scan
        do { scan = try self.scan(app: app) } catch { return .failed(error is CocoaError && (error as! CocoaError).code == .fileReadTooLarge ? .tooLarge : .io) }
        if scan.hasArabic { return .alreadyArabic }
        guard !scan.items.isEmpty else { return .nothingToTranslate }
        let raw: [String: String]
        do { raw = try await translator.translate(bundleID: bundleID, version: version, contentHash: scan.contentHash, items: scan.items) }
        catch let e as ArabicTranslationError { return .failed(e.failure) }
        catch { return .failed(.network) }
        var good: [String: String] = [:]
        for item in scan.items { if let t = raw[item.id], acceptable(source: item.text, translated: t) { good[item.id] = t.trimmingCharacters(in: .whitespacesAndNewlines) } }
        guard good.count * 10 >= scan.items.count * 6 else { return .failed(.invalid) }
        return write(scan: scan, translations: good, app: app)
    }

    static func write(scan: Scan, translations: [String: String], app: URL) -> ArabicLocalizationOutcome {
        let fm = FileManager.default
        let stage = app.deletingLastPathComponent().appendingPathComponent("ar-stage-" + UUID().uuidString, isDirectory: true)
        var created: [URL] = []
        let infoURL = app.appendingPathComponent("Info.plist")
        let originalInfo = try? Data(contentsOf: infoURL)
        func rollback() {
            for u in created { try? fm.removeItem(at: u) }
            if let originalInfo { try? originalInfo.write(to: infoURL, options: .atomic) }
            try? fm.removeItem(at: stage)
        }
        do {
            try fm.createDirectory(at: stage, withIntermediateDirectories: true)
            var byBundle: [URL: [Int]] = [:]
            for (i, f) in scan.files.enumerated() { byBundle[f.bundleDir, default: []].append(i) }
            var count = 0
            var staged: [(URL, URL)] = []
            for (n, bundle) in byBundle.keys.sorted(by: { $0.path < $1.path }).enumerated() {
                let lproj = stage.appendingPathComponent("\(n)", isDirectory: true).appendingPathComponent("ar.lproj", isDirectory: true)
                try fm.createDirectory(at: lproj, withIntermediateDirectories: true)
                for fi in byBundle[bundle]! {
                    var root: Any = scan.files[fi].root
                    for item in scan.items where scan.slots[item.id]!.file == fi {
                        guard let t = translations[item.id] else { continue }
                        guard let updated = setting(root, path: scan.slots[item.id]!.path[...], value: t) else { rollback(); return .failed(.invalid) }
                        root = updated; count += 1
                    }
                    let data = try PropertyListSerialization.data(fromPropertyList: root, format: .xml, options: 0)
                    try data.write(to: lproj.appendingPathComponent(scan.files[fi].name), options: .atomic)
                }
                staged.append((lproj, bundle.appendingPathComponent("ar.lproj", isDirectory: true)))
            }
            for (from, to) in staged {
                guard !fm.fileExists(atPath: to.path) else { continue }
                try fm.moveItem(at: from, to: to); created.append(to)
            }
            try addLocalization(infoURL)
            try? fm.removeItem(at: stage)
            return .applied(count)
        } catch { rollback(); return .failed(.io) }
    }

    /// Adds "ar" to CFBundleLocalizations only when the key already exists. Preserves the plist format.
    static func addLocalization(_ infoURL: URL) throws {
        let data = try Data(contentsOf: infoURL)
        var format = PropertyListSerialization.PropertyListFormat.xml
        guard var plist = try PropertyListSerialization.propertyList(from: data, options: [], format: &format) as? [String: Any],
              var list = plist["CFBundleLocalizations"] as? [String], !list.contains("ar") else { return }
        list.append("ar"); plist["CFBundleLocalizations"] = list
        try PropertyListSerialization.data(fromPropertyList: plist, format: format, options: 0).write(to: infoURL, options: .atomic)
    }
}

struct ArabicTranslationError: Error { let failure: ArabicLocalizationFailure }

/// Calls the owner's Supabase edge function with the per-install anonymous JWT.
struct ArabicBackendTranslator: ArabicTranslating {
    var tokenProvider: DiscoveryTokenProvider? = nil
    static let endpoint = URL(string: WebBackendConfig.defaultProject + "/functions/v1/mirsa-ar-localize")!
    func translate(bundleID: String, version: String, contentHash: String, items: [ArabicIPALocalizer.Item]) async throws -> [String: String] {
        let auth: DiscoveryTokenProvider = tokenProvider ?? DiscoveryAuthClient(projectURL: URL(string: WebBackendConfig.defaultProject)!,
            publishableKey: WebBackendConfig.defaultPublishableKey, store: KeychainSessionStore(), http: SafeMetadataHTTP())
        let body: [String: Any] = ["bundleId": bundleID, "version": version, "contentHash": contentHash,
                                   "items": items.map { ["id": $0.id, "text": $0.text] }]
        let payload = try JSONSerialization.data(withJSONObject: body)
        let config = URLSessionConfiguration.ephemeral; config.timeoutIntervalForRequest = 120; config.timeoutIntervalForResource = 150
        let session = URLSession(configuration: config)
        var forced = false
        for _ in 0..<2 {
            let token: String
            do { token = try await auth.token(forceRefresh: forced) } catch { throw ArabicTranslationError(failure: .notConfigured) }
            var req = URLRequest(url: Self.endpoint); req.httpMethod = "POST"; req.httpBody = payload
            req.setValue("Bearer " + token, forHTTPHeaderField: "Authorization"); req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let (data, response): (Data, URLResponse)
            do { (data, response) = try await session.data(for: req) } catch { throw ArabicTranslationError(failure: .network) }
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            if code == 401, !forced { forced = true; continue }
            if code == 429 { throw ArabicTranslationError(failure: .rateLimited) }
            if code == 503 { throw ArabicTranslationError(failure: .busy) }
            guard (200..<300).contains(code), let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let map = obj["translations"] as? [String: String] else { throw ArabicTranslationError(failure: .network) }
            return map
        }
        throw ArabicTranslationError(failure: .network)
    }
}

// MARK: Preferences, messages

enum ArabicTranslatePrefs {
    private static let onKey = "mirsa.arTranslate.bundles", knownKey = "mirsa.arTranslate.hasArabic"
    static func isOn(_ bundleID: String, defaults: UserDefaults = .standard) -> Bool { (defaults.stringArray(forKey: onKey) ?? []).contains(bundleID) }
    static func set(_ on: Bool, bundleID: String, defaults: UserDefaults = .standard) {
        var s = Set(defaults.stringArray(forKey: onKey) ?? []); if on { s.insert(bundleID) } else { s.remove(bundleID) }
        defaults.set(Array(s).sorted(), forKey: onKey)
    }
    /// Learned only after the IPA has actually been downloaded and inspected.
    static func hasArabicKnown(_ bundleID: String, defaults: UserDefaults = .standard) -> Bool { (defaults.stringArray(forKey: knownKey) ?? []).contains(bundleID) }
    static func markHasArabic(_ bundleID: String, defaults: UserDefaults = .standard) {
        var s = Set(defaults.stringArray(forKey: knownKey) ?? []); s.insert(bundleID); defaults.set(Array(s).sorted(), forKey: knownKey)
    }
}

enum ArabicTranslateText {
    static func t(_ en: String, _ ar: String, _ de: String, _ ckb: String, _ kmr: String) -> String { SourcesText.t(en, ar, de, ckb, kmr) }
    static var rowTitle: String { t("Translate to Arabic", "ترجم للعربي", "Ins Arabische übersetzen", "وەریبگێڕە بۆ عەرەبی", "Bi Erebî wergerîne") }
    static var rowHint: String { t("Checked after download. Only works if the app has no Arabic yet.", "يتحقق بعد التنزيل. يشتغل بس إذا التطبيق ما فيه عربي.", "Wird nach dem Download geprüft. Nur wenn die App noch kein Arabisch hat.", "دوای دابەزاندن پشکنین دەکرێت. تەنها ئەگەر ئەپەکە عەرەبی نەبێت.", "Piştî daxistinê tê kontrolkirin. Tenê heke sepan hêj Erebî nebe.") }
    static var alreadyArabic: String { t("This app already has Arabic.", "هالتطبيق فيه عربي أصلاً.", "Diese App hat bereits Arabisch.", "ئەم ئەپە پێشتر عەرەبی هەیە.", "Ev sepan jixwe Erebî heye.") }
    static var nothing: String { t("No English text found to translate.", "ما لقيت نص إنجليزي للترجمة.", "Kein englischer Text zum Übersetzen gefunden.", "هیچ دەقێکی ئینگلیزی بۆ وەرگێڕان نەدۆزرایەوە.", "Tu nivîsa Îngilîzî ji bo wergerê nehat dîtin.") }
    static var applied: String { t("Arabic translation added.", "انضافت الترجمة العربية.", "Arabische Übersetzung hinzugefügt.", "وەرگێڕانی عەرەبی زیادکرا.", "Wergera Erebî hat zêdekirin.") }
    static var failed: String { t("Couldn't translate to Arabic. Installing the app as is.", "ما قدرت أترجم للعربي. عم نثبّت التطبيق متل ما هو.", "Übersetzung ins Arabische fehlgeschlagen. Die App wird unverändert installiert.", "نەتوانرا وەربگێڕدرێت بۆ عەرەبی. ئەپەکە وەک خۆی دادەمەزرێت.", "Wergera Erebî nehat kirin. Sepan wekî xwe tê saz kirin.") }
    static func message(for o: ArabicLocalizationOutcome) -> String {
        switch o { case .applied: return applied; case .alreadyArabic: return alreadyArabic; case .nothingToTranslate: return nothing; case .failed: return failed }
    }
}

/// Runs between extraction and signing. Fail-open: any failure leaves the extracted app and IPA exactly as they were.
enum ArabicLocalizationPipeline {
    /// Last user-facing result (localized). Read by the UI after a signing run; never blocks signing.
    nonisolated(unsafe) static var lastNotice: String?
    static func apply(workDir: URL, ipa: URL, app: URL, bundleID: String, version: String,
                      translator: ArabicTranslating = ArabicBackendTranslator()) async -> String? {
        guard ArabicTranslatePrefs.isOn(bundleID) else { return nil }
        let fm = FileManager.default
        let stage = workDir.appendingPathComponent("ar-work-" + UUID().uuidString, isDirectory: true)
        defer { try? fm.removeItem(at: stage) }
        do {
            let payload = app.deletingLastPathComponent()
            try fm.createDirectory(at: stage, withIntermediateDirectories: true)
            let copyPayload = stage.appendingPathComponent("Payload", isDirectory: true)
            try fm.copyItem(at: payload, to: copyPayload)
            let appCopy = copyPayload.appendingPathComponent(app.lastPathComponent, isDirectory: true)
            let outcome = await ArabicIPALocalizer.localize(app: appCopy, bundleID: bundleID, version: version, translator: translator)
            if outcome == .alreadyArabic { ArabicTranslatePrefs.markHasArabic(bundleID) }
            guard case .applied = outcome else { return ArabicTranslateText.message(for: outcome) }
            let localized = stage.appendingPathComponent("localized.ipa")
            try await Task.detached { try IPAEditorService.run("pack", input: stage, output: localized) }.value
            guard let size = (try? fm.attributesOfItem(atPath: localized.path)[.size] as? NSNumber)?.int64Value, size > 0 else { return ArabicTranslateText.failed }
            // Swap: keep originals as backups until both replacements succeed.
            let ipaBackup = workDir.appendingPathComponent("untranslated.ipa")
            let appBackup = workDir.appendingPathComponent("untranslated.app", isDirectory: true)
            try? fm.removeItem(at: ipaBackup); try? fm.removeItem(at: appBackup)
            try fm.moveItem(at: ipa, to: ipaBackup)
            do {
                try fm.moveItem(at: localized, to: ipa)
                try fm.moveItem(at: app, to: appBackup)
                do { try fm.moveItem(at: appCopy, to: app) }
                catch { try? fm.moveItem(at: appBackup, to: app); throw error }
            } catch {
                try? fm.removeItem(at: ipa); try? fm.moveItem(at: ipaBackup, to: ipa)
                return ArabicTranslateText.failed
            }
            return ArabicTranslateText.applied
        } catch { return ArabicTranslateText.failed }
    }
}

import SwiftUI

/// Globe row under "Install now". Only a preference: eligibility is learned after the IPA is downloaded and inspected.
struct ArabicTranslateRow: View {
    let bundleID: String
    let theme: SourcesTheme
    @State private var on: Bool
    @State private var known: Bool
    init(bundleID: String, theme: SourcesTheme) {
        self.bundleID = bundleID; self.theme = theme
        _on = State(initialValue: ArabicTranslatePrefs.isOn(bundleID))
        _known = State(initialValue: ArabicTranslatePrefs.hasArabicKnown(bundleID))
    }
    var body: some View {
        if !known && !bundleID.isEmpty {
            HStack(spacing: 12) {
                Image(systemName: "globe").font(.system(size: 18, weight: .semibold)).foregroundStyle(theme.accent[0])
                VStack(alignment: .leading, spacing: 2) {
                    Text(ArabicTranslateText.rowTitle).font(.system(size: 15, weight: .semibold)).foregroundStyle(theme.text)
                    Text(ArabicTranslateText.rowHint).font(.system(size: 12)).foregroundStyle(theme.secondary)
                }
                Spacer(minLength: 8)
                Toggle("", isOn: $on).labelsHidden().accessibilityIdentifier("source-detail-translate-ar")
            }
            .padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .sourcesGlass(theme, radius: 18)
            .onChange(of: on) { _, v in ArabicTranslatePrefs.set(v, bundleID: bundleID) }
            .accessibilityElement(children: .contain)
        }
    }
}

extension ArabicLocalizationPipeline {
    /// Blocking variant for the signing pipeline (already off the main thread). Works on a copy and swaps it in only on success.
    @discardableResult
    static func applyBlocking(app: URL, translator: ArabicTranslating = ArabicBackendTranslator()) -> String? {
        let fm = FileManager.default
        guard let info = try? IPAEditorService.info(in: app), let bid = info["CFBundleIdentifier"] as? String else { return nil }
        let version = (info["CFBundleShortVersionString"] as? String) ?? "1.0"
        let parent = app.deletingLastPathComponent()
        let copy = parent.appendingPathComponent("ar-copy-" + UUID().uuidString, isDirectory: true)
        let backup = parent.appendingPathComponent("ar-backup-" + UUID().uuidString, isDirectory: true)
        do { try fm.copyItem(at: app, to: copy) } catch { return ArabicTranslateText.failed }
        let box = ArabicOutcomeBox(); let sem = DispatchSemaphore(value: 0)
        Task.detached {
            box.value = await ArabicIPALocalizer.localize(app: copy, bundleID: bid, version: version, translator: translator)
            sem.signal()
        }
        sem.wait()
        let outcome = box.value ?? .failed(.io)
        if outcome == .alreadyArabic { ArabicTranslatePrefs.markHasArabic(bid) }
        guard case .applied = outcome else { try? fm.removeItem(at: copy); return ArabicTranslateText.message(for: outcome) }
        do {
            try fm.moveItem(at: app, to: backup)
            do { try fm.moveItem(at: copy, to: app) } catch { try? fm.moveItem(at: backup, to: app); throw error }
            try? fm.removeItem(at: backup)
            return ArabicTranslateText.applied
        } catch { try? fm.removeItem(at: copy); return ArabicTranslateText.failed }
    }
}

final class ArabicOutcomeBox: @unchecked Sendable { var value: ArabicLocalizationOutcome? }
