import Foundation

/// A revision identifies a draft snapshot, not an archival file. Reset is a new
/// revision too: returning to old settings does not silently bless an old export.
enum ProjectArtifactRevision {
    static func current(_ id: UUID, defaults: UserDefaults = .standard) -> String {
        let key = "mirsa.project.revision." + id.uuidString
        if let value = defaults.string(forKey: key) { return value }
        let value = UUID().uuidString
        defaults.set(value, forKey: key)
        return value
    }
    @discardableResult
    static func invalidate(_ id: UUID, defaults: UserDefaults = .standard) -> String {
        let value = UUID().uuidString
        defaults.set(value, forKey: "mirsa.project.revision." + id.uuidString)
        return value
    }
    static func record(_ revision: String, project: UUID, defaults: UserDefaults = .standard) {
        defaults.set(revision, forKey: "mirsa.project.signedRevision." + project.uuidString)
    }
    static func isCurrent(_ revision: String, project: UUID, defaults: UserDefaults = .standard) -> Bool {
        revision == current(project, defaults: defaults)
    }
    static func signedIsCurrent(_ id: UUID, defaults: UserDefaults = .standard) -> Bool {
        guard let signed = defaults.string(forKey: "mirsa.project.signedRevision." + id.uuidString) else { return false }
        return isCurrent(signed, project: id, defaults: defaults)
    }
}
