import Foundation
import ZIPFoundation

/// Many apps (TikTok and its injected variants) keep almost all Objective-C code in Frameworks/*.framework,
/// so the tiny main executable has no __objc_classname section. Reads class names from every framework binary
/// straight out of the IPA (streamed one at a time to a temp file, nothing else is extracted).
enum ForgeFrameworkClasses {
    static let maxBinary = 600 * 1024 * 1024
    static let maxFrameworks = 400
    static let maxClasses = 400_000

    static func classes(ipa: URL) -> [String] {
        guard let archive = try? Archive(url: ipa, accessMode: .read) else { return [] }
        var found = Set<String>()
        var count = 0
        for e in archive where e.type == .file {
            let p = e.path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
            guard p.count == 5, p[0] == "Payload", p[1].hasSuffix(".app"), p[2] == "Frameworks", p[3].hasSuffix(".framework") else { continue }
            let stem = String(p[3].dropLast(".framework".count))
            guard p[4] == stem, e.uncompressedSize <= UInt64(maxBinary) else { continue }
            count += 1
            if count > maxFrameworks || found.count >= maxClasses { break }
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("fwscan-" + UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: tmp) }
            guard (try? archive.extract(e, to: tmp)) != nil, let info = try? ForgeMachO.inspect(tmp), !info.encrypted else { continue }
            found.formUnion(info.classes)
        }
        return found.sorted()
    }
}
