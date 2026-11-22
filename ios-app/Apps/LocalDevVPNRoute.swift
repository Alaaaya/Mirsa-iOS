import Foundation

/// "mirsa" is shared by old Setup builds and the main app. The container scheme
/// is already registered only by main (Setup packaging explicitly strips it).
enum LocalDevVPNRoute {
    static let mainScheme = "mirsa-container"
    static let mainURL = URL(string: "mirsa-container://")!

    static func enableURL(isSetup: Bool, mainInstalled: Bool) -> URL {
        let scheme = isSetup && !mainInstalled ? "mirsa" : mainScheme
        // LocalDevVPN appends "://" itself, so pass a scheme, not an entire URL.
        return URL(string: "localdevvpn://enable?scheme=\(scheme)")!
    }

    /// Self-installing from Setup must restore the main-only scheme that was
    /// stripped when the Setup IPA was packaged. Retain other URL handlers.
    static func mainURLTypes(_ existing: [[String: Any]]) -> [[String: Any]] {
        guard !existing.contains(where: {
            ($0["CFBundleURLSchemes"] as? [String] ?? []).contains(mainScheme)
        }) else { return existing }
        return existing + [["CFBundleURLName": "com.alaa.mirsa.container",
                            "CFBundleURLSchemes": [mainScheme]]]
    }
}
