import Foundation
import BackgroundTasks
import UserNotifications
import SwiftUI

/// A strict numeric comparator, not lexical ordering (2.10 is newer than 2.9).
struct MirsaNotificationVersion: Equatable, Comparable {
    let version: [Int]
    let build: [Int]
    init?(_ version: String, build: String) {
        func components(_ value: String) -> [Int]? {
            guard !value.isEmpty, value.count <= 64 else { return nil }
            let parts = value.split(separator: ".", omittingEmptySubsequences: false)
            guard parts.count <= 8 else { return nil }
            var result: [Int] = []
            for part in parts {
                guard !part.isEmpty, part.allSatisfy({ $0.isASCII && $0.isNumber }),
                      let number = Int(part), number < 1_000_000_000 else { return nil }
                result.append(number)
            }
            while result.count > 1 && result.last == 0 { result.removeLast() }
            return result
        }
        guard let v = components(version), let b = components(build) else { return nil }
        self.version = v; self.build = b
    }
    static func < (lhs: Self, rhs: Self) -> Bool {
        func compare(_ a: [Int], _ b: [Int]) -> Int {
            for i in 0..<max(a.count, b.count) {
                let x = i < a.count ? a[i] : 0, y = i < b.count ? b[i] : 0
                if x != y { return x < y ? -1 : 1 }
            }
            return 0
        }
        let version = compare(lhs.version, rhs.version)
        return version != 0 ? version < 0 : compare(lhs.build, rhs.build) < 0
    }
    var key: String { version.map(String.init).joined(separator: ".") + "-" + build.map(String.init).joined(separator: ".") }
}

struct MirsaNotificationMessage: Decodable, Equatable {
    let id: String
    let title: String
    let message: String
    let language: String
    let target: String
    let createdAt: Double
    func matches(locale: String, ownerAuthorized: Bool) -> Bool {
        UUID(uuidString: id) != nil && !title.isEmpty && title.count <= 100 &&
        !message.isEmpty && message.count <= 2000 && createdAt.isFinite && createdAt > 0 &&
        ["ar", "en", "de", "kmr", "ckb", "all"].contains(language) &&
        (language == "all" || language == locale) &&
        (target == "all" || (target == "owner" && ownerAuthorized))
    }
}

enum MirsaNotificationPayload {
    struct Update { let value: MirsaNotificationVersion; let label: String }
    static func update(_ data: Data, bundle: String) throws -> Update {
        guard ["com.alaa.mirsa", "com.alaa.mirsa.setup"].contains(bundle),
              let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let apps = root["apps"] as? [[String: Any]] else { throw URLError(.cannotParseResponse) }
        let matches = apps.filter { $0["bundleIdentifier"] as? String == bundle }
        guard matches.count == 1, let versions = matches[0]["versions"] as? [[String: Any]], !versions.isEmpty else {
            throw URLError(.cannotParseResponse)
        }
        let parsed: [Update] = versions.compactMap { entry in
            guard let v = entry["version"] as? String, let b = entry["buildVersion"] as? String,
                  let value = MirsaNotificationVersion(v, build: b) else { return nil }
            return Update(value: value, label: v)
        }
        guard parsed.count == versions.count, let latest = parsed.max(by: { $0.value < $1.value }) else {
            throw URLError(.cannotParseResponse)
        }
        return latest
    }
    static func broadcasts(_ data: Data, locale: String, ownerAuthorized: Bool) throws -> [MirsaNotificationMessage] {
        struct Envelope: Decodable { let version: Int; let messages: [MirsaNotificationMessage] }
        let envelope = try JSONDecoder().decode(Envelope.self, from: data)
        guard envelope.version == 1, envelope.messages.count <= 50,
              Set(envelope.messages.map(\.id)).count == envelope.messages.count else { throw URLError(.cannotParseResponse) }
        // Malformed fields fail the whole response; language/target mismatches are not displayed.
        for row in envelope.messages {
            guard UUID(uuidString: row.id) != nil, !row.title.isEmpty, row.title.count <= 100,
                  !row.message.isEmpty, row.message.count <= 2000,
                  row.createdAt.isFinite, row.createdAt > 0,
                  ["ar", "en", "de", "kmr", "ckb", "all"].contains(row.language),
                  ["owner", "all"].contains(row.target) else { throw URLError(.cannotParseResponse) }
        }
        return envelope.messages.filter { $0.matches(locale: locale, ownerAuthorized: ownerAuthorized) }
    }
}

/// Serializes callers across foreground/refresh and persists only successful submissions.
/// The stable UN identifier also reconciles a previous process interrupted between add() and save.
actor MirsaNotificationLedger {
    static let shared = MirsaNotificationLedger(defaults: .standard)
    private let defaults: UserDefaults
    private let key = "mirsa.notifications.delivered.v1"
    private var inFlight = Set<String>()
    init(defaults: UserDefaults) { self.defaults = defaults }
    @discardableResult
    func deliver(id: String, enabled: Bool,
                 permitted: () async -> Bool,
                 submit: () async throws -> Void) async -> Bool {
        guard enabled, !(defaults.stringArray(forKey: key) ?? []).contains(id),
              inFlight.insert(id).inserted else { return false }
        defer { inFlight.remove(id) }
        guard await permitted(), !Task.isCancelled else { return false }
        do {
            try await submit()
            // No await between the durable success check and committing it.
            var sent = defaults.stringArray(forKey: key) ?? []
            sent.append(id)
            defaults.set(sent, forKey: key)
            defaults.synchronize()
            return true
        } catch { return false } // retry next refresh, never pre-mark a failure
    }
}

enum MirsaNotificationText {
    static var title: String { tr5("Mirsa notifications", "إشعارات مرسى", de: "Mirsa-Mitteilungen", ckb: "ئاگادارکردنەوەکانی میرسا", kmr: "Agahiyên Mirsa") }
    static var explanation: String { tr5(
        "Get a local notification when a new Mirsa version or a developer announcement is available. iOS decides when background refresh runs, so alerts may be delayed. Opening Mirsa also checks. No remote push notifications.",
        "بيوصلك إشعار محلي لما ينزل تحديث لمرسى أو إعلان من المطوّر. iOS بيقرر إمتى يفحص بالخلفية، فممكن يتأخر الإشعار. كمان منفحص لما تفتح مرسى. مو إشعارات دفع عن بُعد.",
        de: "Lokale Mitteilungen für neue Mirsa-Versionen und Ankündigungen des Entwicklers. iOS bestimmt die Hintergrundaktualisierung; Hinweise können sich verzögern. Auch beim Öffnen wird geprüft. Keine Push-Mitteilungen.",
        ckb: "بۆ وەشانی نوێی میرسا و ڕاگەیاندنی گەشەپێدەر ئاگادارکردنەوەی ناوخۆیی وەربگرە. iOS کاتی پشکنینی پاشبنەما دیاری دەکات، بۆیە دەکرێت دواکەوێت. کاتێک میرسا دەکەیتەوەش دەپشکنرێت. Push نییە.",
        kmr: "Ji bo guhertoyên nû yên Mirsa û daxuyaniyên pêşdebir agahiyên herêmî bistîne. iOS dema nûkirina paşperdeyê diyar dike, ji ber vê agahî dikarin dereng bibin. Dema Mirsa vedikî jî tê kontrolkirin. Ne push e.") }
    static var enable: String { tr5("Enable notifications", "فعّل الإشعارات", de: "Mitteilungen aktivieren", ckb: "ئاگادارکردنەوەکان چالاک بکە", kmr: "Agahiyan çalak bike") }
    static var systemSettings: String { tr5("Open iOS notification settings", "افتح إعدادات إشعارات iOS", de: "iOS-Mitteilungseinstellungen öffnen", ckb: "ڕێکخستنەکانی ئاگادارکردنەوەی iOS بکەرەوە", kmr: "Mîhengên agahiyên iOS veke") }
    static var updateTitle: String { tr5("A Mirsa update is available", "نزل تحديث جديد لمرسى", de: "Ein Mirsa-Update ist verfügbar", ckb: "نوێکردنەوەی میرسا بەردەستە", kmr: "Nûkirina Mirsa amade ye") }
    static func updateBody(_ version: String) -> String { tr5("Open Mirsa to update to version " + version + ".", "افتح مرسى لتحدّث للنسخة " + version + ".", de: "Öffne Mirsa, um auf Version " + version + " zu aktualisieren.", ckb: "میرسا بکەرەوە بۆ نوێکردنەوە بۆ وەشانی " + version + ".", kmr: "Mirsa veke da ku bi guhertoya " + version + " nû bikî.") }
}

@MainActor
enum MirsaNotifications {
    static let identifier = "com.alaa.mirsa.announcements.refresh"
    static let preference = "mirsa.notifications.enabled"
    static let consent = "mirsa.notifications.consent"
    private static var checking = false
    private static var lastCheck = Date.distantPast
    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { task in
            guard task is BGAppRefreshTask else { task.setTaskCompleted(success: false); return }
            let work = Task { @MainActor in
                schedule()
                let success = await check()
                task.setTaskCompleted(success: success && !Task.isCancelled)
            }
            task.expirationHandler = { work.cancel() }
        }
        schedule()
    }
    static func schedule() {
        guard UserDefaults.standard.bool(forKey: preference) else { return }
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 60 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }
    static func enable() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let allowed = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        if allowed {
            UserDefaults.standard.set(true, forKey: consent)
            UserDefaults.standard.set(true, forKey: preference)
            schedule()
            Task { await check() }
        }
        return allowed
    }
    static func disable() async {
        UserDefaults.standard.set(false, forKey: preference)
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: identifier)
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix("mirsa.notice.") })
    }
    static func foreground() async {
        schedule()
        guard Date().timeIntervalSince(lastCheck) > 60 else { return }
        lastCheck = Date()
        _ = await check()
    }
    private static func allowed() async -> Bool {
        guard UserDefaults.standard.bool(forKey: preference), !Task.isCancelled else { return false }
        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        return (status == .authorized || status == .provisional) && UserDefaults.standard.bool(forKey: preference)
    }
    private static func post(id: String, title: String, body: String) async {
        let center = UNUserNotificationCenter.current()
        await MirsaNotificationLedger.shared.deliver(id: id, enabled: UserDefaults.standard.bool(forKey: preference), permitted: {
            await allowed()
        }, submit: {
            let pending = await center.pendingNotificationRequests()
            let delivered = await center.deliveredNotifications()
            let name = "mirsa.notice." + id
            if pending.contains(where: { $0.identifier == name }) || delivered.contains(where: { $0.request.identifier == name }) { return }
            guard await allowed(), !Task.isCancelled else { throw CancellationError() }
            let content = UNMutableNotificationContent()
            content.title = title; content.body = body; content.sound = .default
            try await center.add(UNNotificationRequest(identifier: name, content: content, trigger: nil))
        })
    }
    private static func get(_ request: URLRequest, maxBytes: Int) async throws -> Data {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil; config.urlCache = nil
        config.timeoutIntervalForRequest = 8; config.timeoutIntervalForResource = 12
        let session = URLSession(configuration: config, delegate: OTANoRedirect(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              response.url == request.url, http.mimeType == "application/json",
              response.expectedContentLength <= Int64(maxBytes) else { throw URLError(.badServerResponse) }
        var data = Data()
        for try await byte in bytes {
            try Task.checkCancellation()
            guard data.count < maxBytes else { throw URLError(.dataLengthExceedsMaximum) }
            data.append(byte)
        }
        return data
    }
    @discardableResult static func check() async -> Bool {
        guard !checking, await allowed() else { return false }
        // Set after the permission await, then re-check, so simultaneous launches cannot both proceed.
        guard !checking else { return false }
        checking = true
        defer { checking = false }
        var success = true
        do {
            let data = try await get(URLRequest(url: URL(string: "https://mirsa-source.mooo.com/source.json")!, timeoutInterval: 8), maxBytes: 2 * 1024 * 1024)
            let bundle = AppsStore.isSetupMode ? "com.alaa.mirsa.setup" : "com.alaa.mirsa"
            let latest = try MirsaNotificationPayload.update(data, bundle: bundle)
            guard let installed = MirsaNotificationVersion(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "",
                         build: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "") else { return false }
            if installed < latest.value {
                await post(id: "update." + latest.value.key, title: MirsaNotificationText.updateTitle,
                           body: MirsaNotificationText.updateBody(latest.label))
            }
        } catch { success = false }
        guard !Task.isCancelled else { return false }
        do {
            let language = L.lang.rawValue
            var request = URLRequest(url: URL(string: "https://mirsa-app.mooo.com/announcements/v1/messages?language=" + language)!, timeoutInterval: 8)
            var ownerAuthorized = false
            // Existing identity only. Never enroll/rotate credentials from background refresh.
            let auth = DiscoveryAuthClient(projectURL: URL(string: WebBackendConfig.defaultProject)!,
                publishableKey: WebBackendConfig.defaultPublishableKey, store: KeychainSessionStore(), http: SafeMetadataHTTP())
            if let bearer = try? await auth.token(forceRefresh: false), let uid = try? ForgeClient.fixUserID(bearer),
               let identity = try? ForgeClient.existingFixCredentials(bearer: bearer, user: uid) {
                request.setValue("Bearer " + bearer, forHTTPHeaderField: "Authorization")
                request.setValue(identity.deviceID, forHTTPHeaderField: "x-mirsa-device")
                request.setValue(identity.deviceToken, forHTTPHeaderField: "x-mirsa-device-token")
                // The server verifies both the signed user and bound token before returning any owner-only row.
                ownerAuthorized = true
            }
            let data = try await get(request, maxBytes: 256 * 1024)
            for row in try MirsaNotificationPayload.broadcasts(data, locale: language, ownerAuthorized: ownerAuthorized) {
                try Task.checkCancellation()
                await post(id: "broadcast." + row.id.lowercased(), title: row.title, body: row.message)
            }
        } catch { success = false }
        return success
    }
}

struct MirsaNotificationSettings: View {
    @AppStorage(MirsaNotifications.preference) private var enabled = false
    @State private var showPermission = false
    @State private var denied = false
    var body: some View {
        Section {
            Toggle(isOn: Binding(get: { enabled }, set: { value in
                if value { showPermission = true }
                else { enabled = false; Task { await MirsaNotifications.disable() } }
            })) { Label(MirsaNotificationText.title, systemImage: "bell.badge") }
            if denied {
                Button(MirsaNotificationText.systemSettings) {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
            }
        } footer: { Text(MirsaNotificationText.explanation) }
        .alert(MirsaNotificationText.title, isPresented: $showPermission) {
            Button(MirsaNotificationText.enable) { Task { denied = !(await MirsaNotifications.enable()) } }
            Button(tr5("Cancel", "إلغاء", de: "Abbrechen", ckb: "هەڵوەشاندنەوە", kmr: "Betal bike"), role: .cancel) {}
        } message: { Text(MirsaNotificationText.explanation) }
        .task {
            let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
            denied = status == .denied
        }
    }
}
