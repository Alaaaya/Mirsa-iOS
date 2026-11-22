import Foundation

/// One presentation boundary for install, renewal and signing diagnostics.
/// Keep the useful stage/OS reason, not Rust source locations or sandbox paths.
enum InstallErrorText {
    /// InstallationProxy uses this precise reason when an installed copy has a
    /// different application-identifier entitlement. Do not auto-delete user apps.
    static func identifierConflictMessage(languageCode: String) -> String {
        switch languageCode {
        case "ar": return "احذف النسخة القديمة أولاً، وبعدين جرّب تثبّت التطبيق من جديد."
        case "de": return "Lösche zuerst die alte Version der App und versuche die Installation erneut."
        case "kmr": return "Pêşî guhertoya kevn jê bibe, paşê dîsa appê saz bike."
        case "ckb": return "سەرەتا وەشانی کۆن بسڕەوە، پاشان دووبارە ئەپەکە دابمەزرێنە."
        default: return "Delete the old version of the app first, then try installing again."
        }
    }

    private static func isIdentifierConflict(_ raw: String) -> Bool {
        raw.localizedCaseInsensitiveContains("MismatchedApplicationIdentifierEntitlement") ||
            ["ar", "en", "de", "kmr", "ckb"].contains {
                raw == identifierConflictMessage(languageCode: $0)
            }
    }

    /// A terminated process is not an installation-proxy failure. In particular,
    /// replacing Mirsa itself ends the process before Swift defer blocks execute.
    static func completedSelfUpdate(expected: String?, previous: String?, current: String) -> Bool {
        guard let expected, let previous, !expected.isEmpty, !previous.isEmpty else { return false }
        return expected == current && previous != current
    }

    static func interrupted(arabic: Bool) -> String {
        arabic
            ? "انتهت جلسة مرسى أثناء التثبيت، وما تسجّل سبب خطأ. إذا كنت عم تحدّث مرسى، شيّك رقم النسخة بالإعدادات أولاً؛ ممكن التحديث اكتمل. إذا التطبيق المطلوب مو مثبت، جرّب من جديد."
            : "Mirsa closed during installation; no failure reason was recorded. If you were updating Mirsa, check its version in Settings first; the update may have completed. Retry only if the requested app is not installed."
    }

    static func nextStep(for raw: String, arabic: Bool, languageCode: String? = nil) -> String {
        if isIdentifierConflict(raw) {
            return identifierConflictMessage(languageCode: languageCode ?? (arabic ? "ar" : "en"))
        }
        let text = raw.lowercased()
        if text.contains("1100") || text.contains("session expired") || text.contains("not signed in") {
            return arabic ? "سجّل خروج من Apple ID داخل مرسى وسجّل دخول من جديد، وبعدين جرّب." : "Sign out of Apple ID in Mirsa, sign in again, then retry."
        }
        if text.contains("timed out") || text.contains("remotexpc") || text.contains("device connection failed") {
            return arabic ? "وصّل على الواي فاي وشغّل LocalDevVPN وتأكد من ملف الاقتران، وبعدين جرّب." : "Connect to Wi-Fi, enable LocalDevVPN and check the pairing file, then retry."
        }
        if text.contains("maximum") && text.contains("app") || text.contains("applicationlimit") {
            return arabic ? "وصلت لحد التطبيقات المسموح. احذف تطبيق موقّع بنفس Apple ID وبعدين جرّب." : "The app limit was reached. Remove an app signed with this Apple ID, then retry."
        }
        if text.contains("provision") || text.contains("certificate") {
            return arabic ? "راجع حالة شهادة Apple ID والتوقيع داخل مرسى، وبعدين أعد التوقيع والتثبيت." : "Check the Apple ID certificate and signing status in Mirsa, then sign and install again."
        }
        if text.contains("cancelled") || text.contains("canceled") {
            return arabic ? "انلغت العملية. ابدأ التثبيت من جديد إذا لسا بدك تثبّت التطبيق." : "The operation was cancelled. Start it again if you still want to install."
        }
        return arabic ? "انسخ السجل من هالتنبيه وابعتو مع وصف اللي صار قبل ما تعيد المحاولة." : "Copy the log from this alert and send it with what happened before retrying."
    }

    static func sanitize(_ raw: String, arabic: Bool, languageCode: String? = nil) -> String {
        if isIdentifierConflict(raw) {
            return identifierConflictMessage(languageCode: languageCode ?? (arabic ? "ar" : "en"))
        }
        if raw == "MIRSA_SOURCE_IPA_MISSING" {
            return arabic ? "ملف التثبيت الأصلي مو موجود. استورد ملف الـIPA أو حمّله من الرابط من جديد." : "The original IPA is missing. Import the IPA again or download it from its link."
        }
        var text = raw
        // Rootcause appends a compiler-machine source location after the cause.
        text = text.replacingOccurrences(of: #"(?m)^\s*(?:at\s+)?/[^\n]+\.rs:\d+(?::\d+)?\s*$"#,
                                         with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: #"(?<![A-Za-z0-9:])/(?:[^\s\x22'<>\[\]()]+)"#,
                                         with: "[path]", options: .regularExpression)
        text = text.replacingOccurrences(of: #"\b[A-Za-z]:\\[^\s\x22'<>]+"#,
                                         with: "[path]", options: .regularExpression)
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return arabic ? "ما اكتملت العملية. جرّب من جديد." : "The operation did not complete. Try again." }
        if arabic {
            let stages = [
                ("Install failed:", "ما اكتمل تثبيت التطبيق"),
                ("Signing failed:", "ما اكتمل توقيع التطبيق"),
                ("Preparing app archive:", "ما اكتمل تجهيز ملف التطبيق"),
                ("Preparing extracted app:", "ما اكتمل تجهيز ملفات التطبيق"),
                ("Preparing install workspace:", "ما اكتمل تجهيز مجلد التثبيت"),
                ("Preparing app snapshot:", "ما اكتمل تجهيز نسخة التثبيت"),
                ("Reading source app:", "ما اكتملت قراءة ملف التطبيق"),
                ("Saving app snapshot:", "ما اكتمل حفظ نسخة التثبيت"),
                ("Publishing app snapshot:", "ما اكتمل تجهيز نسخة التثبيت")
            ]
            for (prefix, localized) in stages where text.hasPrefix(prefix) {
                text = localized + "، " + text.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
                break
            }
            text = text.replacingOccurrences(of: "No such file or directory", with: "ملف أو مجلد مؤقت مو متاح")
        }
        return text
    }
}
