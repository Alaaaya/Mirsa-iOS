import Foundation
import UIKit
import Security

enum MirsaInstallMode {
    static let key = "mirsa.install.mode"
    static var ownCertificate: Bool { UserDefaults.standard.string(forKey: key) == "certificate" }
}
final class OTANoRedirect: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}
/// Why the last install used the upload path instead of local serving (nil = local or not attempted).
@MainActor enum OTARouteLog { static var last: OTAUploadReason?; static var active: LocalOTAServer? }
@MainActor enum CertificateOTA {
    static let endpoint = URL(string: WebBackendConfig.defaultProject + "/functions/v1/certificate-ota")!

    /// Archive callers retain ownership. Only app-folder callers need a new pack.
    /// Actual archive parsing and signature/profile validation remain in the signer.
    nonisolated static func prepareSigningInput(source: URL, sourceIsArchive: Bool, stage: URL,
                                                control: PersonalSigningControl) throws -> URL {
        try control.checkpoint()
        if sourceIsArchive {
            try CertificateInstall.validateIPA(source)
            return source
        }
        let app = stage.appendingPathComponent("Payload/Mirsa.app", isDirectory: true)
        let input = stage.appendingPathComponent("input.ipa")
        try FileManager.default.copyItem(at: source, to: app)
        try control.checkpoint()
        try IPAEditorService.run("pack", input: stage, output: input)
        return input
    }
    nonisolated static func signedMetadata(_ signed: PersonalCertificateSigner.Result) throws -> Data {
        guard let bytes = signed.signedInfoPlist, bytes.count <= 2 * 1024 * 1024,
              let info = try PropertyListSerialization.propertyList(from: bytes, format: nil) as? [String: Any],
              let id = info["CFBundleIdentifier"] as? String, !id.isEmpty,
              let version = info["CFBundleVersion"] as? String, !version.isEmpty else {
            throw SideloadError.message("Signed app metadata is invalid.")
        }
        return bytes
    }
    @discardableResult
    static func install(source: URL, sourceIsArchive: Bool = false, control: PersonalSigningControl = PersonalSigningControl(), material explicitMaterial: PersonalIdentityVault.Material? = nil, options explicitOptions: PersonalProjectOptions? = nil, projectID: UUID? = nil, progress: ((Double) -> Void)? = nil, signingProgress: ((PersonalSigningEvent) -> Void)? = nil) async throws -> PersonalProfileVerification {
        try control.checkpoint()
        try Task.checkCancellation()
        signingProgress?(PersonalSigningEvent(stage: .preparing))
        let selectedMaterial: PersonalIdentityVault.Material
        if let explicitMaterial { selectedMaterial = explicitMaterial }
        else if let identity = try PersonalIdentityVault.savedIdentities().first { selectedMaterial = identity.material }
        else { throw SideloadError.message(personalText("Import your certificate first.", "استورد شهادتك بالأول.")) }
        let device = (try? OwnCertificateDevice.require()) ?? ""
        let fm = FileManager.default
        let stage = fm.temporaryDirectory.appendingPathComponent("ota-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: stage.appendingPathComponent("Payload"), withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: stage) }
        let input = try await Task.detached {
            try prepareSigningInput(source: source, sourceIsArchive: sourceIsArchive, stage: stage, control: control)
        }.value
        try control.checkpoint()
        try Task.checkCancellation()
        let material = selectedMaterial

        var options = explicitOptions ?? PersonalProjectOptions()
        if explicitOptions == nil { options.strictProfile = true }
        _ = options.strictProfile // Self-install requires a profile that actually covers this identity.
        let signingOptions = options
        let signed = try await PersonalEncryptionWarning.signWithConsent { consent in
            try PersonalCertificateSigner.sign(ipa: input, material: material, pairingPath: "", options: signingOptions, cachedUDID: device, control: control, allowEncryptedSigning: consent) { event in
                Task { @MainActor in signingProgress?(event) }
            }
        }
        signingProgress?(PersonalSigningEvent(stage: .packaging, fraction: 1))
        let kept: URL
        do { kept = try CertificateInstall.retain(signed.url) }
        catch { throw CertificateInstall.Failure.retained(CertificateInstall.retainedMessage(error, signed.url), signedURL: signed.url) }
        if let projectID {
            let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("MirsaSignedExports")
            let relative = kept.path.replacingOccurrences(of: base.path + "/", with: "")
            UserDefaults.standard.set(relative, forKey: "mirsa.project.signed." + projectID.uuidString)
        }
        do {
        try control.checkpoint()
        try Task.checkCancellation()
        // Signing can change bundle ID, version and display name. The manifest
        // must describe the exact retained archive sent to either upload host.
        // The signer already validated/extracted the input and read this exact
        // post-signing plist. Re-extracting our deflated output can reject valid
        // highly-compressible resources (and needlessly duplicates large apps).
        let signedInfo = try signedMetadata(signed)
        guard let info = try PropertyListSerialization.propertyList(from: signedInfo, format: nil) as? [String: Any] else {
            throw SideloadError.message(personalText("Signed app metadata is invalid.", "معلومات التطبيق الموقّع غير صالحة."))
        }
        guard let bundleID = info["CFBundleIdentifier"] as? String,
              let version = info["CFBundleVersion"] as? String else { throw SideloadError.message(personalText("Missing application identity.", "هوية التطبيق ناقصة.")) }
        // Archive the actual retained signed bytes, before any OTA handoff or upload failure.
        await MirsaVersionArchive.shared.archiveForInstall(kept, bundleID: bundleID,
            name: (info["CFBundleDisplayName"] as? String) ?? (info["CFBundleName"] as? String) ?? bundleID,
            version: (info["CFBundleShortVersionString"] as? String) ?? version, signed: true)
        let size = ((try? fm.attributesOfItem(atPath: kept.path))?[.size] as? NSNumber)?.int64Value ?? 0
        let title = (info["CFBundleDisplayName"] as? String) ?? (info["CFBundleName"] as? String) ?? bundleID
        // Local route: HTTPS manifest from our broker, IPA bytes served from 127.0.0.1 on this device.
        // "Serving" is announced only with a running listener AND a reachable manifest. Handoff is only reported
        // after iOS actually requested the IPA from us; otherwise we stop and use upload with the real reason.
        var fallback: OTAUploadReason?
        switch OTARouteSelector.select(fileReadable: fm.isReadableFile(atPath: kept.path) && size > 0) {
        case .upload(let reason): fallback = reason
        case .local:
            if let server = try? LocalOTAServer(file: kept) {
                var bg = UIBackgroundTaskIdentifier.invalid
                bg = UIApplication.shared.beginBackgroundTask(withName: "Mirsa local OTA") { server.stop() }
                let bgBox = OTABackgroundBox(bg)
                server.onStop = { bgBox.end() }
                var handedOff = false
                defer { if !handedOff { server.stop(); if OTARouteLog.active === server { OTARouteLog.active = nil } } }
                if let port = try? await server.start() {
                    if let manifest = LocalOTAManifest.url(base: endpoint, port: port, token: server.token, bundleID: bundleID, version: version, title: title, bytes: size),
                       let target = try? OTAInstallLink.make(manifestURL: manifest),
                       await LocalOTAManifest.preflight(manifest, port: port) {
                        OTARouteLog.active?.stop(); OTARouteLog.active = server
                        signingProgress?(PersonalSigningEvent(stage: .serving))
                        try control.checkpoint()
                        _ = await UIApplication.shared.open(target)  // success here does NOT prove download
                        let got = await withTaskCancellationHandler { await server.awaitFirstRequest(timeout: 15) } onCancel: { server.stop() }
                        try control.checkpoint()
                        if got {
                            handedOff = true
                            signingProgress?(PersonalSigningEvent(stage: .handedOff))
                            return signed.verification
                        }
                        server.stop(); OTARouteLog.active = nil; fallback = .noInstallerRequest
                    } else { server.stop(); fallback = .manifestUnreachable }
                } else { server.stop(); fallback = .serverStartFailed }
            } else { fallback = .fileUnavailable }
        }
        OTARouteLog.last = fallback
        if let fallback { signingProgress?(PersonalSigningEvent(stage: .uploading, fallbackReason: fallback)) }
        let plan = try OTAChunkPlan(total: size)
        let auth = DiscoveryAuthClient(projectURL: URL(string: WebBackendConfig.defaultProject)!,
            publishableKey: WebBackendConfig.defaultPublishableKey, store: KeychainSessionStore(), http: SafeMetadataHTTP())
        let token = try await auth.token(forceRefresh: false)
        try control.checkpoint()
        try Task.checkCancellation()
        signingProgress?(PersonalSigningEvent(stage: .uploading))
        let uploadProgress: (Double) -> Void = { fraction in
            progress?(fraction)
            signingProgress?(PersonalSigningEvent(stage: .uploading, fraction: fraction))
        }
        let manifestURL: URL
        do {
            manifestURL = try await oracleUpload(file: kept, plan: plan, token: token, bundleID: bundleID, version: version, title: title, progress: uploadProgress)
        } catch {
            try control.checkpoint()
            try Task.checkCancellation()
            guard !(error is CancellationError), (error as? URLError)?.code != .cancelled,
                  OTAFallbackPolicy.allows(error, size: size) else {
                let down = error is URLError || { if case OTAChunkError.server(let c)? = error as? OTAChunkError { return c >= 500 }; return false }()
                if down && size > OTAFallbackPolicy.limit {
                    throw SideloadError.message(personalText("Upload server unavailable. Large apps need it; try again later.", "سيرفر الرفع مو متاح. التطبيقات الكبيرة بتحتاجه، جرب بعدين."))
                }
                throw error
            }
            manifestURL = try await legacyUpload(file: kept, size: size, token: token, bundleID: bundleID, version: version, title: title)
        }
        try control.checkpoint()
        try Task.checkCancellation()
        signingProgress?(PersonalSigningEvent(stage: .uploading, fraction: 1))
        signingProgress?(PersonalSigningEvent(stage: .connecting))
        let target = try OTAInstallLink.make(manifestURL: manifestURL)
        guard await UIApplication.shared.open(target) else {
            throw SideloadError.message(personalText("iOS could not open installation. Try again.", "iOS ما فتح التثبيت. جرب مرة تانية."))
        }
        signingProgress?(PersonalSigningEvent(stage: .handedOff))
        return signed.verification
        // Opening the installer is not evidence of successful device installation.
        // Keep the signed artifact even after handing off to iOS.
        } catch {
            throw CertificateInstall.Failure.retained(CertificateInstall.retainedMessage(error, kept), signedURL: kept)
        }
    }
}

extension CertificateOTA {
    static let brokerURL = URL(string: WebBackendConfig.defaultProject + "/functions/v1/certificate-ota?action=oracle-session")!
    static func oracleUpload(file: URL, plan: OTAChunkPlan, token: String, bundleID: String, version: String, title: String, progress: ((Double) -> Void)?) async throws -> URL {
        var req = URLRequest(url: brokerURL, timeoutInterval: 30)
        req.httpMethod = "POST"
        req.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["bundleID": bundleID, "version": version, "title": title, "bytes": Int(plan.total)])
        let cfg = URLSessionConfiguration.ephemeral; cfg.httpCookieStorage = nil
        let s = URLSession(configuration: cfg, delegate: OTANoRedirect(), delegateQueue: nil)
        defer { s.invalidateAndCancel() }
        let (d, resp) = try await s.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else { throw OTAChunkError.server(code) }
        let session = try OTAOracleWire.session(from: d)
        return try await OTAChunkUploader.run(file: file, total: plan.total, session: session) { f in
            DispatchQueue.main.async { progress?(f) }
        }
    }
    static func legacyUpload(file: URL, size: Int64, token: String, bundleID: String, version: String, title: String) async throws -> URL {
        let metadata: [String: Any] = ["bundleID": bundleID, "version": version, "title": title, "bytes": Int(size)]
        let data = try JSONSerialization.data(withJSONObject: metadata)
        var request = URLRequest(url: endpoint, timeoutInterval: 120)
        request.httpMethod = "POST"
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        request.setValue(String(size), forHTTPHeaderField: "Content-Length")
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        request.setValue(String(decoding: data, as: UTF8.self).addingPercentEncoding(withAllowedCharacters: allowed), forHTTPHeaderField: "x-mirsa-metadata")
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        let session = URLSession(configuration: config, delegate: OTANoRedirect(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (response, http) = try await session.upload(for: request, fromFile: file)
        guard (http as? HTTPURLResponse)?.statusCode == 200,
              let result = try JSONSerialization.jsonObject(with: response) as? [String: Any],
              let manifest = result["manifestURL"] as? String,
              let url = URL(string: manifest), url.scheme == "https", url.host == endpoint.host,
              url.path == endpoint.path, url.user == nil, url.password == nil else {
            throw SideloadError.message(personalText("Temporary OTA upload failed or quota reached.", "رفع التثبيت المؤقت فشل أو وصل للحد المسموح."))
        }
        return url
    }
}

enum OwnCertificateDevice {
    static let message = "قراءة الجهاز اختيارية للتحقق من شمول البروفايل. بدونها فيك توقّع وتفتح مثبّت iOS، بس شمول هالجهاز مو متحقق منه."
    static var query: [String: Any] {
        [kSecClass as String:kSecClassGenericPassword, kSecAttrService as String:"mirsa.owncert.realdevice.v1", kSecAttrAccount as String:"device", kSecAttrSynchronizable as String:false]
    }
    static func clear() { SecItemDelete(query as CFDictionary); try? FileManager.default.removeItem(at:bindingFile) }
    static var bindingFile: URL {
        FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("owncert-install-binding")
    }
    static func validRecord(_ value: [String:String], vendor: String?, installation: String?) -> Bool {
        guard let vendor, !vendor.isEmpty, let installation, !installation.isEmpty else { return false }
        guard value["binding"] == vendor, value["installation"] == installation, let id=value["udid"] else { return false }
        return id.range(of:"^(?:[0-9a-fA-F]{40}|[0-9a-fA-F]{8}-[0-9a-fA-F]{16})$",options:.regularExpression) != nil
    }
    static func require() throws -> String {
        var q=query; q[kSecReturnData as String]=true
        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary,&item)==errSecSuccess, let data=item as? Data,
              let value=try? JSONDecoder().decode([String:String].self,from:data),
              validRecord(value, vendor:UIDevice.current.identifierForVendor?.uuidString, installation:try? String(contentsOf:bindingFile,encoding:.utf8)),
              let id=value["udid"], !id.isEmpty else {
            clear(); throw SideloadError.message(message)
        }
        return id
    }
    @MainActor static func setup() async throws {
        clear()
        let path=PairingController.pairingFilePath()
        let output=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:output) }
        try await Task.detached {
            try IPAEditorService.run("read_device_once",input:URL(fileURLWithPath:path),output:output)
        }.value
        try FileManager.default.setAttributes([.protectionKey:FileProtectionType.complete],ofItemAtPath:output.path)
        guard let binding=UIDevice.current.identifierForVendor?.uuidString else { throw SideloadError.message(message) }
        let udid=try String(contentsOf:output,encoding:.utf8)
        let installation=UUID().uuidString
        try FileManager.default.createDirectory(at:bindingFile.deletingLastPathComponent(),withIntermediateDirectories:true)
        try Data(installation.utf8).write(to:bindingFile,options:[.atomic,.completeFileProtection])
        var file=bindingFile
        var resource=URLResourceValues(); resource.isExcludedFromBackup=true
        try file.setResourceValues(resource)
        guard validRecord(["udid":udid,"binding":binding,"installation":installation],vendor:binding,installation:installation) else { clear(); throw SideloadError.message(message) }
        let data=try JSONEncoder().encode(["udid":udid,"binding":binding,"installation":installation])
        var q=query; q[kSecValueData as String]=data
        q[kSecAttrAccessible as String]=kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        guard SecItemAdd(q as CFDictionary,nil)==errSecSuccess else { throw SideloadError.message(message) }
    }
}

import SwiftUI
struct OwnCertificateDeviceSetup: View {
    @State private var status = OwnCertificateDevice.message
    @State private var busy = false
    var body: some View {
        VStack(alignment: .leading) {
            Text(status).font(.caption)
            Button("قراءة الجهاز مرة واحدة / إعادة المحاولة") {
                busy = true
                Task {
                    do {
                        try await OwnCertificateDevice.setup()
                        status = "تم حفظ الجهاز بأمان. فيك تطفي VPN وتثبّت بشهادتك."
                    } catch { status = error.localizedDescription }
                    busy = false
                }
            }.disabled(busy)
            Button("مسح بيانات الجهاز المحفوظة", role: .destructive) {
                OwnCertificateDevice.clear()
                status = OwnCertificateDevice.message
            }.disabled(busy)
        }
    }
}

/// Ends a UIKit background task exactly once from any thread.
final class OTABackgroundBox: @unchecked Sendable {
    private let lock = NSLock(); private var id: UIBackgroundTaskIdentifier
    init(_ id: UIBackgroundTaskIdentifier) { self.id = id }
    func end() {
        lock.lock(); let i = id; id = .invalid; lock.unlock()
        guard i != .invalid else { return }
        DispatchQueue.main.async { UIApplication.shared.endBackgroundTask(i) }
    }
}
