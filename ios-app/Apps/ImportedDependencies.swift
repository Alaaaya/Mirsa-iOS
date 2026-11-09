import Foundation
import SwiftUI

struct ImportedLoad: Codable, Equatable, Sendable {
    let owner: String
    let mainOwner: Bool
    let slice: Int
    let subtype: UInt32
    let loadPath: String
    let weak: Bool
    let resolvedPath: String?
    enum CodingKeys: String, CodingKey {
        case owner, slice, subtype, weak
        case mainOwner = "main_owner", loadPath = "load_path", resolvedPath = "resolved_path"
    }
}

struct ImportedLoadReport: Decodable, Sendable {
    let version: Int
    let entries: [ImportedLoad]
    let warning: String
}

struct ImportedLoadEdit: Codable, Equatable, Sendable {
    let owner: String
    var remove: [String] = []
    var order: [String] = []
}

/// Edits describe commands, never arbitrary filesystem paths. All edits are replayed
/// against a fresh archive copy on export; Reset just clears this plan.
enum ImportedLoadPlan {
    static func paths(owner: String, entries: [ImportedLoad], edits: [ImportedLoadEdit]) -> [String] {
        let edit = edits.first { $0.owner == owner }
        var seen = Set<String>()
        let base = entries.filter { $0.owner == owner }.map(\.loadPath)
            .filter { seen.insert($0).inserted && !(edit?.remove.contains($0) ?? false) }
        if let order = edit?.order, !order.isEmpty {
            return order.filter { base.contains($0) } + base.filter { !order.contains($0) }
        }
        return base
    }

    static func removing(_ path: String, owner: String, entries: [ImportedLoad], edits: [ImportedLoadEdit]) -> [ImportedLoadEdit] {
        guard paths(owner: owner, entries: entries, edits: edits).contains(path) else { return edits }
        var result = edits
        var edit = result.first { $0.owner == owner } ?? ImportedLoadEdit(owner: owner)
        edit.remove.append(path)
        edit.order.removeAll { $0 == path }
        result.removeAll { $0.owner == owner }
        result.append(edit)
        return result
    }

    static func moving(_ path: String, by offset: Int, owner: String, entries: [ImportedLoad], edits: [ImportedLoadEdit]) -> [ImportedLoadEdit] {
        var order = paths(owner: owner, entries: entries, edits: edits)
        guard let index = order.firstIndex(of: path), order.indices.contains(index + offset) else { return edits }
        order.swapAt(index, index + offset)
        var result = edits
        var edit = result.first { $0.owner == owner } ?? ImportedLoadEdit(owner: owner)
        edit.order = order
        result.removeAll { $0.owner == owner }
        result.append(edit)
        return result
    }
}

struct ImportedDependenciesView: View {
    let report: ImportedLoadReport?
    let error: String?
    @Binding var edits: [ImportedLoadEdit]?
    @State private var pending: ImportedLoad?
    private var plan: [ImportedLoadEdit] { edits ?? [] }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(sgText("Dependencies already in this IPA", "المكتبات الموجودة بالـ IPA", "کتێبخانەکانی ناو IPA", "Pirtûkxaneyên di IPA de")).font(.subheadline.weight(.semibold))
            Text(sgText("These can be original app libraries, not necessarily injected tweaks. Removing a link may stop the app. Files are kept for safety; signing applies the changes to a copy.",
                        "ممكن تكون مكتبات أصلية للتطبيق، مو بالضرورة إضافات محقونة. حذف الربط ممكن يعطّل التطبيق. الملفات بتضل للأمان، والتغييرات بتنطبق على نسخة وقت التوقيع.",
                        "دەکرێت کتێبخانەی ڕەسەنی ئەپ بن، نەک تویکی زیادکراو. سڕینەوەی بەستەر دەکرێت ئەپ بوەستێنێت. فایلەکان بۆ سەلامەتی دەمێننەوە و گۆڕانکاری لەسەر کۆپی جێبەجێ دەکرێت.",
                        "Dibe ku pirtûkxaneyên resen ên appê bin, ne tweakên lêzêdekirî. Jêbirina girêdanê dikare appê rawestîne. Dosya ji bo ewlehiyê dimînin; guhartin li kopiyê tên kirin.")).font(.caption).foregroundStyle(.secondary)
            if let error { Text(error).font(.caption).foregroundStyle(.orange) }
            else if let report {
                let owners = Array(Set(report.entries.map(\.owner))).sorted()
                if report.entries.isEmpty {
                    Text(sgText("No non-system dependencies found.", "ما لقيت مكتبات غير مكتبات النظام.", "هیچ کتێبخانەیەکی دەرەوەی سیستەم نەدۆزرایەوە.", "Pirtûkxaneyeke derveyî pergalê nehat dîtin.")).font(.caption)
                }
                ForEach(owners, id: \.self) { owner in
                    ownerRows(owner, report.entries)
                }
                if !plan.isEmpty {
                    Button { edits = nil } label: {
                        Label(sgText("Reset to original", "رجّع الأصلي", "گەڕاندنەوەی ڕەسەن", "Vegere resen"), systemImage: "arrow.uturn.backward")
                    }
                }
            } else { ProgressView() }
        }
        .alert(sgText("Remove dependency link?", "تحذف ربط المكتبة؟", "بەستەری کتێبخانە بسڕدرێتەوە؟", "Girêdana pirtûkxaneyê jê bibe?"), isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } })) {
            Button(SourceDeletionText.cancel, role: .cancel) { pending = nil }
            Button(SourceDeletionText.delete, role: .destructive) {
                if let pending, let report {
                    edits = ImportedLoadPlan.removing(pending.loadPath, owner: pending.owner, entries: report.entries, edits: plan)
                }
                pending = nil
            }
        } message: { Text(pending?.loadPath ?? "") }
    }

    @ViewBuilder private func ownerRows(_ owner: String, _ entries: [ImportedLoad]) -> some View {
        let paths = ImportedLoadPlan.paths(owner: owner, entries: entries, edits: plan)
        let main = entries.first { $0.owner == owner }?.mainOwner == true
        Text(main ? sgText("Via main executable", "عبر الملف الرئيسي", "لە ڕێگەی فایلی سەرەکی", "Bi rêya dosyaya sereke")
             : sgText("Via framework / bundled executable", "عبر framework / ملف مضمّن", "لە ڕێگەی framework / فایلی ناوخۆ", "Bi rêya framework / dosyaya hundirîn"))
            .font(.caption.weight(.semibold))
        Text(owner).font(.caption2).foregroundStyle(.secondary).textSelection(.enabled)
        ForEach(Array(paths.enumerated()), id: \.element) { index, path in
            let entry = entries.first { $0.owner == owner && $0.loadPath == path }
            HStack(spacing: 8) {
                Button { pending = entry } label: { Image(systemName: "minus.circle.fill").foregroundStyle(.red) }
                VStack(alignment: .leading, spacing: 3) {
                    Text(path).font(.caption).textSelection(.enabled)
                    if entry?.resolvedPath == nil {
                        Text(sgText("Path unresolved; not proof of a missing file", "المسار مو محسوم، مو دليل إن الملف ناقص", "ڕێڕەو دیار نییە؛ بەڵگەی کەمی فایل نییە", "Rê ne diyar e; ne delîla dosyaya winda ye")).font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
                Button { edits = ImportedLoadPlan.moving(path, by: -1, owner: owner, entries: entries, edits: plan) } label: { Image(systemName: "arrow.up") }.disabled(index == 0)
                Button { edits = ImportedLoadPlan.moving(path, by: 1, owner: owner, entries: entries, edits: plan) } label: { Image(systemName: "arrow.down") }.disabled(index == paths.count - 1)
            }.buttonStyle(.mirsaPress).padding(10).background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
        }
    }
}
