import Foundation

/// Translates an IPA's own UI strings (.strings and .xcstrings) into Arabic, Sorani and Kurmanji (or English)
/// through the Mirsa backend, then repacks the IPA with the new localizations. Nothing is signed here.
enum IPAStringsTranslator {
    struct Target: Hashable { let code: String; let label: String }
    static let targets: [Target] = [
        .init(code: "ar", label: "العربية"), .init(code: "ckb", label: "کوردی (سۆرانی)"),
        .init(code: "kmr", label: "Kurdî (Kurmancî)"), .init(code: "en", label: "English"),
    ]
    struct Scan {
        var strings: [String: [String: String]] = [:]   // key -> source text (per file path, flattened below)
        var files: [URL] = []
        var xcstrings: [URL] = []
    }
    struct Report { let output: URL; let files: Int; let strings: Int; let languages: [String] }

    private static let sourceNames = ["Base.lproj", "en.lproj"]

    /// Reads (file, key, value) from every source-language .strings file in the bundle.
    static func scan(app: URL) throws -> (files: [(url: URL, entries: [String: String])], xc: [URL]) {
        let fm = FileManager.default
        var files: [(URL, [String: String])] = []; var xc: [URL] = []
        guard let en = fm.enumerator(at: app, includingPropertiesForKeys: [.isRegularFileKey]) else { return ([], []) }
        for case let url as URL in en {
            let parent = url.deletingLastPathComponent().lastPathComponent
            if url.pathExtension == "xcstrings" { xc.append(url); continue }
            guard url.pathExtension == "strings", sourceNames.contains(parent) else { continue }
            if let d = try? Data(contentsOf: url),
               let o = try? PropertyListSerialization.propertyList(from: d, options: [], format: nil) as? [String: String], !o.isEmpty {
                files.append((url, o))
            }
        }
        return (files, xc)
    }

    /// Strings that need no translation: empty, only symbols/digits, or file-like.
    static func translatable(_ s: String) -> Bool {
        s.rangeOfCharacter(from: .letters) != nil && !s.hasPrefix("http") && !s.contains("/") || s.contains(" ")
    }

    static func translate(_ items: [String: String], to code: String) async throws -> [String: String] {
        var out: [String: String] = [:]
        let keys = items.keys.sorted()
        var i = 0
        while i < keys.count {
            let slice = keys[i..<min(i + 60, keys.count)]
            let payload = slice.map { ["k": $0, "v": items[$0]!] }
            let r = try await ForgeClient.json(["action": "translate", "target": code, "items": payload])
            for (k, v) in (r["translations"] as? [String: String]) ?? [:] where items[k] != nil { out[k] = v }
            i += 60
        }
        return out
    }

    /// Full pipeline: extract, translate, write localizations, repack. Returns the new IPA in tmp.
    static func run(ipa: URL, languages: [Target], progress: @escaping @Sendable (String) -> Void) async throws -> Report {
        let fm = FileManager.default
        let stage = fm.temporaryDirectory.appendingPathComponent("tr-" + UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: stage, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: stage) }
        let extract = stage.appendingPathComponent("x", isDirectory: true)
        try await Task.detached { try IPAEditorService.run("extract", input: ipa, output: extract) }.value
        let app = try IPAEditorService.app(in: extract)
        let scanned = try scan(app: app)
        guard !scanned.files.isEmpty || !scanned.xc.isEmpty else {
            throw ForgeClient.Failure.message(tr("No translatable strings found in this app.", "ما لقيت نصوص قابلة للترجمة بهالتطبيق.", ckb: "هیچ دەقێکی وەرگێڕدراو لەم ئەپەدا نەدۆزرایەوە.", kmr: "Di vê appê de nivîsa wergerandinê nehat dîtin."))
        }
        var total = 0
        for lang in languages {
            progress(lang.label)
            for (url, entries) in scanned.files {
                let todo = entries.filter { translatable($0.value) }
                guard !todo.isEmpty else { continue }
                var done = try await translate(todo, to: lang.code)
                for (k, v) in entries where done[k] == nil { done[k] = v }
                let dir = url.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent(lang.code + ".lproj", isDirectory: true)
                try fm.createDirectory(at: dir, withIntermediateDirectories: true)
                let data = try PropertyListSerialization.data(fromPropertyList: done, format: .binary, options: 0)
                try data.write(to: dir.appendingPathComponent(url.lastPathComponent), options: .atomic)
                total += todo.count
            }
            for url in scanned.xc { total += try await translateCatalog(url, code: lang.code) }
        }
        try updateLocalizations(app: app, codes: languages.map(\.code))
        let pack = fm.temporaryDirectory.appendingPathComponent("Translated-" + UUID().uuidString + ".ipa")
        let root = extract
        try await Task.detached { try IPAEditorService.run("pack", input: root, output: pack) }.value
        return Report(output: pack, files: scanned.files.count + scanned.xc.count, strings: total, languages: languages.map(\.label))
    }

    /// .xcstrings: add a translated stringUnit for the language to every key that has a source value.
    private static func translateCatalog(_ url: URL, code: String) async throws -> Int {
        guard var root = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any],
              var strings = root["strings"] as? [String: Any] else { return 0 }
        let source = (root["sourceLanguage"] as? String) ?? "en"
        var todo: [String: String] = [:]
        for (key, raw) in strings {
            let entry = raw as? [String: Any] ?? [:]
            let locs = entry["localizations"] as? [String: Any] ?? [:]
            // Plural / device variations and substitutions are not handled yet: skip them instead of translating the key wrongly.
            let srcLoc = locs[source] as? [String: Any]
            if entry["shouldTranslate"] as? Bool == false || srcLoc?["variations"] != nil || srcLoc?["substitutions"] != nil { continue }
            let text = ((locs[source] as? [String: Any])?["stringUnit"] as? [String: Any])?["value"] as? String ?? key
            if translatable(text), locs[code] == nil { todo[key] = text }
        }
        let done = try await translate(todo, to: code)
        for (key, value) in done {
            var entry = strings[key] as? [String: Any] ?? [:]
            var locs = entry["localizations"] as? [String: Any] ?? [:]
            locs[code] = ["stringUnit": ["state": "translated", "value": value]]
            entry["localizations"] = locs; strings[key] = entry
        }
        root["strings"] = strings
        try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys]).write(to: url, options: .atomic)
        return done.count
    }

    private static func updateLocalizations(app: URL, codes: [String]) throws {
        let plist = app.appendingPathComponent("Info.plist")
        var info = try IPAEditorService.info(in: app)
        var list = (info["CFBundleLocalizations"] as? [String]) ?? []
        for c in codes where !list.contains(c) { list.append(c) }
        info["CFBundleLocalizations"] = list
        try PropertyListSerialization.data(fromPropertyList: info, format: .binary, options: 0).write(to: plist, options: .atomic)
    }
}
