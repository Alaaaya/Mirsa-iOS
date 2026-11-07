import XCTest
import Security
import CryptoKit
@testable import Mirsa

private typealias E = DEREncode

final class OCSPAndRestrictionsTests: XCTestCase {
    // MARK: fixtures
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func gt(_ d: Date) -> [UInt8] {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyyMMddHHmmss'Z'"
        return E.tlv(0x18, Array(f.string(from: d).utf8))
    }
    private func oid(_ b: [UInt8]) -> [UInt8] { E.tlv(0x06, b) }
    private let ecdsa256: [UInt8] = [0x2A,0x86,0x48,0xCE,0x3D,0x04,0x03,0x02]
    private func name(_ cn: String) -> [UInt8] {
        E.tlv(0x30, E.tlv(0x31, E.tlv(0x30, oid([0x55,0x04,0x03]) + E.tlv(0x0C, Array(cn.utf8)))))
    }
    private func newKey() -> SecKey {
        let attrs: [String: Any] = [kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom, kSecAttrKeySizeInBits as String: 256]
        return SecKeyCreateRandomKey(attrs as CFDictionary, nil)!
    }
    private func point(_ k: SecKey) -> [UInt8] { [UInt8](SecKeyCopyExternalRepresentation(SecKeyCopyPublicKey(k)!, nil)! as Data) }
    private func sign(_ m: [UInt8], _ k: SecKey) -> [UInt8] {
        [UInt8](SecKeyCreateSignature(k, .ecdsaSignatureMessageX962SHA256, Data(m) as CFData, nil)! as Data)
    }
    private func cert(subject: String, issuer: String, serial: UInt8, key: SecKey, signer: SecKey,
                      from: Date, to: Date, eku: [[UInt8]]? = nil) -> Data {
        let spki = E.tlv(0x30, E.tlv(0x30, oid([0x2A,0x86,0x48,0xCE,0x3D,0x02,0x01]) + oid([0x2A,0x86,0x48,0xCE,0x3D,0x03,0x01,0x07])) + E.tlv(0x03, [0] + point(key)))
        var exts: [UInt8] = []
        if let eku {
            let seq = E.tlv(0x30, eku.flatMap { oid($0) })
            exts = E.tlv(0xA3, E.tlv(0x30, E.tlv(0x30, oid([0x55,0x1D,0x25]) + E.tlv(0x04, seq))))
        }
        let tbs = E.tlv(0x30, [0xA0,0x03,0x02,0x01,0x02] + E.tlv(0x02, [serial]) + E.tlv(0x30, oid(ecdsa256))
                        + name(issuer) + E.tlv(0x30, gt(from) + gt(to)) + name(subject) + spki + exts)
        return Data(E.tlv(0x30, tbs + E.tlv(0x30, oid(ecdsa256)) + E.tlv(0x03, [0] + sign(tbs, signer))))
    }
    private struct Fixture { let issuerKey: SecKey; let issuer: ParsedCertificate; let leaf: ParsedCertificate }
    private func fixture(issuerFrom: Date? = nil, issuerTo: Date? = nil) -> Fixture {
        let ik = newKey(), lk = newKey()
        let issuer = ParsedCertificate(cert(subject: "Issuer", issuer: "Root", serial: 1, key: ik, signer: ik,
                                            from: issuerFrom ?? now.addingTimeInterval(-86400), to: issuerTo ?? now.addingTimeInterval(86400)))!
        let leaf = ParsedCertificate(cert(subject: "Leaf", issuer: "Issuer", serial: 7, key: lk, signer: ik,
                                          from: now.addingTimeInterval(-3600), to: now.addingTimeInterval(86400)))!
        return Fixture(issuerKey: ik, issuer: issuer, leaf: leaf)
    }
    private enum Cert { case good, revoked, unknown }
    private func response(_ fx: Fixture, signer: SecKey? = nil, status: Cert = .good, serial: [UInt8]? = nil,
                          issuerNameForHash: [UInt8]? = nil, thisUpdate: Date? = nil, nextUpdate: Date? = nil,
                          responseStatus: UInt8 = 0, extraCerts: [UInt8] = []) -> Data {
        let nameHash = [UInt8](Insecure.SHA1.hash(data: Data(issuerNameForHash ?? fx.issuer.subjectName)))
        let keyHash = [UInt8](Insecure.SHA1.hash(data: Data(fx.issuer.publicKeyBits)))
        let certID = E.tlv(0x30, E.tlv(0x30, oid([0x2B,0x0E,0x03,0x02,0x1A]) + [0x05,0x00]) + E.tlv(0x04, nameHash) + E.tlv(0x04, keyHash) + E.tlv(0x02, serial ?? fx.leaf.serial))
        let st: [UInt8]
        switch status { case .good: st = [0x80,0x00]; case .revoked: st = E.tlv(0xA1, gt(now.addingTimeInterval(-60))); case .unknown: st = [0x82,0x00] }
        let single = E.tlv(0x30, certID + st + gt(thisUpdate ?? now.addingTimeInterval(-60)) + E.tlv(0xA0, gt(nextUpdate ?? now.addingTimeInterval(3600))))
        let rd = E.tlv(0x30, E.tlv(0xA2, E.tlv(0x04, [UInt8](repeating: 1, count: 20))) + gt(now) + E.tlv(0x30, single))
        let sig = sign(rd, signer ?? fx.issuerKey)
        let basic = E.tlv(0x30, rd + E.tlv(0x30, oid(ecdsa256)) + E.tlv(0x03, [0] + sig) + (extraCerts.isEmpty ? [] : E.tlv(0xA0, E.tlv(0x30, extraCerts))))
        let rb = E.tlv(0x30, oid([0x2B,0x06,0x01,0x05,0x05,0x07,0x30,0x01,0x01]) + E.tlv(0x04, basic))
        return Data(E.tlv(0x30, [0x0A,0x01,responseStatus] + (responseStatus == 0 ? E.tlv(0xA0, rb) : [])))
    }
    private func parse(_ fx: Fixture, _ data: Data) -> RevocationStatus {
        OCSPChecker.parse(response: data, leaf: fx.leaf, issuer: fx.issuer, issuerKey: fx.issuerKey, now: now)
    }
    private func assertNotVerified(_ s: RevocationStatus, file: StaticString = #filePath, line: UInt = #line) {
        if case .notVerified = s { return }
        XCTFail("expected notVerified, got \(s)", file: file, line: line)
    }

    // MARK: OCSP
    func testCertificateFieldsParsed() {
        let k = newKey()
        let c = ParsedCertificate(cert(subject: "D", issuer: "I", serial: 3, key: k, signer: k, from: now, to: now.addingTimeInterval(10),
                                       eku: [[0x2B,0x06,0x01,0x05,0x05,0x07,0x03,0x09]]))!
        XCTAssertEqual(c.notBefore, now); XCTAssertEqual(c.notAfter, now.addingTimeInterval(10))
        XCTAssertEqual(c.extendedKeyUsage, [[0x2B,0x06,0x01,0x05,0x05,0x07,0x03,0x09]])
        XCTAssertEqual(c.publicKeyBits, point(k))
    }
    func testAuthenticatedGoodAnswerIsGood() {
        let fx = fixture()
        XCTAssertEqual(parse(fx, response(fx)), .good(checked: now))
    }
    func testRevokedAnswerReportsRevoked() {
        let fx = fixture()
        if case .revoked(let at) = parse(fx, response(fx, status: .revoked)) { XCTAssertNotNil(at) } else { XCTFail("not revoked") }
    }
    func testUnknownStatusIsNotGood() { let fx = fixture(); assertNotVerified(parse(fx, response(fx, status: .unknown))) }
    func testSignatureFromOtherKeyRejected() { let fx = fixture(); assertNotVerified(parse(fx, response(fx, signer: newKey()))) }
    func testTamperedBodyRejected() {
        let fx = fixture(); var d = [UInt8](response(fx))
        if let i = d.lastIndex(of: 0x80) { d[i] = 0x82 }   // flip good -> unknown after signing
        assertNotVerified(parse(fx, Data(d)))
    }
    func testSerialMismatchRejected() { let fx = fixture(); assertNotVerified(parse(fx, response(fx, serial: [9]))) }
    func testIssuerNameHashMismatchRejected() {
        let fx = fixture(); assertNotVerified(parse(fx, response(fx, issuerNameForHash: name("Someone Else"))))
    }
    func testStaleAnswerRejected() {
        let fx = fixture(); assertNotVerified(parse(fx, response(fx, thisUpdate: now.addingTimeInterval(-7200), nextUpdate: now.addingTimeInterval(-3600))))
    }
    func testFutureThisUpdateRejected() { let fx = fixture(); assertNotVerified(parse(fx, response(fx, thisUpdate: now.addingTimeInterval(3600)))) }
    func testUnsuccessfulResponseStatusRejected() { let fx = fixture(); assertNotVerified(parse(fx, response(fx, responseStatus: 6))) }
    func testGarbageAndTruncatedRejected() {
        let fx = fixture()
        assertNotVerified(parse(fx, Data([1, 2, 3])))
        let d = response(fx); assertNotVerified(parse(fx, d.prefix(d.count / 2)))
    }
    func testExpiredIssuerRejected() {
        let fx = fixture(issuerFrom: now.addingTimeInterval(-86400 * 3), issuerTo: now.addingTimeInterval(-86400))
        assertNotVerified(parse(fx, response(fx)))
    }
    func testDelegateWithoutOCSPSigningEKURejected() {
        let fx = fixture(); let dk = newKey()
        let delegate = cert(subject: "Delegate", issuer: "Issuer", serial: 5, key: dk, signer: fx.issuerKey,
                            from: now.addingTimeInterval(-60), to: now.addingTimeInterval(600), eku: [[0x2B,0x06,0x01,0x05,0x05,0x07,0x03,0x01]])
        assertNotVerified(parse(fx, response(fx, signer: dk, extraCerts: [UInt8](delegate))))
    }
    func testDelegateIssuedByDifferentCARejected() {
        let fx = fixture(); let dk = newKey()
        let delegate = cert(subject: "Delegate", issuer: "Other CA", serial: 5, key: dk, signer: newKey(),
                            from: now.addingTimeInterval(-60), to: now.addingTimeInterval(600), eku: [[0x2B,0x06,0x01,0x05,0x05,0x07,0x03,0x09]])
        assertNotVerified(parse(fx, response(fx, signer: dk, extraCerts: [UInt8](delegate))))
    }
    func testExpiredDelegateRejected() {
        let fx = fixture(); let dk = newKey()
        let delegate = cert(subject: "Delegate", issuer: "Issuer", serial: 5, key: dk, signer: fx.issuerKey,
                            from: now.addingTimeInterval(-7200), to: now.addingTimeInterval(-3600), eku: [[0x2B,0x06,0x01,0x05,0x05,0x07,0x03,0x09]])
        assertNotVerified(parse(fx, response(fx, signer: dk, extraCerts: [UInt8](delegate))))
    }

    // MARK: restrictions + clone
    private func writePlist(_ dict: [String: Any], to url: URL) throws {
        try PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0).write(to: url)
    }
    private let restricted: [String: Any] = ["CFBundleIdentifier": "com.x.app", "UIDeviceFamily": [1], "MinimumOSVersion": "15.0",
                                            "UIRequiredDeviceCapabilities": ["arm64"]]
    func testStripRemovesOnlyRestrictionKeys() {
        var info = restricted
        DeviceRestrictions.strip(&info)
        XCTAssertEqual(Array(info.keys), ["CFBundleIdentifier"])
        XCTAssertEqual(DeviceRestrictions.removed(from: restricted).sorted(), DeviceRestrictions.keys.sorted())
    }
    func testStripExtensionsChangesCopyNotOriginal() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("restr-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: root) }
        let original = root.appendingPathComponent("orig/Mirsa.app")
        let appex = original.appendingPathComponent("PlugIns/W.appex")
        try fm.createDirectory(at: appex, withIntermediateDirectories: true)
        try writePlist(restricted, to: appex.appendingPathComponent("Info.plist"))
        try writePlist(restricted, to: original.appendingPathComponent("Info.plist"))
        let before = try Data(contentsOf: appex.appendingPathComponent("Info.plist"))
        let copy = root.appendingPathComponent("copy/Mirsa.app")
        try fm.createDirectory(at: copy.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.copyItem(at: original, to: copy)
        try DeviceRestrictions.stripExtensions(in: copy)
        XCTAssertEqual(try Data(contentsOf: appex.appendingPathComponent("Info.plist")), before, "original must be untouched")
        let changed = try PropertyListSerialization.propertyList(from: Data(contentsOf: copy.appendingPathComponent("PlugIns/W.appex/Info.plist")), format: nil) as! [String: Any]
        XCTAssertNil(changed["UIDeviceFamily"]); XCTAssertNil(changed["MinimumOSVersion"]); XCTAssertEqual(changed["CFBundleIdentifier"] as? String, "com.x.app")
    }
    func testCloneIDAndProfilePattern() {
        let id = AppClone.cloneID(from: "com.x.app")
        XCTAssertNotEqual(id, "com.x.app"); XCTAssertTrue(IPAEditorService.validBundleID(id))
        XCTAssertNotEqual(AppClone.cloneID(from: "com.x.app", existing: [id]), id)
        XCTAssertTrue(AppClone.profileAllows("com.me.a", pattern: "T1.com.me.*", teamID: "T1"))
        XCTAssertTrue(AppClone.profileAllows("com.any", pattern: "T1.*", teamID: "T1"))
        XCTAssertFalse(AppClone.profileAllows("com.other.a", pattern: "T1.com.me.*", teamID: "T1"))
        XCTAssertFalse(AppClone.profileAllows("com.me.a", pattern: "T1.com.me.b", teamID: "T1"))
    }
    func testCloneOptionsRejectSameAndInvalidAndAcceptEdited() throws {
        XCTAssertThrowsError(try AppClone.options(base: .init(), originalID: "a.b", originalName: "A", newID: "a.b", newName: nil, identity: nil))
        XCTAssertThrowsError(try AppClone.options(base: .init(), originalID: "a.b", originalName: "A", newID: "bad id", newName: nil, identity: nil))
        let o = try AppClone.options(base: .init(), originalID: "a.b", originalName: "A", newID: "a.c", newName: "  My Copy ", identity: nil)
        XCTAssertEqual(o.bundleID, "a.c"); XCTAssertEqual(o.displayName, "My Copy")
    }
}
