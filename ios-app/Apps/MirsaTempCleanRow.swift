import SwiftUI

/// Small Settings item: shows the size of Mirsa's own managed temporary files and clears the ones not in use.
struct MirsaTempCleanRow: View {
    @State private var size = MirsaManagedTmp.sizeText
    @State private var busy = false
    var body: some View {
        Section {
            Button {
                busy = true
                DispatchQueue.global(qos: .utility).async {
                    MirsaManagedTmp.cleanNow()
                    let t = MirsaManagedTmp.sizeText
                    DispatchQueue.main.async { size = t; busy = false }
                }
            } label: {
                HStack {
                    Text(tr("Clean temporary files", "تنظيف الملفات المؤقتة", ckb: "پاککردنەوەی فایلە کاتییەکان", kmr: "Pelên demkî paqij bike"))
                    Spacer()
                    Text(size).foregroundStyle(.secondary).monospacedDigit()
                }
            }.disabled(busy)
            .accessibilityIdentifier("settings-clean-temp")
        } footer: {
            Text(tr("Only Mirsa's own working files that are not in use. Your apps, library and projects are never touched.", "بس ملفات الشغل المؤقتة تبع مرسى اللي مو مستخدمة. تطبيقاتك ومكتبتك ومشاريعك ما بتنلمس.", ckb: "تەنها فایلە کاتییەکانی خودی میرسا کە بەکارنایەن. ئەپ و کتێبخانە و پڕۆژەکانت دەست لێ نادرێت.", kmr: "Tenê pelên xebatê yên Mirsayê yên ku nayên bikaranîn. Sepan, pirtûkxane û projeyên te nayên destlêdan."))
        }
        .onAppear { size = MirsaManagedTmp.sizeText }
    }
}
