import Foundation
import ZIPFoundation

/// Localization helper with a real German slot (the older tr() maps German to English).
func tr5(_ en: String, _ ar: String, de: String, ckb: String, kmr: String) -> String {
    switch L.lang { case .english: return en; case .german: return de; case .arabic: return ar; case .sorani: return ckb; case .kurmanji: return kmr }
}

/// Names only. Never contains code, strings, paths or app data.
struct ForgePortScan: Equatable {
    var version: String
    var build: String
    var bundleID: String
    var encrypted: Bool
    var classes: Set<String>
    var selectors: Set<String>
    var swiftSymbols: Int
}

enum ForgePortError: Error, LocalizedError {
    case notIPA, noApp, encrypted, unreadable, tooLarge, differentApp, nothingHooked
    var errorDescription: String? {
        switch self {
        case .notIPA: return tr5("Choose a decrypted .ipa file.", "اختار ملف .ipa مفكوك التشفير.", de: "Wähle eine entschlüsselte .ipa-Datei.", ckb: "فایلی .ipaی کراوەی ڕەمز هەڵبژێرە.", kmr: "Dosyayeke .ipa ya bê şîfre hilbijêre.")
        case .noApp: return tr5("No app was found inside this IPA.", "ما لقيت تطبيق جوا هالـ IPA.", de: "In dieser IPA wurde keine App gefunden.", ckb: "لەم IPAیەدا هیچ ئەپێک نەدۆزرایەوە.", kmr: "Di vê IPA de app nehat dîtin.")
        case .encrypted: return tr5("This IPA is still encrypted, so its classes cannot be read. Decrypt it first.", "هالـ IPA لسا مشفّر، فما بنقدر نقرأ الكلاسات. فك تشفيره أول.", de: "Diese IPA ist noch verschlüsselt, ihre Klassen können nicht gelesen werden. Entschlüssele sie zuerst.", ckb: "ئەم IPAیە هێشتا ڕەمزکراوە و کڵاسەکانی ناخوێنرێنەوە. سەرەتا ڕەمزەکەی لابەرە.", kmr: "Ev IPA hê şîfrekirî ye, ji ber vê klas nayên xwendin. Pêşî şîfreyê rake.")
        case .unreadable: return tr5("Could not read this IPA.", "ما قدرت اقرأ هالـ IPA.", de: "Diese IPA konnte nicht gelesen werden.", ckb: "نەتوانرا ئەم IPAیە بخوێندرێتەوە.", kmr: "Ev IPA nehat xwendin.")
        case .tooLarge: return tr5("The app binary is too large to scan (limit 600 MB).", "ملف التطبيق كبير للفحص (الحد 600 ميغا).", de: "Die App-Binärdatei ist zu groß zum Scannen (Limit 600 MB).", ckb: "فایلی ئەپەکە زۆر گەورەیە بۆ پشکنین (سنوور 600 مێگا).", kmr: "Binarya appê ji bo şopandinê pir mezin e (sînor 600 MB).")
        case .differentApp: return tr5("The old and new IPA are different apps. Choose two versions of the same app.", "الـ IPA القديم والجديد تطبيقين مختلفين. اختار نسختين من نفس التطبيق.", de: "Alte und neue IPA sind verschiedene Apps. Wähle zwei Versionen derselben App.", ckb: "IPAی کۆن و نوێ دوو ئەپی جیاوازن. دوو وەشانی هەمان ئەپ هەڵبژێرە.", kmr: "IPAya kevn û nû du appên cuda ne. Du guhertoyên heman appê hilbijêre.")
        case .nothingHooked: return tr5("This tweak has no hooked classes to check.", "هالتويك ما فيه كلاسات مهووكة للفحص.", de: "Dieser Tweak hat keine gehookten Klassen zum Prüfen.", ckb: "ئەم تویکە هیچ کڵاسی هووککراوی بۆ پشکنین نییە.", kmr: "Di vê tweakê de klasa hookkirî ji bo kontrolê tune ye.")
        }
    }
}

enum ForgePortScanner {
    static let maxBinary = 600 * 1024 * 1024
    static let maxItems = 400_000

    static func scan(ipa: URL) throws -> ForgePortScan {
        guard ipa.pathExtension.lowercased() == "ipa" else { throw ForgePortError.notIPA }
        guard let archive = try? Archive(url: ipa, accessMode: .read) else { throw ForgePortError.unreadable }
        var plistEntry: Entry?
        for e in archive where e.type == .file {
            let parts = e.path.split(separator: "/")
            if parts.count == 3, parts[0] == "Payload", parts[1].hasSuffix(".app"), parts[2] == "Info.plist" { plistEntry = e; break }
        }
        guard let plistEntry else { throw ForgePortError.noApp }
        var plistData = Data()
        guard plistEntry.uncompressedSize < 4_000_000,
              (try? archive.extract(plistEntry, consumer: { plistData.append($0) })) != nil,
              let plist = try? PropertyListSerialization.propertyList(from: plistData, options: [], format: nil) as? [String: Any],
              let exe = plist["CFBundleExecutable"] as? String, !exe.contains("/"), !exe.isEmpty
        else { throw ForgePortError.noApp }
        let appDir = plistEntry.path.split(separator: "/").prefix(2).joined(separator: "/")
        guard let binEntry = archive[appDir + "/" + exe] else { throw ForgePortError.noApp }
        guard binEntry.uncompressedSize <= UInt64(maxBinary) else { throw ForgePortError.tooLarge }
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("port-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tmp) }
        do { _ = try archive.extract(binEntry, to: tmp) } catch { throw ForgePortError.unreadable }
        let data = try Data(contentsOf: tmp, options: .alwaysMapped)
        var scan = try parse(data)
        scan.version = (plist["CFBundleShortVersionString"] as? String).map { String($0.prefix(32)) } ?? ""
        scan.build = (plist["CFBundleVersion"] as? String).map { String($0.prefix(32)) } ?? ""
        scan.bundleID = (plist["CFBundleIdentifier"] as? String) ?? ""
        if scan.encrypted { throw ForgePortError.encrypted }
        scan.classes.formUnion(ForgeFrameworkClasses.classes(ipa: ipa))
        return scan
    }

    static func parse(_ data: Data) throws -> ForgePortScan {
        func u32(_ o: Int, big: Bool = false) -> UInt32? {
            guard o >= 0, o + 4 <= data.count else { return nil }
            let v = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: o, as: UInt32.self) }
            return big ? v.byteSwapped : v
        }
        func u64(_ o: Int) -> Int? {
            guard o >= 0, o + 8 <= data.count else { return nil }
            let v = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: o, as: UInt64.self) }
            return v <= UInt64(Int.max) ? Int(v) : nil
        }
        guard let magic = u32(0) else { throw ForgePortError.unreadable }
        var base = 0, sliceEnd = data.count
        if magic == 0xBEBAFECA {
            guard let n = u32(4, big: true), n > 0, n <= 16 else { throw ForgePortError.unreadable }
            var found = false
            for i in 0..<Int(n) {
                let e = 8 + i * 20
                if u32(e, big: true) == 0x0100000C, let off = u32(e + 8, big: true), let sz = u32(e + 12, big: true),
                   Int(off) + Int(sz) <= data.count { base = Int(off); sliceEnd = Int(off) + Int(sz); found = true; break }
            }
            guard found else { throw ForgePortError.unreadable }
        }
        guard u32(base) == 0xFEEDFACF, let ncmds = u32(base + 16), ncmds <= 4096 else { throw ForgePortError.unreadable }
        var off = base + 32
        var encrypted = false
        var classes = Set<String>(), selectors = Set<String>()
        var swift = 0
        func strings(_ start: Int, _ size: Int, into set: inout Set<String>) {
            guard start >= 0, size > 0, start + size <= sliceEnd else { return }
            var cur = start
            let end = start + size
            while cur < end, set.count < maxItems {
                guard let z = data[cur..<end].firstIndex(of: 0) else { break }
                if z > cur, z - cur <= 256, let s = String(data: data[cur..<z], encoding: .utf8) { set.insert(s) }
                cur = z + 1
            }
        }
        for _ in 0..<Int(ncmds) {
            guard off + 8 <= sliceEnd, let cmd = u32(off), let size = u32(off + 4), size >= 8 else { break }
            if cmd == 0x2C { encrypted = (u32(off + 16) ?? 0) != 0 }
            if cmd == 0x19, let nsects = u32(off + 64), nsects <= 256 {
                var s = off + 72
                for _ in 0..<Int(nsects) {
                    guard s + 80 <= sliceEnd, let nameBytes = Optional(data[s..<s + 16].prefix { $0 != 0 }) else { break }
                    let name = String(decoding: nameBytes, as: UTF8.self)
                    if name == "__objc_classname" || name == "__objc_methname", let sz = u64(s + 40), let fo = u32(s + 48) {
                        if name == "__objc_classname" { strings(base + Int(fo), sz, into: &classes) }
                        else { strings(base + Int(fo), sz, into: &selectors) }
                    }
                    s += 80
                }
            }
            if cmd == 0x2, let symoff = u32(off + 8), let nsyms = u32(off + 12), let stroff = u32(off + 16), let strsize = u32(off + 20) {
                var seen = 0
                for i in 0..<min(Int(nsyms), 400_000) {
                    guard let strx = u32(base + Int(symoff) + i * 16), strx < strsize else { continue }
                    let p = base + Int(stroff) + Int(strx)
                    if p + 3 <= sliceEnd, data[p] == 0x5F, data[p + 1] == 0x24, data[p + 2] == 0x73 { seen += 1 }
                }
                swift = seen
            }
            off += Int(size)
        }
        return ForgePortScan(version: "", build: "", bundleID: "", encrypted: encrypted, classes: classes, selectors: selectors, swiftSymbols: swift)
    }
}

struct ForgePortUnresolved: Equatable { let kind: String; let name: String; let candidates: [String] }
struct ForgePortMapping: Equatable { let old: String; let new: String; let reason: String }
struct ForgePortPlan: Equatable {
    var intact: [String]
    var mappings: [ForgePortMapping]
    var unresolved: [ForgePortUnresolved]
}

enum ForgePortMapper {
    /// Class names the tweak source hooks, with the selectors it overrides in each %hook block.
    static func hooks(in code: String) -> [String: Set<String>] {
        var result: [String: Set<String>] = [:]
        var current: String?
        let hookRe = try! NSRegularExpression(pattern: "^\\s*%hook\\s+([A-Za-z_][A-Za-z0-9_.$]*)")
        let methRe = try! NSRegularExpression(pattern: "^\\s*[-+]\\s*\\([^)]*\\)\\s*(.+?)\\s*\\{?\\s*$")
        let getRe = try! NSRegularExpression(pattern: "(?:objc_getClass\\(\\s*\"|NSClassFromString\\(\\s*@\")([A-Za-z_][A-Za-z0-9_.$]*)\"")
        for raw in code.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(raw), ns = line as NSString, range = NSRange(location: 0, length: ns.length)
            if let m = hookRe.firstMatch(in: line, range: range) {
                current = ns.substring(with: m.range(at: 1)); result[current!, default: []] = result[current!] ?? []; continue
            }
            if line.trimmingCharacters(in: .whitespaces) == "%end" { current = nil; continue }
            for m in getRe.matches(in: line, range: range) { let n = ns.substring(with: m.range(at: 1)); result[n] = result[n] ?? [] }
            if let c = current, let m = methRe.firstMatch(in: line, range: range) {
                result[c, default: []].insert(selector(ns.substring(with: m.range(at: 1))))
            }
        }
        return result
    }
    static func selector(_ declaration: String) -> String {
        let re = try! NSRegularExpression(pattern: "([A-Za-z_][A-Za-z0-9_]*)\\s*:")
        let ns = declaration as NSString
        let parts = re.matches(in: declaration, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range(at: 1)) + ":" }
        if !parts.isEmpty { return parts.joined() }
        let id = declaration.prefix { $0.isLetter || $0.isNumber || $0 == "_" }
        return String(id)
    }
    /// Swift-exposed names: _TtC<n>Module<n>Name or Module.Name reduce to Name.
    static func baseName(_ name: String) -> String {
        if name.hasPrefix("_TtC") {
            var rest = Substring(name.dropFirst(4)), last = ""
            while let n = Int(rest.prefix { $0.isNumber }), n > 0 {
                let digits = rest.prefix { $0.isNumber }.count
                rest = rest.dropFirst(digits)
                guard rest.count >= n else { break }
                last = String(rest.prefix(n)); rest = rest.dropFirst(n)
            }
            if !last.isEmpty { return last }
        }
        if let dot = name.lastIndex(of: "."), name.index(after: dot) < name.endIndex { return String(name[name.index(after: dot)...]) }
        return name
    }

    /// Deterministic and conservative. Only an unambiguous exact base-name match is mapped.
    /// Everything else is reported, never guessed. Selectors are checked, never rewritten.
    static func plan(code: String, old: ForgePortScan, new: ForgePortScan) -> ForgePortPlan {
        var plan = ForgePortPlan(intact: [], mappings: [], unresolved: [])
        let added = new.classes.subtracting(old.classes)
        for (cls, sels) in hooks(in: code).sorted(by: { $0.key < $1.key }) {
            if new.classes.contains(cls) {
                plan.intact.append(cls)
            } else {
                let exact = added.filter { baseName($0) == baseName(cls) }.sorted()
                if old.classes.contains(cls), exact.count == 1 {
                    plan.mappings.append(ForgePortMapping(old: cls, new: exact[0], reason: "exactName"))
                } else {
                    let hint = Array(new.classes.filter { baseName($0).lowercased().hasPrefix(String(baseName(cls).lowercased().prefix(6))) }.sorted().prefix(5))
                    plan.unresolved.append(ForgePortUnresolved(kind: "class", name: cls, candidates: exact.isEmpty ? hint : Array(exact.prefix(5))))
                    continue
                }
            }
            for s in sels.sorted() where !s.isEmpty && !new.selectors.contains(s) {
                plan.unresolved.append(ForgePortUnresolved(kind: "selector", name: cls + " " + s, candidates: []))
            }
        }
        return plan
    }
}
