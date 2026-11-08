import Foundation

enum ForgeDylibDebImport {
    /// Uses the existing Rust tar/ar/gzip/xz implementation. It rejects traversal,
    /// links, devices, case-colliding paths, excessive counts/expansion and never runs scripts.
    /// Output files remain inert. A single-package import never silently picks a library.
    static func extract(_ package: URL, in workspace: URL) throws -> URL {
        let extracted = workspace.appendingPathComponent("extracted", isDirectory: true)
        do { try IPAEditorService.run("deb_tweak", input: package, output: extracted) }
        catch { throw ForgeDylibImportError.unsafePackage }
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: extracted, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey],
                                             options: [], errorHandler: { _, _ in false }) else { throw ForgeDylibImportError.unsafePackage }
        var candidates: [URL] = []
        var count = 0
        while let url = enumerator.nextObject() as? URL {
            count += 1
            guard count <= 20_000 else { throw ForgeDylibImportError.unsafePackage }
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            guard values.isSymbolicLink != true else { throw ForgeDylibImportError.unsafePackage }
            if url.pathExtension.lowercased() == "dylib", values.isRegularFile == true {
                guard let size = values.fileSize, size <= ForgeDylibInspector.maximumBytes else { throw ForgeDylibImportError.tooLarge }
                candidates.append(url)
                if candidates.count > 1 { throw ForgeDylibImportError.multipleDylibs }
            }
        }
        guard let only = candidates.first else { throw ForgeDylibImportError.noDylib }
        return only
    }
}
