import SwiftUI

/// Presentation only. Ownership and upload permissions are unchanged and checked again by the server.
struct ForgeCommunityEntry {
    let name: String
    let bundleID: String
    let description: String
    let uploaded: Bool
    let mine: Bool

    init(_ entry: [String: Any]) {
        name = (entry["name"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        bundleID = (entry["target_bundle_id"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        description = (entry["description"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        uploaded = entry["provenance"] as? String == "uploaded"
        mine = entry["mine"] as? Bool == true
    }

    // Never infer a capability from a bundle ID or from another person's local project.
    func groundedDescription(projects: [ForgeProject]) -> String? {
        if !description.isEmpty { return description }
        guard mine, !uploaded,
              let p = projects.first(where: { $0.bundleID == bundleID && $0.name == name }),
              let v = p.currentVersion else { return nil }
        let explanation = v.explain.trimmingCharacters(in: .whitespacesAndNewlines)
        if !explanation.isEmpty { return explanation }
        let prompt = v.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let manual = ["Manual edit", "تعديل يدوي", "دەستکاری دەستی", "Guhertina destan"]
        return prompt.isEmpty || manual.contains(prompt) ? nil : prompt
    }
}

struct ForgeCommunityCard: View {
    let entry: [String: Any]
    var knownTargetIcon: UIImage? = nil
    var onUse: () -> Void
    var onEdit: () -> Void
    var onVersion: () -> Void
    var onDelete: () -> Void
    var onReport: () -> Void
    @ObservedObject private var library = PersonalAppsLibrary.shared
    @ObservedObject private var store = ForgeStore.shared
    @State private var extractedIcon: UIImage?

    static let sheetColor = Color(red: 22/255, green: 25/255, blue: 34/255)
    static let cardColor = Color(red: 31/255, green: 34/255, blue: 44/255)
    static var title: String { tr("Community tweaks", "تويكس المجتمع", ckb: "تویکی کۆمەڵگا", kmr: "Tweakên civakê") }
    private var item: ForgeCommunityEntry { ForgeCommunityEntry(entry) }
    private var app: PersonalLibraryApp? { library.apps.first { $0.bundleID == item.bundleID } }
    private var project: ForgeProject? { store.projects.first { $0.bundleID == item.bundleID } }
    private var targetName: String {
        // Names come from real imported metadata, never guessed by splitting a bundle identifier.
        store.liveMetadataName(item.bundleID) ?? project?.appName ?? item.bundleID
    }
    private var icon: UIImage? { knownTargetIcon ?? app.flatMap { library.icon(for: $0) } ?? extractedIcon }
    private var description: String {
        item.groundedDescription(projects: store.projects) ??
            tr("No description provided.", "ما انضاف وصف لهالتويك.", ckb: "وەسفێک نەدراوە.", kmr: "Danasîn nehatiye dayîn.")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                Group {
                    if let icon { Image(uiImage: icon).resizable().scaledToFit() }
                    else {
                        Image(systemName: "app.dashed")
                            .font(.system(size: 30)).foregroundStyle(.white.opacity(0.55))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Color(red: 34/255, green: 41/255, blue: 58/255))
                    }
                }
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                .accessibilityLabel(targetName)
                VStack(alignment: .trailing, spacing: 5) {
                    Text(item.name).font(.system(size: 19, weight: .bold))
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    Text(item.bundleID).font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.58))
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    Text(description).font(.system(size: 15, weight: .medium))
                        .lineLimit(2).multilineTextAlignment(.trailing)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .accessibilityLabel(description)
                    (
                        Text(tr("Target app: ", "التطبيق المستهدف: ", ckb: "ئەپی ئامانج: ", kmr: "Sepana armanc: ") + targetName + "  |  ")
                        + Text(item.uploaded
                               ? tr("Uploaded · unverified", "مرفوع · غير مجرّب", ckb: "بارکراو · تاقی نەکراو", kmr: "Barkirî · neceribandî")
                               : tr("Server-built", "مبني بالسيرفر", ckb: "دروستکراوی سێرڤەر", kmr: "Li serverê hat çêkirin"))
                    )
                    .font(.system(size: 12)).foregroundStyle(.white.opacity(0.6))
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }.fixedSize(horizontal: false, vertical: true)
            }
            HStack(alignment: .top, spacing: 8) {
                action("square.and.arrow.down", tr("Use", "استخدم", ckb: "بەکاربهێنە", kmr: "Bi kar bîne"), onUse)
                if item.mine {
                    action("pencil", tr("Edit", "تعديل", ckb: "دەستکاری", kmr: "Biguherîne"), onEdit)
                    // Keep the equal-width slot but do not enable a code rebuild for uploaded binaries.
                    action("square.on.square", tr("New version", "نسخة جديدة", ckb: "وەشانی نوێ", kmr: "Guhertoya nû"), onVersion, enabled: !item.uploaded)
                    action("trash", tr("Delete", "حذف", ckb: "سڕینەوە", kmr: "Jê bibe"), onDelete, destructive: true)
                } else {
                    action("flag", tr("Report", "بلّغ", ckb: "ڕاپۆرت", kmr: "Ragihîne"), onReport)
                }
            }
        }
        .padding(16).background(Self.cardColor, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .foregroundStyle(.white)
        .environment(\.layoutDirection, .leftToRight)
        .task(id: item.bundleID) {
            extractedIcon = nil
            if let app { extractedIcon = await library.ensureIcon(for: app) }
            if extractedIcon == nil, let project {
                let source = store.dir(project).appendingPathComponent("source.ipa")
                if let data = await Self.sourceIcon(source, bundleID: item.bundleID) {
                    extractedIcon = UIImage(data: data)
                }
            }
        }
    }

    private func action(_ symbol: String, _ title: String, _ run: @escaping () -> Void,
                        enabled: Bool = true, destructive: Bool = false) -> some View {
        Button(action: run) {
            VStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 20, weight: .medium)).frame(height: 24)
                    .foregroundStyle(destructive ? Color(red: 226/255, green: 77/255, blue: 77/255) : Color.white)
                Text(title).font(.system(size: 12, weight: .semibold))
                    .lineLimit(2).multilineTextAlignment(.center).frame(height: 30, alignment: .top)
            }
            .frame(maxWidth: .infinity).padding(.top, 12).padding(.bottom, 5)
            .foregroundStyle(Color.white)
            .background(Color(red: 34/255, green: 41/255, blue: 58/255), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color(red: 49/255, green: 61/255, blue: 86/255), lineWidth: 1))
            .opacity(enabled ? 1 : 0.35)
        }.buttonStyle(.mirsaPress).disabled(!enabled)
    }

    /// Read-only, bounded archive inspection, reusing the existing protected extractor/icon parser.
    /// No executable is loaded, no network icon lookup and no arbitrary remote icon URLs.
    private nonisolated static func sourceIcon(_ source: URL, bundleID: String) async -> Data? {
        await Task.detached(priority: .utility) {
            guard let size = try? source.resourceValues(forKeys: [.fileSizeKey]).fileSize,
                  size > 0, size <= 512 * 1024 * 1024 else { return nil }
            let fm = FileManager.default
            let stage = fm.temporaryDirectory.appendingPathComponent("community-icon-" + UUID().uuidString)
            defer { try? fm.removeItem(at: stage) }
            do {
                try fm.createDirectory(at: stage, withIntermediateDirectories: true)
                let extracted = stage.appendingPathComponent("a")
                try IPAEditorService.run("extract_inspection", input: source, output: extracted)
                let bundle = try IPAEditorService.app(in: extracted)
                let info = try IPAEditorService.info(in: bundle)
                guard info["CFBundleIdentifier"] as? String == bundleID else { return nil }
                return PersonalAppsLibrary.iconPNG(bundle: bundle, info: info)
            } catch { return nil }
        }.value
    }
}
