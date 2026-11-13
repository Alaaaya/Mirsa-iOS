import SwiftUI

/// Available for every existing tweak, including guard failures and old build errors.
/// Opening, previewing or cancelling never uploads anything.
struct ForgeFixReportView: View {
    let projectID: UUID
    let versionID: UUID
    let initialDiagnostic: String
    @State var kind: String = "crash"
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ""
    @State private var preview = ""
    @State private var consent = false
    @State private var sending = false
    @State private var sent = false
    @State private var error: String?
    @State private var reportID = UUID()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(ForgeFixText.privacy).font(.footnote)
                    Picker(tr("Failure", "المشكلة", ckb: "کێشە", kmr: "Pirsgirêk"), selection: $kind) {
                        Text(tr("Crash / guard", "كراش / حماية التويك", ckb: "داخستن / پاراستن", kmr: "Qelibîn / parastin")).tag("crash")
                        Text(tr("Build failure", "فشل البناء", ckb: "شکستی دروستکردن", kmr: "Têkçûna çêkirinê")).tag("build")
                    }.pickerStyle(.segmented)
                    TextEditor(text: $draft).frame(height: 140).scrollContentBackground(.hidden)
                        .padding(8).background(Color.white.opacity(0.06)).cornerRadius(10)
                    Button(tr("Preview safe report", "معاينة التقرير الآمن", ckb: "پێشبینینی ڕاپۆرتی پارێزراو", kmr: "Rapora ewle bibîne")) {
                        preview = ForgeFixDiagnostic.sanitized(draft, kind: kind)
                        consent = false; reportID = UUID()
                    }
                    if !preview.isEmpty {
                        Text(preview).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                        Toggle(tr("I reviewed this report and agree to send it", "راجعت هالتقرير وبوافق عإرساله", ckb: "ڕاپۆرتەکەم پشکنیوە و ڕازیم بنێردرێت", kmr: "Min ev rapor kontrol kir û razî me bê şandin"), isOn: $consent)
                        Button(ForgeFixText.report) {
                            guard consent, !sending, !sent else { return }
                            sending = true; error = nil
                            Task { @MainActor in
                                defer { sending = false }
                                do {
                                    try await ForgeStore.shared.sendFixReport(projectID: projectID, versionID: versionID, kind: kind, diagnostic: draft, consent: consent, reportID: reportID)
                                    sent = true
                                } catch { self.error = error.localizedDescription }
                            }
                        }.disabled(!consent || sending || sent)
                    }
                    if sending { ProgressView() }
                    if sent {
                        Text(tr("Report sent. Reopen Mirsa later to check for a fixed version. Your current tweak is unchanged.", "انبعت التقرير. افتح ميرسا بعدين لحتى يتفقّد نسخة إصلاح. تويكك الحالي ما تغيّر.", ckb: "ڕاپۆرت نێردرا. دواتر میرسا بکەرەوە بۆ پشکنینی چاککردنەوە. تویکی ئێستا نەگۆڕا.", kmr: "Rapor hat şandin. Paşê Mirsa veke ji bo sererastkirinê. Tweaka niha neguherî."))
                            .foregroundStyle(.green)
                    }
                    if let error { Text(error).foregroundStyle(.orange) }
                }.padding(18)
            }
            .background(forgeCard.ignoresSafeArea()).foregroundStyle(.white)
            .navigationTitle(ForgeFixText.report).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) {
                Button(tr("Done", "تم", ckb: "تەواو", kmr: "Temam")) { dismiss() }.disabled(sending)
            } }
            .onAppear { draft = initialDiagnostic }
            .onChange(of: draft) { _, _ in preview = ""; consent = false; sent = false }
            .onChange(of: kind) { _, _ in preview = ""; consent = false; sent = false }
            .disabled(sending)
        }.environment(\.layoutDirection, .leftToRight)
    }
}

struct ForgeFixReportTarget: Identifiable {
    var id = UUID()
    let versionID: UUID
    let kind: String
    let diagnostic: String
}
