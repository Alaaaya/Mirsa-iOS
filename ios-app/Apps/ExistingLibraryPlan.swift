import SwiftUI

/// Pure editing model for libraries a project already links (original IPA is never modified; the plan
/// is applied on the disposable signing copy). Reset = empty plan.
enum ExistingLibraryPlan {
    /// Executable lives at the app root, so its owner path has no "/".
    static func isMain(_ owner: String) -> Bool { !owner.contains("/") }

    /// Owning framework folder name for a bundled binary, e.g. "Frameworks/Foo.framework/Foo" -> "Foo.framework".
    static func frameworkName(_ owner: String) -> String {
        owner.split(separator: "/").first(where: { $0.hasSuffix(".framework") || $0.hasSuffix(".appex") }).map(String.init)
            ?? (owner.split(separator: "/").last.map(String.init) ?? owner)
    }

    static func provenanceLabel(_ lib: ExistingProjectLibrary) -> String {
        isMain(lib.owner)
            ? tr("Via main executable", "عبر الملف الرئيسي", ckb: "لە ڕێگەی فایلی سەرەکییەوە", kmr: "Bi riya pelê sereke")
            : tr("Via ", "عبر ", ckb: "لە ڕێگەی ", kmr: "Bi riya ") + frameworkName(lib.owner)
    }

    static func stateLabel(_ lib: ExistingProjectLibrary) -> String {
        lib.provenance == "bundledDependency"
            ? tr("Bundled in the app", "موجودة داخل التطبيق", ckb: "لەناو ئەپەکەدایە", kmr: "Di nav sepanê de ye")
            : tr("Location unresolved", "المكان غير محدد", ckb: "شوێنەکەی دیارینەکراوە", kmr: "Cih nehatiye diyarkirin")
    }

    static func removeTitle() -> String { tr("Remove this library?", "تشيل هالمكتبة؟", ckb: "ئەم کتێبخانەیە لابدرێت؟", kmr: "Ev pirtûkxane were rakirin?") }
    static func removeWarning() -> String {
        tr("If the app or another library needs it, the app can crash or fail to open. Shared files and files used by frameworks are kept. Only the signed copy changes.",
           "إذا التطبيق أو مكتبة تانية محتاجتها، ممكن التطبيق يسكّر أو ما يفتح. الملفات المشتركة وملفات الفريموركات بتضل. النسخة الموقّعة بس بتتغيّر.",
           ckb: "ئەگەر ئەپەکە یان کتێبخانەیەکی تر پێویستی پێی بێت، ڕەنگە ئەپەکە دابخرێت یان نەکرێتەوە. فایلە هاوبەشەکان و فایلەکانی فرەیمۆرک دەمێننەوە. تەنها کۆپی واژۆکراو دەگۆڕێت.",
           kmr: "Ger sepan an pirtûkxaneyek din hewceyî wê be, sepan dikare bigire an venebe. Pelên hevpar û yên frameworkan dimînin. Tenê kopiya îmzekirî diguherîne.")
    }

    static let explainer: () -> String = {
        tr("These libraries came with the app already. Having a file inside the app does not mean Mirsa injected it. Removing or reordering only changes the copy that gets signed.",
           "هاي المكتبات كانت أصلاً مع التطبيق. وجود ملف جوّا التطبيق ما يعني إنّو Mirsa حقنو. الحذف أو الترتيب بيغيّر النسخة اللي بتنوقّع بس.",
           ckb: "ئەم کتێبخانانە لە سەرەتاوە لەگەڵ ئەپەکە بوون. بوونی فایل لەناو ئەپەکە مانای ئەوە نییە Mirsa تێیکردووە. سڕینەوە یان ڕیزکردن تەنها ئەو کۆپییە دەگۆڕێت کە واژۆ دەکرێت.",
           kmr: "Ev pirtûkxane ji destpêkê ve bi sepanê re bûn. Heye ku pelek di nav sepanê de be wateya wê nîne ku Mirsa danî. Jêbirin an rêzkirin tenê kopiya ku tê îmzekirin diguherîne.")
    }

    /// Libraries of one owner in their effective order, removed ones kept (flagged) so they can be restored.
    static func effective(_ libs: [ExistingProjectLibrary], owner: String, edits: [ExistingLibraryEdit]) -> [(lib: ExistingProjectLibrary, removed: Bool)] {
        let mine = libs.filter { $0.owner == owner }
        let edit = edits.first { $0.owner == owner }
        let removed = Set(edit?.removed ?? [])
        let order = edit?.order ?? []
        let ordered = mine.sorted {
            (order.firstIndex(of: $0.loadPath) ?? Int.max, mine.firstIndex(of: $0) ?? 0) < (order.firstIndex(of: $1.loadPath) ?? Int.max, mine.firstIndex(of: $1) ?? 0)
        }
        return ordered.map { ($0, removed.contains($0.loadPath)) }
    }

    private static func normalized(_ edits: [ExistingLibraryEdit]) -> [ExistingLibraryEdit] {
        edits.filter { !$0.removed.isEmpty || !$0.order.isEmpty }
    }

    static func toggleRemoved(_ lib: ExistingProjectLibrary, in edits: [ExistingLibraryEdit]) -> [ExistingLibraryEdit] {
        var out = edits
        var e = out.first { $0.owner == lib.owner } ?? ExistingLibraryEdit(owner: lib.owner)
        if let i = e.removed.firstIndex(of: lib.loadPath) { e.removed.remove(at: i) }
        else { e.removed.append(lib.loadPath); e.order.removeAll { $0 == lib.loadPath } }
        out.removeAll { $0.owner == lib.owner }
        out.append(e)
        return normalized(out)
    }

    /// Moves a kept library up (-1) or down (+1) among the kept libraries of its owner. Writes a full order list.
    static func move(_ lib: ExistingProjectLibrary, by delta: Int, libs: [ExistingProjectLibrary], in edits: [ExistingLibraryEdit]) -> [ExistingLibraryEdit] {
        var kept = effective(libs, owner: lib.owner, edits: edits).filter { !$0.removed }.map(\.lib.loadPath)
        guard let i = kept.firstIndex(of: lib.loadPath), kept.indices.contains(i + delta) else { return edits }
        kept.swapAt(i, i + delta)
        var out = edits.filter { $0.owner != lib.owner }
        let removed = edits.first { $0.owner == lib.owner }?.removed ?? []
        out.append(ExistingLibraryEdit(owner: lib.owner, removed: removed, order: kept))
        return normalized(out)
    }

    static func reset() -> [ExistingLibraryEdit] { [] }
}

struct ExistingLibrariesCard: View {
    let libraries: [ExistingProjectLibrary]
    @Binding var edits: [ExistingLibraryEdit]
    @State private var open = true
    @State private var pendingRemove: ExistingProjectLibrary?

    private var owners: [String] {
        var seen = Set<String>(); var out: [String] = []
        for l in libraries where seen.insert(l.owner).inserted { out.append(l.owner) }
        return out.sorted { ExistingLibraryPlan.isMain($0) && !ExistingLibraryPlan.isMain($1) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button { withAnimation(.easeOut(duration: 0.25)) { open.toggle() } } label: {
                HStack {
                    Label(tr("Existing libraries", "المكتبات الموجودة", ckb: "کتێبخانە هەبووەکان", kmr: "Pirtûkxaneyên heyî"), systemImage: "books.vertical").font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("\(libraries.count)").foregroundStyle(.secondary)
                    Image(systemName: open ? "chevron.up" : "chevron.down")
                }
            }.buttonStyle(.mirsaPress)
            Text(ExistingLibraryPlan.explainer()).font(.caption2).foregroundStyle(.secondary)
            if open {
                ForEach(owners, id: \.self) { owner in
                    let rows = ExistingLibraryPlan.effective(libraries, owner: owner, edits: edits)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(ExistingLibraryPlan.isMain(owner) ? tr("Main executable", "الملف الرئيسي", ckb: "فایلی سەرەکی", kmr: "Pelê sereke") : ExistingLibraryPlan.frameworkName(owner))
                            .font(.caption.weight(.semibold))
                        ForEach(Array(rows.enumerated()), id: \.element.lib.id) { idx, row in
                            let keptIdx = rows.prefix(idx).filter { !$0.removed }.count
                            let keptCount = rows.filter { !$0.removed }.count
                            HStack(spacing: 8) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(row.lib.loadPath).font(.caption2.monospaced()).lineLimit(2)
                                        .strikethrough(row.removed)
                                    Text(ExistingLibraryPlan.provenanceLabel(row.lib) + " · " + ExistingLibraryPlan.stateLabel(row.lib))
                                        .font(.caption2).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 4)
                                if !row.removed {
                                    Button { edits = ExistingLibraryPlan.move(row.lib, by: -1, libs: libraries, in: edits) } label: { Image(systemName: "arrow.up") }
                                        .disabled(keptIdx == 0)
                                        .accessibilityLabel(tr("Move up", "تحريك لفوق", ckb: "بۆ سەرەوە", kmr: "Biçe jor"))
                                    Button { edits = ExistingLibraryPlan.move(row.lib, by: 1, libs: libraries, in: edits) } label: { Image(systemName: "arrow.down") }
                                        .disabled(keptIdx >= keptCount - 1)
                                        .accessibilityLabel(tr("Move down", "تحريك لتحت", ckb: "بۆ خوارەوە", kmr: "Biçe jêr"))
                                }
                                Button { if row.removed { edits = ExistingLibraryPlan.toggleRemoved(row.lib, in: edits) } else { pendingRemove = row.lib } } label: {
                                    Image(systemName: row.removed ? "arrow.uturn.backward" : "trash")
                                }.tint(row.removed ? .green : .red)
                                .accessibilityLabel(row.removed ? tr("Restore", "استرجاع", ckb: "گەڕاندنەوە", kmr: "Vegerîne") : tr("Remove", "إزالة", ckb: "لابردن", kmr: "Rakirin"))
                            }
                            .buttonStyle(.borderless)
                            .opacity(row.removed ? 0.55 : 1)
                        }
                    }
                }
                if !edits.isEmpty {
                    Button { edits = ExistingLibraryPlan.reset() } label: {
                        Label(tr("Reset libraries", "إعادة المكتبات للأصل", ckb: "گەڕاندنەوەی کتێبخانەکان", kmr: "Pirtûkxaneyan vegerîne"), systemImage: "arrow.counterclockwise")
                    }.font(.caption.weight(.semibold))
                }
            }
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading).appsGlass(cornerRadius: 24)
        .confirmationDialog(ExistingLibraryPlan.removeTitle(), isPresented: Binding(get: { pendingRemove != nil }, set: { if !$0 { pendingRemove = nil } }), titleVisibility: .visible, presenting: pendingRemove) { lib in
            Button(tr("Remove", "إزالة", ckb: "لابردن", kmr: "Rakirin"), role: .destructive) { edits = ExistingLibraryPlan.toggleRemoved(lib, in: edits); pendingRemove = nil }
            Button(tr("Cancel", "إلغاء", ckb: "پاشگەزبوونەوە", kmr: "Betal"), role: .cancel) { pendingRemove = nil }
        } message: { _ in Text(ExistingLibraryPlan.removeWarning()) }
    }
}
