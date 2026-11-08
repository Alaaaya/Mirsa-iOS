import Foundation
import UIKit
import ImageIO

enum ForgeFeaturePolicy {
    static func classes(_ list: [String]) -> [String] {
        Array(list.filter { $0.range(of: "^[A-Za-z_][A-Za-z0-9_.$]{0,80}$", options: .regularExpression) != nil }.prefix(400))
    }
    static func name(_ text: String) -> String {
        let raw = String(text.unicodeScalars.filter { $0.isASCII && CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789 _.-").contains($0) }.prefix(34))
        return "Mirsa " + raw
    }
    static func mergeSelection(_ items: [(ForgeProject, ForgeVersion)], bundleID: String) throws {
        guard (2...5).contains(items.count),
              Set(items.map { $0.1.id }).count == items.count,
              items.allSatisfy({ $0.0.bundleID == bundleID && !$0.1.code.isEmpty }) else {
            throw ForgeClient.Failure.message("Choose 2–5 different versions for the same app.")
        }
    }
    static func sanitizedLog(_ input: String) -> String {
        var s = String(input.prefix(24000))
        for pattern in [
            #"(?im)^.*(?:authorization|bearer|cookie|password|passwd|secret|token|api.?key|certificate|private.?key|pairing|udid|serial).*$"#,
            #"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#,
            #"/(?:private/)?var/[^\s\"]+"#,
            #"(?i)\b[a-f0-9]{32,}\b"#
        ] {
            s = s.replacingOccurrences(of: pattern, with: "[redacted]", options: [.regularExpression, .caseInsensitive])
        }
        while s.utf8.count > 24000 { s.removeLast() }; return s
    }
    static func jpeg(_ data: Data) throws -> Data {
        guard data.count <= 20 * 1024 * 1024,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let facts = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = facts[kCGImagePropertyPixelWidth] as? NSNumber, let height = facts[kCGImagePropertyPixelHeight] as? NSNumber,
              width.doubleValue > 0, height.doubleValue > 0, width.doubleValue * height.doubleValue <= 40_000_000,
              let image = UIImage(data: data),
              image.size.width > 0, image.size.height > 0 else {
            throw ForgeClient.Failure.message("Choose a valid image under 20 MB.")
        }
        let scale = min(1, 1600 / max(image.size.width, image.size.height))
        let size = CGSize(width: max(1, floor(image.size.width * scale)), height: max(1, floor(image.size.height * scale)))
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true; format.preferredRange = .standard
        let clean = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            UIColor.white.setFill(); ctx.fill(CGRect(origin: .zero, size: size))
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        guard let jpeg = clean.jpegData(compressionQuality: 0.75), jpeg.count <= 1024 * 1024 else {
            throw ForgeClient.Failure.message("Image is too large after cleaning. Choose a smaller image.")
        }
        return jpeg
    }
}

/// Explicitly imported local capture, never reads another application's container.
struct ForgeCapture: Decodable {
    let schema: String
    let bundleID: String
    let tweakID: UUID
    let guardDisabled: Bool?
    let nodes: [Node]
    let truncated: Bool
    let limitations: String
    let logs: [String]
    struct Node: Decodable {
        let `class`: String
        let depth: Int
        let parent: Int
        let frame: [Double]
        let identifier: String
        let label: String
        let text: String
        let secure: Bool
    }
    static func read(_ data: Data, bundleID: String) throws -> ForgeCapture {
        guard data.count <= 24000 else { throw ForgeClient.Failure.message("Capture exceeds 24 KB.") }
        let report = try JSONDecoder().decode(Self.self, from: data)
        let safe = Set(["[redacted]", "OK", "Cancel", "Back", "Done", "Settings", "Home", "Search", "إلغاء", "رجوع", "تم", "الإعدادات"])
        guard report.schema == "mirsa.inspector.v1", report.bundleID == bundleID,
              report.nodes.count <= 400, report.logs.count <= 20, report.limitations.utf8.count <= 1000,
              report.nodes.enumerated().allSatisfy({ index, node in
                  (0...32).contains(node.depth) && node.parent >= -1 && node.parent < index &&
                  node.frame.count == 4 && node.frame.allSatisfy(\.isFinite) &&
                  node.class.range(of: "^[A-Za-z_][A-Za-z0-9_.$]{0,127}$", options: .regularExpression) != nil && node.identifier == "[redacted]" &&
                  node.label == "[redacted]" && safe.contains(node.text) &&
                  (!node.secure || node.text == "[redacted]")
              }), report.logs.allSatisfy({ $0 == "inspector: explicit foreground capture requested" || $0 == "inspector: user copied redacted preview locally" }) else {
            throw ForgeClient.Failure.message("Capture is invalid, unredacted or from a different app.")
        }
        return report
    }
    func repairAllowed(tweakID: UUID) -> Bool { self.tweakID == tweakID && guardDisabled == false }
}

extension ForgeStore {
    func suggestions(_ id: UUID) async throws -> [String] {
        guard let p = project(id) else { return [] }
        let out = try await ForgeClient.json(["action": "suggest", "bundleID": p.bundleID,
                    "classes": ForgeFeaturePolicy.classes(p.classes), "selectors": [String]()])
        guard let list = out["suggestions"] as? [String], (4...6).contains(list.count),
              list.allSatisfy({ !$0.isEmpty && $0.count <= 300 }) else { throw ForgeClient.Failure.message("Invalid suggestions.") }
        return list
    }

    func imageGenerate(_ id: UUID, jpeg: Data, prompt: String) async throws {
        guard let p = project(id), !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard jpeg.count <= 1024 * 1024 else { throw ForgeClient.Failure.message("Image exceeds 1 MB.") }
        let out = try await ForgeClient.json(["action": "image-generate", "name": ForgeFeaturePolicy.name(p.name),
            "bundleID": p.bundleID, "classes": ForgeFeaturePolicy.classes(p.classes), "selectors": [String](),
            "prompt": String(prompt.prefix(2000)), "image": ["mime": "image/jpeg", "base64": jpeg.base64EncodedString()]])
        addVersion(id, try responseVersion(out, prompt: prompt))
    }

    func merge(_ id: UUID, selected: [(ForgeProject, ForgeVersion)]) async throws {
        guard let p = project(id) else { throw ForgeClient.Failure.message("No project.") }
        try ForgeFeaturePolicy.mergeSelection(selected, bundleID: p.bundleID)
        let mergedID = UUID()
        let items: [[String: Any]] = selected.map { project, version in
            ["id": version.id.uuidString.lowercased(), "bundleID": project.bundleID, "code": version.code,
             "settings": version.settings.map { ["key": $0.key, "title": $0.title, "default": $0.default] as [String: Any] },
             "values": project.current == version.id ? project.values : (version.builtWithValues ?? Dictionary(uniqueKeysWithValues: version.settings.map { ($0.key, $0.default) }))]
        }
        let out = try await ForgeClient.json(["action": "merge", "id": mergedID.uuidString.lowercased(),
                "name": ForgeFeaturePolicy.name(p.name), "bundleID": p.bundleID, "items": items])
        guard let job = out["job"] as? String, job.range(of: "^[0-9a-f]{32}$", options: .regularExpression) != nil else { throw ForgeClient.Failure.message("Invalid merge job.") }
        let parsed = try responseVersion(out, prompt: "Merged \(selected.count) versions")
        let values = out["values"] as? [String: Bool] ?? Dictionary(uniqueKeysWithValues: parsed.settings.map { ($0.key, $0.default) })
        var merged = ForgeVersion(id: mergedID, prompt: parsed.prompt, code: parsed.code, settings: parsed.settings, explain: parsed.explain)
        let bytes = try await fetchBuild(job: job)
        let destination = dylibURL(p, merged)
        try bytes.write(to: destination, options: [.atomic, .completeFileProtection])
        merged.builtWithValues = values
        addVersion(id, merged)
        update(id) { $0.values = values }
    }

    func responseVersion(_ out: [String: Any], prompt: String) throws -> ForgeVersion {
        guard let code = out["code"] as? String, (8...24000).contains(code.utf8.count) else { throw ForgeClient.Failure.message("Invalid generated source.") }
        let data = try JSONSerialization.data(withJSONObject: out["settings"] ?? [])
        let settings = try JSONDecoder().decode([ForgeSetting].self, from: data)
        guard settings.count <= 8, Set(settings.map(\.key)).count == settings.count else { throw ForgeClient.Failure.message("Invalid generated settings.") }
        return ForgeVersion(prompt: prompt, code: code, settings: settings, explain: out["explain"] as? String ?? "")
    }

    /// Sequential per-app generation, each request uses that app's own inspected IPA.
    /// Originals and current selections are left intact; results are reviewable versions.
    func generateVisualForApps(_ ids: Set<UUID>, prompt: String) async -> [String] {
        var outcomes: [String] = []
        for app in PersonalAppsLibrary.shared.apps.filter({ ids.contains($0.id) }) {
            do {
                let source = PersonalAppsLibrary.shared.url(app)
                let info = try await Self.inspect(ipa: source)
                guard info.bundleID == app.bundleID else { throw ForgeClient.Failure.message("App identity changed.") }
                let id = try create(ipa: source, info: info)
                do { try await generate(id, prompt: String(prompt.prefix(1800)) + "\nOnly safe font size/color/background changes using this app's supplied classes or standard UIKit. No other behavior.")
                    outcomes.append(app.name + " ✓")
                } catch { outcomes.append(app.name + ": " + error.localizedDescription) }
            } catch { outcomes.append(app.name + ": " + error.localizedDescription) }
        }
        return outcomes
    }

    /// Persisted opt-in and stable chain are separate from a version's build identity.
    func repairChain(_ id: UUID, versionID: UUID) throws -> (UUID, UUID) {
        guard let p = project(id), let v = p.versions.first(where: { $0.id == versionID }) else { throw ForgeClient.Failure.message("No version.") }
        let key = "forge.repair.chain." + v.tweakID.uuidString
        let chain = UserDefaults.standard.string(forKey: key).flatMap(UUID.init(uuidString:)) ?? UUID()
        UserDefaults.standard.set(chain.uuidString, forKey: key)
        return (v.tweakID, chain)
    }
    func repairProposal(_ id: UUID, versionID: UUID, capture: ForgeCapture, crashLog: String, optedIn: Bool, consent: Bool) async throws -> ForgeVersion {
        guard let p = project(id), let v = p.versions.first(where: { $0.id == versionID }),
              optedIn, consent, capture.repairAllowed(tweakID: v.tweakID) else {
            throw ForgeClient.Failure.message("Repair needs explicit consent and a known enabled guard for this exact tweak. Unknown or disabled guards cannot be repaired.")
        }
        let (original, chain) = try repairChain(id, versionID: versionID)
        let safe = ForgeFeaturePolicy.sanitizedLog(crashLog)
        let out = try await ForgeClient.json(["action": "crash-repair", "chainID": chain.uuidString.lowercased(),
            "id": original.uuidString.lowercased(), "name": ForgeFeaturePolicy.name(p.name), "bundleID": p.bundleID,
            "code": v.code, "settings": v.settings.map { ["key": $0.key, "title": $0.title, "default": $0.default] as [String: Any] },
            "classes": ForgeFeaturePolicy.classes(p.classes), "selectors": [String](), "crashLog": safe,
            "repairOptIn": optedIn, "consent": consent, "crashGuardDisabled": false])
        guard out["requiresReview"] as? Bool == true, out["autoEnable"] as? Bool == false,
              (out["id"] as? String).flatMap(UUID.init(uuidString:)) == original,
              (out["chainID"] as? String).flatMap(UUID.init(uuidString:)) == chain else { throw ForgeClient.Failure.message("Unsafe repair response.") }
        var proposal = try responseVersion(out, prompt: "Crash repair · review required")
        proposal.guardID = original; proposal.repairChainID = chain
        return proposal
    }
    func acceptRepair(_ id: UUID, proposal: ForgeVersion) {
        // Save a selectable version but do not switch, build, inject, install, or reset guard.
        update(id) { $0.versions.append(proposal) }
    }
}
