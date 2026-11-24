import Foundation

/// CI configures the test runner, not the app. Local runs retain full coverage.
enum MirsaUILanguages {
    private static var arabicOnly: Bool {
        let mode = ProcessInfo.processInfo.environment["MIRSA_UI_LANGUAGE_MODE"] ?? "full"
        precondition(["ar", "full"].contains(mode), "Invalid UI test language mode")
        return mode == "ar"
    }
    static var primary: String { arabicOnly ? "ar" : "en" }
    static func selected(_ languages: [String]) -> [String] {
        precondition(languages.contains("ar"), "Arabic must be covered in every language matrix")
        return arabicOnly ? ["ar"] : languages
    }
    static func language(_ requested: String) -> String { arabicOnly ? "ar" : requested }
}
