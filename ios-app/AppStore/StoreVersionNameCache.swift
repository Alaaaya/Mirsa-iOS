import Foundation

/// Version names never change for an external version ID, so keep them on disk per app.
enum StoreVersionNameCache {
    private static func k(_ b: String) -> String { "mirsa.store.vnames." + b }
    static func get(_ bundle: String, _ id: String) -> String? {
        (UserDefaults.standard.dictionary(forKey: k(bundle)) as? [String: String])?[id]
    }
    static func set(_ bundle: String, _ id: String, _ v: String) {
        var d = (UserDefaults.standard.dictionary(forKey: k(bundle)) as? [String: String]) ?? [:]
        if d.count > 2000 { d = [:] }
        d[id] = v
        UserDefaults.standard.set(d, forKey: k(bundle))
    }
}
