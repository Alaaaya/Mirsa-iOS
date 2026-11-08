import Foundation
import SwiftUI

struct ForgeSetting: Codable, Hashable, Identifiable { var key: String; var title: String; var `default`: Bool; var id: String { key } }
struct ForgeVersion: Codable, Identifiable, Hashable {
    var id = UUID(); var created = Date(); var prompt: String; var code: String
    var settings: [ForgeSetting]; var explain: String; var builtWithValues: [String: Bool]?
    var guardID: UUID?
    var title: String?
    var repairChainID: UUID?
    var fixSourceSHA256: String?
    var fixDylibSHA256: String?
    var tweakID: UUID { guardID ?? id }
    var hasBuild: Bool { builtWithValues != nil }
}
struct ForgeProject: Codable, Identifiable {
    var id = UUID(); var name: String; var bundleID: String; var appName: String; var appVersion: String
    var executable: String; var classes: [String]; var versions: [ForgeVersion] = []; var current: UUID?
    var values: [String: Bool] = [:]
    var currentVersion: ForgeVersion? { versions.first { $0.id == current } ?? versions.last { $0.fixSourceSHA256 == nil } }
}

/// Persistence, AI generation, remote build, injection and export for tweak projects.
@MainActor final class ForgeStore: ObservableObject {
    static let shared = ForgeStore()
    @Published var projects: [ForgeProject] = []
    @Published var busy: String?
    @Published var builderReady = false
    @Published var pendingGalleryCode: String?
    @Published var fixNotice: String?
    var fixSyncing = false
    nonisolated static var root: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("MirsaForge", isDirectory: true)
    }
    private var index: URL { Self.root.appendingPathComponent("projects.json") }
    private init() {
        try? FileManager.default.createDirectory(at: Self.root, withIntermediateDirectories: true)
        if let d = try? Data(contentsOf: index), let p = try? JSONDecoder().decode([ForgeProject].self, from: d) { projects = p }
    }
    private func save() { try? JSONEncoder().encode(projects).write(to: index, options: .atomic) }
    func dir(_ p: ForgeProject) -> URL {
        let d = Self.root.appendingPathComponent(p.id.uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true); return d
    }
    func update(_ id: UUID, _ f: (inout ForgeProject) -> Void) {
        guard let i = projects.firstIndex(where: { $0.id == id }) else { return }
        f(&projects[i]); save()
    }
    func project(_ id: UUID) -> ForgeProject? { projects.first { $0.id == id } }

    struct TargetInfo { let name: String; let bundleID: String; let appName: String; let version: String; let executable: String; let classes: [String] }

    /// Opens the IPA, reads identity and (only if the binary is decrypted) the class list.
    nonisolated static func inspect(ipa: URL) async throws -> TargetInfo {
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory.appendingPathComponent("forge-" + UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tmp) }
        let x = tmp.appendingPathComponent("x", isDirectory: true)
        try IPAEditorService.run("extract_inspection", input: ipa, output: x)
        let app = try IPAEditorService.app(in: x)
        let info = try IPAEditorService.info(in: app)
        guard let id = info["CFBundleIdentifier"] as? String, let exe = info["CFBundleExecutable"] as? String else { throw ForgeClient.Failure.message(IPAEditorService.archiveError("Invalid app metadata")) }
        let mach: ForgeMachO.Info
        do { mach = try ForgeMachO.inspect(app.appendingPathComponent(exe)) }
        catch { throw ForgeClient.Failure.message(IPAEditorService.archiveError("Invalid app executable")) }
        if mach.encrypted {
            throw ForgeClient.Failure.message(tr("This app is encrypted (App Store build). Import a decrypted IPA to build tweaks for it.", "هالتطبيق مشفّر (نسخة App Store). استورد نسخة IPA مفكوكة التشفير لتبني تويكس إله.", ckb: "ئەم ئەپە ڕەمزکراوە (وەشانی App Store). IPAیەکی ڕەمزنەکراو هاوردە بکە بۆ دروستکردنی تویک.", kmr: "Ev app şîfrekirî ye (guhertoya App Store). IPAyeke bê şîfre têxe da ku tweak çêbikî."))
        }
        guard !mach.classes.isEmpty else { throw ForgeClient.Failure.message(tr("No Objective-C classes found in this app (Swift-only apps are not supported yet).", "ما لقيت كلاسات Objective-C بهالتطبيق (تطبيقات Swift فقط مو مدعومة بعد).", ckb: "هیچ کلاسێکی Objective-C نەدۆزرایەوە (ئەپی Swift تەنها هێشتا پشتگیری ناکرێت).", kmr: "Di vê appê de klasên Objective-C nehatin dîtin (appên Swift-only hê nayên piştgirîkirin).")) }
        let name = (info["CFBundleDisplayName"] as? String) ?? (info["CFBundleName"] as? String) ?? id
        return TargetInfo(name: name, bundleID: id, appName: name, version: (info["CFBundleShortVersionString"] as? String) ?? "?", executable: exe, classes: mach.classes)
    }

    func create(ipa: URL, info: TargetInfo) throws -> UUID {
        var p = ForgeProject(name: String(info.name.filter { $0.isLetter || $0.isNumber }.prefix(24)).isEmpty ? "Tweak" : "T" + String(info.name.filter { $0.isLetter || $0.isNumber }.prefix(24)),
                             bundleID: info.bundleID, appName: info.appName, appVersion: info.version, executable: info.executable, classes: info.classes)
        let scoped = ipa.startAccessingSecurityScopedResource(); defer { if scoped { ipa.stopAccessingSecurityScopedResource() } }
        try FileManager.default.copyItem(at: ipa, to: dir(p).appendingPathComponent("source.ipa"))
        p.name = "Tweak" + String(info.name.filter { $0.isLetter || $0.isNumber }.prefix(24))
        projects.insert(p, at: 0); save(); return p.id
    }
    /// Removes the entry with every version, dylib and the source IPA. The entry is kept when the files cannot be removed.
    func delete(_ id: UUID) throws {
        let folder = Self.root.appendingPathComponent(id.uuidString, isDirectory: true)
        if FileManager.default.fileExists(atPath: folder.path) { try FileManager.default.removeItem(at: folder) }
        projects.removeAll { $0.id == id }
        try JSONEncoder().encode(projects).write(to: index, options: .atomic)
    }
    /// Reads the display name from the stored source IPA (a snapshot, only the last fallback).
    nonisolated static func liveName(ipa: URL) async -> String? {
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory.appendingPathComponent("forgename-" + UUID().uuidString, isDirectory: true)
        defer { try? fm.removeItem(at: tmp) }
        guard (try? fm.createDirectory(at: tmp, withIntermediateDirectories: true)) != nil else { return nil }
        let x = tmp.appendingPathComponent("x", isDirectory: true)
        guard (try? IPAEditorService.run("extract_inspection", input: ipa, output: x)) != nil,
              let app = try? IPAEditorService.app(in: x), let info = try? IPAEditorService.info(in: app) else { return nil }
        return pickName(info)
    }
    nonisolated static func pickName(_ info: [String: Any]) -> String? {
        for k in ["CFBundleDisplayName", "CFBundleName"] { if let v = info[k] as? String, !v.trimmingCharacters(in: .whitespaces).isEmpty { return v } }
        return nil
    }
    /// Priority: project draft name, personal library, managed apps, downloads, then the source IPA snapshot.
    nonisolated static func resolveName(bundleID: String, drafts: [(bundleID: String, name: String)], library: [(bundleID: String, name: String)],
                                        managed: [(bundleID: String, name: String)], downloads: [(bundleID: String, name: String)]) -> String? {
        for list in [drafts, library, managed, downloads] {
            if let m = list.first(where: { $0.bundleID == bundleID && !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }) { return m.name }
        }
        return nil
    }
    func liveMetadataName(_ bundleID: String) -> String? {
        let lib = PersonalAppsLibrary.shared
        var drafts: [(bundleID: String, name: String)] = []
        for app in lib.apps {
            guard let d = try? Data(contentsOf: lib.draftURL(app)), let dr = try? JSONDecoder().decode(PersonalProjectDraft.self, from: d) else { continue }
            drafts.append((dr.bundleID.isEmpty ? app.bundleID : dr.bundleID, dr.name))
        }
        return Self.resolveName(bundleID: bundleID, drafts: drafts,
            library: lib.apps.map { ($0.bundleID, $0.name) },
            managed: AppsStore.shared.apps.map { ($0.id, $0.name) },
            downloads: DownloadsLibrary.shared.items.map { ($0.bundleID, $0.name) })
    }
    func refreshNames() async {
        for p in projects {
            var name = liveMetadataName(p.bundleID)
            if name == nil {
                let src = dir(p).appendingPathComponent("source.ipa")
                if FileManager.default.fileExists(atPath: src.path) { name = await Self.liveName(ipa: src) }
            }
            guard let n = name, n != p.appName else { continue }
            update(p.id) { $0.appName = n }
        }
    }

    // MARK: versions
    func generate(_ id: UUID, prompt: String) async throws {
        guard let p = project(id) else { return }
        busy = tr("Writing the tweak…", "عم أكتب التويك…", ckb: "تویک دەنووسم…", kmr: "Tweak tê nivîsandin…"); defer { busy = nil }
        let r = try await ForgeClient.json(["action": "generate", "prompt": prompt, "bundleID": p.bundleID, "name": ForgeFeaturePolicy.name(p.name),
                                            "classes": ForgeFeaturePolicy.classes(p.classes), "selectors": [String](), "previousCode": p.currentVersion?.code ?? ""])
        guard let code = r["code"] as? String else { throw ForgeClient.Failure.message("Bad response") }
        let settings = ((r["settings"] as? [[String: Any]]) ?? []).compactMap { s -> ForgeSetting? in
            guard let k = s["key"] as? String, let t = s["title"] as? String, let d = s["default"] as? Bool else { return nil }
            return ForgeSetting(key: k, title: t, default: d)
        }
        addVersion(id, ForgeVersion(prompt: prompt, code: code, settings: settings, explain: (r["explain"] as? String) ?? ""))
    }
    func addVersion(_ id: UUID, _ v: ForgeVersion) {
        update(id) { $0.versions.append(v); $0.current = v.id
            $0.values = Dictionary(uniqueKeysWithValues: v.settings.map { ($0.key, $0.default) }) }
    }
    func editCode(_ id: UUID, code: String) {
        guard let p = project(id), let cur = p.currentVersion else { return }
        addVersion(id, ForgeVersion(prompt: tr("Manual edit", "تعديل يدوي", ckb: "دەستکاری دەستی", kmr: "Guhertina destan"), code: code, settings: cur.settings, explain: ""))
    }
    func revert(_ id: UUID, to version: UUID) {
        update(id) { p in p.current = version
            if let v = p.versions.first(where: { $0.id == version }) { p.values = Dictionary(uniqueKeysWithValues: v.settings.map { ($0.key, p.values[$0.key] ?? $0.default) }) } }
    }
    func renameVersion(_ id: UUID, _ versionID: UUID, to title: String) {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        update(id) { p in if let i = p.versions.firstIndex(where: { $0.id == versionID }) { p.versions[i].title = t.isEmpty ? nil : t } }
    }
    /// Code edit of any version: appends a NEW version, the original stays untouched.
    func editVersionCode(_ id: UUID, _ versionID: UUID, code: String) {
        guard let p = project(id), let src = p.versions.first(where: { $0.id == versionID }) else { return }
        var v = ForgeVersion(prompt: src.prompt, code: code, settings: src.settings, explain: src.explain)
        v.title = src.title.map { $0 + " *" }
        addVersion(id, v)
    }
    /// Deletes only this version's own dylib (never a file another version uses). Files are removed first; on failure nothing changes.
    /// If it was active, falls back to the previous version, else the next one, else none (project and IPA are kept).
    func deleteVersion(_ id: UUID, _ versionID: UUID) throws {
        guard let p = project(id), let idx = p.versions.firstIndex(where: { $0.id == versionID }) else { return }
        let fm = FileManager.default
        let lib = dylibURL(p, p.versions[idx])
        let shared = p.versions.enumerated().contains { $0.offset != idx && dylibURL(p, $0.element) == lib }
        if !shared && fm.fileExists(atPath: lib.path) { try fm.removeItem(at: lib) }
        update(id) { p in
            let wasCurrent = p.currentVersion?.id == versionID
            p.versions.remove(at: idx)
            if wasCurrent || p.current == versionID {
                let next = p.versions.isEmpty ? nil : p.versions[max(0, idx - 1)]
                p.current = next?.id
                if let n = next { p.values = Dictionary(uniqueKeysWithValues: n.settings.map { ($0.key, p.values[$0.key] ?? $0.default) }) } else { p.values = [:] }
            }
        }
    }
    func setValue(_ id: UUID, key: String, _ on: Bool) { update(id) { $0.values[key] = on } }

    // MARK: build / inject / export
    func dylibURL(_ p: ForgeProject, _ v: ForgeVersion) -> URL { dir(p).appendingPathComponent(p.name + "-" + v.id.uuidString.prefix(8) + ".dylib") }

    @discardableResult
    func build(_ id: UUID) async throws -> URL {
        guard let p = project(id), let v = p.currentVersion else { throw ForgeClient.Failure.message("No version") }
        busy = tr("Building on the server…", "عم ببني عالسيرفر…", ckb: "لەسەر سێرڤەر دروست دەکرێت…", kmr: "Li ser serverê tê çêkirin…"); defer { busy = nil }
        let started = try await ForgeClient.json(["action": "build", "id": v.tweakID.uuidString.lowercased(), "name": p.name, "bundleID": p.bundleID, "code": v.code,
            "settings": v.settings.map { ["key": $0.key, "title": $0.title, "default": $0.default] }, "values": p.values])
        guard let job = started["job"] as? String else { throw ForgeClient.Failure.message("Build did not start") }
        let data = try await fetchBuild(job: job)
        let url = dylibURL(p, v)
        try data.write(to: url, options: .atomic)
        update(id) { pr in if let i = pr.versions.firstIndex(where: { $0.id == v.id }) { pr.versions[i].builtWithValues = pr.values } }
        return url
    }
    func fetchBuild(job: String) async throws -> Data {
        var data = Data()
        for _ in 0..<120 {
            try await Task.sleep(nanoseconds: 4_000_000_000)
            let st = try await ForgeClient.get(["action": "build-status", "job": job])
            let state = st["state"] as? String
            if state == "failed" {
                let (ct, key, _) = try await ForgeClient.getData(["action": "build-status", "job": job, "fetch": "1"])
                let log = (try? ForgeClient.open(ct, masterB64: key, job: job, purpose: "err")).flatMap { String(data: $0, encoding: .utf8) } ?? "Build failed"
                throw ForgeBuildFailure(rawLog: log)
            }
            if state == "done" {
                let (ct, key, _) = try await ForgeClient.getData(["action": "build-status", "job": job, "fetch": "1"])
                data = try ForgeClient.open(ct, masterB64: key, job: job, purpose: "out"); break
            }
        }
        if data.count > 4 * 1024 * 1024 { throw ForgeClient.Failure.message("Library too large") }
        guard data.count > 1000, data.prefix(4) == Data([0xCF, 0xFA, 0xED, 0xFE]) || data.prefix(4) == Data([0xCA, 0xFE, 0xBA, 0xBE]) || data.prefix(4) == Data([0xBE, 0xBA, 0xFE, 0xCA]) else {
            throw ForgeClient.Failure.message(tr("The server did not return a valid library.", "السيرفر ما رجّع مكتبة صالحة.", ckb: "سێرڤەر کتێبخانەیەکی دروستی نەگەڕاندەوە.", kmr: "Server pirtûkxaneyeke derbasdar venegerand."))
        }
        return data
    }
    /// A toggle changed after the last build: the dylib has the old values compiled in.
    func needsRebuild(_ p: ForgeProject) -> Bool { guard let v = p.currentVersion else { return false }; return v.builtWithValues != p.values }

    /// Real injection: copies the source IPA, injects the dylib into the main binary, repacks. Returns the new IPA.
    func inject(_ id: UUID) async throws -> URL {
        guard let p = project(id), let v = p.currentVersion else { throw ForgeClient.Failure.message("No version") }
        var lib = dylibURL(p, v)
        if needsRebuild(p) || !FileManager.default.fileExists(atPath: lib.path) { lib = try await build(id) }
        busy = tr("Injecting…", "عم أحقن…", ckb: "دەچەسپێنرێت…", kmr: "Tê xistin…"); defer { busy = nil }
        let source = dir(p).appendingPathComponent("source.ipa"), exe = p.executable, name = p.appName
        let out = FileManager.default.temporaryDirectory.appendingPathComponent(name.filter { $0.isLetter || $0.isNumber } + "-Tweaked-" + UUID().uuidString.prefix(6) + ".ipa")
        try await Task.detached {
            let fm = FileManager.default
            let tmp = fm.temporaryDirectory.appendingPathComponent("forgeinj-" + UUID().uuidString, isDirectory: true)
            try fm.createDirectory(at: tmp, withIntermediateDirectories: true); defer { try? fm.removeItem(at: tmp) }
            let x = tmp.appendingPathComponent("x", isDirectory: true)
            try IPAEditorService.run("extract", input: source, output: x)
            let app = try IPAEditorService.app(in: x)
            try IPAEditorService.run("inject", input: app, executable: exe, libraries: [lib])
            try IPAEditorService.run("pack", input: x, output: out)
        }.value
        return out
    }
    func addToLibrary(_ id: UUID) async throws {
        let url = try await build(id)
        try await IPATweakLibrary.shared.addFile(url)
    }
    /// Primary output: the built tweak dylib itself.
    func exportDylib(_ id: UUID) async throws -> URL {
        guard let p = project(id), let v = p.currentVersion else { throw ForgeClient.Failure.message("No version") }
        var lib = dylibURL(p, v)
        if needsRebuild(p) || !FileManager.default.fileExists(atPath: lib.path) { lib = try await build(id) }
        let out = FileManager.default.temporaryDirectory.appendingPathComponent(p.name.filter { $0.isLetter || $0.isNumber } + ".dylib")
        try? FileManager.default.removeItem(at: out)
        try FileManager.default.copyItem(at: lib, to: out); return out
    }
    func exportDeb(_ id: UUID) async throws -> URL {
        guard let p = project(id), let v = p.currentVersion else { throw ForgeClient.Failure.message("No version") }
        var lib = dylibURL(p, v)
        if needsRebuild(p) || !FileManager.default.fileExists(atPath: lib.path) { lib = try await build(id) }
        let deb = ForgeDeb.build(name: p.name, bundleID: p.bundleID, dylib: try Data(contentsOf: lib))
        let out = FileManager.default.temporaryDirectory.appendingPathComponent(p.name + ".deb")
        try deb.write(to: out, options: .atomic); return out
    }
    /// Auto-rebuild: when the app was updated, record the new version and rebuild the same code against it.
    func updateTarget(_ id: UUID, ipa: URL) async throws -> Bool {
        guard let p = project(id) else { return false }
        let info = try await Self.inspect(ipa: ipa)
        guard info.bundleID == p.bundleID else { throw ForgeClient.Failure.message(tr("This IPA is a different app.", "هالـ IPA لتطبيق ثاني.", ckb: "ئەم IPA ئەپێکی تره.", kmr: "Ev IPA appeke din e.")) }
        let scoped = ipa.startAccessingSecurityScopedResource(); defer { if scoped { ipa.stopAccessingSecurityScopedResource() } }
        let dest = dir(p).appendingPathComponent("source.ipa")
        try? FileManager.default.removeItem(at: dest); try FileManager.default.copyItem(at: ipa, to: dest)
        let changed = info.appVersion != p.appVersion
        update(id) { $0.appVersion = info.version; $0.classes = info.classes }
        if changed || project(id)?.currentVersion?.hasBuild == true { _ = try await build(id) }
        return changed
    }
}
extension ForgeStore.TargetInfo { var appVersion: String { version } }

extension ForgeStore {
    func publish(_ id: UUID) async throws {
        guard let p = project(id), let v = p.currentVersion else { return }
        _ = try await ForgeClient.json(["action": "publish", "name": p.name, "bundleID": p.bundleID, "description": v.prompt, "code": v.code,
            "settings": v.settings.map { ["key": $0.key, "title": $0.title, "default": $0.default] }])
    }
    /// Uploads the project's current version as a new version of an existing gallery entry (server checks ownership/admin).
    func updateGallery(entry: String, from id: UUID) async throws {
        guard let p = project(id), let v = p.currentVersion else { throw ForgeClient.Failure.message("No version") }
        _ = try await ForgeClient.json(["action": "gallery-update", "id": entry, "code": v.code,
            "settings": v.settings.map { ["key": $0.key, "title": $0.title, "default": $0.default] }])
    }
    /// Temporarily swaps in the tap inspector (long-press any view to copy its class chain), injects, then restores the user's version.
    func injectInspector(_ id: UUID) async throws -> URL {
        guard let p = project(id) else { throw ForgeClient.Failure.message("No project") }
        let prev = p.current; let pv = p.currentVersion
        let savedValues = p.values
        let iv = ForgeVersion(prompt: "Inspector", code: ForgeInspector.code(tweakID: pv?.tweakID ?? p.id), settings: [], explain: "")
        addVersion(id, iv)
        defer { update(id) { $0.versions.removeAll { $0.id == iv.id }; $0.current = prev; $0.values = savedValues }
                try? FileManager.default.removeItem(at: dylibURL(p, iv)); _ = pv }
        return try await inject(id)
    }
}

extension ForgeStore {
    func refreshStatus() async { builderReady = ((try? await ForgeClient.get(["action": "status"]))?["builder"] as? Bool) ?? false }
}
