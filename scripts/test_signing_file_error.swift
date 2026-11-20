import Foundation

/// Stable backend envelope keeps the failing relative file and original reason.
/// Technical reasons are retained verbatim instead of being replaced by "invalid Mach-O".
enum PersonalSigningFileError {
    static func localized(_ message: String, language: String) -> String {
        let marker = "MIRSA_SIGN_FILE|"
        guard message.hasPrefix(marker),
              let data = String(message.dropFirst(marker.count)).data(using: .utf8),
              let value = try? JSONSerialization.jsonObject(with: data) as? [String: String],
              let path = value["path"], let reason = value["reason"] else { return message }
        let title: String
        let detail: String
        switch language {
        case "ar": title = "تعذّر توقيع الملف"; detail = "السبب"
        case "de": title = "Datei konnte nicht signiert werden"; detail = "Grund"
        case "kmr": title = "Pel nehat îmzekirin"; detail = "Sedem"
        case "ckb": title = "واژۆکردنی پەڕگەکە سەرکەوتوو نەبوو"; detail = "هۆکار"
        default: title = "Could not sign file"; detail = "Reason"
        }
        return "\(title)\n\(path)\n\(detail): \(reason)"
    }
}

let payload = #"MIRSA_SIGN_FILE|{"path":"Frameworks/Test.framework/Test","reason":"Invalid slice bounds"}"#
for language in ["ar","en","de","kmr","ckb"] {
    let text = PersonalSigningFileError.localized(payload, language: language)
    precondition(text.contains("Frameworks/Test.framework/Test"))
    precondition(text.contains("Invalid slice bounds"))
    precondition(!text.contains("MIRSA_SIGN_FILE"))
}
precondition(PersonalSigningFileError.localized("other error", language: "ar") == "other error")
print("Five localized file-error formatters passed")
