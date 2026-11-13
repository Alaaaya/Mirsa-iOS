import Foundation

/// Per-component injection method. Raw values are the backend contract keys (inject_plan "method").
enum InjectionMethod: String, Codable, CaseIterable, Sendable {
    case direct, load_control, shared_library, separate_extension

    var title: String {
        switch self {
        case .direct: return tr("Direct (Mach-O load command)", "مباشر (أمر تحميل في Mach-O)", ckb: "ڕاستەوخۆ (فەرمانی بارکردنی Mach-O)", kmr: "Rasterast (fermana barkirinê ya Mach-O)")
        case .load_control: return tr("LoadControl (in-app, arm64 only)", "LoadControl (داخل التطبيق، arm64 بس)", ckb: "LoadControl (لەناو ئەپ، تەنها arm64)", kmr: "LoadControl (di nav sepanê de, tenê arm64)")
        case .shared_library: return tr("Shared library", "مكتبة مشتركة", ckb: "کتێبخانەی هاوبەش", kmr: "Pirtûkxaneya parvekirî")
        case .separate_extension: return tr("Separate extension", "امتداد منفصل", ckb: "پێوەکراوی جیا", kmr: "Pêvekeya cuda")
        }
    }

    var explanation: String {
        switch self {
        case .direct: return tr("Adds a load command to the selected executable(s).", "بيضيف أمر تحميل للملف التنفيذي المحدد.", ckb: "فەرمانی بارکردن زیاد دەکات بۆ فایلی جێبەجێکراوی هەڵبژێردراو.", kmr: "Fermana barkirinê li pelê hilbijartî zêde dike.")
        case .load_control: return tr("Loads libraries in order through an app-owned loader in the main app or a selected extension. Thin arm64 only.", "بيحمّل المكتبات بالترتيب من التطبيق الرئيسي أو امتداد بتختاره. arm64 مفرد بس.", ckb: "کتێبخانەکان بە ڕیز لە ئەپی سەرەکی یان پێوەکراوی هەڵبژێردراو بار دەکات. تەنها arm64ی تاک.", kmr: "Pirtûkxaneyan bi rêz di sepana sereke an pêveka hilbijartî de bar dike. Tenê arm64.")
        case .shared_library: return tr("Adds a shared dependency to each selected process. Scopes are separate processes; load order across them is not guaranteed at runtime.", "بيضيف اعتمادية مشتركة لكل عملية محددة. كل عملية مستقلة وترتيب التحميل بينها مو مضمون وقت التشغيل.", ckb: "پشتبەستنێکی هاوبەش بۆ هەر پرۆسەیەکی هەڵبژێردراو زیاد دەکات. پرۆسەکان جیان و ڕیزبەندی بارکردن لە کاتی کارکردن زامن نییە.", kmr: "Girêdaneke parvekirî li her pêvajoya hilbijartî zêde dike. Pêvajo ji hev cuda ne û rêza barkirinê di dema xebatê de nayê garantîkirin.")
        case .separate_extension: return tr("Injects into existing app extension(s) you pick, optionally with the main app too. No new extension is created.", "بيحقن بامتدادات التطبيق الموجودة اللي بتختارها، وممكن مع التطبيق الرئيسي. ما بنعمل امتداد جديد.", ckb: "دەیخاتە ناو پێوەکراوە بوونەکانی ئەپ کە هەڵیدەبژێریت، دەکرێت لەگەڵ ئەپی سەرەکی. پێوەکراوی نوێ دروست ناکرێت.", kmr: "Di pêvekên heyî yên ku hilbijêrî de dixe, dikare bi sepana sereke re jî. Pêvekeke nû nayê çêkirin.")
        }
    }
}

struct InjectionTarget: Sendable, Equatable { var id: String; var kind: String; var label: String }
struct SharedCandidate: Sendable, Equatable { var id: String; var label: String; var processes: [String]
    /// Candidate identity includes its verified process pair, not just the shared binary.
    var selectionID: String {
        let data = (try? JSONEncoder().encode([id] + processes)) ?? Data()
        return data.base64EncodedString()
    }
}

/// Per-component, backend-verified capability. Missing component or missing method = disabled (fail closed).
struct ComponentCapabilities: Sendable, Equatable {
    var id: String
    var enabled: Set<InjectionMethod> = []
    var reasons: [InjectionMethod: String] = [:]
    /// Exact process/executable ids the backend probed as valid per method. No entry = no valid target.
    var eligibleTargets: [InjectionMethod: [String]] = [:]
    var sharedCandidates: [SharedCandidate] = []
    func isEnabled(_ m: InjectionMethod) -> Bool { enabled.contains(m) }
    func eligible(_ m: InjectionMethod) -> [String] { eligibleTargets[m] ?? [] }
}

/// Backend-verified capabilities. Default is EMPTY: nothing is enabled until the backend reported it for that component.
/// Global fields are informational only; gating always uses the per-component entry and never inherits from another component or the global list.
struct InjectionCapabilities: Sendable, Equatable {
    var enabled: Set<InjectionMethod> = []
    var reasons: [InjectionMethod: String] = [:]
    var targets: [InjectionTarget] = []
    var sharedCandidates: [SharedCandidate] = []
    var sharedDisabledReason: String? = nil
    var components: [String: ComponentCapabilities] = [:]

    func component(_ id: String) -> ComponentCapabilities? { components[id] }
    func isEnabled(_ m: InjectionMethod, component id: String) -> Bool { components[id]?.isEnabled(m) ?? false }
    var extensionTargets: [InjectionTarget] { targets.filter { $0.kind == "extension" } }
    var mainTarget: InjectionTarget? { targets.first { $0.kind == "main" } }
    func label(_ id: String) -> String { targets.first { $0.id == id }?.label ?? id }

    private static func candidates(_ raw: Any?) -> [SharedCandidate] {
        var out: [SharedCandidate] = []
        for c in raw as? [[String: Any]] ?? [] {
            guard let id = c["id"] as? String else { continue }
            out.append(SharedCandidate(id: id, label: c["label"] as? String ?? id, processes: c["processes"] as? [String] ?? []))
        }
        return out
    }

    /// Parses the backend injection_capabilities JSON. Unknown method ids are ignored, never enabled.
    static func parse(_ data: Data) -> InjectionCapabilities? {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        var caps = InjectionCapabilities()
        for t in root["targets"] as? [[String: Any]] ?? [] {
            guard let id = t["id"] as? String, let kind = t["kind"] as? String else { continue }
            caps.targets.append(InjectionTarget(id: id, kind: kind, label: t["label"] as? String ?? id))
        }
        for m in root["methods"] as? [[String: Any]] ?? [] {
            guard let raw = m["id"] as? String, let method = InjectionMethod(rawValue: raw) else { continue }
            if m["enabled"] as? Bool == true { caps.enabled.insert(method) }
            if let r = m["reason"] as? String { caps.reasons[method] = r }
        }
        caps.sharedCandidates = candidates(root["sharedCandidates"])
        caps.sharedDisabledReason = root["sharedDisabledReason"] as? String
        for c in root["components"] as? [[String: Any]] ?? [] {
            guard let id = c["id"] as? String, caps.components[id] == nil else { continue }
            var comp = ComponentCapabilities(id: id)
            for m in c["methods"] as? [[String: Any]] ?? [] {
                guard let raw = m["id"] as? String, let method = InjectionMethod(rawValue: raw) else { continue }
                if m["enabled"] as? Bool == true { comp.enabled.insert(method) }
                if let r = m["reason"] as? String { comp.reasons[method] = r }
            }
            if let el = c["eligibleTargets"] as? [String: Any] {
                for (k, v) in el { if let method = InjectionMethod(rawValue: k), let ids = v as? [String] { comp.eligibleTargets[method] = ids } }
            }
            comp.sharedCandidates = candidates(c["sharedCandidates"])
            // A method is only usable with something to select.
            if comp.sharedCandidates.isEmpty { comp.enabled.remove(.shared_library) }
            if comp.eligible(.separate_extension).isEmpty { comp.enabled.remove(.separate_extension) }
            if comp.eligible(.direct).isEmpty { comp.enabled.remove(.direct) }
            if comp.eligible(.load_control).isEmpty { comp.enabled.remove(.load_control) }
            caps.components[id] = comp
        }
        return caps
    }

    /// Localized reason for a method being disabled for one component.
    func disabledReason(_ m: InjectionMethod, component id: String) -> String? {
        guard let comp = components[id] else {
            return tr("Reload targets to check this tweak.", "أعد تحميل الأهداف لنتأكد من هالإضافة.", ckb: "ئامانجەکان دووبارە بار بکە بۆ پشکنینی ئەم زیادکراوە.", kmr: "Armancan ji nû ve bar bike da ku ev pêvek were kontrolkirin.")
        }
        if comp.isEnabled(m) { return nil }
        guard let code = comp.reasons[m] else {
            return tr("The backend did not confirm this method for this tweak.", "الباكند ما أكد هالطريقة لهالإضافة.", ckb: "باکێند ئەم ڕێگایەی بۆ ئەم زیادکراوە پشتڕاست نەکردەوە.", kmr: "Paşxanê ev rêbaz ji bo vê pêvekê piştrast nekir.")
        }
        return Self.reasonText(code)
    }

    static func reasonText(_ code: String) -> String {
        switch code {
        case "no_extensions": return tr("This app has no extensions to inject into.", "هالتطبيق ما فيه امتدادات للحقن.", ckb: "ئەم ئەپە پێوەکراوی نییە بۆ تێخستن.", kmr: "Di vê sepanê de pêvek tune ne ku tê de were derzîkirin.")
        case "shared_requires_main_and_extension", "shared_requires_process_targets": return tr("Needs the main app and at least one extension.", "بدها التطبيق الرئيسي وامتداد واحد على الأقل.", ckb: "ئەپی سەرەکی و لانیکەم یەک پێوەکراوی پێویستە.", kmr: "Sepana sereke û herî kêm pêvekek divê.")
        case "shared_no_common_dependency": return tr("The processes share no common bundled library.", "العمليات ما بتشترك بأي مكتبة مضمّنة.", ckb: "پرۆسەکان هیچ کتێبخانەیەکی هاوبەشیان نییە.", kmr: "Di navbera pêvajoyan de pirtûkxaneyeke hevpar tune ye.")
        case "shared_unsupported_fat_or_abi": return tr("A required binary is not a thin arm64 file.", "في ملف مطلوب مو arm64 مفرد.", ckb: "فایلێکی پێویست arm64ی تاک نییە.", kmr: "Pelekî pêwîst ne arm64ya tenê ye.")
        case "shared_dependency_cycle", "shared_graph_limit", "shared_unresolved_or_ambiguous_dependency": return tr("The dependency graph could not be verified safely.", "ما قدرنا نتحقق من رسم الاعتماديات بأمان.", ckb: "نەتوانرا گرافی پشتبەستن بە سەلامەتی بسەلمێنرێت.", kmr: "Grafika girêdanan bi ewlehî nehat verastkirin.")
        default: return tr("The backend reports this method is unavailable for this app.", "الباكند بيقول هالطريقة مو متاحة لهالتطبيق.", ckb: "باکێند دەڵێت ئەم ڕێگایە بۆ ئەم ئەپە بەردەست نییە.", kmr: "Paşxanê dibêje ev rêbaz ji bo vê sepanê ne berdest e.")
        }
    }
}

/// One inject_plan entry. targets/sharedTarget are optional and only emitted when set.
struct InjectionPlanEntry: Codable, Sendable, Equatable {
    var id: String
    var library: String
    var target: String
    var method: InjectionMethod
    var targets: [String]? = nil
    var sharedTarget: String? = nil

    var json: [String: Any] {
        var d: [String: Any] = ["id": id, "library": library, "target": target, "method": method.rawValue]
        if let targets { d["targets"] = targets }
        if let sharedTarget { d["sharedTarget"] = sharedTarget }
        return d
    }
}

enum InjectionMethodStore {
    /// Persisted method for a component. Explicit unknown values return nil (invalid, fail closed, no fallback).
    /// Only an absent entry migrates from the legacy global flag (false = LoadControl).
    static func method(for id: String, methods: [String: String]?, legacyDirect: Bool?) -> InjectionMethod? {
        if let raw = methods?[id] { return InjectionMethod(rawValue: raw) }
        return legacyDirect == false ? .load_control : .direct
    }

    /// Whether a method was explicitly configured by the user for this component (vs default/legacy).
    static func isConfigured(_ id: String, methods: [String: String]?) -> Bool { methods?[id] != nil }

    /// nil when the backend does not currently report the method as enabled.
    static func effective(_ m: InjectionMethod, componentID: String, caps: InjectionCapabilities) -> InjectionMethod? {
        caps.isEnabled(m, component: componentID) ? m : nil
    }

    enum PlanError: Error, Equatable { case unknownMethod(String), unsupported(InjectionMethod), missingSelection(InjectionMethod), staleTarget(String), duplicateProcess(String) }

    /// Builds one entry from stored choices, validated against THIS component's backend capabilities.
    /// Explicit choices fail closed on missing component caps, disabled method, stale target or duplicates.
    /// Unconfigured legacy defaults (direct/LoadControl on the main executable) are preserved; the backend stays authoritative at inject time.
    static func entry(id: String, library: String, tweakTarget: String?, methods: [String: String]?, legacyDirect: Bool?,
                      processTargets: [String: [String]]?, sharedTargets: [String: String]?, caps: InjectionCapabilities) throws -> InjectionPlanEntry {
        guard let m = method(for: id, methods: methods, legacyDirect: legacyDirect) else { throw PlanError.unknownMethod(methods?[id] ?? "") }
        guard let main = caps.mainTarget?.id else { throw PlanError.unsupported(m) }
        if !isConfigured(id, methods: methods) && (m == .direct || m == .load_control) {
            return InjectionPlanEntry(id: id, library: library, target: tweakTarget ?? main, method: m)
        }
        guard let comp = caps.component(id), comp.isEnabled(m) else { throw PlanError.unsupported(m) }
        let eligible = Set(comp.eligible(m))
        switch m {
        case .direct:
            let t = tweakTarget ?? main
            guard eligible.contains(t) else { throw PlanError.staleTarget(t) }
            return InjectionPlanEntry(id: id, library: library, target: t, method: m)
        case .load_control:
            let t = tweakTarget ?? main
            guard eligible.contains(t) else { throw PlanError.staleTarget(t) }
            return InjectionPlanEntry(id: id, library: library, target: t, method: m)
        case .separate_extension:
            let picked = processTargets?[id] ?? []
            guard !picked.isEmpty else { throw PlanError.missingSelection(m) }
            var seen = Set<String>()
            for p in picked {
                guard seen.insert(p).inserted else { throw PlanError.duplicateProcess(p) }
                let mainAllowed = p == main && comp.eligible(.direct).contains(main)
                guard eligible.contains(p) || mainAllowed else { throw PlanError.staleTarget(p) }
            }
            guard picked.contains(where: { p in caps.targets.contains { $0.id == p && $0.kind == "extension" } }) else { throw PlanError.missingSelection(m) }
            return InjectionPlanEntry(id: id, library: library, target: picked.contains(main) ? main : picked[0], method: m, targets: picked)
        case .shared_library:
            guard let s = sharedTargets?[id] else { throw PlanError.missingSelection(m) }
            let exact = comp.sharedCandidates.filter { $0.selectionID == s }
            let legacy = comp.sharedCandidates.filter { $0.id == s }
            guard let c = exact.first ?? (legacy.count == 1 ? legacy.first : nil) else { throw PlanError.staleTarget(s) }
            var seen = Set<String>()
            for p in c.processes { guard seen.insert(p).inserted else { throw PlanError.duplicateProcess(p) } }
            guard c.processes.contains(main), c.processes.count >= 2,
                  c.processes.allSatisfy({ id in caps.targets.contains { $0.id == id && ($0.kind == "main" || $0.kind == "extension") } })
            else { throw PlanError.missingSelection(m) }
            return InjectionPlanEntry(id: id, library: library, target: main, method: m, targets: c.processes, sharedTarget: c.id)
        }
    }
}
