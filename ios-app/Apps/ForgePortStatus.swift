import Foundation

/// Port job status. "Ready" is shown only when the server confirms a fix inbox receipt AND the hashes bind to the local tweak.
struct ForgePortStatus: Equatable {
    var status: String
    var reviewedFixReady: Bool
    var fixID: UUID?
    var newSourceSHA256: String?
    static let statuses: Set<String> = ["queued", "ready_for_build", "awaiting_review", "unresolved", "delivered", "failed"]

    static func parse(_ o: [String: Any], localSourceSHA256: String) -> ForgePortStatus? {
        func hex(_ s: Any?) -> String? { (s as? String).flatMap { $0.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil ? $0 : nil } }
        guard let s = o["status"] as? String, statuses.contains(s),
              o["autoEnable"] as? Bool == false, o["manualEnableRequired"] as? Bool == true,
              hex(o["originalSourceSHA256"]) == localSourceSHA256 else { return nil }
        let fix = (o["fixID"] as? String).flatMap(UUID.init(uuidString:))
        let new = hex(o["newSourceSHA256"])
        let ready = o["reviewedFixReady"] as? Bool == true && s == "delivered" && fix != nil && new != nil && new != localSourceSHA256
        return ForgePortStatus(status: s, reviewedFixReady: ready, fixID: ready ? fix : nil, newSourceSHA256: ready ? new : nil)
    }
}
