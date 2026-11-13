import Foundation

/// Independent four-language helper for signing tools (Arabic / Sorani / Kurmanji / English).
func sgText(_ en: String, _ ar: String, _ ckb: String, _ kmr: String) -> String {
    switch AppLanguageStore.shared.current {
    case .english, .german: return en
    case .arabic: return ar
    case .sorani: return ckb
    case .kurmanji: return kmr
    }
}
