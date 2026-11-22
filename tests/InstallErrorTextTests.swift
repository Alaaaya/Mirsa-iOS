import XCTest
@testable import Mirsa

final class InstallErrorTextTests: XCTestCase {
    func testIdentifierConflictExplainsRemovalInAllFiveLanguagesWithoutGenericLogAdvice() {
        let raw = "Install failed: MismatchedApplicationIdentifierEntitlement: installed app has a different application-identifier"
        let words = ["ar": "احذف النسخة القديمة أولاً", "en": "Delete the old version", "de": "Lösche zuerst", "kmr": "Pêşî", "ckb": "سەرەتا"]
        for (language, expected) in words {
            let safe = InstallErrorText.sanitize(raw, arabic: language == "ar", languageCode: language)
            XCTAssertTrue(safe.contains(expected))
            XCTAssertFalse(safe.contains("MismatchedApplicationIdentifierEntitlement"))
            XCTAssertEqual(InstallErrorText.sanitize(safe, arabic: language == "ar", languageCode: language), safe)
            XCTAssertEqual(InstallErrorText.nextStep(for: raw, arabic: language == "ar", languageCode: language), safe)
            XCTAssertEqual(InstallErrorText.nextStep(for: safe, arabic: language == "ar", languageCode: language), safe)
        }
        XCTAssertTrue(InstallErrorText.sanitize(raw.lowercased(), arabic: true).contains("احذف النسخة القديمة أولاً"))
        XCTAssertEqual(InstallErrorText.sanitize("Install failed: unrelated entitlement failure", arabic: false),
                       "Install failed: unrelated entitlement failure")
    }

    func testOnlyExactChangedSelfBuildSuppressesInterruptedAlert() {
        XCTAssertTrue(InstallErrorText.completedSelfUpdate(expected: "476", previous: "472", current: "476"))
        XCTAssertFalse(InstallErrorText.completedSelfUpdate(expected: "476", previous: "476", current: "476"))
        XCTAssertFalse(InstallErrorText.completedSelfUpdate(expected: "476", previous: "472", current: "472"))
        XCTAssertFalse(InstallErrorText.completedSelfUpdate(expected: nil, previous: nil, current: "476"))
        XCTAssertFalse(InstallErrorText.completedSelfUpdate(expected: "", previous: "472", current: "476"))
    }
    func testNextStepMatchesRecordedCauseNotBlanketVPNAdvice() {
        for (cause, expected) in [("session expired 1100", "Apple ID"),
                                   ("RemoteXPC timed out", "LocalDevVPN"),
                                   ("maximum apps reached", "احذف"),
                                   ("provisioning failed", "شهادة"),
                                   ("cancelled", "انلغت"),
                                   ("unknown error 42", "انسخ السجل")] {
            XCTAssertTrue(InstallErrorText.nextStep(for: cause, arabic: true).contains(expected))
        }
        XCTAssertTrue(InstallErrorText.interrupted(arabic: true).contains("ممكن التحديث اكتمل"))
    }
    func testOnlyConfirmedSourceAbsenceSuggestsRedownload() {
        XCTAssertEqual(InstallErrorText.sanitize("MIRSA_SOURCE_IPA_MISSING", arabic: false),
                       "The original IPA is missing. Import the IPA again or download it from its link.")
        XCTAssertEqual(InstallErrorText.sanitize("MIRSA_SOURCE_IPA_MISSING", arabic: true),
                       "ملف التثبيت الأصلي مو موجود. استورد ملف الـIPA أو حمّله من الرابط من جديد.")
        let error = "Install failed: No such file or directory (os error 2)\n/Users/runner/.cargo/registry/src/isideload-0.5.2/src/sideload/install.rs:162"
        for arabic in [true, false] {
            let safe = InstallErrorText.sanitize(error, arabic: arabic)
            XCTAssertFalse(safe.contains("runner"))
            XCTAssertFalse(safe.contains("isideload"))
            XCTAssertFalse(safe.contains("Download"))
            XCTAssertFalse(safe.contains("نزّله"))
            XCTAssertTrue(safe.contains("os error 2"))
        }
    }
    func testPreparationAndOtherENOENTKeepTheirOwnStage() {
        let error = "Preparing app snapshot: No such file or directory (os error 2)"
        let en = InstallErrorText.sanitize(error, arabic: false)
        XCTAssertTrue(en.hasPrefix("Preparing app snapshot:"))
        XCTAssertFalse(en.contains("Download"))
        XCTAssertTrue(InstallErrorText.sanitize(error, arabic: true).contains("تجهيز نسخة التثبيت"))
    }
    func testPathRedactionPreservesUsefulCause() {
        let raw = "Signing failed: permission denied /home/kit/private/Test.app and /private/var/mobile/tmp/output"
        let safe = InstallErrorText.sanitize(raw, arabic: false)
        XCTAssertTrue(safe.contains("Signing failed: permission denied"))
        XCTAssertFalse(safe.contains("/home/"))
        XCTAssertFalse(safe.contains("/private/"))
        XCTAssertEqual(InstallErrorText.sanitize(safe, arabic: false), safe)
    }
    func testOtherInstallCausesRemainUseful() {
        let raw = "Install failed: provisioning profile expired (0xe8008015)"
        XCTAssertEqual(InstallErrorText.sanitize(raw, arabic: false), raw)
    }
}
