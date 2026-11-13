import Foundation
import UniformTypeIdentifiers

/// Picker types for IPA files: the real IPA types plus a broad fallback (files may be untyped), validated after picking.
enum IPAPick {
    static var types: [UTType] {
        [UTType("com.apple.itunes.ipa"), UTType(filenameExtension: "ipa"), .zip, .data].compactMap { $0 }
    }
    enum Failure: LocalizedError {
        case notIPA
        var errorDescription: String? { tr("Please choose a .ipa file.", "اختار ملف بصيغة ipa.", ckb: "فایلی ipa هەڵبژێرە.", kmr: "Pelgeyek ipa hilbijêre.") }
    }
    /// Copies the picked file into a private temp location while access is open (iCloud download via coordination, streamed copy).
    static func privateCopy(_ url: URL) async throws -> URL {
        guard url.pathExtension.lowercased() == "ipa" else { throw Failure.notIPA }
        return try await Task.detached(priority: .userInitiated) {
            let scoped = url.startAccessingSecurityScopedResource(); defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ipa-pick-" + UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let dest = dir.appendingPathComponent(url.lastPathComponent)
            var coordErr: NSError?; var copyErr: Error?
            NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordErr) { src in
                do { try FileManager.default.copyItem(at: src, to: dest) } catch { copyErr = error }
            }
            if let e = coordErr ?? copyErr { try? FileManager.default.removeItem(at: dir); throw e }
            guard let h = try? FileHandle(forReadingFrom: dest), let magic = try? h.read(upToCount: 2), magic == Data([0x50, 0x4B]) else {
                try? FileManager.default.removeItem(at: dir); throw Failure.notIPA
            }
            try? h.close()
            return dest
        }.value
    }
}
