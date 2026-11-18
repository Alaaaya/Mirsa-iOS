import SwiftUI
import UniformTypeIdentifiers
import CryptoKit

/// Server capability gate. Anything but an explicit true is OFF, and OFF never submits.
struct ForgeRepairCapabilities: Equatable { var port = false; var blackbox = false }

enum ForgeRepairGate {
    static func fetch() async -> ForgeRepairCapabilities {
        do {
            let token = try await ForgeClient.fixToken()
            let data = try await ForgeClient.fixRequest(["action": "port-capabilities"], deviceToken: token, maxBytes: 4096)
            guard let o = try JSONSerialization.jsonObject(with: data) as? [String: Any], o["schema"] as? Int == 1, o["autoEnable"] as? Bool == false, o["delivery"] as? String == "fix-inbox" else { return .init() }
            return .init(port: o["portAvailable"] as? Bool == true && o["uploads"] as? String == "authenticated-stream-v1" && ForgePortUploader.base != nil, blackbox: o["blackboxAvailable"] as? Bool == true)
        } catch { return .init() }
    }
}

extension ForgeStore {
    /// Uploads both IPAs (raw stream) then submits ids+hashes. Requires capability AND an approved base.
    func sendPortRequest(projectID: UUID, versionID: UUID, oldFile: URL, newFile: URL, old: ForgePortScan, new: ForgePortScan, requestID: UUID) async throws -> String {
        guard let p = project(projectID), let v = p.versions.first(where: { $0.id == versionID }), old.bundleID == p.bundleID, new.bundleID == p.bundleID
        else { throw ForgeClient.Failure.message("No matching tweak.") }
        guard await ForgeRepairGate.fetch().port else { throw ForgeClient.Failure.message(ForgePortText.unavailable) }
        let cr = try await ForgeClient.fixToken()
        let a = try await ForgePortUploader.upload(file: oldFile, role: "old", credentials: cr)
        let b = try await ForgePortUploader.upload(file: newFile, role: "new", credentials: cr)
        let o = try await ForgePortUploader.request(id: requestID, tweakID: v.tweakID, bundleID: p.bundleID, name: ForgeFeaturePolicy.name(p.name),
            sourceSHA256: ForgeFixItem.sha(Data(v.code.utf8)), code: v.code, old: a, new: b, credentials: cr)
        return (o["status"] as? String) ?? "queued"
    }
}

enum ForgePortText {
    static var title: String { tr5("Port tweak", "انقل التويك", de: "Tweak übertragen", ckb: "تویک بگوازەوە", kmr: "Tweakê veguhezîne") }
    static var unavailable: String { tr5("Porting is not available on the server yet. Nothing was sent.", "النقل لسا مو متاح عالسيرفر. ما انبعت شي.", de: "Das Übertragen ist auf dem Server noch nicht verfügbar. Es wurde nichts gesendet.", ckb: "گواستنەوە هێشتا لە سێرڤەر بەردەست نییە. هیچ نەنێردرا.", kmr: "Veguhastin hê li ser serverê peyda nîne. Tiştek nehat şandin.") }
    static var privacy: String { tr5("The analysis runs on your device. Sending is not active yet. When it is, the server would receive your tweak source and the two IPAs privately for this one request. A name match is a suggestion, not proof the app still behaves the same, so any repaired version comes back for your review and never enables itself.", "التحليل بيصير عجهازك. الإرسال لسا مو شغّال. لما يشتغل السيرفر بيستقبل كود التويك والـ IPAين بشكل خاص لهالطلب بس. تطابق الأسماء اقتراح مو إثبات، فأي نسخة مصلّحة بترجع لمراجعتك وما بتتفعّل لحالها.", de: "Die Analyse läuft auf deinem Gerät. Senden ist noch nicht aktiv. Später würde der Server Tweak-Quellcode und beide IPAs privat nur für diese Anfrage erhalten. Ein Namensgleichheit ist ein Vorschlag, kein Beweis für gleiches Verhalten; eine reparierte Version kommt zur Prüfung zurück und aktiviert sich nie selbst.", ckb: "شیکاری لەسەر ئامێرەکەت ئەنجام دەدرێت. ناردن هێشتا چالاک نییە. دواتر سێرڤەر سەرچاوەی تویک و هەردوو IPA بە تایبەتی تەنها بۆ ئەم داواکارییە وەردەگرێت. هاوشێوەیی ناو پێشنیارە نەک بەڵگە؛ وەشانی چاککراو بۆ پێداچوونەوە دەگەڕێتەوە و خۆی چالاک نابێت.", kmr: "Analîz li ser cîhaza te dibe. Şandin hê çalak nîne. Paşê server dê koda tweakê û her du IPA bi taybetî tenê ji bo vê daxwazê bistîne. Hevtayiya navê pêşniyar e, ne delîl; guhertoya sererastkirî ji bo kontrolê vedigere û bi xwe çalak nabe.") }
}

struct ForgePortView: View {
    let projectID: UUID
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = ForgeStore.shared
    @State private var old: ForgePortScan?
    @State private var new: ForgePortScan?
    @State private var picking: String?
    @State private var busy = false
    @State private var plan: ForgePortPlan?
    @State private var error: String?
    @State private var sent = false
    @State private var consent = false
    @State private var caps = ForgeRepairCapabilities()
    @State private var requestID = UUID()
    @State private var oldFile: URL?
    @State private var newFile: URL?

    private var project: ForgeProject? { store.project(projectID) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForgeFeatureGuide(.port)
                    Text(ForgePortText.privacy).font(.footnote)
                    if !caps.port { Text(ForgePortText.unavailable).font(.footnote).foregroundStyle(.orange) }
                    pickRow("old", tr5("Old app IPA (tweak worked)", "IPA القديم (التويك كان شغال)", de: "Alte App-IPA (Tweak funktionierte)", ckb: "IPAی کۆن (تویک کاری دەکرد)", kmr: "IPAya kevn (tweak dixebitî)"), old)
                    pickRow("new", tr5("New app IPA (tweak broke)", "IPA الجديد (التويك خرب)", de: "Neue App-IPA (Tweak defekt)", ckb: "IPAی نوێ (تویک تێکچوو)", kmr: "IPAya nû (tweak xira bû)"), new)
                    if busy { ProgressView() }
                    if let plan { planView(plan) }
                    if sent { Text(tr5("Request sent for manual review. Nothing is repaired automatically; a reviewed version may appear in Versions later.", "انبعت الطلب. افتح مرسى بعدين؛ بتظهر نسخة مصلّحة بالنسخ للمراجعة.", de: "Anfrage gesendet. Öffne Mirsa später; eine reparierte Version erscheint zur Prüfung unter Versionen.", ckb: "داواکاری نێردرا. دواتر میرسا بکەرەوە؛ وەشانی چاککراو لە وەشانەکان دەردەکەوێت.", kmr: "Daxwaz hat şandin. Paşê Mirsa veke; guhertoyeke sererastkirî di Guhertoyan de xuya dibe.")).foregroundStyle(.green).font(.footnote) }
                    if let error { Text(error).foregroundStyle(.orange).font(.footnote) }
                }.padding(18)
            }
            .background(forgeCard.ignoresSafeArea()).foregroundStyle(.white)
            .navigationTitle(ForgePortText.title).navigationBarTitleDisplayMode(.inline)
            .onDisappear { for f in [oldFile, newFile].compactMap({ $0 }) { try? FileManager.default.removeItem(at: f) } }
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(tr("Done", "تم", ckb: "تەواو", kmr: "Temam")) { dismiss() }.disabled(busy) } }
            .fileImporter(isPresented: Binding(get: { picking != nil }, set: { if !$0 { picking = nil } }), allowedContentTypes: IPAPick.types) { result in
                let slot = picking; picking = nil
                if case .success(let url) = result, let slot { load(url, slot: slot) }
            }
            .task { caps = await ForgeRepairGate.fetch() }
        }.environment(\.layoutDirection, .leftToRight)
    }

    private func pickRow(_ slot: String, _ title: String, _ scan: ForgePortScan?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Button(title) { picking = slot }.buttonStyle(.mirsaSecondary).disabled(busy)
            if let scan { Text(scan.version + " (" + scan.build + ") · " + String(scan.classes.count) + " " + tr5("classes", "كلاس", de: "Klassen", ckb: "کڵاس", kmr: "klas")).font(.caption).foregroundStyle(.white.opacity(0.65)) }
        }
    }

    @ViewBuilder private func planView(_ plan: ForgePortPlan) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(tr5("Still working: ", "لسا شغّال: ", de: "Funktioniert weiter: ", ckb: "هێشتا کار دەکات: ", kmr: "Hê dixebite: ") + String(plan.intact.count)).font(.subheadline)
            ForEach(plan.mappings, id: \.old) { m in
                Text(m.old + " → " + m.new).font(.system(.caption, design: .monospaced)).foregroundStyle(.green)
            }
            if !plan.unresolved.isEmpty {
                Text(tr5("Needs a decision, not guessed:", "بدو قرار، ما انخمّن:", de: "Braucht eine Entscheidung, nicht geraten:", ckb: "پێویستی بە بڕیار هەیە، گومان نەکراوە:", kmr: "Hewceyî biryarê ye, nehat texmînkirin:")).font(.subheadline)
                ForEach(plan.unresolved, id: \.name) { u in
                    Text(u.name + (u.candidates.isEmpty ? "" : "  ≈ " + u.candidates.joined(separator: ", "))).font(.system(.caption, design: .monospaced)).foregroundStyle(.orange)
                }
            }
            if plan.mappings.isEmpty && plan.unresolved.isEmpty {
                Text(tr5("All hooked classes still exist. Nothing to port.", "كل الكلاسات المهووكة لسا موجودة. ما في شي للنقل.", de: "Alle gehookten Klassen existieren noch. Nichts zu übertragen.", ckb: "هەموو کڵاسە هووککراوەکان ماون. هیچ شتێک نییە بگوازرێتەوە.", kmr: "Hemû klasên hookkirî hê hene. Tiştek ji bo veguhastinê tune.")).foregroundStyle(.green).font(.footnote)
            } else {
                Toggle(tr5("I agree to send this list", "بوافق عإرسال هالقائمة", de: "Ich stimme zu, diese Liste zu senden", ckb: "ڕازیم ئەم لیستە بنێردرێت", kmr: "Razî me ev lîste bê şandin"), isOn: $consent)
                Button(tr5("Send repair request", "إرسال طلب الإصلاح", de: "Reparaturanfrage senden", ckb: "ناردنی داواکاری چاککردن", kmr: "Daxwaza sererastkirinê bişîne")) { send(plan) }
                    .disabled(!consent || !caps.port || busy || sent)
            }
        }.padding(12).background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
    }

    private func load(_ url: URL, slot: String) {
        busy = true; error = nil; plan = nil; consent = false; sent = false
        let scoped = url.startAccessingSecurityScopedResource()
        Task { @MainActor in
            defer { busy = false; if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                let copy = FileManager.default.temporaryDirectory.appendingPathComponent("port-" + UUID().uuidString + ".ipa")
                try await Task.detached(priority: .userInitiated) { try FileManager.default.copyItem(at: url, to: copy) }.value
                let s: ForgePortScan
                do { s = try await Task.detached(priority: .userInitiated) { try ForgePortScanner.scan(ipa: copy) }.value } catch { try? FileManager.default.removeItem(at: copy); throw error }
                if let p = project, s.bundleID != p.bundleID { try? FileManager.default.removeItem(at: copy); throw ForgePortError.differentApp }
                if slot == "old" { if let f = oldFile { try? FileManager.default.removeItem(at: f) }; oldFile = copy } else { if let f = newFile { try? FileManager.default.removeItem(at: f) }; newFile = copy }
                if slot == "old" { old = s } else { new = s }
                if let o = old, let n = new, let p = project, let v = p.currentVersion {
                    let hooks = ForgePortMapper.hooks(in: v.code)
                    guard !hooks.isEmpty else { throw ForgePortError.nothingHooked }
                    plan = ForgePortMapper.plan(code: v.code, old: o, new: n); requestID = UUID()
                }
            } catch { self.error = error.localizedDescription }
        }
    }

    private func send(_ plan: ForgePortPlan) {
        guard let o = old, let n = new, let oldF = oldFile, let nf = newFile, let v = project?.currentVersion, consent, !busy, !sent else { return }
        busy = true; error = nil
        Task { @MainActor in
            defer { busy = false }
            do { _ = try await store.sendPortRequest(projectID: projectID, versionID: v.id, oldFile: oldF, newFile: nf, old: o, new: n, requestID: requestID); sent = true }
            catch { self.error = error.localizedDescription }
        }
    }
}
