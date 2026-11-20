import Foundation

/// Scans a decrypted app binary for premium / paywall signals and turns them
/// into the hook list the Premium Unlock (فك المميزات) dylib consumes.
///
/// Parsing mirrors `ForgeMachO`: fat binaries are reduced to their arm64 slice,
/// then the load commands are walked (LC_SEGMENT_64 = 0x19, sections at
/// off+72, 80 bytes each; LC_ENCRYPTION_INFO_64 = 0x2C, cryptid at off+16).
/// Besides the `__objc_classname` section ForgeMachO reads, this also reads
/// method names from `__objc_methname` and string constants from `__cstring`.
///
/// Encrypted binaries (cryptid != 0) cannot be scanned — decrypt first.
/// The scanner never hardcodes hooks for a specific app: everything comes
/// from the binary itself plus the generic pattern tables in
/// `PremiumPatternStore` (bundled `patterns.json`, remotely updatable).
enum PremiumScanner {

    // MARK: - Public API

    /// One method to hook. `className` is empty for "any class": the dylib
    /// scans every class for a method with this selector.
    /// `returns` tells the dylib what the replacement must return:
    /// "yes" (BOOL YES, the premium default), "no" (BOOL NO),
    /// "count" (integer 999), "zero" (integer 0),
    /// "future" (a date ~10 years out), "noop" (void, do nothing),
    /// "dismiss" (void viewDidAppear that dismisses the view controller).
    /// `feature` is the feature id this hook belongs to ("premium" for the
    /// classic premium hooks, "limit" for usage limits, otherwise one of
    /// the `features` ids in patterns.json). It is used by the UI toggles
    /// to include/exclude hooks, and is NOT written to the dylib config.
    struct Hook: Codable, Equatable {
        var className: String
        var selector: String
        var returns: String
        var feature: String

        init(className: String, selector: String, returns: String = "yes", feature: String = "premium") {
            self.className = className
            self.selector = selector
            self.returns = returns
            self.feature = feature
        }

        // Encoded as {"class": ..., "selector": ..., "returns": ...}.
        // "feature" is scanner-side only and never reaches the dylib.
        private enum CodingKeys: String, CodingKey {
            case className = "class"
            case selector, returns, feature
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            className = try c.decodeIfPresent(String.self, forKey: .className) ?? ""
            selector = try c.decode(String.self, forKey: .selector)
            returns = try c.decodeIfPresent(String.self, forKey: .returns) ?? "yes"
            feature = try c.decodeIfPresent(String.self, forKey: .feature) ?? "premium"
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(className, forKey: .className)
            try c.encode(selector, forKey: .selector)
            try c.encode(returns, forKey: .returns)
        }
    }

    enum FindingKind: String, Codable {
        case sdk, custom, server, ads
        case limit, paywall, tracking, watermark, login, jailbreak, ssl,
             location, flags, onboarding, update, trial, connectivity
    }

    struct Finding: Identifiable, Equatable {
        var id: String { kind.rawValue + ":" + name }
        var kind: FindingKind
        var name: String
        var detail: String
        var unlockable: Bool
    }

    struct Report: Equatable {
        var findings: [Finding]
        var unlockableCount: Int { findings.filter(\.unlockable).count }
        var serverCount: Int { findings.filter { $0.kind == .server }.count }
        var adsCount: Int { findings.filter { $0.kind == .ads }.count }
        var hasAds: Bool { adsCount > 0 }
        var limitCount: Int { findings.filter { $0.kind == .limit }.count }
        /// Feature ids detected in this scan (limit + the `features`
        /// sections), sorted. The UI offers one toggle per id.
        var features: [String] {
            Array(Set(findings.compactMap { f -> String? in
                switch f.kind {
                case .sdk, .custom, .server, .ads: return nil
                default: return f.kind.rawValue
                }
            })).sorted()
        }
        var hooks: [Hook]
        var sdks: [String]
        /// Lowercase ad-SDK ids the dylib recognises, e.g. ["admob", "unity"].
        var adSDKs: [String]
        /// Live-tracing candidates: every hook selector (deduped) plus
        /// common subscription getters the scan did not find. The dylib
        /// wraps them (original implementation + record) instead of
        /// replacing them; "returns" is a placeholder and is ignored.
        var traceCandidates: [Hook]

        /// Compact JSON for the dylib:
        /// {"version":2,"hooks":[...],"sdks":[...],
        ///  "ads":{"block":true,"accelerate":true,"sdks":["admob",...]},
        ///  "features":{"paywall":true,"tracking":true,...},
        ///  "location":{"latitude":40.7128,"longitude":-74.006},
        ///  "aggressive":false}.
        /// Hook objects use the keys "class", "selector" and "returns"
        /// ("yes" | "no" | "count" | "zero" | "future" | "noop" | "dismiss";
        /// missing "returns" means "yes" for old configs).
        /// `enabledFeatures` is the set of feature ids the user left on;
        /// hooks of a disabled feature are dropped. With `aggressive`
        /// every detected hook is kept and every built-in feature flag
        /// (jailbreak / ssl / location) is turned on, even undetected.
        /// block/accelerate follow `includeAds`: the dylib only activates
        /// the ad hooks when they are true.
        func configJSON(includeAds: Bool, enabledFeatures: Set<String>, aggressive: Bool) throws -> Data {
            struct AdsConfig: Encodable {
                var block: Bool
                var accelerate: Bool
                var sdks: [String]
            }
            struct LocationConfig: Encodable {
                var latitude: Double
                var longitude: Double
            }
            struct Config: Encodable {
                var version: Int
                var hooks: [Hook]
                var sdks: [String]
                var ads: AdsConfig
                var features: [String: Bool]
                var location: LocationConfig?
                var aggressive: Bool
            }
            let keptHooks = hooks.filter { hook in
                aggressive || hook.feature == "premium" || enabledFeatures.contains(hook.feature)
            }
            var featureFlags: [String: Bool] = [:]
            for id in features {
                featureFlags[id] = aggressive || enabledFeatures.contains(id)
            }
            // Built-in dylib features (jailbreak / ssl / location) have no
            // per-method hook: their flag is what activates them. With
            // aggressive they are all on, even when undetected.
            if aggressive {
                featureFlags["jailbreak"] = true
                featureFlags["ssl"] = true
                featureFlags["location"] = true
            }
            let locationOn = aggressive || featureFlags["location"] == true
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            return try encoder.encode(Config(
                version: 2, hooks: keptHooks, sdks: sdks,
                ads: AdsConfig(block: includeAds, accelerate: includeAds, sdks: adSDKs),
                features: featureFlags,
                location: locationOn ? LocationConfig(latitude: 40.7128, longitude: -74.006) : nil,
                aggressive: aggressive))
        }

        /// Backwards-compatible entry point (everything on, no aggressive).
        func configJSON(includeAds: Bool) throws -> Data {
            try configJSON(includeAds: includeAds, enabledFeatures: Set(features), aggressive: false)
        }

        /// Discovery-only config for a tracing injection: no unlock
        /// replacements at all, tracing on, candidates = every hook
        /// selector plus the common subscription getters. The dylib
        /// records the original return values while the app runs
        /// normally; the unlock comes later, from the trace.
        /// {"version":2,"hooks":[],"sdks":[],"ads":{"block":false,
        ///  "accelerate":false,"sdks":[]},"features":{},
        ///  "tracing":true,"trace_candidates":[{"class":"","selector":"isPremium","returns":"yes"},…]}.
        func traceConfigJSON() throws -> Data {
            struct AdsConfig: Encodable {
                var block: Bool
                var accelerate: Bool
                var sdks: [String]
            }
            struct TraceConfig: Encodable {
                var version: Int
                var hooks: [Hook]
                var sdks: [String]
                var ads: AdsConfig
                var features: [String: Bool]
                var tracing: Bool
                var traceCandidates: [Hook]
                enum CodingKeys: String, CodingKey {
                    case version, hooks, sdks, ads, features, tracing
                    case traceCandidates = "trace_candidates"
                }
            }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            return try encoder.encode(TraceConfig(
                version: 2, hooks: [], sdks: [],
                ads: AdsConfig(block: false, accelerate: false, sdks: []),
                features: [:], tracing: true, traceCandidates: traceCandidates))
        }
    }

    enum ScanError: LocalizedError {
        case encrypted, unreadable, noBinary

        var errorDescription: String? {
            switch self {
            case .encrypted:
                return tr("This app is still encrypted. Decrypt it first.",
                          "هالتطبيق لسا مشفّر. فك تشفيره أولاً.",
                          ckb: "ئەم ئەپە هێشتا مشەفەرە. سەرەتا مشەفەرەکەی بکەرەوە.",
                          kmr: "Ev sepan hê jî şîfrekirî ye. Pêşî şîfreyê veke.")
            case .unreadable:
                return tr("Could not read the app binary.",
                          "ما قدرنا نقرأ ملف التطبيق.",
                          ckb: "نەتوانرا فایلی ئەپەکە بخوێندرێتەوە.",
                          kmr: "Pelê sepanê nehat xwendin.")
            case .noBinary:
                return tr("No app binary found.",
                          "ما لقينا ملف التطبيق.",
                          ckb: "هیچ فایلێکی ئەپ نەدۆزرایەوە.",
                          kmr: "Pela sepanê nehat dîtin.")
            }
        }
    }

    // MARK: - Pattern database

    /// Pattern tables live in `PremiumPatternStore` (bundled patterns.json
    /// merged with the remotely fetched copy when one is available), so a
    /// scan always uses the newest patterns without an app update. Read
    /// fresh on every scan via `snapshot()` — never cached here, never
    /// fetched here, and never blocking on the network.
    /// SDK display name -> class names that prove the SDK is linked.
    /// Matched exactly, or by containment for Swift-mangled (`_TtC…`) names.
    private static var sdkClasses: [(sdk: String, classes: [String])] {
        PremiumPatternStore.shared.snapshot().sdks.map { ($0.name, $0.classes) }
    }

    /// Ad-SDK display name -> lowercase id the dylib recognises -> class
    /// names that prove the SDK is linked. A detected ad SDK is a fallback
    /// target: when the premium check is server-side (not unlockable), the
    /// tool can still block the ads and accelerate rewarded ones.
    private static var adSDKClasses: [(sdk: String, id: String, classes: [String])] {
        PremiumPatternStore.shared.snapshot().adSDKs.map { ($0.name, $0.id, $0.classes) }
    }

    /// Substrings (matched case-insensitively) that mark a method as a
    /// premium check. Each match becomes a finding and a hook.
    private static var premiumPatterns: [String] {
        PremiumPatternStore.shared.snapshot().premiumSymbols
    }

    /// Substrings (matched case-insensitively) that mark a URL-looking
    /// string constant as a server-side receipt/subscription check.
    private static var serverKeywords: [String] {
        PremiumPatternStore.shared.snapshot().serverIndicators
    }

    /// Usage-limit method names (remainingUses, dailyLimit, …).
    private static var limitPatterns: [String] {
        PremiumPatternStore.shared.snapshot().limitSymbols
    }

    /// Usage-limit string constants ("free uses", "daily limit", …).
    private static var limitStrings: [String] {
        PremiumPatternStore.shared.snapshot().limitStrings
    }

    /// Per-feature detection patterns, keyed by feature id.
    private static var featurePatterns: [String: PremiumPatternSet.FeaturePatterns] {
        PremiumPatternStore.shared.snapshot().features
    }

    /// What a detected method of this feature must return in the dylib.
    /// "none" means: finding only, no hook — the dylib handles the
    /// feature with a built-in hook gated by the feature flag instead
    /// (ssl challenge handler, fake location), or the method cannot be
    /// replaced safely (see the dylib header).
    private static func returnsFor(feature: String, method: String) -> String? {
        let lower = method.lowercased()
        switch feature {
        case "limit":
            if lower.contains("remaining") || lower.contains("left") || lower.contains("usesremaining") {
                return "count" // 999 remaining uses
            }
            if lower.contains("count") || lower.contains("used") || lower.contains("quota") || lower.contains("maxfree") {
                return "zero" // 0 used / 0 quota consumed
            }
            return "no" // hasReachedLimit / isLimitReached / limitReached
        case "paywall", "tracking", "watermark":
            return "noop"
        case "login":
            if lower.contains("isloggedin") || lower.contains("isuserloggedin") {
                return "yes"
            }
            return "noop" // showLogin / presentLogin: never present it
        case "jailbreak":
            return "no" // isJailbroken / isJailbreak -> NO
        case "ssl", "location":
            return nil // built-in dylib hooks (feature flag), no per-method hook
        case "flags":
            return "yes" // isFeatureEnabled / boolForKey -> YES
        case "onboarding":
            return "noop" // showOnboarding / presentOnboarding: never show it
        case "update":
            return "no" // isUpdateRequired / needsUpdate -> NO
        case "trial":
            if lower.contains("trialenddate") { return "future" }
            if lower.contains("daysremaining") || lower.contains("daysleft") { return "count" }
            return "no" // isTrialExpired / trialExpired -> NO
        case "connectivity":
            return "yes" // isConnected / isReachable -> YES
        default:
            return "yes"
        }
    }

    /// Features whose detected view-controller classes are auto-dismissed
    /// on appearance (hook: viewDidAppear -> dismiss).
    private static let dismissFeatures: Set<String> = ["paywall", "onboarding", "login"]

    // MARK: - Scan

    static func scan(binaryURL: URL) throws -> Report {
        let data: Data
        do {
            data = try Data(contentsOf: binaryURL, options: .alwaysMapped)
        } catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileNoSuchFileError {
            throw ScanError.noBinary
        } catch {
            throw ScanError.unreadable
        }
        guard data.count > 64 else { throw ScanError.unreadable }

        func u32(_ o: Int, big: Bool = false) -> UInt32 {
            let v = data.subdata(in: o..<o + 4).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
            return big ? v.byteSwapped : v
        }

        // Fat binary: pick the arm64 slice (same as ForgeMachO).
        var base = 0
        if u32(0) == 0xBEBAFECA {
            let n = min(Int(u32(4, big: true)), 16)
            for i in 0..<n {
                let e = 8 + i * 20
                guard e + 20 <= data.count else { break }
                if u32(e, big: true) == 0x0100000C {
                    base = Int(u32(e + 8, big: true))
                    guard base + 64 <= data.count else { throw ScanError.unreadable }
                    break
                }
            }
        }
        guard u32(base) == 0xFEEDFACF else { throw ScanError.unreadable }

        let ncmds = Int(u32(base + 16))
        var off = base + 32
        var encrypted = false
        var sections: [(name: String, offset: Int, size: Int)] = []
        for _ in 0..<ncmds {
            guard off + 8 <= data.count else { break }
            let cmd = u32(off), size = Int(u32(off + 4))
            if cmd == 0x2C, off + 20 <= data.count { encrypted = u32(off + 16) != 0 } // LC_ENCRYPTION_INFO_64
            if cmd == 0x19, off + 72 <= data.count { // LC_SEGMENT_64
                let nsects = Int(u32(off + 64))
                var s = off + 72
                for _ in 0..<nsects {
                    guard s + 80 <= data.count else { break }
                    let sect = String(decoding: data.subdata(in: s..<s + 16).prefix { $0 != 0 }, as: UTF8.self)
                    if sect == "__objc_classname" || sect == "__objc_methname" || sect == "__cstring" {
                        let size64 = data.subdata(in: s + 40..<s + 48).withUnsafeBytes { $0.loadUnaligned(as: UInt64.self) }
                        let fileOff = Int(u32(s + 48))
                        sections.append((name: sect, offset: fileOff, size: Int(min(size64, UInt64(Int.max)))))
                    }
                    s += 80
                }
            }
            off += max(size, 8)
        }
        if encrypted { throw ScanError.encrypted }

        func sectionStrings(_ name: String) -> [String] {
            var out: [String] = []
            for sec in sections where sec.name == name {
                let start = base + sec.offset
                let end = min(data.count, start + sec.size)
                guard start >= 0, start < end else { continue }
                out += data.subdata(in: start..<end).split(separator: 0)
                    .map { String(decoding: $0, as: UTF8.self) }
            }
            return out
        }

        let classes = sectionStrings("__objc_classname")
            .filter { !$0.isEmpty && (!$0.hasPrefix("_") || $0.hasPrefix("_TtC")) }
            .sorted()
        let methods = Array(Set(sectionStrings("__objc_methname").filter { !$0.isEmpty })).sorted()
        let cstrings = sectionStrings("__cstring").filter { !$0.isEmpty }

        // (a) SDKs — one finding per detected SDK, detail is a matching class.
        var sdkFindings: [Finding] = []
        var sdks: [String] = []
        for (sdk, sdkNames) in sdkClasses {
            if let match = classes.first(where: { c in sdkNames.contains { c == $0 || c.contains($0) } }) {
                sdks.append(sdk)
                sdkFindings.append(Finding(kind: .sdk, name: sdk, detail: match, unlockable: true))
            }
        }
        sdkFindings.sort { $0.name < $1.name }
        sdks.sort()
        var findings = sdkFindings

        // (b) Premium symbols in method names — one finding + hook per method.
        let loweredPatterns = premiumPatterns.map { $0.lowercased() }
        var hooks: [Hook] = []
        var seenSelectors = Set<String>()
        for method in methods {
            let lower = method.lowercased()
            guard loweredPatterns.contains(where: { lower.contains($0) }) else { continue }
            guard seenSelectors.insert(method).inserted else { continue }
            findings.append(Finding(kind: .custom, name: method,
                detail: tr("premium check", "فحص الاشتراك المميز",
                           ckb: "پشکنینی بەشداربوونی پریمیەم",
                           kmr: "Kontrola aboneya premium"),
                unlockable: true))
            hooks.append(Hook(className: "", selector: method))
        }

        // (b2) Usage limits — method names (finding + hook) and string
        // constants (finding only: a string proves a limit exists but
        // names no method to hook, so it is not counted unlockable).
        let loweredLimit = limitPatterns.map { $0.lowercased() }
        for method in methods {
            let lower = method.lowercased()
            guard loweredLimit.contains(where: { lower.contains($0) }) else { continue }
            guard seenSelectors.insert(method).inserted else { continue }
            let ret = returnsFor(feature: "limit", method: method) ?? "no"
            findings.append(Finding(kind: .limit, name: method,
                detail: tr("usage limit: \(ret == "count" ? "999 remaining" : ret == "zero" ? "0 used" : "limit removed")",
                           "حد استخدام: \(ret == "count" ? "999 متبقي" : ret == "zero" ? "0 مستخدم" : "تم إلغاء الحد")",
                           ckb: "سنووری بەکارهێنان: \(ret == "count" ? "999 ماوە" : ret == "zero" ? "0 بەکارهاتووە" : "سنوورەکە لابرا")",
                           kmr: "Sînorê bikaranînê: \(ret == "count" ? "999 mayî" : ret == "zero" ? "0 hatiye bikaranîn" : "Sînor hat rakirin")"),
                unlockable: true))
            hooks.append(Hook(className: "", selector: method, returns: ret, feature: "limit"))
        }
        var seenLimitStrings = Set<String>()
        let loweredLimitStrings = limitStrings.map { $0.lowercased() }
        for s in cstrings {
            let lower = s.lowercased()
            guard loweredLimitStrings.contains(where: { lower.contains($0) }) else { continue }
            guard seenLimitStrings.insert(s).inserted else { continue }
            findings.append(Finding(kind: .limit, name: s,
                detail: tr("usage-limit text (no method found to hook)",
                           "نص حد استخدام (ما لقينا دالة لتعطيلها)",
                           ckb: "دەقی سنووری بەکارهێنان (هیچ فەنکشنێک نەدۆزرایەوە)",
                           kmr: "Nivîsa sînorê bikaranînê (rêbaz nehat dîtin)"),
                unlockable: false))
        }

        // (b3) Extra features — method symbols, class names and string
        // constants from patterns.json `features`, one finding per match.
        // Method matches get a hook (unless the feature is handled by a
        // built-in dylib hook); class matches of dismiss-type features
        // (paywall / onboarding / login screens) get a viewDidAppear
        // dismiss hook; other class matches are findings only.
        let featureIDs = featurePatterns.keys.sorted()
        for id in featureIDs {
            guard let kind = FindingKind(rawValue: id) else { continue }
            let pats = featurePatterns[id]!
            let loweredSymbols = pats.symbols.map { $0.lowercased() }
            for method in methods {
                let lower = method.lowercased()
                guard loweredSymbols.contains(where: { lower.contains($0) }) else { continue }
                guard seenSelectors.insert(method).inserted else { continue }
                findings.append(Finding(kind: kind, name: method,
                    detail: featureDetail(for: id),
                    unlockable: true))
                if let ret = returnsFor(feature: id, method: method) {
                    hooks.append(Hook(className: "", selector: method, returns: ret, feature: id))
                }
            }
            for cls in classes {
                guard pats.classes.contains(where: { cls == $0 || cls.contains($0) }) else { continue }
                findings.append(Finding(kind: kind, name: cls,
                    detail: featureDetail(for: id),
                    unlockable: true))
                if dismissFeatures.contains(id) {
                    hooks.append(Hook(className: cls, selector: "viewDidAppear:", returns: "dismiss", feature: id))
                }
            }
            let loweredStrings = pats.strings.map { $0.lowercased() }
            if !loweredStrings.isEmpty {
                var seen = Set<String>()
                for s in cstrings {
                    let lower = s.lowercased()
                    guard loweredStrings.contains(where: { lower.contains($0) }) else { continue }
                    guard seen.insert(s).inserted else { continue }
                    findings.append(Finding(kind: kind, name: s,
                        detail: featureDetail(for: id),
                        unlockable: false))
                }
            }
        }

        // (c) Ad SDKs — one finding per detected ad SDK. `unlockable` is
        // false: ads are not a premium check, they are a fallback target
        // (blockable). The dylib gets their lowercase ids via `adSDKs`.
        var adFindings: [Finding] = []
        var adSDKs: [String] = []
        for (sdk, id, sdkNames) in adSDKClasses {
            if let match = classes.first(where: { c in sdkNames.contains { c == $0 || c.contains($0) } }) {
                adSDKs.append(id)
                adFindings.append(Finding(kind: .ads, name: sdk, detail: match, unlockable: false))
            }
        }
        adFindings.sort { $0.name < $1.name }
        adSDKs.sort()
        findings += adFindings

        // (d) Server-side indicators in __cstring URL-like strings.
        var serverFindings: [Finding] = []
        var seenServers = Set<String>()
        for s in cstrings {
            let lower = s.lowercased()
            let looksLikeURL = lower.contains("http") || lower.hasPrefix("api.")
            guard looksLikeURL, serverKeywords.contains(where: { lower.contains($0) }) else { continue }
            let name = serverDisplayName(s)
            guard seenServers.insert(name).inserted else { continue }
            serverFindings.append(Finding(kind: .server, name: name,
                detail: tr("server-side check", "فحص من جهة السيرفر",
                           ckb: "پشکنینی لایەنی سێرڤەر",
                           kmr: "Kontrola aliyê serverê"),
                unlockable: false))
        }
        serverFindings.sort { $0.name < $1.name }
        findings += serverFindings

        // Live-tracing candidates: every hook selector (deduped) plus
        // common subscription getters the binary did not name. The dylib
        // only wraps zero-arg getters, so selectors that take arguments
        // are listed here and skipped there with a log line.
        var traceCandidates: [Hook] = []
        var seenCandidateSelectors = Set<String>()
        for h in hooks where seenCandidateSelectors.insert(h.selector).inserted {
            traceCandidates.append(Hook(className: h.className, selector: h.selector, returns: "yes", feature: "trace"))
        }
        for sel in Self.commonSubscriptionSelectors where seenCandidateSelectors.insert(sel).inserted {
            traceCandidates.append(Hook(className: "", selector: sel, returns: "yes", feature: "trace"))
        }

        return Report(findings: findings, hooks: hooks, sdks: sdks, adSDKs: adSDKs, traceCandidates: traceCandidates)
    }

    /// Common subscription getters, traced even when the binary never
    /// names them (obfuscated / Swift-mangled code). Best-effort: the
    /// dylib only wraps the ones that exist as zero-arg getters.
    static let commonSubscriptionSelectors = [
        "isPremium", "isPro", "isSubscribed", "isSubscriber", "hasPremium",
        "isPremiumUser", "hasActiveSubscription", "isEntitled", "hasEntitlement",
        "isVIP", "isPaid", "hasPaidAccess", "isLifetime", "hasLifetimeAccess",
        "subscriptionStatus", "isTrialActive", "hasTrialExpired", "validateReceipt",
        "isUserPremium", "hasActiveEntitlement",
    ]

    /// Short detail line per feature id, shown under each finding.
    private static func featureDetail(for id: String) -> String {
        switch id {
        case "paywall":
            return tr("paywall screen", "شاشة الدفع", "شاشەی پارەدان", "Dîmendera dravdanê")
        case "tracking":
            return tr("analytics / tracking", "تتبّع وتحليلات", "شوێنکەوتن و شیکاری", "Şopandin û analîtîk")
        case "watermark":
            return tr("watermark", "علامة مائية", "نیشانەی ئاوی", "Nîşana avê")
        case "login":
            return tr("forced login", "تسجيل دخول إجباري", "چوونەژوورەوەی زۆرەملێ", "Têketina zorê")
        case "jailbreak":
            return tr("jailbreak / tamper check", "فحص جيلبريك / تلاعب", "پشکنینی جەیڵبرەیک", "Kontrola jailbreak")
        case "ssl":
            return tr("SSL pinning (diagnostic)", "تثبيت SSL (تشخيصي)", "پینکردنی SSL (دەستنیشانکردن)", "SSL pinning (teşhîs)")
        case "location":
            return tr("location / region", "الموقع / المنطقة", "شوێن / ناوچە", "Cih / herêm")
        case "flags":
            return tr("hidden feature flag", "ميزة مخفية", "تایبەتمەندیی شاراوە", "Taybetmendiya veşartî")
        case "onboarding":
            return tr("onboarding / splash screen", "شاشة البداية", "شاشەی دەستپێک", "Dîmendera destpêkê")
        case "update":
            return tr("forced update check", "فحص تحديث إجباري", "پشکنینی نوێکردنەوەی زۆرەملێ", "Kontrola nûvekirina zorê")
        case "trial":
            return tr("trial expiry", "انتهاء التجربة", "بەسەرچوونی تاقیکردنەوە", "Qedandina ceribandinê")
        case "connectivity":
            return tr("connectivity check", "فحص الاتصال", "پشکنینی پەیوەندی", "Kontrola girêdanê")
        default:
            return tr("extra feature", "ميزة إضافية", "تایبەتمەندیی زیاتر", "Taybetmendiyeke zêde")
        }
    }

    /// Host of a URL string when it parses, otherwise the string truncated
    /// to 64 characters. "api."-prefixed strings get a scheme for parsing.
    private static func serverDisplayName(_ s: String) -> String {
        let candidate = s.lowercased().hasPrefix("http") ? s : "https://" + s
        if let host = URL(string: candidate)?.host, !host.isEmpty { return host }
        if s.count > 64 { return String(s.prefix(64)) + "…" }
        return s
    }
}
