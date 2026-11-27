import Foundation
import CryptoKit

enum RuntimeArabicText {
    static var encrypted: String { personalText("This app is encrypted, so it cannot be translated.", "هالتطبيق مشفّر، وما فينا نعرّبه.") }
    static var unavailable: String { personalText("Arabic translation is not activated. Activate the translation service, then sign again. Signing was stopped; the original app was kept.", "خدمة التعريب مو مفعّلة. فعّل خدمة التعريب وبعدين أعد التوقيع. وقف التوقيع، والملف الأصلي ما تغيّر.") }
    static var signIn: String { personalText("Your Mirsa session expired or is missing. Open Mirsa, sign in again, then retry signing. No file was exported.", "جلسة حسابك بمرسى منتهية أو مو موجودة. افتح مرسى وسجّل دخولك من جديد، وبعدين أعد التوقيع. ما تم تصدير أي ملف.") }
    static var failed: String { personalText("Could not add Arabic translation. Signing was stopped; check the connection and try again. The original app was kept.", "ما قدرت أضيف التعريب. وقف التوقيع؛ تأكد من الاتصال وجرّب مرة تانية. الملف الأصلي ما تغيّر.") }
    static var offline: String { personalText("Arabic dictionary added. Online translation is unavailable.", "انضاف قاموس التعريب. ترجمة النصوص الناقصة عبر الإنترنت مو متاحة.") }
}

struct RuntimeTranslationPackage {
    /// Exact source text to Arabic. Contains no user/provider credentials.
    let translations: [String: String]
    var online: [String: String]? = nil
    var queueReceipts: [[String: Any]] = []
    var deferredReasons: [String] = []
}

protocol RuntimeDictionaryTranslating {
    func dictionary(bundleID: String, revision: String, items: [ArabicIPALocalizer.Item]) async throws -> RuntimeTranslationPackage
}

enum RuntimeTranslationError: Error { case notConfigured, network, invalid, timeout, changedOriginal, httpStatus(Int) }

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
        do {
            return try applyRequired(app: app, translator: translator, dylib: dylib, timeout: timeout,
                                     originalRevision: originalRevision, bundleIDOverride: bundleIDOverride)
        } catch { return error.localizedDescription }
    }

    /// A requested signing feature is mandatory. Only diagnostic callers use the notice wrapper.
    static func failure(_ error: Error) -> Error {
        if let known = error as? SideloadError { return known }
        switch error {
        case RuntimeTranslationScanError.encrypted: return SideloadError.message(RuntimeArabicText.encrypted)
        case is DiscoveryAuthError, RuntimeTranslationError.httpStatus(401): return SideloadError.message(RuntimeArabicText.signIn)
        case RuntimeTranslationError.notConfigured: return SideloadError.message(RuntimeArabicText.unavailable)
        default: return SideloadError.message(RuntimeArabicText.failed)
        }
    }

    /// Validate actual filesystem state and parsed Mach-O dependencies, never a notice or substring.
    /// Used before transactional commit AND again after the Rust signer, before any export/install.
    @discardableResult static func verifyInstalled(app: URL, revision: String, bundleID: String,
                                                  expectedConfiguration: String? = nil) throws -> String {
        do {
            let fm = FileManager.default
            let frameworks = app.appendingPathComponent("Frameworks")
            let dylib = frameworks.appendingPathComponent("MirsaTranslate.dylib")
            let config = frameworks.appendingPathComponent("MirsaTranslations.json")
            for path in [app, frameworks, dylib, config] {
                guard (try? fm.destinationOfSymbolicLink(atPath: path.path)) == nil else { throw RuntimeTranslationError.invalid }
            }
            let attrs = try config.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            guard attrs.isRegularFile == true, let size = attrs.fileSize, size > 0, size < 4 * 1_048_576,
                  let object = try JSONSerialization.jsonObject(with: Data(contentsOf: config)) as? [String: Any],
                  object["revision"] as? String == revision,
                  let table = object["translations"] as? [String: String],
                  (try dylib.resourceValues(forKeys: [.isRegularFileKey])).isRegularFile == true else { throw RuntimeTranslationError.invalid }
            let online = RuntimeArabicBackendTranslator.validOnline(object["online"] as? [String: String], bundleID: bundleID, revision: revision)
            if object["online"] != nil {
                guard online != nil, table.allSatisfy({ ArabicIPALocalizer.acceptable(source: $0.key, translated: $0.value) }) else {
                    throw RuntimeTranslationError.invalid
                }
            } else {
                guard !table.isEmpty, table.allSatisfy({ ArabicIPALocalizer.acceptable(source: $0.key, translated: $0.value) }) else {
                    throw RuntimeTranslationError.invalid
                }
            }
            let info = try IPAEditorService.info(in: app)
            guard let executable = info["CFBundleExecutable"] as? String, !executable.isEmpty,
                  !executable.contains("/"), !executable.contains("\\"), executable != ".", executable != ".." else { throw RuntimeTranslationError.invalid }
            let loads = try IPAEditorService.dependencies(of: app.appendingPathComponent(executable))
            guard loads.filter({ $0 == "@loader_path/Frameworks/MirsaTranslate.dylib" }).count == 1 else { throw RuntimeTranslationError.invalid }
            try IPAEditorService.run("validate", input: dylib)
            let actual = try RuntimeOriginalIPA.hash(config)
            if let expectedConfiguration, actual != expectedConfiguration { throw RuntimeTranslationError.invalid }
            return actual
        } catch { throw failure(error) }
    }

    static func applyRequired(app: URL, translator: RuntimeDictionaryTranslating = RuntimeArabicBackendTranslator(),
                              dylib: URL? = bundledDylib, timeout: TimeInterval = 180,
                              originalRevision: String? = nil, bundleIDOverride: String? = nil) throws -> String {
        let fm = FileManager.default
        let work = fm.temporaryDirectory.appendingPathComponent("runtime-ar-" + UUID().uuidString)
        defer { if fm.fileExists(atPath: work.path) { try? fm.removeItem(at: work) } }
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
            // Mach-O bind/fixup ordinals refer to the original dependency order.
            // Translation is additive, never prepend its dylib ahead of those slots.
            let originalDependencies = try IPAEditorService.dependencies(of: copy.appendingPathComponent(executable))
            try IPAEditorService.run("inject", input: copy, executable: executable, libraries: [dylib], newFirst: false)
            guard try IPAEditorService.dependencies(of: copy.appendingPathComponent(executable)) ==
                    originalDependencies + ["@loader_path/Frameworks/MirsaTranslate.dylib"] else {
                throw RuntimeTranslationError.invalid
            }
            var dictionary: [String: Any] = ["translations": table, "substrings": [:], "regex": [], "revision": revision]
            if let online { dictionary["online"] = online }  // full scoped dictionary stays embedded: first frame is Arabic
            let data = try JSONSerialization.data(withJSONObject: dictionary, options: [.sortedKeys])
            guard data.count < 4 * 1_048_576 else { throw RuntimeTranslationError.invalid }
            try data.write(to: config, options: [.atomic, .completeFileProtection])
            try verifyInstalled(app: copy, revision: revision, bundleID: bundleID)
            // Original .ipa is not involved in this swap, and remains reusable with toggle off.
            let backup = work.appendingPathComponent("untranslated.app")
            try fm.moveItem(at: app, to: backup)
            do { try fm.moveItem(at: copy, to: app) }
            catch { try fm.moveItem(at: backup, to: app); throw error }
            return online == nil ? RuntimeArabicText.offline : ArabicTranslateText.applied
        } catch { throw failure(error) }
    }
}

/// A release must explicitly configure a reviewed HTTPS endpoint; this branch has no live deployment.
struct RuntimeArabicBackendTranslator: RuntimeDictionaryTranslating {
    /// Public endpoint only. Every signing operation obtains an account-scoped grant automatically.
    /// Manual owner test sessions are never used by the user signing path.
    var endpoint: URL? = RuntimeArabicBackendTranslator.defaultEndpoint()
    var tokenProvider: DiscoveryTokenProvider? = nil
    static func defaultEndpoint() -> URL? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "MirsaRuntimeTranslationEndpoint") as? String,
              !raw.isEmpty else { return nil }
        return URL(string: raw)
    }
    var http: RuntimeTranslationHTTP = RuntimeTranslationHTTP()
    func dictionary(bundleID: String, revision: String, items: [ArabicIPALocalizer.Item]) async throws -> RuntimeTranslationPackage {
        guard let endpoint, endpoint.scheme == "https", endpoint.host != nil, endpoint.user == nil,
              endpoint.password == nil, endpoint.query == nil, endpoint.fragment == nil,
              DiscoveryURLPolicy.isSafe(endpoint) else { throw RuntimeTranslationError.notConfigured }
        let auth: DiscoveryTokenProvider = tokenProvider ?? DiscoveryAuthClient(projectURL: URL(string: WebBackendConfig.defaultProject)!,
            publishableKey: WebBackendConfig.defaultPublishableKey, store: KeychainSessionStore(), http: SafeMetadataHTTP(), existingOnly: true)
        var token = try await auth.token(forceRefresh: false)
        let account = try ForgeClient.fixUserID(token)
        let defaults = UserDefaults.standard
        let installKey = "MirsaRuntimeInstallationClaim25"
        let installation = defaults.string(forKey: installKey) ?? UUID().uuidString.lowercased()
        defaults.set(installation, forKey: installKey)
        let issue: [String: Any] = ["action": "issue", "consent": true, "bundleId": bundleID,
                                  "revision": revision, "installationId": installation]
        let issued: [String: Any]
        do { issued = try await http.post(endpoint, token: token, object: issue) }
        catch RuntimeTranslationError.httpStatus(401) {
            token = try await auth.token(forceRefresh: true)
            guard try ForgeClient.fixUserID(token) == account else { throw RuntimeTranslationError.invalid }
            issued = try await http.post(endpoint, token: token, object: issue)
        }
        guard let online = Self.validOnline(issued["online"] as? [String: String], bundleID: bundleID, revision: revision),
              let activation = online["activation"],
              activationScope(activation, account: account, bundle: bundleID, revision: revision, installation: installation,
                              capability: online["token"] ?? "") else { throw RuntimeTranslationError.invalid }
        var groups: [[ArabicIPALocalizer.Item]] = [], current: [ArabicIPALocalizer.Item] = [], chars = 0
        for item in items where RuntimeTranslationScanner.safeText(item.text) {
            if current.count == 128 || chars + item.text.utf16.count > 8192 { groups.append(current); current = []; chars = 0 }
            current.append(item); chars += item.text.utf16.count
        }
        if !current.isEmpty { groups.append(current) }
        var translations: [String: String] = [:]
        var receipts: [[String: Any]] = [], reasons: [String] = []
        for group in groups {
            try Task.checkCancellation()
            let response = try await http.post(endpoint, token: token, activation: activation, object: [
                "action": "dictionary", "consent": true, "bundleId": bundleID, "revision": revision,
                "items": group.map { ["id": $0.id, "text": $0.text] }
            ])
            guard response["bundleId"] as? String == bundleID, response["revision"] as? String == revision,
                  let map = response["translations"] as? [String: String] else { throw RuntimeTranslationError.invalid }
            if let deferred = response["deferred"] as? String {
                guard let verified = Self.acceptedDeferredReceipt(response, bundleID: bundleID,
                    revision: revision, sources: group.map(\.text)) else { throw RuntimeTranslationError.invalid }
                receipts += verified; reasons.append(deferred)
            } else if let verified = Self.queueReceipt(response, sources: group.map(\.text)) { receipts += verified }
            for item in group {
                if let value = map[item.id], ArabicIPALocalizer.acceptable(source: item.text, translated: value) { translations[item.text] = value }
            }
        }
        return RuntimeTranslationPackage(translations: translations, online: online, queueReceipts: receipts, deferredReasons: reasons)
    }
    func activationScope(_ token: String, account: UUID, bundle: String, revision: String,
                                 installation: String, capability: String) -> Bool {
        let parts = token.split(separator: ".")
        guard parts.count == 3 else { return false }
        var text = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while text.count % 4 != 0 { text += "=" }
        guard let bytes = Data(base64Encoded: text),
              let claims = (try? JSONSerialization.jsonObject(with: bytes)) as? [String: Any] else { return false }
        // Server verifies the signature; these checks prevent accepting any response for another scope/account.
        let hash = SHA256.hash(data: Data(capability.utf8)).map { String(format: "%02x", $0) }.joined()
        return (claims["sub"] as? String).flatMap(UUID.init(uuidString:)) == account &&
            claims["iss"] as? String == "urn:mirsa:translation25" &&
            claims["aud"] as? String == "mirsa-translated-app" &&
            claims["bundleId"] as? String == bundle && claims["revision"] as? String == revision &&
            claims["installationId"] as? String == installation && claims["capHash"] as? String == hash
    }
    /// A deferred result is successful only when this exact app/revision's complete
    /// public source set has a durable, versioned review receipt. No provider fallback.
    static func acceptedDeferredReceipt(_ response: [String: Any], bundleID: String,
                                        revision: String, sources: [String]) -> [[String: Any]]? {
        guard response["bundleId"] as? String == bundleID,
              response["revision"] as? String == revision,
              response["translations"] is [String: String],
              let reason = response["deferred"] as? String,
              ["provider_429", "provider_503", "provider_throttled", "kat_review_required"].contains(reason)
        else { return nil }
        return queueReceipt(response, sources: sources)
    }
    /// Only a scoped committed label + durable outbox review counts as a designed fallback.
    static func queueReceipt(_ response: [String: Any], sources: [String]) -> [[String: Any]]? {
        guard let queue = response["queue"] as? [String: Any], queue["persisted"] as? Bool == true,
              let entries = queue["entries"] as? [[String: Any]], entries.count == Set(sources).count else { return nil }
        var seen = Set<String>()
        for entry in entries {
            guard let source = entry["source"] as? String, Set(sources).contains(source), seen.insert(source).inserted,
                  let label = entry["labelId"] as? String, UUID(uuidString: label) != nil,
                  let review = entry["reviewId"] as? String, UUID(uuidString: review) != nil,
                  let version = entry["version"] as? Int, version > 0,
                  let kind = entry["kind"] as? String, ["missing", "review"].contains(kind) else { return nil }
        }
        return entries
    }
    static func validOnline(_ value: [String: String]?, bundleID: String, revision: String, now: Date = Date()) -> [String: String]? {
        guard let value, revision.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil,
              value["bundleId"] == bundleID, value["revision"] == revision,
              let token = value["token"], token.range(of: "^mrt1\\.[0-9a-f]{64}$", options: .regularExpression) != nil,
              let raw = value["endpoint"], let url = URL(string: raw), url.scheme == "https", url.user == nil, url.password == nil,
              url.query == nil, url.fragment == nil, DiscoveryURLPolicy.isSafe(url),
              let expiry = value["expiresAt"],
              let activation = value["activation"], activation.count <= 4096,
              activation.split(separator: ".", omittingEmptySubsequences: false).count == 3,
              activation.split(separator: ".", omittingEmptySubsequences: false).allSatisfy({ !$0.isEmpty }),
              let installation = value["installationId"], !installation.isEmpty, installation.count <= 128 else { return nil }
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
    #if DEBUG
    func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        // Numeric/boolean connection milestones only, never URLs, headers or credentials.
        let values = metrics.transactionMetrics
        print("RuntimeTranslationHTTP metrics transactions=\(values.count) duration=\(metrics.taskInterval.duration) dns=\(values.contains { $0.domainLookupEndDate != nil }) connected=\(values.contains { $0.connectEndDate != nil }) sent=\(values.contains { $0.requestEndDate != nil }) response=\(values.contains { $0.responseStartDate != nil })")
    }
    #endif
    func post(_ endpoint: URL, token: String, activation: String? = nil, object: [String: Any]) async throws -> [String: Any] {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 25; configuration.timeoutIntervalForResource = 28
        configuration.httpCookieStorage = nil; configuration.urlCache = nil; configuration.urlCredentialStorage = nil
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let body = try JSONSerialization.data(withJSONObject: object)
        guard body.count <= 48 * 1024 else { throw RuntimeTranslationError.invalid }
        var request = URLRequest(url: endpoint); request.httpMethod = "POST"; request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("MirsaRuntimeTranslation/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        if let activation { request.setValue(activation, forHTTPHeaderField: "X-Mirsa-Activation") }
        let bytes: URLSession.AsyncBytes
        let response: URLResponse
        do { (bytes, response) = try await session.bytes(for: request) }
        catch {
            #if DEBUG
            // Allowlisted diagnostics only. Never log endpoint, headers, body or error userInfo.
            let code = (error as NSError).code
            let phase = ["issue", "dictionary", "refresh"].contains(object["action"] as? String ?? "")
                ? (object["action"] as? String ?? "unknown") : "unknown"
            print("RuntimeTranslationHTTP transport phase=\(phase) code=\(code) main=\(Thread.isMainThread)")
            #endif
            throw error
        }
        guard let response = response as? HTTPURLResponse else { throw RuntimeTranslationError.network }
        // Status is safe to diagnose; never include response bodies, URLs or credentials in errors.
        guard response.statusCode == 200 else { throw RuntimeTranslationError.httpStatus(response.statusCode) }
        guard response.expectedContentLength <= 48 * 1024 else { throw RuntimeTranslationError.invalid }
        var data = Data()
        for try await byte in bytes {
            data.append(byte)
            guard data.count <= 48 * 1024 else { throw RuntimeTranslationError.invalid }
        }
        guard let result = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw RuntimeTranslationError.invalid }
        return result
    }
}
