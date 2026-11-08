import Foundation

/// A failed server build. `log` is the sanitized full compiler output, `summary` is a short localized message.
struct ForgeBuildFailure: LocalizedError {
    let summary: String
    let log: String
    var errorDescription: String? { summary }

    init(rawLog: String) {
        let clean = ForgeBuildLog.sanitize(rawLog)
        self.log = String(clean.suffix(4000))
        self.summary = ForgeBuildLog.summary(clean)
    }
}

enum ForgeBuildLog {
    /// Removes ANSI escape sequences (also the bare "[0m" form whose ESC byte got lost) and other control codes.
    static func sanitize(_ s: String) -> String {
        // OSC sequences (ESC ] ... BEL or ESC \\), e.g. terminal titles/hyperlinks
        var t = s.replacingOccurrences(of: "\u{1B}\\][^\u{07}\u{1B}]*(\u{07}|\u{1B}\\\\)", with: "", options: .regularExpression)
        t = t.replacingOccurrences(of: "\u{1B}\\[[0-9;?]*[ -/]*[@-~]", with: "", options: .regularExpression)
        t = t.replacingOccurrences(of: "\\[[0-9;]*m", with: "", options: .regularExpression)
        t = t.replacingOccurrences(of: "\r\n?", with: "\n", options: .regularExpression)
        t = String(t.unicodeScalars.filter { $0 == "\n" || $0 == "\t" || $0.value >= 0x20 && $0.value != 0x7F })
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// First compiler "error:" line (file:line + message) or a generic message.
    static func summary(_ clean: String) -> String {
        let lower = clean.lowercased()
        if lower.contains("no known instance method for selector") || lower.contains("deprecated") || lower.contains("-wdeprecated") || lower.contains("is unavailable") {
            return tr("The tweak uses an old iOS function that no longer exists (for example UIAlertView). Ask Mirsa to rewrite it with the new API.", "التويك بيستخدم دالة قديمة بـ iOS ما عادت موجودة (مثل UIAlertView). اطلب من مرسى يعيد كتابته بالدالة الجديدة.", ckb: "تویکەکە فەنکشنێکی کۆنی iOS بەکاردەهێنێت.", kmr: "Tweak fonksiyoneke kevn a iOS bi kar tîne.")
        }
        let generic = tr("The tweak failed to build. Tap for the full log.", "فشل بناء التويك. اضغط لعرض السجل الكامل.", ckb: "دروستکردنی تویک سەرکەوتوو نەبوو.", kmr: "Çêkirina tweak têk çû.")
        guard let line = clean.split(separator: "\n").first(where: { $0.contains("error:") && !$0.hasPrefix("make") }) else { return generic }
        _ = line
        return generic
    }
}
