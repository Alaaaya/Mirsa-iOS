import Foundation
import SwiftUI
import BackgroundTasks
import UserNotifications

@MainActor
final class StoreLibraryModel: ObservableObject {
    static let shared = StoreLibraryModel()
    @Published private(set) var wishlist: [StoreWishItem] = []
    @Published private(set) var pins: [String: StoreVersionPin] = [:]
    @Published var error: String?
    private var checkingWishlist = false
    private let root: URL
    private struct State: Codable { var wishlist: [StoreWishItem]; var pins: [String: StoreVersionPin] }
    init() {
        root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("StoreLibrary", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var excluded = root; var values = URLResourceValues(); values.isExcludedFromBackup = true
        try? excluded.setResourceValues(values)
        if let data = try? Data(contentsOf: root.appendingPathComponent("state.json")),
           let state = try? JSONDecoder().decode(State.self, from: data) {
            wishlist = Array(state.wishlist.prefix(100)); pins = state.pins
        }
    }
    private func save() {
        do {
            let data = try JSONEncoder().encode(State(wishlist: wishlist, pins: pins))
            try data.write(to: root.appendingPathComponent("state.json"), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch { self.error = error.localizedDescription }
    }
    private func key(_ bundleID: String, _ country: String) -> String { country.lowercased() + ":" + bundleID }
    func pin(bundleID: String, country: String) -> StoreVersionPin? { pins[key(bundleID, country)] }
    func setPin(app: MirsaStoreApp, country: String, externalVersionID: String, version: String) {
        guard !externalVersionID.isEmpty, externalVersionID.utf8.allSatisfy({ (48...57).contains($0) }),
              (try? MirsaStorePolicy.country(country)) != nil else { return }
        pins[key(app.bundleID, country)] = StoreVersionPin(bundleID: app.bundleID, country: country.lowercased(),
                                                          externalVersionID: externalVersionID, version: version)
        save()
    }
    func clearPin(bundleID: String, country: String) { pins.removeValue(forKey: key(bundleID, country)); save() }
    func isPinned(bundleID: String) -> Bool { pins.values.contains { $0.bundleID == bundleID } }
    func addWish(app: MirsaStoreApp, country: String) async throws {
        let item = try await StoreCatalog.fetch(appID: app.id, bundleID: app.bundleID, country: country)
        guard let price = item.app.price, price > 0, let currency = item.currency else { throw StoreCatalog.Failure.invalidMetadata }
        let wish = StoreWishItem(appID: app.id, bundleID: app.bundleID, name: app.name,
                                 country: item.country, currency: currency, price: price, checkedAt: Date())
        guard !wishlist.contains(where: { $0.id == wish.id }), wishlist.count < 100 else { return }
        wishlist.append(wish); save(); StoreWishlistNotifications.schedule()
    }
    func removeWish(id: String) { wishlist.removeAll { $0.id == id }; save() }

    func checkWishlist() async {
        guard !checkingWishlist else { return }
        checkingWishlist = true
        defer { checkingWishlist = false }
        // Persist a cursor so short OS grants eventually visit the full list.
        let cursor = UserDefaults.standard.integer(forKey: "mirsa.store.wishlistCursor")
        let ids = wishlist.map(\.id)
        guard !ids.isEmpty else { return }
        for offset in 0..<min(ids.count, 5) {
            guard !Task.isCancelled else { return }
            let position = (max(0, cursor) + offset) % ids.count
            let id = ids[position]
            guard let before = wishlist.first(where: { $0.id == id }) else { continue }
            do {
                let item = try await StoreCatalog.fetch(appID: before.appID, bundleID: before.bundleID, country: before.country)
                guard !Task.isCancelled, let index = wishlist.firstIndex(where: { $0.id == id }) else { return }
                var changed = wishlist[index]
                let notify = changed.observe(item)
                wishlist[index] = changed; save()
                if notify, await StoreWishlistNotifications.post(changed) {
                    // Removal/re-add or another observation must not receive a stale stamp.
                    if let current = wishlist.firstIndex(where: { $0.id == id }),
                       wishlist[current].price == 0, wishlist[current].checkedAt == changed.checkedAt {
                        wishlist[current].notified = true; save()
                    }
                }
            } catch {
                if Task.isCancelled { return }
                // Unknown/not available/network failure is NOT a zero price observation.
            }
            UserDefaults.standard.set((position + 1) % ids.count, forKey: "mirsa.store.wishlistCursor")
        }
    }

}

@MainActor
enum StoreIPAProtection {
    private static var sharing: Set<UUID> = []
    private static let savedKey = "mirsa.store.savedIPAs"
    static func markSaved(id: UUID) {
        var values = Set(UserDefaults.standard.stringArray(forKey: savedKey) ?? [])
        values.insert(id.uuidString)
        UserDefaults.standard.set(Array(values), forKey: savedKey)
    }
    static func beginSharing(id: UUID) { sharing.insert(id); markSaved(id: id) }
    static func endSharing(id: UUID) { sharing.remove(id) }
    static func shareURL(id: UUID) throws -> URL {
        let url = EncryptedAppsStore.ipaURL(id)
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true,
              FileManager.default.isReadableFile(atPath: url.path),
              url.resolvingSymlinksInPath().deletingLastPathComponent() == EncryptedAppsStore.root.resolvingSymlinksInPath() else {
            throw MirsaStoreError.invalidPackage
        }
        beginSharing(id: id)
        return url
    }
    static func mayClean(_ entry: EncryptedIPAEntry, confirmed: Bool) -> Bool {
        StoreIPACleanupPolicy.mayDelete(
            enabled: UserDefaults.standard.bool(forKey: "mirsa.store.autoCleanIPA"), confirmed: confirmed,
            saved: (UserDefaults.standard.stringArray(forKey: savedKey) ?? []).contains(entry.id.uuidString),
            active: sharing.contains(entry.id),
            pinned: StoreLibraryModel.shared.isPinned(bundleID: entry.bundleID))
    }
}

@MainActor
enum StoreWishlistNotifications {
    static let identifier = "com.alaa.mirsa.store.wishlist.refresh"
    static let preference = "mirsa.store.wishlistNotifications"
    static func enable() async -> Bool {
        let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
        UserDefaults.standard.set(granted, forKey: preference)
        if granted { schedule() }
        return granted
    }
    static func disable() { UserDefaults.standard.set(false, forKey: preference) }
    static func post(_ wish: StoreWishItem) async -> Bool {
        guard UserDefaults.standard.bool(forKey: preference) else { return false }
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return false }
        let content = UNMutableNotificationContent()
        content.title = StoreFeatureText.becameFree
        content.body = wish.name + " · " + wish.country.uppercased() + " · " + wish.currency
        content.sound = .default
        content.userInfo = ["mirsaRoute": "wishlist"]
        let request = UNNotificationRequest(identifier: "mirsa.wishlist." + wish.id, content: content, trigger: nil)
        do { try await center.add(request); return true } catch { return false }
    }
    static func register() {
        UNUserNotificationCenter.current().delegate = PairNotifier.shared
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { task in
            Task { @MainActor in
                schedule()
                let job = Task { @MainActor in
                    await StoreLibraryModel.shared.checkWishlist()
                    task.setTaskCompleted(success: !Task.isCancelled)
                }
                task.expirationHandler = { job.cancel() }
            }
        }
    }
    static func schedule() {
        guard UserDefaults.standard.bool(forKey: preference) else { return }
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 4 * 60 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }
}
