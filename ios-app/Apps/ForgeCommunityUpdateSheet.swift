import SwiftUI

/// Pure, testable decisions behind the update sheet and the consumer badge.
enum ForgeCommunityUpdateLogic {
    /// Accepts plain ISO8601 and Supabase-style fractional seconds of any length (e.g. 2026-11-09T00:30:01.123456+00:00).
    static func parseDate(_ raw: String) -> Date? {
        let s = raw.trimmingCharacters(in: .whitespaces)
        guard let r = s.range(of: #"\.\d+"#, options: .regularExpression) else { return ISO8601DateFormatter().date(from: s) }
        let frac = Double("0" + s[r]) ?? 0
        guard let base = ISO8601DateFormatter().date(from: s.replacingCharacters(in: r, with: "")) else { return nil }
        return base.addingTimeInterval(frac)
    }
    /// The fetched source must be the exact revision the card shows, otherwise a diff/publish would compare different CAS versions.
    static func sourceMatches(fetchedVersion: Int?, entryVersion: Int?) -> Bool {
        guard let f = fetchedVersion, let e = entryVersion else { return false }
        return f == e
    }
    /// Facts only. Returns nil when the published code could not be fetched: never a misleading zero.
    static func changeLines(publishedCode: String?, publishedSettings: Int?, local: ForgeVersion?) -> [String]? {
        guard let pub = publishedCode, let lv = local else { return nil }
        let a = pub.split(separator: "\n", omittingEmptySubsequences: false), b = lv.code.split(separator: "\n", omittingEmptySubsequences: false)
        var add = 0, rem = 0
        for c in b.difference(from: a) { if case .insert = c { add += 1 } else { rem += 1 } }
        if add == 0 && rem == 0 && (publishedSettings == nil || publishedSettings == lv.settings.count) {
            return [tr("Code is identical to the published version.", "الكود نفس المنشور.", ckb: "کۆدەکە وەک بڵاوکراوە.", kmr: "Kod wekî ya weşandî ye.")]
        }
        var out = [tr("\(add) lines added, \(rem) removed", "انضاف \(add) سطر، انحذف \(rem)", ckb: "\(add) دێڕ زیادکرا، \(rem) سڕایەوە", kmr: "\(add) rêz hat zêdekirin, \(rem) hat jêbirin")]
        if let ps = publishedSettings, ps != lv.settings.count {
            out.append(tr("Settings: \(ps) to \(lv.settings.count)", "الإعدادات: \(ps) إلى \(lv.settings.count)", ckb: "ڕێکخستنەکان: \(ps) → \(lv.settings.count)", kmr: "Mîheng: \(ps) → \(lv.settings.count)"))
        }
        return out
    }
    static func canPublish(uploaded: Bool, publishedVersion: Int?, local: ForgeLocalVersion?, changelog: String, publishedLoaded: Bool, working: Bool) -> Bool {
        !working && !uploaded && publishedVersion != nil && local != nil && publishedLoaded
            && !changelog.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    /// Badge only for another user's entry and a local copy really created from THIS entry at an older published version.
    static func usedOlderVersion(entryID: String, published: Int?, mine: Bool, projects: [ForgeProject]) -> Int? {
        guard !mine, !entryID.isEmpty, let pub = published else { return nil }
        let used = projects.flatMap(\.versions).filter { $0.communitySourceID == entryID }.compactMap(\.usedPublishedVersion)
        guard let m = used.max(), m < pub else { return nil }
        return m
    }
}

/// تحديث بالمجتمع: compares the ACTUAL published version with the latest LOCAL version of the author's linked original project.
struct ForgeCommunityUpdateSheet: View {
    let entry: [String: Any]
    var preloaded: (code: String, settings: Int?)? = nil
    var onPublished: () -> Void
    @ObservedObject private var store = ForgeStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var changelog = ""
    @State private var chosen: UUID?
    @State private var working = false
    @State private var failure: String?
    private var item: ForgeCommunityEntry { ForgeCommunityEntry(entry) }

    private var linked: ForgeProject? {
        if let id = chosen ?? item.authorProjectID, let p = store.projects.first(where: { $0.id == id }) { return p }
        return nil
    }
    /// Explicit matching only when the entry carries no link (legacy): same bundle ID AND same name.
    private var candidates: [ForgeProject] {
        item.authorProjectID == nil ? store.projects.filter { $0.bundleID == item.bundleID && $0.name == item.name } : []
    }
    private var local: ForgeLocalVersion? { linked.flatMap(ForgeLocalVersion.latest(in:)) }
    private var localVersion: ForgeVersion? { local.flatMap { l in linked?.versions.first { $0.id == l.versionID } } }
    private var nextNumber: Int? { item.version.map { $0 + 1 } }
    private var canPublish: Bool {
        ForgeCommunityUpdateLogic.canPublish(uploaded: item.uploaded, publishedVersion: item.version, local: local, changelog: changelog, publishedLoaded: publishedLoaded, working: working)
    }

    private func dateText(_ d: Date?) -> String { d?.formatted(date: .abbreviated, time: .shortened) ?? tr("unknown", "غير معروف", ckb: "نەزانراو", kmr: "nenas") }

    private var changes: [String]? { ForgeCommunityUpdateLogic.changeLines(publishedCode: publishedCode, publishedSettings: publishedSettings, local: localVersion) }
    @State private var publishedCode: String?
    @State private var publishedSettings: Int?
    @State private var publishedLoaded = false
    @State private var loadFailed = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(tr("Update in community", "تحديث بالمجتمع", ckb: "نوێکردنەوە لە کۆمەڵگا", kmr: "Nûkirin di civakê de")).font(.system(size: 24, weight: .bold))
                Text(tr("Publishes your latest local version of this tweak so everyone who uses it can update. Your local copies stay untouched.", "بينشر آخر نسخة عندك من هالتويك ليقدر الكل يحدّث. نسخك المحلية ما بتتغير.", ckb: "نوێترین وەشانی خۆجێیی بڵاو دەکاتەوە. کۆپییە خۆجێییەکان نەگۆڕاون.", kmr: "Guhertoya herî nû ya herêmî diweşîne. Kopiyên herêmî nayên guhertin.")).font(.system(size: 14)).foregroundStyle(.white.opacity(0.7))
                if item.uploaded {
                    note(tr("Uploaded binary files can't be updated from here.", "ملفات التويك المرفوعة ما بتنحدث من هون.", ckb: "فایلە بارکراوەکان لێرە نانوێنرێنەوە.", kmr: "Pelên barkirî ji vir nayên nûkirin."))
                } else if item.version == nil {
                    note(tr("This older entry has no version data, so the app can't compare versions. Nothing is guessed.", "هالإدخال قديم وما فيه بيانات نسخة، فما بنقدر نقارن. ما في تخمين.", ckb: "ئەم تۆمارە کۆنە و داتای وەشانی نییە.", kmr: "Ev tomar kevn e û daneya guhertoyê tune."))
                } else if linked == nil {
                    if candidates.isEmpty {
                        note(tr("No linked local project was found for this entry on this device.", "ما لقينا مشروع محلي مرتبط بهالإدخال على هالجهاز.", ckb: "هیچ پڕۆژەیەکی خۆجێیی بەستراو نەدۆزرایەوە.", kmr: "Projeya herêmî ya girêdayî nehat dîtîn."))
                    } else {
                        Text(tr("Choose the original project", "اختر المشروع الأصلي", ckb: "پڕۆژەی بنەڕەتی هەڵبژێرە", kmr: "Projeya eslî hilbijêre")).font(.system(size: 15, weight: .semibold))
                        ForEach(candidates) { p in
                            Button { chosen = p.id } label: { Text("\(p.name) · \(p.appName)").frame(maxWidth: .infinity, alignment: .leading).padding(12).background(Color(red: 34/255, green: 41/255, blue: 58/255), in: RoundedRectangle(cornerRadius: 12, style: .continuous)) }
                        }
                    }
                } else if let l = local {
                    HStack(alignment: .top, spacing: 10) {
                        column(tr("Published", "المنشور", ckb: "بڵاوکراو", kmr: "Weşandî"), "v\(item.version ?? 0)", dateText(item.updatedAt))
                        Image(systemName: "arrow.right").padding(.top, 26).foregroundStyle(.white.opacity(0.6))
                        column(tr("Latest local", "آخر نسخة محلية", ckb: "نوێترین خۆجێیی", kmr: "Herêmiya nûtirîn"), "v\(l.number)", dateText(l.created))
                    }
                    Text(tr("Will publish as v\(nextNumber ?? 0)", "رح تنشر كـ v\(nextNumber ?? 0)", ckb: "وەک v\(nextNumber ?? 0) بڵاو دەبێتەوە", kmr: "Wek v\(nextNumber ?? 0) tê weşandin")).font(.system(size: 13, weight: .semibold)).foregroundStyle(Color(red: 120/255, green: 190/255, blue: 255/255))
                    Text(tr("What's new", "شو الجديد", ckb: "چی نوێیە", kmr: "Çi nû ye")).font(.system(size: 15, weight: .semibold))
                    TextEditor(text: $changelog).frame(minHeight: 90).scrollContentBackground(.hidden).padding(8)
                        .background(Color(red: 34/255, green: 41/255, blue: 58/255), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    Text(tr("Changes", "التغييرات", ckb: "گۆڕانکاری", kmr: "Guhertin")).font(.system(size: 15, weight: .semibold))
                    if let changes {
                        ForEach(changes, id: \.self) { Text("• " + $0).font(.system(size: 13)).foregroundStyle(.white.opacity(0.85)) }
                    } else if loadFailed {
                        note(tr("Couldn't load the published version, so changes can't be shown and publishing is disabled.", "ما قدرنا نحمّل النسخة المنشورة، فما فينا نعرض التغييرات والنشر معطّل.", ckb: "وەشانی بڵاوکراو بار نەبوو، بۆیە نابینرێت و بڵاوکردنەوە ناچالاکە.", kmr: "Guhertoya weşandî nehat barkirin, ji ber vê weşandin neçalak e."))
                    } else { ProgressView().tint(.white) }
                }
                if let failure { Text(failure).font(.system(size: 13)).foregroundStyle(.red) }
                HStack(spacing: 10) {
                    Button(tr("Cancel", "إلغاء", ckb: "پاشگەزبوونەوە", kmr: "Betal")) { dismiss() }
                        .frame(maxWidth: .infinity).padding(.vertical, 13).background(Color(red: 34/255, green: 41/255, blue: 58/255), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    Button { Task { await publish() } } label: {
                        Text(tr("Publish update", "انشر التحديث", ckb: "نوێکردنەوە بڵاو بکە", kmr: "Nûkirinê biweşîne")).fontWeight(.bold)
                    }.disabled(!canPublish).opacity(canPublish ? 1 : 0.35)
                        .frame(maxWidth: .infinity).padding(.vertical, 13).background(Color(red: 52/255, green: 120/255, blue: 246/255), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }.padding(20)
        }
        .foregroundStyle(.white).background(ForgeCommunityCard.sheetColor.ignoresSafeArea())
        .environment(\.layoutDirection, .leftToRight)
        .task {
            if let p = preloaded { publishedCode = p.code; publishedSettings = p.settings; publishedLoaded = true }
            else { await loadPublished() }
        }
    }

    private func note(_ t: String) -> some View {
        Text(t).font(.system(size: 14)).padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(red: 34/255, green: 41/255, blue: 58/255), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
    private func column(_ title: String, _ v: String, _ date: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 12)).foregroundStyle(.white.opacity(0.6))
            Text(v).font(.system(size: 22, weight: .bold))
            Text(date).font(.system(size: 12)).foregroundStyle(.white.opacity(0.7))
        }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(red: 34/255, green: 41/255, blue: 58/255), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
    /// Owner-only read that must NOT count as an install and returns only the author's own published code/settings.
    private func loadPublished() async {
        guard !item.id.isEmpty, item.mine, !item.uploaded,
              let d = try? await ForgeClient.get(item.version.map { ["action": "gallery-source", "id": item.id, "expectedVersion": String($0)] } ?? ["action": "gallery-source", "id": item.id]),
              let code = d["code"] as? String,
              ForgeCommunityUpdateLogic.sourceMatches(fetchedVersion: d["version"] as? Int, entryVersion: item.version) else { loadFailed = true; return }
        publishedCode = code
        publishedSettings = (d["settings"] as? [Any])?.count
        publishedLoaded = true
    }
    private func publish() async {
        guard let p = linked, let l = local else { return }
        working = true; failure = nil
        do {
            try await store.updateGallery(entry: item.id, from: p.id, changelog: changelog.trimmingCharacters(in: .whitespacesAndNewlines), expectedVersion: item.version, local: l)
            onPublished(); dismiss()
        } catch { failure = error.localizedDescription }
        working = false
    }
}
