import Foundation
import SwiftUI

enum IPATweakImportText {
    static func error(_ detail: String) -> String {
        if detail.contains("cancelled") { return tr("Import cancelled.", "انلغت الإضافة.", ckb: "هاوردەکردن هەڵوەشایەوە.", kmr: "Anîn hat betalkirin.") }
        if detail.contains("limits") || detail.contains("disk") {
            return tr("Not enough space or this archive exceeds safe import limits (128 MB per file, 256 MB expanded, 10,000 entries).",
                      "المساحة مو كافية أو الأرشيف أكبر من حدود الإضافة الآمنة (128 MB للملف، 256 MB بعد الفك، 10,000 ملف).",
                      ckb: "شوێن بەس نییە یان ئەرشیفەکە لە سنووری سەلامەتی زیاترە (128 MB بۆ فایل، 256 MB دوای کردنەوە، 10,000 فایل).",
                      kmr: "Cih têr nake an arşîv ji sînorê ewle mezintir e (128 MB her dosya, 256 MB vekirî, 10,000 dosya).")
        }
        return tr("Cannot import this archive. It may be damaged, encrypted, contain unsafe paths or links, or have no valid arm64 tweak. Import ordinary ZIP, .deb, .dylib or link-free .framework files. Nothing was installed.",
                  "ما قدرت أضيف هالأرشيف. ممكن تالف، مشفّر، فيه مسارات أو روابط غير آمنة، أو ما فيه تويك arm64 صالح. اختار ZIP عادي أو deb أو dylib أو framework بلا روابط. ما تثبّت شي.",
                  ckb: "نەتوانرا ئەرشیفەکە هاوردە بکرێت. ڕەنگە خراپ یان نهێنیکراو بێت، ڕێڕەو یان بەستەری ناسەلامەت بگرێتەوە، یان tweaki arm64 دروستی نەبێت. ZIPی ئاسایی، deb، dylib یان frameworkی بێ بەستەر هەڵبژێرە. هیچ شتێک دانەمەزرا.",
                  kmr: "Arşîv nayê anîn. Dibe ku xerab, şîfrekirî, rê an girêdanên neewle tê de bin, an tweakeke arm64 ya derbasdar tê de tune be. ZIPa asayî, deb, dylib an framework bê girêdan hilbijêre. Tiştek nehat sazkirin.")
    }
}

struct IPATweakImportCandidate: Decodable, Identifiable, Sendable {
    let id: String
    let path: String
    let name: String
    let kind: String
    let origin: String
    let sha256: String
    let identity: String
    let ambiguous: Bool
}

struct IPATweakImportChoice: Identifiable {
    let id = UUID()
    let candidates: [IPATweakImportCandidate]
}

struct IPATweakImportSelectionView: View {
    let choice: IPATweakImportChoice
    let finish: ([String]?) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var selected = Set<String>()
    private var valid: Bool {
        let chosen = choice.candidates.filter { selected.contains($0.id) }
        return !chosen.isEmpty && Set(chosen.map(\.identity)).count == chosen.count
    }
    var body: some View {
        NavigationStack {
            ZStack {
                AuroraBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(tr("Choose additions to keep. Matching .deb copies were removed in favor of the identical direct dylib. Different versions with the same name need your choice.",
                                "اختار الإضافات اللي بدك تحتفظ فيها. نسخة deb المطابقة انشالت لصالح dylib نفسه. إذا في نسخ مختلفة بنفس الاسم، اختار وحدة.",
                                ckb: "زیادکراوەکان هەڵبژێرە. کۆپی debی هاوشێوە بە dylibی ڕاستەوخۆ جێگیر کراوە. لە وەشانە جیاوازەکانی هەمان ناو یەکێک هەڵبژێرە.",
                                kmr: "Pêvekan hilbijêre. Kopiya deb ya heman bi dyliba rasterast hat guhertin. Ji guhertoyên cuda yên bi heman navî yekê hilbijêre."))
                            .font(.footnote).foregroundStyle(.secondary)
                        ForEach(choice.candidates) { candidate in
                            Button {
                                if selected.contains(candidate.id) { selected.remove(candidate.id) }
                                else {
                                    for other in choice.candidates where other.identity == candidate.identity { selected.remove(other.id) }
                                    selected.insert(candidate.id)
                                }
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: selected.contains(candidate.id) ? "checkmark.circle.fill" : "circle")
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(candidate.name).font(.headline)
                                        Text(candidate.origin + " · " + candidate.path).font(.caption).foregroundStyle(.secondary)
                                        Text(String(candidate.sha256.prefix(12))).font(.caption.monospaced()).foregroundStyle(.secondary)
                                    }
                                    Spacer(minLength: 0)
                                }.frame(maxWidth: .infinity, alignment: .leading).padding(14).appsGlass(cornerRadius: 16)
                            }.buttonStyle(.plain)
                        }
                        Text(tr("Only code and complete framework bundles are kept. Scripts are never executed. Review trust before signing or installing.",
                                "بينحفظ الكود والفريمورك كامل بس. السكربتات ما بتشتغل أبداً. راجع الثقة قبل التوقيع أو التثبيت.",
                                ckb: "تەنیا کۆد و frameworkی تەواو دەپارێزرێت. سکریپت جێبەجێ ناکرێت. پێش واژۆکردن یان دامەزراندن متمانە بپشکنە.",
                                kmr: "Tenê kod û frameworkên tevahî tên parastin. Skrîpt qet nayên meşandin. Berî îmzekirin an sazkirinê baweriyê kontrol bike."))
                            .font(.footnote).foregroundStyle(.secondary)
                    }.padding(20)
                }
            }
            .navigationTitle(tr("Choose additions", "اختيار الإضافات", ckb: "زیادکراوەکان هەڵبژێرە", kmr: "Pêvekan hilbijêre"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(tr("Cancel", "إلغاء", ckb: "هەڵوەشاندنەوە", kmr: "Betal")) { finish(nil); dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(tr("Add", "إضافة", ckb: "زیادکردن", kmr: "Zêde bike")) { finish(Array(selected)); dismiss() }.disabled(!valid)
                }
            }
        }
        .environment(\.layoutDirection, .leftToRight)
        .onAppear { selected = Set(choice.candidates.filter { !$0.ambiguous }.map(\.id)) }
    }
}
