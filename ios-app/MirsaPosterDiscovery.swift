import Foundation

@_silgen_name("mirsa_pb_candidates_copy_json")
private func copyCandidateJSON() -> UnsafeMutablePointer<CChar>?
@_silgen_name("mirsa_pb_target_identity_json")
private func copyTargetIdentity(_ path: UnsafePointer<CChar>) -> UnsafeMutablePointer<CChar>?
@_silgen_name("mirsa_pb_has_own_group")
private func hasOwnGroup(_ log: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>) -> Int32
@_silgen_name("mirsa_pb_access_free_string")
private func freeProbeString(_ value: UnsafeMutablePointer<CChar>)


enum MirsaPosterDiscovery {
    static func identifiesPosterBoard(_ path: String, log: (String) -> Void) throws -> Bool {
        guard let pointer = path.withCString({ copyTargetIdentity($0) }) else {
            throw PosterBoardStore.failure("Metadata identity report missing.")
        }
        let text = String(cString: pointer)
        freeProbeString(pointer)
        log("IDENTITY metadata result \(text)")
        guard let bytes = text.data(using: .utf8),
              let identity = try JSONSerialization.jsonObject(with: bytes) as? [String: Any] else { return false }
        if identity["restoreFailure"] as? Bool == true {
            throw PosterBoardStore.failure("Own Caches restore failed. Stop; backup retained.")
        }
        return identity["matched"] as? Bool == true
    }
    static func discover(log: @escaping (String) -> Void) throws -> String {
        log("DISCOVERY BEFORE own-group query")
        var details: UnsafeMutablePointer<CChar>?
        let groupCount = hasOwnGroup(&details)
        if let details { log(String(cString: details)); freeProbeString(details) }
        log("DISCOVERY AFTER own-group query; count=\(groupCount)")
        guard groupCount > 0 else {
            throw PosterBoardStore.failure("placard-style needs one usable own app group. See the entitlement acquisition, embedded group values and per-group containerURL results above. Cause is not established. get-task-allow is NOT required.")
        }
        // Listing a data-container parent may be denied even when exact-path
        // extensions work. Resolve UUID candidates on our own data volume first.
        log("DISCOVERY BEFORE copyCandidateJSON; synchronous calls cannot be forcibly cancelled safely")
        let deadline = ProcessInfo.processInfo.systemUptime + 20
        var attempts = 0
        if let pointer = copyCandidateJSON() {
            log("DISCOVERY AFTER copyCandidateJSON")
            let json = String(cString: pointer)
            freeProbeString(pointer)
            if let data = json.data(using: .utf8),
               let report = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                log("placard-style inode discovery visited=\(report["visitedInodes"] ?? "?") seconds=\(report["seconds"] ?? "?") limited=\(report["timeLimited"] ?? "?") UUIDs=\(report["UUIDContainersSeen"] ?? "?")")
                if let error = report["error"] { log("discovery ERROR \(error)") }
                log("DISCOVERY aggregate unknown xattr=\(report["unknownIdentityCount"] ?? "?") other identity=\(report["otherIdentityCount"] ?? "?"); these receive NO access grants")
                log("DISCOVERY scan start=\(report["startInode"] ?? "?") next=\(report["nextInode"] ?? "?") complete=\(report["scanComplete"] ?? "?"); next Diagnose resumes if time-limited")
                let exact = report["matched"] as? [String] ?? []
                let hints = report["hinted"] as? [String] ?? []
                let candidates = Array(Set(exact + hints)).sorted()
                log("DISCOVERY exact xattr matches=\(exact.count) PosterBoard-specific path hints=\(hints.count); verify exact metadata only, no arbitrary candidate roots")
                for raw in candidates {
                    guard attempts < 8, ProcessInfo.processInfo.systemUptime < deadline else {
                        log("DISCOVERY targeted metadata budget reached; no further access calls")
                        break
                    }
                    attempts += 1
                    let path = try PosterBoardStore.canonicalContainer(raw)
                    log("IDENTITY target \(attempts) · \(path) · reason=\(exact.contains(raw) ? "exact PosterBoard xattr" : "PosterBoard-specific path hint")")
                    if try identifiesPosterBoard(path, log: log) {
                        log("PosterBoard VERIFIED by MCMMetadataIdentifier=com.apple.PosterBoard · \(path)")
                        return path
                    }
                }
            }
        }
        log("DISCOVERY FINISHED · no metadata-verified PosterBoard in this bounded pass. Unknown containers were NOT granted access. If scan was time-limited, Diagnose resumes scanning. No writes performed.")
        throw PosterBoardStore.failure("No PosterBoard candidate identified. Paste a known canonical container path to diagnose directly.")
    }
}
