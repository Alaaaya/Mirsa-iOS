import Foundation

/// Unlock history (سجل الفك): every Premium Unlock that was actually
/// applied is persisted as one entry in a local JSON file, so the user
/// can see what was unlocked before, without any server involved.
/// Deliberately local-only: sharing reports to the server needs a POST
/// receive endpoint + review of submitted reports and is deferred.
struct UnlockHistoryEntry: Codable, Identifiable, Equatable {
    var id: UUID
    var appName: String
    var date: Date
    /// Finding names from the scan (e.g. "isPremium", "dailyLimit").
    var findings: [String]
    /// What the unlock applied (e.g. ["Premium", "Usage limits", "Ads blocked"]).
    var applied: [String]
    var adsBlocked: Bool

    init(appName: String, date: Date = Date(), findings: [String], applied: [String], adsBlocked: Bool) {
        self.id = UUID()
        self.appName = appName
        self.date = date
        self.findings = findings
        self.applied = applied
        self.adsBlocked = adsBlocked
    }
}

@MainActor
final class PremiumUnlockHistory: ObservableObject {
    static let shared = PremiumUnlockHistory()

    static let fileName = "premium-unlock-history.json"
    /// Newest first, capped so the file never grows without bound.
    static let maxEntries = 100

    @Published private(set) var entries: [UnlockHistoryEntry] = []

    private var fileURL: URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent(Self.fileName)
    }

    private init() {
        entries = Self.load()
    }

    /// Appends one entry (newest first) and persists. Called after a
    /// successful unlock pack, never on scan alone.
    func record(appName: String, findings: [String], applied: [String], adsBlocked: Bool) {
        var all = [UnlockHistoryEntry(appName: appName, findings: findings, applied: applied, adsBlocked: adsBlocked)] + entries
        if all.count > Self.maxEntries { all = Array(all.prefix(Self.maxEntries)) }
        entries = all
        save()
    }

    func clear() {
        entries = []
        save()
    }

    private func save() {
        guard let url = fileURL else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(entries) else { return }
        try? data.write(to: url, options: .atomic)
    }

    private static func load() -> [UnlockHistoryEntry] {
        guard let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
                .appendingPathComponent(fileName),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([UnlockHistoryEntry].self, from: data) else {
            return []
        }
        return decoded.sorted { $0.date > $1.date }
    }
}
