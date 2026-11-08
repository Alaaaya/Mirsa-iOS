import Foundation

/// Decodes server refusal bodies into one localized, user-readable message (message/reason + optional step-by-step nextSteps).
enum ForgeServerMessage {
    static func lang() -> String {
        switch L.lang { case .english: return "en"; case .arabic: return "ar"; case .sorani: return "ckb"; case .kurmanji: return "kmr" }
    }

    private static func pick(_ v: Any?, _ lang: String) -> String? {
        if let s = v as? String { let t = s.trimmingCharacters(in: .whitespacesAndNewlines); return t.isEmpty ? nil : t }
        if let d = v as? [String: Any] {
            for k in [lang, "en"] { if let s = pick(d[k], lang) { return s } }
            return nil
        }
        return nil
    }
    private static func pickList(_ v: Any?, _ lang: String) -> [String] {
        if let a = v as? [Any] {
            return a.compactMap { pick($0, lang) ?? (($0 as? [String: Any]).flatMap { pick($0["text"] ?? $0["step"], lang) }) }
        }
        if let d = v as? [String: Any] {
            for k in [lang, "en"] { if d[k] != nil { let l = pickList(d[k], lang); if !l.isEmpty { return l } } }
        }
        if let s = pick(v, lang) { return [s] }
        return []
    }
    private static func field(_ o: [String: Any], _ names: [String], _ lang: String) -> String? {
        for n in names {
            if let s = pick(o[n], lang) { return s }
            let cap = n.prefix(1).uppercased() + n.dropFirst()
            for key in [n + "_" + lang, n + cap.prefix(0) + lang.capitalized, n + "_" + lang.uppercased(), n + lang.prefix(1).uppercased() + lang.dropFirst()] {
                if let s = pick(o[key], lang) { return s }
            }
        }
        return nil
    }

    /// Returns nil when the body has no usable server text.
    static func text(_ data: Data, lang: String) -> String? {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        var objs = [root]
        if let e = root["error"] as? [String: Any] { objs.append(e) }
        if let d = root["details"] as? [String: Any] { objs.append(d) }
        var main: String?, steps: [String] = []
        for o in objs {
            if main == nil { main = field(o, ["message", "reason", "detail", "localized", "error_description"], lang) }
            if steps.isEmpty {
                for n in ["nextSteps", "next_steps", "steps", "hints"] {
                    var l = pickList(o[n], lang)
                    if l.isEmpty { l = pickList(o[n + "_" + lang] ?? o[n + lang.prefix(1).uppercased() + lang.dropFirst()], lang) }
                    if !l.isEmpty { steps = Array(l.prefix(8)); break }
                }
            }
        }
        guard main != nil || !steps.isEmpty else { return nil }
        var out = main ?? ""
        if !steps.isEmpty {
            if !out.isEmpty { out += "\n\n" }
            out += steps.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
        }
        return String(out.prefix(1500))
    }
}
