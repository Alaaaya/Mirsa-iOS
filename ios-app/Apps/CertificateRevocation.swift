import SwiftUI
import CryptoKit
import Security
import UserNotifications

/// Result of an online OCSP check. Only an authenticated "good" answer is reported as good.
enum RevocationStatus: Equatable {
    case good(checked: Date)
    case revoked(at: Date?)
    /// Network failure, unknown certificate, bad/stale/unsigned response. NEVER shown as valid.
    case notVerified(reason: String)
}

private struct DERNode {
    let tag: UInt8
    let start: Int      // start of header
    let content: Range<Int>
    var end: Int { content.upperBound }
}

private struct DER {
    let bytes: [UInt8]
    init(_ data: Data) { bytes = [UInt8](data) }
    init(_ b: [UInt8]) { bytes = b }
    func node(at i: Int, limit: Int? = nil) -> DERNode? {
        let lim = limit ?? bytes.count
        guard i + 2 <= lim else { return nil }
        let tag = bytes[i]
        var p = i + 1
        var len = Int(bytes[p]); p += 1
        if len & 0x80 != 0 {
            let n = len & 0x7F
            guard n > 0, n <= 4, p + n <= lim else { return nil }
            len = 0
            for _ in 0..<n { len = (len << 8) | Int(bytes[p]); p += 1 }
        }
        guard len >= 0, p + len <= lim else { return nil }
        return DERNode(tag: tag, start: i, content: p..<(p + len))
    }
    func children(_ n: DERNode) -> [DERNode] {
        var out: [DERNode] = []; var p = n.content.lowerBound
        while p < n.end, let c = node(at: p, limit: n.end) { out.append(c); p = c.end }
        return out
    }
    func raw(_ n: DERNode) -> [UInt8] { Array(bytes[n.start..<n.end]) }
    func body(_ n: DERNode) -> [UInt8] { Array(bytes[n.content]) }
}

enum DEREncode {
    static func len(_ n: Int) -> [UInt8] {
        if n < 128 { return [UInt8(n)] }
        var b: [UInt8] = []; var v = n
        while v > 0 { b.insert(UInt8(v & 0xFF), at: 0); v >>= 8 }
        return [0x80 | UInt8(b.count)] + b
    }
    static func tlv(_ tag: UInt8, _ content: [UInt8]) -> [UInt8] { [tag] + len(content.count) + content }
}

/// Minimal X.509 / OCSP reader for exactly what revocation checking needs.
struct ParsedCertificate {
    let der: [UInt8]
    let tbs: [UInt8]
    let sigAlgOID: [UInt8]
    let signature: [UInt8]
    let issuerName: [UInt8]
    let subjectName: [UInt8]
    let serial: [UInt8]       // raw INTEGER content bytes
    let publicKeyBits: [UInt8] // subjectPublicKey BIT STRING contents (no unused-bits byte)
    let ocspURL: URL?
    let issuerURL: URL?

    static let oidAIA: [UInt8] = [0x2B, 0x06, 0x01, 0x05, 0x05, 0x07, 0x01, 0x01]
    static let oidOCSP: [UInt8] = [0x2B, 0x06, 0x01, 0x05, 0x05, 0x07, 0x30, 0x01]
    static let oidCAIssuers: [UInt8] = [0x2B, 0x06, 0x01, 0x05, 0x05, 0x07, 0x30, 0x02]

    init?(_ data: Data) {
        let d = DER(data)
        guard let cert = d.node(at: 0), cert.tag == 0x30, cert.end == d.bytes.count else { return nil }
        let top = d.children(cert)
        guard top.count == 3, let tbsNode = top.first, tbsNode.tag == 0x30 else { return nil }
        let alg = d.children(top[1])
        guard let oid = alg.first, oid.tag == 0x06, top[2].tag == 0x03, top[2].content.count > 1 else { return nil }
        var f = d.children(tbsNode)
        if let first = f.first, first.tag == 0xA0 { f.removeFirst() }
        guard f.count >= 6, f[0].tag == 0x02, f[2].tag == 0x30, f[4].tag == 0x30, f[5].tag == 0x30 else { return nil }
        let spki = d.children(f[5])
        guard spki.count == 2, spki[1].tag == 0x03, spki[1].content.count > 1 else { return nil }
        der = d.bytes
        tbs = d.raw(tbsNode)
        sigAlgOID = d.body(oid)
        signature = Array(d.body(top[2]).dropFirst())
        serial = d.body(f[0])
        issuerName = d.raw(f[2])
        subjectName = d.raw(f[4])
        publicKeyBits = Array(d.body(spki[1]).dropFirst())
        var ocsp: URL?; var issuer: URL?
        if let ext = f.last(where: { $0.tag == 0xA3 }) {
            for e in d.children(ext).flatMap({ d.children($0) }) {
                let parts = d.children(e)
                guard parts.count >= 2, parts[0].tag == 0x06, d.body(parts[0]) == Self.oidAIA,
                      let octet = parts.last, octet.tag == 0x04,
                      let seq = d.node(at: octet.content.lowerBound, limit: octet.end) else { continue }
                for access in d.children(seq) {
                    let ad = d.children(access)
                    guard ad.count == 2, ad[0].tag == 0x06, ad[1].tag == 0x86,
                          let s = String(bytes: d.body(ad[1]), encoding: .ascii), let u = URL(string: s) else { continue }
                    if d.body(ad[0]) == Self.oidOCSP { ocsp = u }
                    if d.body(ad[0]) == Self.oidCAIssuers { issuer = u }
                }
            }
        }
        ocspURL = ocsp; issuerURL = issuer
    }
}

enum OCSPChecker {
    private static func secAlgorithm(_ oid: [UInt8]) -> SecKeyAlgorithm? {
        switch oid {
        case [0x2A,0x86,0x48,0x86,0xF7,0x0D,0x01,0x01,0x0B]: return .rsaSignatureMessagePKCS1v15SHA256
        case [0x2A,0x86,0x48,0x86,0xF7,0x0D,0x01,0x01,0x0C]: return .rsaSignatureMessagePKCS1v15SHA384
        case [0x2A,0x86,0x48,0x86,0xF7,0x0D,0x01,0x01,0x05]: return .rsaSignatureMessagePKCS1v15SHA1
        case [0x2A,0x86,0x48,0xCE,0x3D,0x04,0x03,0x02]: return .ecdsaSignatureMessageX962SHA256
        case [0x2A,0x86,0x48,0xCE,0x3D,0x04,0x03,0x03]: return .ecdsaSignatureMessageX962SHA384
        default: return nil
        }
    }
    private static func verify(_ message: [UInt8], oid: [UInt8], signature: [UInt8], key: SecKey) -> Bool {
        guard let alg = secAlgorithm(oid), SecKeyIsAlgorithmSupported(key, .verify, alg) else { return false }
        return SecKeyVerifySignature(key, alg, Data(message) as CFData, Data(signature) as CFData, nil)
    }
    private static func key(of der: [UInt8]) -> SecKey? {
        SecCertificateCreateWithData(nil, Data(der) as CFData).flatMap { SecCertificateCopyKey($0) }
    }
    private static let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 15; c.timeoutIntervalForResource = 30
        c.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: c)
    }()
    private static func fetch(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200, data.count <= 1_000_000 else {
            throw SideloadError.message("HTTP")
        }
        return data
    }
    static func generalizedTime(_ s: String) -> Date? {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyyMMddHHmmss'Z'"
        return f.date(from: s)
    }
    static func requestBody(issuer: ParsedCertificate, serial: [UInt8]) -> [UInt8] {
        let sha1: [UInt8] = [0x2B, 0x0E, 0x03, 0x02, 0x1A]
        let nameHash = [UInt8](Insecure.SHA1.hash(data: Data(issuer.subjectName)))
        let keyHash = [UInt8](Insecure.SHA1.hash(data: Data(issuer.publicKeyBits)))
        let certID = DEREncode.tlv(0x30,
            DEREncode.tlv(0x30, DEREncode.tlv(0x06, sha1) + [0x05, 0x00]) +
            DEREncode.tlv(0x04, nameHash) + DEREncode.tlv(0x04, keyHash) + DEREncode.tlv(0x02, serial))
        return DEREncode.tlv(0x30, DEREncode.tlv(0x30, DEREncode.tlv(0x30, DEREncode.tlv(0x30, certID))))
    }

    /// Full OCSP check of a leaf certificate (DER). Any doubt yields .notVerified.
    static func check(leafDER: Data, now: Date = Date()) async -> RevocationStatus {
        func nv(_ en: String, _ ar: String, _ ckb: String, _ kmr: String) -> RevocationStatus { .notVerified(reason: sgText(en, ar, ckb, kmr)) }
        guard let leaf = ParsedCertificate(leafDER) else {
            return nv("Certificate could not be read.", "ما قدرنا نقرأ الشهادة.", "شەهادەکە نەخوێنرایەوە.", "Sertîfîka nehat xwendin.")
        }
        guard let ocspURL = leaf.ocspURL, let issuerURL = leaf.issuerURL,
              ["http", "https"].contains(ocspURL.scheme), ["http", "https"].contains(issuerURL.scheme) else {
            return nv("The certificate has no OCSP address.", "الشهادة ما فيها عنوان OCSP.", "شەهادەکە ناونیشانی OCSPی نییە.", "Di sertîfîkayê de navnîşana OCSP tune.")
        }
        let issuer: ParsedCertificate
        do {
            let data = try await fetch(URLRequest(url: issuerURL))
            guard let p = ParsedCertificate(data) else { throw SideloadError.message("issuer") }
            issuer = p
        } catch {
            return nv("Could not fetch the issuer certificate (network).", "ما قدرنا نجيب شهادة المُصدِر (الشبكة).", "شەهادەی دەرکەر نەهێنرا (تۆڕ).", "Sertîfîka derxerê nehat anîn (tor).")
        }
        // The issuer must really have signed the leaf, and the leaf must name it.
        guard issuer.subjectName == leaf.issuerName,
              let issuerKey = key(of: issuer.der),
              verify(leaf.tbs, oid: leaf.sigAlgOID, signature: leaf.signature, key: issuerKey) else {
            return nv("Issuer certificate does not match.", "شهادة المُصدِر ما بتطابق.", "شەهادەی دەرکەر نایەتەوە.", "Sertîfîka derxerê li hev nayê.")
        }
        var request = URLRequest(url: ocspURL)
        request.httpMethod = "POST"
        request.setValue("application/ocsp-request", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(requestBody(issuer: issuer, serial: leaf.serial))
        let response: Data
        do { response = try await fetch(request) }
        catch { return nv("Could not reach the OCSP server (network).", "ما قدرنا نوصل لسيرفر OCSP (الشبكة).", "نەتوانرا بگەیتە سێرڤەری OCSP (تۆڕ).", "Negihîşt serverê OCSP (tor).") }
        return parse(response: response, leaf: leaf, issuer: issuer, issuerKey: issuerKey, now: now)
    }

    static func parse(response data: Data, leaf: ParsedCertificate, issuer: ParsedCertificate, issuerKey: SecKey, now: Date) -> RevocationStatus {
        func bad(_ en: String, _ ar: String, _ ckb: String, _ kmr: String) -> RevocationStatus { .notVerified(reason: sgText(en, ar, ckb, kmr)) }
        let invalid = { bad("The OCSP answer is invalid.", "جواب OCSP غير صالح.", "وەڵامی OCSP دروست نییە.", "Bersiva OCSP derbasdar nîne.") }
        let d = DER(data)
        guard let top = d.node(at: 0), top.tag == 0x30 else { return invalid() }
        let parts = d.children(top)
        guard parts.count >= 1, parts[0].tag == 0x0A, d.body(parts[0]) == [0] else {
            return bad("The OCSP server did not return a definite answer.", "سيرفر OCSP ما رجّع جواب مؤكد.", "سێرڤەری OCSP وەڵامێکی دیاریکراوی نەدایەوە.", "Serverê OCSP bersivek diyar neda.")
        }
        guard parts.count == 2, parts[1].tag == 0xA0, let rb = d.children(parts[1]).first, rb.tag == 0x30 else { return invalid() }
        let rbc = d.children(rb)
        guard rbc.count == 2, rbc[1].tag == 0x04, let basic = d.node(at: rbc[1].content.lowerBound, limit: rbc[1].end), basic.tag == 0x30 else { return invalid() }
        let b = d.children(basic)
        guard b.count >= 3, b[0].tag == 0x30, b[1].tag == 0x30, b[2].tag == 0x03, b[2].content.count > 1,
              let sigOID = d.children(b[1]).first, sigOID.tag == 0x06 else { return invalid() }
        let tbsBytes = d.raw(b[0])
        let sig = Array(d.body(b[2]).dropFirst())
        // Authenticate: signed by the issuer or by a delegated responder certified by the issuer.
        var authenticated = verify(tbsBytes, oid: d.body(sigOID), signature: sig, key: issuerKey)
        if !authenticated, b.count >= 4, b[3].tag == 0xA0, let list = d.children(b[3]).first {
            for c in d.children(list) {
                let certDER = d.raw(c)
                let ocspSigning: [UInt8] = [0x2B, 0x06, 0x01, 0x05, 0x05, 0x07, 0x03, 0x09]
                guard let parsed = ParsedCertificate(Data(certDER)), contains(certDER, ocspSigning),
                      verify(parsed.tbs, oid: parsed.sigAlgOID, signature: parsed.signature, key: issuerKey),
                      let rk = key(of: certDER),
                      verify(tbsBytes, oid: d.body(sigOID), signature: sig, key: rk) else { continue }
                authenticated = true; break
            }
        }
        guard authenticated else {
            return bad("The OCSP answer signature could not be verified.", "ما قدرنا نتحقق من توقيع جواب OCSP.", "واژووی وەڵامی OCSP پشتڕاست نەکرایەوە.", "Îmzeya bersiva OCSP nehat piştrastkirin.")
        }
        var f = d.children(b[0])
        if let first = f.first, first.tag == 0xA0 { f.removeFirst() }
        guard f.count >= 3, f[2].tag == 0x30 else { return invalid() }
        for single in d.children(f[2]) {
            let s = d.children(single)
            guard s.count >= 3, s[0].tag == 0x30 else { continue }
            let id = d.children(s[0])
            guard id.count == 4, d.body(id[3]) == leaf.serial,
                  d.body(id[1]) == [UInt8](Insecure.SHA1.hash(data: Data(issuer.subjectName))),
                  d.body(id[2]) == [UInt8](Insecure.SHA1.hash(data: Data(issuer.publicKeyBits))) else { continue }
            guard s[2].tag == 0x18, let thisUpdate = generalizedTime(String(decoding: d.body(s[2]), as: UTF8.self)) else { return invalid() }
            if thisUpdate > now.addingTimeInterval(300) { return invalid() }
            if s.count >= 4, s[3].tag == 0xA0, let n = d.children(s[3]).first,
               let next = generalizedTime(String(decoding: d.body(n), as: UTF8.self)), next < now.addingTimeInterval(-300) {
                return bad("The OCSP answer is outdated.", "جواب OCSP قديم.", "وەڵامی OCSP کۆنە.", "Bersiva OCSP kevn e.")
            }
            switch s[1].tag {
            case 0x80: return .good(checked: now)
            case 0xA1:
                let t = d.children(s[1]).first.flatMap { $0.tag == 0x18 ? generalizedTime(String(decoding: d.body($0), as: UTF8.self)) : nil }
                return .revoked(at: t)
            default:
                return bad("The OCSP server does not know this certificate.", "سيرفر OCSP ما بيعرف هالشهادة.", "سێرڤەری OCSP ئەم شەهادەیە نازانێت.", "Serverê OCSP vê sertîfîkayê nas nake.")
            }
        }
        return bad("The OCSP answer is for another certificate.", "جواب OCSP لشهادة ثانية.", "وەڵامی OCSP بۆ شەهادەیەکی ترە.", "Bersiva OCSP ji bo sertîfîkayeke din e.")
    }
    private static func contains(_ haystack: [UInt8], _ needle: [UInt8]) -> Bool {
        guard haystack.count >= needle.count else { return false }
        for i in 0...(haystack.count - needle.count) where Array(haystack[i..<(i + needle.count)]) == needle { return true }
        return false
    }
}

@MainActor
final class CertificateRevocationMonitor: ObservableObject {
    static let shared = CertificateRevocationMonitor()
    @Published private(set) var results: [String: RevocationStatus] = [:]
    @Published private(set) var checking: Set<String> = []
    private var lastRun: [String: Date] = [:]

    func check(_ identity: PersonalIdentityVault.SavedIdentity, force: Bool = false) async {
        let id = identity.id
        if !force, let last = lastRun[id], Date().timeIntervalSince(last) < 6 * 3600 { return }
        guard !checking.contains(id) else { return }
        checking.insert(id); defer { checking.remove(id) }
        let status: RevocationStatus
        do {
            let (_, cert) = try PersonalIdentityVault.identity(identity.material)
            status = await OCSPChecker.check(leafDER: cert)
        } catch {
            status = .notVerified(reason: error.localizedDescription)
        }
        results[id] = status
        if case .notVerified = status {} else { lastRun[id] = Date() }
        if case .revoked = status { await alert(identity) }
    }
    func checkAll() async {
        guard let list = try? PersonalIdentityVault.savedIdentities() else { return }
        for item in list { await check(item) }
    }
    private func alert(_ identity: PersonalIdentityVault.SavedIdentity) async {
        let key = "mirsa.revocation.alerted." + identity.id
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
        let content = UNMutableNotificationContent()
        content.title = sgText("Certificate revoked", "الشهادة ملغاة", "شەهادە هەڵوەشێنراوەتەوە", "Sertîfîka hate betalkirin")
        content.body = identity.name + " · " + sgText("Apple reports this certificate as revoked. Apps signed with it will stop opening.", "أبل بتبلّغ إنو هالشهادة ملغاة. التطبيقات الموقّعة فيها رح توقف.", "ئەپڵ ڕایدەگەیەنێت ئەم شەهادەیە هەڵوەشێنراوەتەوە. ئەپە واژووکراوەکان ناکرێنەوە.", "Apple radigihîne ku ev sertîfîka hatiye betalkirin. Sepanên pê îmzekirî venabin.")
        try? await center.add(UNNotificationRequest(identifier: key, content: content, trigger: nil))
    }
    /// Gate for signing: revoked or locally expired certificates are refused. Unknown does not block (shown as unverified).
    func signingBlocker(_ identity: PersonalIdentityVault.SavedIdentity) -> String? {
        if let expiry = identity.expiry, expiry < Date() {
            return sgText("The certificate has expired.", "الشهادة منتهية.", "شەهادەکە بەسەرچووە.", "Sertîfîka qediyaye.")
        }
        if case .revoked = results[identity.id] {
            return sgText("The certificate is revoked.", "الشهادة ملغاة.", "شەهادەکە هەڵوەشێنراوەتەوە.", "Sertîfîka hatiye betalkirin.")
        }
        return nil
    }
}

struct CertificateRevocationBanner: View {
    let identity: PersonalIdentityVault.SavedIdentity
    @ObservedObject private var monitor = CertificateRevocationMonitor.shared
    var body: some View {
        let status = monitor.results[identity.id]
        let busy = monitor.checking.contains(identity.id)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                if busy { ProgressView() } else { Image(systemName: icon(status)).foregroundStyle(color(status)) }
                Text(title(status, busy: busy)).font(.subheadline.weight(.semibold)).foregroundStyle(color(status))
                Spacer(minLength: 0)
                Button(sgText("Check", "فحص", "پشکنین", "Kontrol")) { Task { await monitor.check(identity, force: true) } }
                    .font(.caption.weight(.semibold)).disabled(busy)
            }
            if case .notVerified(let reason)? = status { Text(reason).font(.caption).foregroundStyle(.secondary) }
            Text(sgText("Online OCSP check with Apple. Without a clear answer the certificate is NOT treated as valid.",
                        "فحص OCSP أونلاين مع أبل. بدون جواب واضح ما بنعتبر الشهادة صالحة.",
                        "پشکنینی OCSPی ئۆنلاین لەگەڵ ئەپڵ. بەبێ وەڵامی ڕوون شەهادەکە وەک دروست دانانرێت.",
                        "Kontrola OCSP ya serhêl bi Apple re. Bêyî bersiva zelal sertîfîka wekî derbasdar nayê hesibandin."))
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(14).appsGlass(cornerRadius: 20)
        .task { await monitor.check(identity) }
    }
    private func icon(_ s: RevocationStatus?) -> String {
        switch s { case .good?: return "checkmark.shield.fill"; case .revoked?: return "xmark.shield.fill"; default: return "questionmark.circle.fill" }
    }
    private func color(_ s: RevocationStatus?) -> Color {
        switch s { case .good?: return .green; case .revoked?: return .red; default: return .orange }
    }
    private func title(_ s: RevocationStatus?, busy: Bool) -> String {
        if busy { return sgText("Checking with Apple", "عم نفحص مع أبل", "لەگەڵ ئەپڵ دەپشکنین", "Bi Apple re tê kontrolkirin") }
        switch s {
        case .good?: return sgText("Not revoked", "مو ملغاة", "هەڵنەوەشێنراوەتەوە", "Nehatiye betalkirin")
        case .revoked?: return sgText("Revoked by Apple", "ملغاة من أبل", "ئەپڵ هەڵیوەشاندووەتەوە", "Apple betal kiriye")
        case .notVerified?: return sgText("Not verified", "غير متحقق منها", "پشتڕاست نەکراوەتەوە", "Nehatiye piştrastkirin")
        case nil: return sgText("Not checked yet", "لسا ما انفحصت", "هێشتا نەپشکنراوە", "Hê nehatiye kontrolkirin")
        }
    }
}
