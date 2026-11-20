import Foundation
import SwiftUI

/// Premium Unlock (فك المميزات): scan a decrypted App Store IPA for
/// client-side premium checks, then inject the bundled MirsaUnlock dylib
/// (+ its JSON config) and hand the unlocked IPA to the normal Apps-tab
/// importer. Only the user's own purchased apps can be decrypted, so the
/// scan first decrypts via EncryptedAppsStore when needed.
///
/// The Rust IPA editor blocks — every extract / inject / pack call runs
/// inside Task.detached, exactly like ForgeStore.inject.
@MainActor
final class PremiumUnlockStore: ObservableObject {
    enum Step: Equatable {
        case idle, scanning, report, unlocking, done
    }

    /// The four scan phases shown with checkmarks + a progress bar.
    static let scanSteps: [(String, String, String, String)] = [
        ("Decrypting", "فك التشفير", "ڕەمزکردنەوە", "Şîfre vekirin"),
        ("Reading binary", "قراءة الباينري", "خوێندنەوەی باینەری", "Binary xwendin"),
        ("Matching patterns", "مطابقة الأنماط", "هاوشێوەکردنی نەخشەکان", "Nimûneyan li hev bîne"),
        ("Generating injection", "توليد الحقنة", "دروستکردنی چەسپاندن", "Derzî çêkirin"),
    ]

    @Published var step: Step = .idle
    @Published var progress: Double = 0
    @Published var report: PremiumScanner.Report?
    @Published var error: String?
    @Published var selectedEntry: EncryptedIPAEntry?
    @Published var installing = false
    /// The report screen's ad toggle: when on, the unlock also blocks the
    /// detected ad SDKs and accelerates rewarded ads (same injection).
    @Published var includeAds = false
    /// Per-feature toggles on the report screen (keyed by feature id:
    /// "limit", "paywall", "tracking", …). Enabled by default when the
    /// feature was detected; a disabled feature's hooks are dropped from
    /// the config, so one injection applies exactly what is toggled on.
    @Published var featureEnabled: [String: Bool] = [:]
    /// "Try all" mode: keeps every detected hook and turns on every
    /// built-in feature (jailbreak / ssl / location) even when undetected.
    @Published var aggressive = false
    /// Live tracing (التتبع الحي): the last injection was a tracing
    /// build (no unlock replacements), and the trace pasted back from
    /// the target app's floating "● Trace" button.
    @Published var tracing = false
    @Published var traceEntries: [PremiumTrace.Entry] = []
    @Published var traceNote: String?
    /// Hooks the user added from the trace or the AI suggestion.
    /// Merged into the config by unlock(); cleared on a new scan.
    @Published var extraHooks: [PremiumScanner.Hook] = []
    @Published var aiSuggestion: PremiumTrace.Suggestion?
    @Published var aiStatus: AIStatus = .unknown
    @Published var aiError: String?

    enum AIStatus: Equatable {
        case unknown, checking, ready, unavailable
    }
    /// What the last unlock actually applied (set when it starts).
    private(set) var appliedAds = false
    private(set) var appliedFeatures: [String] = []
    private(set) var unlockedURL: URL?
    private var unlockedDir: URL?
    private var busy = false

    /// Whether a finding counts towards the unlock (premium findings
    /// always do; feature findings only when their toggle is on or
    /// aggressive mode is on).
    func isFindingEnabled(_ f: PremiumScanner.Finding) -> Bool {
        switch f.kind {
        case .sdk, .custom: return true
        case .server, .ads: return false
        default:
            if aggressive { return true }
            return featureEnabled[f.kind.rawValue] ?? true
        }
    }

    /// Unlockable findings after the feature toggles (drives the
    /// "فك المميزات (N)" button).
    var enabledUnlockableCount: Int {
        (report?.findings ?? []).filter { $0.unlockable && isFindingEnabled($0) }.count
    }

    /// Feature ids detected in the current report, for the toggle rows.
    var detectedFeatures: [String] { report?.features ?? [] }

    /// Display name for a feature id (shared with the report screen).
    static func featureName(_ id: String) -> String {
        switch id {
        case "limit": return tr("Usage limits", "حدود الاستخدام", ckb: "سنوورەکانی بەکارهێنان", kmr: "Sînorên bikaranînê")
        case "paywall": return tr("Paywall skip", "تخطّي شاشة الدفع", ckb: "بازدان لە شاشەی پارەدان", kmr: "Derbaskirina dîmendera dravdanê")
        case "tracking": return tr("Tracking block", "حجب التتبّع", ckb: "بلۆککردنی شوێنکەوتن", kmr: "Astengkirina şopandinê")
        case "watermark": return tr("Watermark removal", "إزالة العلامة المائية", ckb: "لابردنی نیشانەی ئاوی", kmr: "Rakiriina nîşana avê")
        case "login": return tr("Forced-login skip", "تخطّي تسجيل الدخول", ckb: "بازدان لە چوونەژوورەوە", kmr: "Derbaskirina têketinê")
        case "jailbreak": return tr("Jailbreak-detection bypass", "تجاوز كشف الجيلبريك", ckb: "بەزاندنی دۆزینەوەی جەیڵبرەیک", kmr: "Derbaskirina tespîtkirina jailbreak")
        case "ssl": return tr("SSL pinning bypass (diagnostic)", "تجاوز تثبيت SSL (تشخيصي)", ckb: "بەزاندنی پینکردنی SSL (دەستنیشانکردن)", kmr: "Derbaskirina SSL pinning (teşhîs)")
        case "location": return tr("Location spoofing", "تزييف الموقع", ckb: "ساختەکردنی شوێن", kmr: "Sextekirina cihê")
        case "flags": return tr("Hidden feature flags", "الميزات المخفية", ckb: "تایبەتمەندییە شاراوەکان", kmr: "Taybetmendiyên veşartî")
        case "onboarding": return tr("Onboarding skip", "تخطّي شاشة البداية", ckb: "بازدان لە شاشەی دەستپێک", kmr: "Derbaskirina dîmendera destpêkê")
        case "update": return tr("Forced-update skip", "تخطّي التحديث الإجباري", ckb: "بازدان لە نوێکردنەوەی زۆرەملێ", kmr: "Derbaskirina nûvekirina zorê")
        case "trial": return tr("Trial-expiry removal", "إلغاء انتهاء التجربة", ckb: "لابردنی بەسەرچوونی تاقیکردنەوە", kmr: "Rakiriina qedandina ceribandinê")
        case "connectivity": return tr("Fake connectivity", "اتصال وهمي", ckb: "پەیوەندیی ساختە", kmr: "Girêdana sexte")
        default: return id
        }
    }

    private func t(_ en: String, _ ar: String, _ ckb: String, _ kmr: String) -> String {
        tr(en, ar, ckb: ckb, kmr: kmr)
    }

    // MARK: - Scan

    /// Decrypts first when the entry has no decrypted copy yet (unless the
    /// binary was never encrypted), then extracts the decrypted IPA and
    /// runs PremiumScanner on the main executable.
    func scan(entry: EncryptedIPAEntry) async {
        guard !busy else { return }
        busy = true
        error = nil
        report = nil
        // A new scan starts the tracing flow over: new candidates, no
        // stale trace hooks or AI suggestion.
        extraHooks = []
        traceEntries = []
        traceNote = nil
        aiSuggestion = nil
        aiStatus = .unknown
        aiError = nil
        tracing = false
        selectedEntry = entry
        step = .scanning
        progress = 0
        defer { busy = false }
        let lib = EncryptedAppsStore.shared
        let source: URL
        if lib.decryptedIDs.contains(entry.id) {
            source = EncryptedAppsStore.decryptedURL(entry.id)
        } else if entry.encryptedBinary == false {
            source = EncryptedAppsStore.ipaURL(entry.id)
        } else {
            await lib.decrypt(entry, vm: nil)
            if let e = lib.error {
                lib.error = nil
                self.error = e
                step = .idle
                return
            }
            guard lib.decryptedIDs.contains(entry.id) else {
                self.error = t("Decryption did not produce a file. Try decrypting the app again.",
                               "فك التشفير ما طلّع ملف. جرّب فك تشفير التطبيق مرة تانية.",
                               "ڕەمزکردنەوە فایلێکی دروست نەکرد. دووبارە هەوڵبدەرەوە.",
                               "Vekirina şîfreyê pel çênekir. Dîsa biceribîne.")
                step = .idle
                return
            }
            source = EncryptedAppsStore.decryptedURL(entry.id)
        }
        progress = 0.25
        do {
            let work = try await Task.detached(priority: .userInitiated) { () -> (URL, URL) in
                let fm = FileManager.default
                let tmp = fm.temporaryDirectory.appendingPathComponent("premium-scan-" + UUID().uuidString, isDirectory: true)
                try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
                let x = tmp.appendingPathComponent("x", isDirectory: true)
                try IPAEditorService.run("extract", input: source, output: x)
                let app = try IPAEditorService.app(in: x)
                let info = try IPAEditorService.info(in: app)
                guard let exe = info["CFBundleExecutable"] as? String, !exe.isEmpty else {
                    throw PremiumScanner.ScanError.noBinary
                }
                return (tmp, app.appendingPathComponent(exe))
            }.value
            progress = 0.5
            defer { try? FileManager.default.removeItem(at: work.0) }
            let found = try await Task.detached(priority: .userInitiated) {
                try PremiumScanner.scan(binaryURL: work.1)
            }.value
            progress = 1
            report = found
            // Newly detected features default to enabled; keep the
            // user's earlier toggles for features seen before.
            for id in found.features where featureEnabled[id] == nil {
                featureEnabled[id] = true
            }
            step = .report
        } catch {
            self.error = error.localizedDescription
            step = .idle
        }
    }

    // MARK: - Unlock

    /// Injects the bundled MirsaUnlock dylib into a fresh extraction of the
    /// decrypted IPA, writes the scanner's config JSON next to it, and packs
    /// the unlocked IPA. The Install button then calls installUnlocked.
    func unlock(entry: EncryptedIPAEntry) async {
        guard var rep = report, !busy else { return }
        let enabled = Set(featureEnabled.filter { $0.value }.map(\.key))
        // Hooks added from the live trace / AI suggestion ride along.
        rep.hooks += extraHooks
        let config: Data
        do {
            config = try rep.configJSON(includeAds: includeAds, enabledFeatures: enabled, aggressive: aggressive)
        } catch {
            self.error = error.localizedDescription
            step = .report
            return
        }
        appliedAds = includeAds
        // What this injection actually applies (for the done screen +
        // the unlock history).
        var applied: [String] = []
        if rep.hooks.contains(where: { $0.feature == "premium" }) {
            applied.append(t("Premium", "المميزات", "پرێمیۆم", "Premium"))
        }
        for id in rep.features where aggressive || enabled.contains(id) {
            applied.append(Self.featureName(id))
        }
        if appliedAds {
            applied.append(t("Ads blocked", "الإعلانات محجوبة", "ڕیکلام بلۆک کراوە", "Reklam hatin astengkirin"))
        }
        appliedFeatures = applied
        guard let dylib = Bundle.main.url(forResource: "MirsaUnlock", withExtension: "dylib", subdirectory: "Frameworks") else {
            error = t("MirsaUnlock dylib not found in this build.",
                      "مكتبة MirsaUnlock مو موجودة بهالبناء.",
                      "کتێبخانەی MirsaUnlock لەم بنیادەدا نەدۆزرایەوە.",
                      "Pirtûkxaneya MirsaUnlock di vê çêkirinê de nehat dîtin.")
            step = .report
            return
        }
        let source = EncryptedAppsStore.decryptedURL(entry.id)
        guard FileManager.default.fileExists(atPath: source.path) else {
            error = t("Decrypted file not found. Decrypt the app again.",
                      "ملف المفكوك مو موجود. فك تشفير التطبيق مرة تانية.",
                      "فایلی ڕەمزکراوەکە نەدۆزرایەوە. دووبارە ڕەمزکردنەوە بکە.",
                      "Pelê şîfrevekirî nehat dîtin. Sepanê dîsa şîfre veke.")
            step = .report
            return
        }
        busy = true
        error = nil
        tracing = false // a real unlock, not a tracing build
        step = .unlocking
        progress = 0
        defer { busy = false }
        let safeName = entry.name.filter { $0.isLetter || $0.isNumber }
        let fileName = (safeName.isEmpty ? "App" : safeName) + "-Unlocked-" + UUID().uuidString.prefix(6) + ".ipa"
        do {
            let out = try await packInjectedIPA(entry: entry, dylib: dylib, config: config, fileName: fileName)
            unlockedDir = out.0
            unlockedURL = out.1
            progress = 1
            step = .done
            // Persist the unlock in the local history (scan report +
            // what was actually applied). Local JSON only — no server.
            PremiumUnlockHistory.shared.record(
                appName: entry.name,
                findings: rep.findings.map(\.name),
                applied: appliedFeatures,
                adsBlocked: appliedAds)
        } catch {
            self.error = error.localizedDescription
            step = .report
        }
    }

    // MARK: - Live tracing

    /// Injects the same dylib with a TRACING config (no unlock
    /// replacements) and packs a "…-Trace.ipa". The user installs it,
    /// opens the app, taps the paid feature, copies the trace from the
    /// floating "● Trace" button, and pastes it back here. No history
    /// entry: nothing was unlocked yet.
    func startTracing(entry: EncryptedIPAEntry) async {
        guard let rep = report, !busy else { return }
        let config: Data
        do {
            config = try rep.traceConfigJSON()
        } catch {
            self.error = error.localizedDescription
            step = .report
            return
        }
        guard let dylib = Bundle.main.url(forResource: "MirsaUnlock", withExtension: "dylib", subdirectory: "Frameworks") else {
            error = t("MirsaUnlock dylib not found in this build.",
                      "مكتبة MirsaUnlock مو موجودة بهالبناء.",
                      "کتێبخانەی MirsaUnlock لەم بنیادەدا نەدۆزرایەوە.",
                      "Pirtûkxaneya MirsaUnlock di vê çêkirinê de nehat dîtin.")
            step = .report
            return
        }
        let source = EncryptedAppsStore.decryptedURL(entry.id)
        guard FileManager.default.fileExists(atPath: source.path) else {
            error = t("Decrypted file not found. Decrypt the app again.",
                      "ملف المفكوك مو موجود. فك تشفير التطبيق مرة تانية.",
                      "فایلی ڕەمزکراوەکە نەدۆزرایەوە. دووبارە ڕەمزکردنەوە بکە.",
                      "Pelê şîfrevekirî nehat dîtin. Sepanê dîsa şîfre veke.")
            step = .report
            return
        }
        busy = true
        error = nil
        tracing = true
        appliedAds = false
        appliedFeatures = []
        step = .unlocking
        progress = 0
        defer { busy = false }
        let safeName = entry.name.filter { $0.isLetter || $0.isNumber }
        let fileName = (safeName.isEmpty ? "App" : safeName) + "-Trace-" + UUID().uuidString.prefix(6) + ".ipa"
        do {
            let out = try await packInjectedIPA(entry: entry, dylib: dylib, config: config, fileName: fileName)
            unlockedDir = out.0
            unlockedURL = out.1
            progress = 1
            step = .done
        } catch {
            tracing = false
            self.error = error.localizedDescription
            step = .report
        }
    }

    /// Shared pack step for unlock() and startTracing(): extract the
    /// decrypted IPA, inject the dylib, write the config next to it,
    /// pack. Returns (work dir, packed IPA).
    private func packInjectedIPA(entry: EncryptedIPAEntry, dylib: URL, config: Data, fileName: String) async throws -> (URL, URL) {
        let source = EncryptedAppsStore.decryptedURL(entry.id)
        return try await Task.detached(priority: .userInitiated) { () -> (URL, URL) in
            let fm = FileManager.default
            let tmp = fm.temporaryDirectory.appendingPathComponent("premium-unlock-" + UUID().uuidString, isDirectory: true)
            try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
            let x = tmp.appendingPathComponent("x", isDirectory: true)
            try IPAEditorService.run("extract", input: source, output: x)
            let app = try IPAEditorService.app(in: x)
            let info = try IPAEditorService.info(in: app)
            guard let exe = info["CFBundleExecutable"] as? String, !exe.isEmpty else {
                throw PremiumScanner.ScanError.noBinary
            }
            try IPAEditorService.run("inject", input: app, executable: exe, libraries: [dylib])
            let frameworks = app.appendingPathComponent("Frameworks", isDirectory: true)
            try fm.createDirectory(at: frameworks, withIntermediateDirectories: true)
            try config.write(to: frameworks.appendingPathComponent("MirsaUnlock.json"), options: .atomic)
            let outIPA = tmp.appendingPathComponent(fileName)
            try IPAEditorService.run("pack", input: x, output: outIPA)
            return (tmp, outIPA)
        }.value
    }

    /// Reads the trace the user copied from the target app's floating
    /// button (shared pasteboard) and parses it. Returns the number of
    /// imported calls; 0 + traceNote when the pasteboard has no trace.
    @discardableResult
    func importTraceFromPasteboard() -> Int {
        guard let text = UIPasteboard.general.string, !text.isEmpty else {
            traceNote = t("The clipboard is empty. In the app, tap the \"● Trace\" button, then \"Copy trace\", and come back here.",
                         "الحافظة فاضية. بالتطبيق اكبس زر \"● Trace\" بعدين \"نسخ التتبع\"، وارجع لهون.",
                         "کلیپبۆرد بەتاڵە. لە ئەپەکە دوگمەی \"● Trace\" دابگرە پاشان \"کۆپیکردنی شوێنکەوتن\"، و بگەڕێرەوە بۆ ئێرە.",
                         "Panoya vala ye. Di sepanê de bişkoka \"● Trace\" bitikîne, paşê \"Şopandinê kopî bike\", û vegere vir.")
            return 0
        }
        let entries = PremiumTrace.parse(text)
        guard !entries.isEmpty else {
            traceNote = t("No trace found on the clipboard. Copy the trace from the app first.",
                         "ما لقينا تتبع بالحافظة. انسخ التتبع من التطبيق أولاً.",
                         "هیچ شوێنکەوتنێک لە کلیپبۆرد نەدۆزرایەوە. سەرەتا شوێنکەوتنەکە لە ئەپەکە کۆپی بکە.",
                         "Li panoyê şopandin nehat dîtin. Pêşî şopandinê ji sepanê kopî bike.")
            return 0
        }
        traceEntries = entries
        aiSuggestion = nil
        aiStatus = .unknown
        aiError = nil
        traceNote = nil
        return entries.count
    }

    /// Adds one traced call as a hook, with the suggested "returns"
    /// value (YES for BOOL, 999 for a remaining counter, 0 for a used
    /// counter). Returns the applied "returns" value, or nil when no
    /// safe suggestion exists (object getters) or it is already added.
    @discardableResult
    func addHookFromTrace(_ entry: PremiumTrace.Entry) -> String? {
        guard let returns = PremiumTrace.suggestedReturns(for: entry) else { return nil }
        guard !extraHooks.contains(where: { $0.selector == entry.selector }) else { return returns }
        extraHooks.append(PremiumScanner.Hook(
            className: entry.className == "?" ? "" : entry.className,
            selector: entry.selector, returns: returns, feature: "premium"))
        return returns
    }

    /// Adds the confirmed AI suggestion as a hook. Returns false when
    /// there is no suggestion or it is already added.
    @discardableResult
    func addAISuggestion() -> Bool {
        guard let s = aiSuggestion else { return false }
        guard !extraHooks.contains(where: { $0.selector == s.selector }) else { return false }
        extraHooks.append(PremiumScanner.Hook(
            className: s.className, selector: s.selector, returns: s.returns, feature: "premium"))
        return true
    }

    /// Asks the Forge AI for a hook suggestion from the scan + trace.
    /// Checks the server status first: when the LLM is not configured
    /// there, it reports that immediately without sending anything.
    /// Any failure leaves tracing and manual selection working.
    func suggestHookFromAI() async {
        guard !traceEntries.isEmpty, let entry = selectedEntry else { return }
        guard aiStatus != .checking else { return }
        aiStatus = .checking
        aiError = nil
        aiSuggestion = nil
        if await PremiumTrace.AI.llmAvailable() == false {
            aiStatus = .unavailable
            aiError = t("The AI service is not set up on the server yet. Add the hook manually from the trace below.",
                        "خدمة الذكاء الاصطناعي مو مفعّلة على السيرفر بعد. أضِف الخطّافة يدويًا من التتبع تحت.",
                        "خزمەتگوزاری زیرەکی دەستکرد هێشتا لەسەر سێرڤەر چالاک نەکراوە. هۆکەکە بە دەست لە شوێنکەوتنەکەی خوارەوە زیاد بکە.",
                        "Xizmeta AI hê li ser serverê ne çalak e. Hookê bi destan ji şopandina jêrîn lê zêde bike.")
            return
        }
        do {
            let scanSummary: String
            if let rep = report {
                scanSummary = rep.findings.map(\.name).joined(separator: ", ")
            } else {
                scanSummary = ""
            }
            aiSuggestion = try await PremiumTrace.AI.suggest(
                appName: entry.name, bundleID: entry.bundleID,
                scanSummary: scanSummary, entries: traceEntries)
            aiStatus = .ready
        } catch {
            aiStatus = .unavailable
            aiError = error.localizedDescription
        }
    }

    // MARK: - Install

    /// Hands the unlocked IPA to the normal Apps-tab importer and switches
    /// to the Apps tab, mirroring EncryptedAppsStore.installDecrypted.
    /// Returns false when the import failed (error is set).
    func installUnlocked(vm: AppViewModel?) async -> Bool {
        guard let url = unlockedURL else { return false }
        installing = true
        defer { installing = false }
        await AppsStore.shared.importIPA(from: url)
        if let message = AppsStore.shared.error {
            AppsStore.shared.error = nil
            error = message
            return false
        }
        (vm ?? AppViewModel.shared)?.selectedTab = .apps
        if let dir = unlockedDir {
            try? FileManager.default.removeItem(at: dir)
            unlockedDir = nil
            unlockedURL = nil
        }
        return true
    }

    func reset() {
        step = .idle
        progress = 0
        report = nil
        error = nil
        selectedEntry = nil
        includeAds = false
        appliedAds = false
        appliedFeatures = []
        featureEnabled = [:]
        aggressive = false
        tracing = false
        traceEntries = []
        traceNote = nil
        extraHooks = []
        aiSuggestion = nil
        aiStatus = .unknown
        aiError = nil
        if let dir = unlockedDir {
            try? FileManager.default.removeItem(at: dir)
            unlockedDir = nil
            unlockedURL = nil
        }
    }
}
