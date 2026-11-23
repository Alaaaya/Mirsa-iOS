import Foundation

/// Metadata adapter only; no upstream source code or artwork is bundled.
enum CAPlaygroundSource {
    static let repository = URL(string: "https://github.com/CAPlayground/wallpapers")!
    static let manifest = URL(string: "https://raw.githubusercontent.com/CAPlayground/wallpapers/main/wallpapers.json")!
    static let limit: Int64 = 32 * 1_048_576
    private static let root = URL(string: "https://raw.githubusercontent.com/CAPlayground/wallpapers/main/")!
    private struct Feed: Decodable { let wallpapers: [Item] }
    private struct Item: Decodable {
        let name: String
        let id: String
        let creator: String?
        let file: String
        let preview: String
        let description: String?

        private enum CodingKeys: String, CodingKey { case name, id, creator, file, preview, description }
        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            name = try values.decode(String.self, forKey: .name)
            // Upstream mixes numeric IDs with zero-prefixed string IDs. Preserve
            // textual IDs exactly, rather than discarding the whole catalog.
            if let text = try? values.decode(String.self, forKey: .id) {
                id = text
            } else {
                id = String(try values.decode(Int.self, forKey: .id))
            }
            creator = try values.decodeIfPresent(String.self, forKey: .creator)
            file = try values.decode(String.self, forKey: .file)
            description = try values.decodeIfPresent(String.self, forKey: .description)
            preview = try values.decode(String.self, forKey: .preview)
        }
    }

    static func asset(_ path: String, prefix: String, extension suffix: String) throws -> URL {
        guard path.utf8.count <= 1024, path.hasPrefix(prefix),
              !path.contains("\\"), !path.contains("%"),
              !path.contains("?"), !path.contains("#"),
              path.split(separator: "/", omittingEmptySubsequences: false).allSatisfy({
                  !$0.isEmpty && $0 != "." && $0 != ".."
              }) else { throw WallpaperSourceError.invalid }
        let url = root.appendingPathComponent(path)
        guard url.pathExtension.lowercased() == suffix else { throw WallpaperSourceError.invalid }
        return url
    }

    static func decode(_ data: Data) throws -> WallpaperSourceFeed {
        guard data.count <= 2_097_152 else { throw WallpaperSourceError.tooLarge }
        let upstream = try JSONDecoder().decode(Feed.self, from: data)
        guard upstream.wallpapers.count <= 1000 else { throw WallpaperSourceError.invalid }
        let entries = try upstream.wallpapers.map { item -> WallpaperSourceEntry in
            let previewExtension = (item.preview as NSString).pathExtension.lowercased()
            guard ["gif", "png", "jpg", "jpeg", "webp", "mp4", "mov", "m4v"].contains(previewExtension) else {
                throw WallpaperSourceError.invalid
            }
            var entry = WallpaperSourceEntry(
                id: item.id, name: item.name, author: item.creator ?? "CAPlayground",
                previewImage: try asset(item.preview, prefix: "previews/", extension: previewExtension),
                url: try asset(item.file, prefix: "wallpapers/", extension: "tendies"),
                size: limit, category: "CAPlayground"
            )
            entry.description = item.description
            if ["mp4", "mov", "m4v"].contains(previewExtension) { entry.previewVideo = entry.previewImage }
            // Upstream has no byte sizes. This is a bounded cap, never a fabricated exact size.
            entry.sizeIsEstimated = true
            return entry
        }
        return try WallpaperSourceFeed(name: "CAPlayground", author: "CAPlayground · GPL-3.0 · GitHub", wallpapers: entries).validated()
    }
}
