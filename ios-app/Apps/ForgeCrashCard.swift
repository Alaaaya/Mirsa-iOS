import SwiftUI

/// Crash marker written by GuestLoader.m just before the guest main() runs and cleared after 20 s alive or on a clean background/terminate.
/// A leftover marker at the next Mirsa start means the container session ended abnormally. Container launches only.
enum ForgeCrashMonitor {
    static let markerKey = "mirsa.guest.crashMarker"
    static let countsKey = "mirsa.guest.crashCounts"
    static let pendingKey = "mirsa.guest.crashPending"

    /// Moves a leftover marker to counters and a pending card. Safe to call repeatedly.
    @discardableResult static func consume(_ d: UserDefaults = .standard) -> (bundleID: String, count: Int)? {
        guard let m = d.dictionary(forKey: markerKey), let id = m["bundleID"] as? String, !id.isEmpty else { return nil }
        d.removeObject(forKey: markerKey)
        var counts = d.dictionary(forKey: countsKey) as? [String: Int] ?? [:]
        counts[id, default: 0] += 1
        d.set(counts, forKey: countsKey)
        d.set(["bundleID": id, "count": counts[id] ?? 1, "at": Date().timeIntervalSince1970], forKey: pendingKey)
        return (id, counts[id] ?? 1)
    }
    static func pending(_ d: UserDefaults = .standard) -> (bundleID: String, count: Int)? {
        guard let p = d.dictionary(forKey: pendingKey), let id = p["bundleID"] as? String, let c = p["count"] as? Int else { return nil }
        return (id, c)
    }
    static func dismiss(_ d: UserDefaults = .standard) { d.removeObject(forKey: pendingKey) }
    static func reset(_ bundleID: String, _ d: UserDefaults = .standard) {
        var counts = d.dictionary(forKey: countsKey) as? [String: Int] ?? [:]
        counts[bundleID] = nil; d.set(counts, forKey: countsKey)
    }
}

/// Card shown on the tweaks page after an abnormal end. One tap opens the existing consent + sanitized report sheet.
struct ForgeCrashCard: View {
    @ObservedObject private var store = ForgeStore.shared
    @State private var info: (bundleID: String, count: Int)?
    @State private var report: (project: UUID, version: UUID, text: String)?
    @State private var showReport = false

    var body: some View {
        Group {
            if let info {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(tr("The last app session ended unexpectedly", "آخر تشغيل للتطبيق انتهى بشكل غير متوقع", ckb: "دوایین کارپێکردنی ئەپەکە بە شێوەیەکی چاوەڕواننەکراو کۆتایی هات", kmr: "Danişîna dawî ya appê ji nişkê ve qediya")).font(.subheadline.bold())
                            Text(info.bundleID + " · " + tr("crashes", "كراشات", ckb: "داخستنەکان", kmr: "qelibîn") + " \(info.count)").font(.caption).foregroundStyle(.white.opacity(0.65))
                        }
                        Spacer()
                        Button { ForgeCrashMonitor.dismiss(); self.info = nil } label: { Image(systemName: "xmark") }
                            .accessibilityLabel(tr("Dismiss", "إخفاء", ckb: "داخستن", kmr: "Veşêre"))
                    }
                    if let target = project(info.bundleID) {
                        Button(tr("Send for a fix", "ابعت للإصلاح", ckb: "بنێرە بۆ چاککردنەوە", kmr: "Ji bo sererastkirinê bişîne")) {
                            report = (target.0, target.1, "Guest app ended abnormally within 20 seconds of launch. Count: \(info.count).")
                            showReport = true
                        }.buttonStyle(.mirsaSecondary)
                        Text(tr("You review the sanitized report first. Nothing is sent without your OK.", "بتشوف التقرير المنظّف أول. ما بينبعت شي بدون موافقتك.", ckb: "یەکەم ڕاپۆرتی پاککراو دەبینیت. بێ ڕەزامەندی تۆ هیچ نانێردرێت.", kmr: "Tu pêşî raporê paqijkirî dibînî. Bê erêkirina te tiştek nayê şandin.")).font(.caption2).foregroundStyle(.white.opacity(0.55))
                    }
                }.foregroundStyle(.white).padding(14).appsGlass(cornerRadius: MirsaRadius.l)
            }
        }
        .onAppear { _ = ForgeCrashMonitor.consume(); info = ForgeCrashMonitor.pending() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            _ = ForgeCrashMonitor.consume(); info = ForgeCrashMonitor.pending()
        }
        .sheet(isPresented: $showReport) {
            if let r = report { ForgeFixReportView(projectID: r.project, versionID: r.version, initialDiagnostic: r.text, kind: "crash") }
        }
    }
    private func project(_ bundleID: String) -> (UUID, UUID)? {
        guard let p = store.projects.first(where: { $0.bundleID == bundleID }), let v = p.currentVersion else { return nil }
        return (p.id, v.id)
    }
}
