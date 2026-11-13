import Foundation

/// Import never changes history, enables a tweak, or executes it.
/// The caller owns the returned temporary file and must delete it after persisting/cancelling.
enum ForgeDylibImporter {
    static func fromFile(_ url: URL) async throws -> (dylib: URL, info: ForgeDylibInfo) {
        // File-provider access must encompass the copy, not just the call that starts it.
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        return try await Task.detached(priority: .userInitiated) { try importLocal(url) }.value
    }

    static func fromURL(_ string: String) async throws -> (dylib: URL, info: ForgeDylibInfo) {
        guard let url = URL(string: string.trimmingCharacters(in: .whitespacesAndNewlines)) else { throw ForgeDylibImportError.invalidURL }
        try ForgeDylibDownload.validate(url)
        let temporary = try await ForgeDylibDownload.fetch(url)
        defer { try? FileManager.default.removeItem(at: temporary) }
        // Never trust a server-supplied filename, Content-Disposition or redirected suffix.
        return try await Task.detached(priority: .userInitiated) {
            try importLocal(temporary, type: url.pathExtension.lowercased())
        }.value
    }

    private static func importLocal(_ source: URL, type: String? = nil) throws -> (dylib: URL, info: ForgeDylibInfo) {
        let fm = FileManager.default
        let workspace = fm.temporaryDirectory.appendingPathComponent("mirsa-dylib-import-" + UUID().uuidString, isDirectory: true)
        var result: URL?
        defer {
            try? fm.removeItem(at: workspace)
        }
        do {
            try Task.checkCancellation()
            let ext = type ?? source.pathExtension.lowercased()
            guard ["dylib", "deb"].contains(ext) else { throw ForgeDylibImportError.unreadable }
            let values = try source.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true, let size = values.fileSize, size > 0 else { throw ForgeDylibImportError.unreadable }
            guard size <= ForgeDylibInspector.maximumBytes else { throw ForgeDylibImportError.tooLarge }
            try fm.createDirectory(at: workspace, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            let snapshot = workspace.appendingPathComponent("source." + ext)
            // Copy a bounded stream, not FileManager.copyItem: providers can change size while copying.
            guard let input = InputStream(url: source), let output = OutputStream(url: snapshot, append: false) else { throw ForgeDylibImportError.unreadable }
            input.open(); output.open()
            defer { input.close(); output.close() }
            var buffer = [UInt8](repeating: 0, count: 64 * 1024)
            var copied = 0
            while true {
                try Task.checkCancellation()
                let count = input.read(&buffer, maxLength: buffer.count)
                guard count >= 0 else { throw ForgeDylibImportError.unreadable }
                if count == 0 { break }
                guard count <= ForgeDylibInspector.maximumBytes - copied else { throw ForgeDylibImportError.tooLarge }
                copied += count
                try buffer.withUnsafeBufferPointer { raw in
                    var offset = 0
                    while offset < count {
                        let n = output.write(raw.baseAddress!.advanced(by: offset), maxLength: count - offset)
                        guard n > 0 else { throw ForgeDylibImportError.unreadable }
                        offset += n
                    }
                }
            }
            output.close(); input.close()
            guard copied > 0 else { throw ForgeDylibImportError.unreadable }
            // Sniff bytes independently of suffix or MIME. A renamed binary/package remains safe to inspect.
            let head = try FileHandle(forReadingFrom: snapshot)
            let signature = try head.read(upToCount: 8) ?? Data()
            try head.close()
            let isDeb = signature == Data("!<arch>\n".utf8)
            let machoMagic = Array(signature.prefix(4))
            let isMachO = [[UInt8](arrayLiteral: 0xcf, 0xfa, 0xed, 0xfe),
                           [0xca, 0xfe, 0xba, 0xbe], [0xca, 0xfe, 0xba, 0xbf],
                           [0xbe, 0xba, 0xfe, 0xca], [0xbf, 0xba, 0xfe, 0xca]].contains(machoMagic)
            guard isDeb || isMachO else { throw ForgeDylibImportError.invalidBinary }
            let library = isDeb ? try ForgeDylibDebImport.extract(snapshot, in: workspace) : snapshot
            let data = try Data(contentsOf: library, options: [.mappedIfSafe])
            let info = try ForgeDylibInspector.inspect(data)
            try Task.checkCancellation()
            let destination = fm.temporaryDirectory.appendingPathComponent("mirsa-imported-" + UUID().uuidString + ".dylib")
            result = destination
            try fm.moveItem(at: library, to: destination)
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
            return (destination, info)
        } catch {
            if let result { try? fm.removeItem(at: result) }
            if error is CancellationError { throw ForgeDylibImportError.cancelled }
            if let known = error as? ForgeDylibImportError { throw known }
            throw ForgeDylibImportError.unreadable
        }
    }
}
