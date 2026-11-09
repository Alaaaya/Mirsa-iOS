import Foundation

/// Only this persisted identity is protected, never an arbitrary matching name or URL.
enum SourceDeletionPolicy {
    static let primaryID = "mirsa.source.canonical.primary"
    static func canDelete(_ source: RepoSource) -> Bool { source.id != primaryID }

    static func migrate(_ input: [RepoSource]) -> [RepoSource] {
        var result = input
        for index in result.indices {
            if MirsaSourceFeed.legacyURLs.contains(MirsaSourceFeed.norm(result[index].url)) {
                result[index].url = MirsaSourceFeed.primary
            }
        }
        // Preserve a previously assigned canonical identity. On the first migration only,
        // select one primary entry; all other identical rows remain independent user entries.
        let canonical = result.firstIndex { $0.entryID == primaryID }
            ?? result.firstIndex { MirsaSourceFeed.norm($0.url) == MirsaSourceFeed.norm(MirsaSourceFeed.primary) }
        var seen = Set<String>()
        for index in result.indices {
            if index == canonical {
                result[index].entryID = primaryID
            } else if result[index].entryID == nil || result[index].entryID == primaryID ||
                        seen.contains(result[index].id) {
                result[index].entryID = UUID().uuidString
            }
            seen.insert(result[index].id)
        }
        if canonical == nil {
            var primary = RepoSource(url: MirsaSourceFeed.primary, name: "Mirsa")
            primary.entryID = primaryID
            result.append(primary)
        }
        return result
    }
}

enum SourceDeletionText {
    static var delete: String { sgText("Delete", "حذف", "سڕینەوە", "Jê bibe") }
    static var cancel: String { sgText("Cancel", "إلغاء", "پاشگەزبوونەوە", "Betal bike") }
    static var title: String { sgText("Delete source?", "تحذف السورس؟", "سەرچاوە بسڕدرێتەوە؟", "Çavkanî were jêbirin?") }
    static var message: String {
        sgText("Only this source entry will be removed. Installed apps will stay.",
               "رح ينحذف هالسورس بس. التطبيقات المثبّتة بتضل متل ما هي.",
               "تەنها ئەم سەرچاوەیە دەسڕدرێتەوە. ئەپە دامەزراوەکان دەمێننەوە.",
               "Tenê ev çavkanî tê jêbirin. Appên sazkirî dimînin.")
    }
}
