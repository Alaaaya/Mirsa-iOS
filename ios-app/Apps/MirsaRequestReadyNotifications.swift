import Foundation

/// A first snapshot establishes a baseline, never a flood of historical deliveries.
struct MirsaRequestReadyPolicy: Codable {
    var statuses: [UUID: String] = [:]
    var initialized = false
    static func ready(_ status: String?) -> Bool {
        ["done", "ready", "completed", "delivered"].contains((status ?? "").lowercased())
    }
    mutating func observe(_ threads: [ForgeChatThread], now: Date = Date()) -> [ForgeChatThread] {
        let result = threads.filter { thread in
            guard initialized, let old = statuses[thread.id], !Self.ready(old), Self.ready(thread.status),
                  let stamp = thread.updatedAt else { return false }
            let parser = ISO8601DateFormatter()
            parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let date = parser.date(from: stamp) ?? ISO8601DateFormatter().date(from: stamp)
            guard let date else { return false }
            let age = now.timeIntervalSince(date)
            return age >= -300 && age <= 24 * 60 * 60
        }
        // Keep absent rows: paginated/lossy reads must not reset the baseline.
        for thread in threads { statuses[thread.id] = thread.status ?? "" }
        if !threads.isEmpty { initialized = true }
        return result
    }
}

#if canImport(UIKit)
import UIKit

@MainActor
enum MirsaRequestReadyNotifications {
    private static let key = "mirsa.requests.ready.observed.v1"
    private static var checking = false
    static weak var activeStore: ForgeChatStore?
    static func observe(_ threads: [ForgeChatThread]) async {
        guard !ForgeChatStore.fixture else { return }
        let defaults = UserDefaults.standard
        var policy = defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(MirsaRequestReadyPolicy.self, from: $0) } ?? MirsaRequestReadyPolicy()
        ForgeChatLocal.shared.baselineIfNeeded(threads)
        let ready = policy.observe(threads)
        defaults.set(try? JSONEncoder().encode(policy), forKey: key)
        ForgeChatLocal.shared.markReadyUnread(ready.map(\.id))
        guard defaults.bool(forKey: MirsaNotifications.preference), defaults.bool(forKey: MirsaNotifications.consent) else { return }
        for thread in ready {
                guard !Task.isCancelled else { return }
                await MirsaNotifications.post(id: "request." + thread.id.uuidString.lowercased() + "." + (thread.updatedAt ?? ""),
                    title: tr5("Your request is ready", "طلبك جاهز", de: "Dein Auftrag ist fertig", ckb: "داواکارییەکەت ئامادەیە", kmr: "Daxwaza te amade ye"),
                    body: tr5("Open Mirsa AI to see your delivery.", "افتح مرسى AI لتشوف طلبك.", de: "Öffne Mirsa AI, um dein Ergebnis anzusehen.", ckb: "میرسا AI بکەرەوە بۆ بینینی داواکارییەکەت.", kmr: "Mirsa AI veke da ku daxwaza xwe bibînî."))
        }
    }

    /// Read a valid session only. Expired credentials wait for normal foreground authentication.
    /// Never refresh/rotate a session alongside the existing foreground auth client.
    static func existingCredentials() -> ForgeFixCredentials? {
        guard let session = KeychainSessionStore().load(), session.expiresAt.timeIntervalSinceNow > 60,
              let user = try? ForgeClient.fixUserID(session.accessToken) else { return nil }
        return try? ForgeClient.existingFixCredentials(bearer: session.accessToken, user: user)
    }

    static func check() async {
        guard !checking, !ForgeChatStore.fixture,
              UserDefaults.standard.bool(forKey: MirsaNotifications.preference),
              UserDefaults.standard.bool(forKey: MirsaNotifications.consent),
              UserDefaults.standard.bool(forKey: ForgeChatLocal.usedKey) else { return }
        checking = true
        defer { checking = false }
        guard let credentials = existingCredentials() else { return }
        do {
            var request = URLRequest(url: ForgeClient.endpoint, timeoutInterval: 8)
            request.httpMethod = "POST"
            request.setValue("Bearer " + credentials.accessToken, forHTTPHeaderField: "Authorization")
            request.setValue(credentials.deviceID, forHTTPHeaderField: "x-mirsa-device")
            request.setValue(credentials.deviceToken, forHTTPHeaderField: "x-mirsa-device-token")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: ["action": "chat-list"])
            let data = try await MirsaNotifications.get(request, maxBytes: 2 * 1024 * 1024)
            struct Snapshot: Decodable { let threads: [ForgeChatThread] }
            let snapshot = try JSONDecoder().decode(Snapshot.self, from: data)
            guard !Task.isCancelled else { return }
            await observe(snapshot.threads)
            activeStore?.mergeReadyNotificationThreads(snapshot.threads)
        } catch { /* Best effort. Never rebind or enroll from background refresh. */ }
    }
}
#endif
