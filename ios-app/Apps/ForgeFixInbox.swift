import Foundation
import CryptoKit
import Security

/// No arbitrary URLs, redirects, auto-injection or guard changes in this protocol.
struct ForgeFixItem: Codable {
    let id: UUID
    let tweakID: UUID
    let bundleID: String
    let name: String
    let version: Int
    let code: String
    let settings: [ForgeSetting]
    let sourceSHA256: String
    let dylibSHA256: String
    let dylibBytes: Int
    let createdAt: String
    let requiresReview: Bool
    let autoEnable: Bool

    static func sha(_ bytes: Data) -> String { SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined() }
    func validate() throws {
        let hex = "^[a-f0-9]{64}$"
        guard requiresReview, !autoEnable, version > 0,
              bundleID.range(of: "^[A-Za-z0-9][A-Za-z0-9.-]{0,254}$", options: .regularExpression) != nil,
              !name.isEmpty, name.utf8.count <= 128, createdAt.utf8.count <= 64,
              Self.validDate(createdAt),
              (8...196608).contains(code.utf8.count), (1001...4194304).contains(dylibBytes),
              sourceSHA256.range(of: hex, options: .regularExpression) != nil,
              dylibSHA256.range(of: hex, options: .regularExpression) != nil,
              Self.sha(Data(code.utf8)) == sourceSHA256,
              settings.count <= 8, Set(settings.map(\.key)).count == settings.count,
              settings.allSatisfy({ $0.key.range(of: "^[A-Za-z_][A-Za-z0-9_]{0,63}$", options: .regularExpression) != nil && $0.title.utf8.count <= 256 })
        else { throw ForgeClient.Failure.message("Invalid fix metadata.") }
    }
    static func validDate(_ text: String) -> Bool {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if formatter.date(from: text) != nil { return true }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text) != nil
    }
    func validateLibrary(_ bytes: Data) throws {
        try validate()
        guard bytes.count == dylibBytes, Self.sha(bytes) == dylibSHA256,
              [Data([0xCF,0xFA,0xED,0xFE]), Data([0xCA,0xFE,0xBA,0xBE]), Data([0xBE,0xBA,0xFE,0xCA])].contains(Data(bytes.prefix(4)))
        else { throw ForgeClient.Failure.message("Fix library verification failed.") }
    }
}

/// The index is the commit record. An orphan dylib after a crash is harmless;
/// retry overwrites it, and the deterministic fix UUID makes replays idempotent.
enum ForgeFixPersistence {
    static func commit(_ item: ForgeFixItem, bytes: Data, projects: [ForgeProject], root: URL) throws -> [ForgeProject] {
        try item.validateLibrary(bytes)
        guard let pi = projects.firstIndex(where: { $0.bundleID == item.bundleID && $0.versions.contains(where: { $0.tweakID == item.tweakID }) }),
              projects.filter({ $0.bundleID == item.bundleID && $0.versions.contains(where: { $0.tweakID == item.tweakID }) }).count == 1
        else { throw ForgeClient.Failure.message("No unique matching local tweak.") }
        var result = projects
        let project = result[pi]
        if let existing = project.versions.first(where: { $0.id == item.id }) {
            guard existing.fixSourceSHA256 == item.sourceSHA256, existing.fixDylibSHA256 == item.dylibSHA256,
                  existing.guardID == item.tweakID, existing.code == item.code else {
                throw ForgeClient.Failure.message("Conflicting fix replay.")
            }
        }
        let folder = root.appendingPathComponent(project.id.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let lib = folder.appendingPathComponent(project.name + "-" + item.id.uuidString.prefix(8) + ".dylib")
        // Never overwrite a library belonging to a different local version.
        guard !project.versions.contains(where: { $0.id != item.id && $0.id.uuidString.prefix(8) == item.id.uuidString.prefix(8) }) else {
            throw ForgeClient.Failure.message("Fix filename conflict.")
        }
        try bytes.write(to: lib, options: [.atomic, .completeFileProtection])
        try item.validateLibrary(Data(contentsOf: lib))
        if !result[pi].versions.contains(where: { $0.id == item.id }) {
            var v = ForgeVersion(id: item.id, prompt: ForgeFixText.label, code: item.code, settings: item.settings, explain: ForgeFixText.notice)
            v.guardID = item.tweakID
            v.builtWithValues = Dictionary(uniqueKeysWithValues: item.settings.map { ($0.key, $0.default) })
            v.fixSourceSHA256 = item.sourceSHA256; v.fixDylibSHA256 = item.dylibSHA256
            result[pi].versions.append(v)
            // Leave current, values and original versions exactly unchanged.
        }
        try JSONEncoder().encode(result).write(to: root.appendingPathComponent("projects.json"), options: [.atomic, .completeFileProtection])
        let committed = try JSONDecoder().decode([ForgeProject].self, from: Data(contentsOf: root.appendingPathComponent("projects.json")))
        guard committed[pi].versions.contains(where: { $0.id == item.id && $0.fixDylibSHA256 == item.dylibSHA256 }) else {
            throw ForgeClient.Failure.message("Fix persistence verification failed.")
        }
        return committed
    }
}

enum ForgeFixText {
    static var label: String { tr("Fix", "إصلاح", ckb: "چاککردنەوە", kmr: "Sererastkirin") }
    static var notice: String { tr("A fixed version was saved in Versions for review. Your current version is unchanged. Nothing was enabled or injected.", "انحفظت نسخة إصلاح بالنسخ للمراجعة. نسختك الحالية ما تغيّرت، وما تفعّل أو انحقن شي.", ckb: "وەشانی چاککراو لە وەشانەکان پاشەکەوت کرا بۆ پێداچوونەوە. وەشانی ئێستا نەگۆڕا و هیچ شتێک چالاک نەکرا.", kmr: "Guhertoya sererastkirî ji bo kontrolê hat tomarkirin. Guhertoya niha neguherî û tiştek nehat çalakkirin.") }
    static var report: String { tr("Send repair report", "إرسال تقرير للإصلاح", ckb: "ناردنی ڕاپۆرتی چاککردنەوە", kmr: "Rapora sererastkirinê bişîne") }
    static var privacy: String { tr("Review the sanitized diagnostic below. Sending shares only this diagnostic, tweak ID, app ID/name and source hash, not app files, source code or private app data. A fix will need your review and will never enable itself.", "راجع التقرير المنظّف تحت. الإرسال بيشارك هالتقرير ومعرّف التويك والتطبيق واسمه وبصمة الكود بس، مو ملفات التطبيق ولا الكود ولا بياناتك الخاصة. أي إصلاح بده مراجعتك وما بيتفعّل لحاله.", ckb: "ڕاپۆرتە پاککراوەکە بپشکنە. تەنها ڕاپۆرت و ناسنامەکانی تویک و ئەپ و پەنجەمۆری کۆد دەنێردرێن، نە فایل و کۆد و داتای تایبەت. چاککردنەوە پێویستی بە پێداچوونەوەی تۆ هەیە.", kmr: "Rapora paqijkirî kontrol bike. Tenê rapor, nasnameyên tweak û appê û hashê kodê tên şandin, ne pel, kod an daneyên taybet. Sererastkirin hewceyê kontrola te ye.") }
}

/// Strict allowlist, never ships pasted source lines, stack payloads, paths or user text.
enum ForgeFixDiagnostic {
    static func sanitized(_ input: String, kind: String) -> String {
        let lower = String(input.prefix(24000)).lowercased()
        if kind == "crash", lower.contains("mirsa launch marker reports an interrupted launch") {
            return "Exception Type: not provided\nTermination Reason: Mirsa launch marker reports an interrupted launch; attribution unconfirmed. No system crash log is available."
        }
        let signals = ["error:", "warning:", "undefined symbol", "undeclared identifier", "no known", "unavailable", "deprecated", "killed", "memory", "layout", "recursion", "sigabrt", "sigsegv", "exception", "crash", "guard disabled", "guard enabled"]
        let found = signals.filter { lower.contains($0) }
        let summary = found.isEmpty ? "unspecified failure" : found.joined(separator: ", ")
        if kind == "build" { return "error: user-reported tweak build failure; signals=" + summary }
        return "Exception Type: not provided\nApplication Specific Information: user-reported tweak failure; signals=" + summary
    }
}

@MainActor extension ForgeStore {
    func syncFixInbox() async {
        guard !fixSyncing else { return }
        fixSyncing = true; defer { fixSyncing = false }
        do {
            let token = try await ForgeClient.fixToken()
            let data = try await ForgeClient.fixRequest(["action": "fix-inbox"], deviceToken: token)
            struct Inbox: Decodable { let items: [ForgeFixItem]; let version: Int }
            let inbox = try JSONDecoder().decode(Inbox.self, from: data)
            guard inbox.version == 1, inbox.items.count <= 20 else { return }
            for item in inbox.items {
                do {
                    try item.validate()
                    // Do not download unknown, deleted or mismatched local tweaks.
                    guard projects.contains(where: { $0.bundleID == item.bundleID && $0.versions.contains(where: { $0.tweakID == item.tweakID }) }) else { continue }
                    let fresh = !projects.contains(where: { $0.versions.contains(where: { $0.id == item.id }) })
                    let bytes = try await ForgeClient.fixRequest(["action": "fix-download", "id": item.id.uuidString.lowercased()], deviceToken: token, maxBytes: 4194304)
                    projects = try ForgeFixPersistence.commit(item, bytes: bytes, projects: projects, root: Self.root)
                    if fresh { fixNotice = ForgeFixText.notice }
                    _ = try await ForgeClient.fixRequest(["action": "fix-ack", "id": item.id.uuidString.lowercased(), "dylibSHA256": item.dylibSHA256], deviceToken: token)
                } catch { continue } // No ack on any validation/persistence failure. Retry on next foreground.
            }
        } catch { /* Offline/auth failures are non-destructive and retried at foreground. */ }
    }

    func sendFixReport(projectID: UUID, versionID: UUID, kind: String, diagnostic: String, consent: Bool, reportID: UUID) async throws {
        guard consent, ["build", "crash"].contains(kind), let p = project(projectID),
              let v = p.versions.first(where: { $0.id == versionID }) else { throw ForgeClient.Failure.message("Explicit consent and a local tweak are required.") }
        let token = try await ForgeClient.fixToken()
        _ = try await ForgeClient.fixRequest(["action": "fix-report", "id": reportID.uuidString.lowercased(),
            "tweakID": v.tweakID.uuidString.lowercased(), "bundleID": p.bundleID, "name": ForgeFeaturePolicy.name(p.name),
            "kind": kind, "consent": true, "diagnostics": ForgeFixDiagnostic.sanitized(diagnostic, kind: kind),
            "sourceSHA256": ForgeFixItem.sha(Data(v.code.utf8))], deviceToken: token)
    }
}
