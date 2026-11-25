import Foundation
import CryptoKit

enum RuntimeArabicText {
    static var encrypted: String { personalText("This app is encrypted, so it cannot be translated.", "هالتطبيق مشفّر، وما فينا نعرّبه.") }
    static var unavailable: String { personalText("Arabic translation is not configured in this private build. The original app was kept.", "خدمة التعريب مو مفعّلة بهالنسخة التجريبية. التطبيق ضل متل ما هو.") }
    static var failed: String { personalText("Could not add Arabic translation. The original app was kept.", "ما قدرت أضيف التعريب. التطبيق ضل متل ما هو.") }
    static var offline: String { personalText("Arabic dictionary added. Online translation is unavailable.", "انضاف قاموس التعريب. ترجمة النصوص الناقصة عبر الإنترنت مو متاحة.") }
}

struct RuntimeTranslationPackage {
    /// Exact source text to Arabic. Contains no user/provider credentials.
    let translations: [String: String]
    var online: [String: String]? = nil
}

protocol RuntimeDictionaryTranslating {
    func dictionary(bundleID: String, revision: String, items: [ArabicIPALocalizer.Item]) async throws -> RuntimeTranslationPackage
}

enum RuntimeTranslationError: Error { case notConfigured, network, invalid, timeout, changedOriginal }

/// The retained library IPA is the immutable input, never a previous signed export.
/// Hash sidecars migrate/delete alongside that original and are checked before every preparation.
enum RuntimeOriginalIPA {
    static func manifest(for ipa: URL) -> URL { ipa.appendingPathExtension("mirsa-original.sha256") }
    static func hash(_ url: URL) throws -> String {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true else { throw RuntimeTranslationError.changedOriginal }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var digest = SHA256()
        while let block = try handle.read(upToCount: 1_048_576), !block.isEmpty { digest.update(data: block) }
        return digest.finalize().map { String(format: "%02x", $0) }.joined()
    }
    @discardableResult static func pin(_ ipa: URL) throws -> String {
        let actual = try hash(ipa), sidecar = manifest(for: ipa)
        if FileManager.default.fileExists(atPath: sidecar.path) {
            let values = try sidecar.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true, (values.fileSize ?? Int.max) <= 128,
                  try String(contentsOf: sidecar, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines) == actual else {
                throw RuntimeTranslationError.changedOriginal
            }
        } else {
            if (try? FileManager.default.destinationOfSymbolicLink(atPath: sidecar.path)) != nil { throw RuntimeTranslationError.changedOriginal }
            try Data((actual + "\n").utf8).write(to: sidecar, options: [.atomic, .completeFileProtection])
        }
        return actual
    }
    static func verify(_ ipa: URL, expected: String) throws {
        guard try hash(ipa) == expected else { throw RuntimeTranslationError.changedOriginal }
    }
}

/// All filesystem edits are isolated until a complete dictionary and safe injection exist.
/// Network tasks return values only; timeout cannot leave a task mutating/deleting staging files.
enum RuntimeArabicPipeline {
    private final class Box: @unchecked Sendable {
        private let lock = NSLock()
        private var value: Result<RuntimeTranslationPackage, Error>?
        func set(_ result: Result<RuntimeTranslationPackage, Error>) { lock.lock(); value = result; lock.unlock() }
        func get() -> Result<RuntimeTranslationPackage, Error>? { lock.lock(); defer { lock.unlock() }; return value }
    }
    #if DEBUG
    /// Constructs an encrypted Mach-O fixture, then exercises the real production gate.
    static func encryptedFixtureNotice() -> String {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("encrypted-ui-" + UUID().uuidString).appendingPathComponent("Encrypted.app")
        defer { try? fm.removeItem(at: dir.deletingLastPathComponent()) }
        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            var binary = Data(repeating: 0, count: 56)
            func put(_ value: UInt32, _ offset: Int) {
                for i in 0..<4 { binary[offset + i] = UInt8(truncatingIfNeeded: value >> (i * 8)) }
            }
            put(0xFEEDFACF, 0); put(0x0100000C, 4); put(1, 16); put(24, 20)
            put(0x2C, 32); put(24, 36); put(1, 48)
            try binary.write(to: dir.appendingPathComponent("Main"))
            try PropertyListSerialization.data(fromPropertyList: ["CFBundleExecutable": "Main", "CFBundleIdentifier": "com.mirsa.encrypted-fixture"],
                format: .binary, options: 0).write(to: dir.appendingPathComponent("Info.plist"))
            return applyBlocking(app: dir) ?? RuntimeArabicText.failed
        } catch { return RuntimeArabicText.failed }
    }
    #endif
    static var bundledDylib: URL? { Bundle.main.url(forResource: "MirsaTranslate", withExtension: "dylib", subdirectory: "RuntimeTranslationAssets") }

    static func applyBlocking(app: URL, translator: RuntimeDictionaryTranslating = RuntimeArabicBackendTranslator(),
                              dylib: URL? = bundledDylib, timeout: TimeInterval = 180,
                              originalRevision: String? = nil, bundleIDOverride: String? = nil) -> String? {
        let fm = FileManager.default
        let work = fm.temporaryDirectory.appendingPathComponent("runtime-ar-" + UUID().uuidString)
        defer { try? fm.removeItem(at: work) }
        do {
            let scan = try RuntimeTranslationScanner.scan(app: app)
            let revision = originalRevision ?? scan.revision
            guard revision.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil else { throw RuntimeTranslationError.invalid }
            let info = try IPAEditorService.info(in: app)
            guard let bundleID = bundleIDOverride ?? (info["CFBundleIdentifier"] as? String), IPAEditorService.validBundleID(bundleID),
                  let executable = info["CFBundleExecutable"] as? String,
                  !executable.isEmpty, !executable.contains("/"), executable != ".", executable != ".." else {
                throw RuntimeTranslationError.invalid
            }
            // Empty initial dictionary is allowed only with a valid online capability.
            let box = Box(), semaphore = DispatchSemaphore(value: 0)
            let task = Task.detached {
                do { box.set(.success(try await translator.dictionary(bundleID: bundleID, revision: revision, items: scan.items))) }
                catch { box.set(.failure(error)) }
                semaphore.signal()
            }
            guard semaphore.wait(timeout: .now() + timeout) == .success else { task.cancel(); throw RuntimeTranslationError.timeout }
            guard let result = box.get() else { throw RuntimeTranslationError.network }
            let package = try result.get()
            let allowed = Dictionary(scan.items.map { ($0.text, $0.text) }, uniquingKeysWith: { first, _ in first })
            var table: [String: String] = [:]
            for (source, value) in package.translations where allowed[source] != nil {
                if ArabicIPALocalizer.acceptable(source: source, translated: value),
                   value.range(of: "[\\u0600-\\u06ff]", options: .regularExpression) != nil {
                    table[source] = value
                }
            }
            let online = RuntimeArabicBackendTranslator.validOnline(package.online, bundleID: bundleID, revision: revision)
            guard !table.isEmpty || online != nil else { throw RuntimeTranslationError.invalid }
            guard let dylib, (try dylib.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])).isRegularFile == true,
                  (try dylib.resourceValues(forKeys: [.isSymbolicLinkKey])).isSymbolicLink != true else { throw RuntimeTranslationError.notConfigured }
            try fm.createDirectory(at: work, withIntermediateDirectories: true)
            let copy = work.appendingPathComponent(app.lastPathComponent)
            try fm.copyItem(at: app, to: copy)
            let frameworks = copy.appendingPathComponent("Frameworks")
            if (try? frameworks.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true { throw RuntimeTranslationError.invalid }
            let config = frameworks.appendingPathComponent("MirsaTranslations.json")
            guard !fm.fileExists(atPath: config.path),
                  (try? fm.destinationOfSymbolicLink(atPath: config.path)) == nil else { throw RuntimeTranslationError.invalid }
            try IPAEditorService.run("inject", input: copy, executable: executable, libraries: [dylib], newFirst: true)
            var dictionary: [String: Any] = ["translations": table, "substrings": [:], "regex": [], "revision": revision]
            if let online { dictionary["online"] = online }
            let data = try JSONSerialization.data(withJSONObject: dictionary, options: [.sortedKeys])
            guard data.count < 4 * 1_048_576 else { throw RuntimeTranslationError.invalid }
            try data.write(to: config, options: [.atomic, .completeFileProtection])
            // Original .ipa is not involved in this swap, and remains reusable with toggle off.
            let backup = work.appendingPathComponent("untranslated.app")
            try fm.moveItem(at: app, to: backup)
            do { try fm.moveItem(at: copy, to: app) }
            catch { try fm.moveItem(at: backup, to: app); throw error }
            return online == nil ? RuntimeArabicText.offline : ArabicTranslateText.applied
        } catch RuntimeTranslationScanError.encrypted { return RuntimeArabicText.encrypted }
        catch RuntimeTranslationError.notConfigured { return RuntimeArabicText.unavailable }
        catch { return RuntimeArabicText.failed }
    }
}

/// A release must explicitly configure a reviewed HTTPS endpoint; this branch has no live deployment.
struct RuntimeArabicBackendTranslator: RuntimeDictionaryTranslating {
    var endpoint: URL? = (Bundle.main.object(forInfoDictionaryKey: "MirsaRuntimeTranslationEndpoint") as? String).flatMap(URL.init(string:))
    var tokenProvider: DiscoveryTokenProvider? = nil
    var http: RuntimeTranslationHTTP = RuntimeTranslationHTTP()
    func dictionary(bundleID: String, revision: String, items: [ArabicIPALocalizer.Item]) async throws -> RuntimeTranslationPackage {
        guard let endpoint, endpoint.scheme == "https", endpoint.host != nil, endpoint.user == nil,
              endpoint.password == nil, endpoint.query == nil, endpoint.fragment == nil,
              DiscoveryURLPolicy.isSafe(endpoint) else { throw RuntimeTranslationError.notConfigured }
        let auth: DiscoveryTokenProvider = tokenProvider ?? DiscoveryAuthClient(projectURL: URL(string: WebBackendConfig.defaultProject)!,
            publishableKey: WebBackendConfig.defaultPublishableKey, store: KeychainSessionStore(), http: SafeMetadataHTTP())
        let token = try await auth.token(forceRefresh: false)
        var groups: [[ArabicIPALocalizer.Item]] = [], current: [ArabicIPALocalizer.Item] = [], chars = 0
        for item in items where RuntimeTranslationScanner.safeText(item.text) {
            if current.count == 128 || chars + item.text.utf16.count > 8192 { groups.append(current); current = []; chars = 0 }
            current.append(item); chars += item.text.utf16.count
        }
        if !current.isEmpty { groups.append(current) }
        var translations: [String: String] = [:]
        for group in groups {
            try Task.checkCancellation()
            let response = try await http.post(endpoint, token: token, object: [
                "action": "dictionary", "consent": true, "bundleId": bundleID, "revision": revision,
                "items": group.map { ["id": $0.id, "text": $0.text] }
            ])
            guard response["bundleId"] as? String == bundleID, response["revision"] as? String == revision,
                  let map = response["translations"] as? [String: String] else { throw RuntimeTranslationError.invalid }
            for item in group {
                if let value = map[item.id], ArabicIPALocalizer.acceptable(source: item.text, translated: value) { translations[item.text] = value }
            }
        }
        // A dictionary remains useful if issuing an online grant fails. Never embed the bootstrap JWT.
        let issued = try? await http.post(endpoint, token: token, object: ["action": "issue", "consent": true, "bundleId": bundleID, "revision": revision])
        let online = Self.validOnline(issued?["online"] as? [String: String], bundleID: bundleID, revision: revision)
        return RuntimeTranslationPackage(translations: translations, online: online)
    }
    static func validOnline(_ value: [String: String]?, bundleID: String, revision: String, now: Date = Date()) -> [String: String]? {
        guard let value, revision.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil,
              value["bundleId"] == bundleID, value["revision"] == revision,
              let token = value["token"], token.range(of: "^mrt1\\.[0-9a-f]{64}$", options: .regularExpression) != nil,
              let raw = value["endpoint"], let url = URL(string: raw), url.scheme == "https", url.user == nil, url.password == nil,
              url.query == nil, url.fragment == nil, DiscoveryURLPolicy.isSafe(url),
              let expiry = value["expiresAt"] else { return nil }
        let formatter = ISO8601DateFormatter()
        var date = formatter.date(from: expiry)
        if date == nil { formatter.formatOptions.insert(.withFractionalSeconds); date = formatter.date(from: expiry) }
        guard let date, date > now, date.timeIntervalSince(now) <= 86_400 else { return nil }
        return value
    }
}

/// Rejects redirects even to the same host. Streams and caps response bytes before JSON parsing.
final class RuntimeTranslationHTTP: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
    func post(_ endpoint: URL, token: String, object: [String: Any]) async throws -> [String: Any] {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 25; configuration.timeoutIntervalForResource = 28
        configuration.httpCookieStorage = nil; configuration.urlCache = nil; configuration.urlCredentialStorage = nil
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let body = try JSONSerialization.data(withJSONObject: object)
        guard body.count <= 48 * 1024 else { throw RuntimeTranslationError.invalid }
        var request = URLRequest(url: endpoint); request.httpMethod = "POST"; request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        let (bytes, response) = try await session.bytes(for: request)
        guard let response = response as? HTTPURLResponse, response.statusCode == 200,
              response.expectedContentLength <= 48 * 1024 else { throw RuntimeTranslationError.network }
        var data = Data()
        for try await byte in bytes {
            data.append(byte)
            guard data.count <= 48 * 1024 else { throw RuntimeTranslationError.invalid }
        }
        guard let result = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw RuntimeTranslationError.invalid }
        return result
    }
}
