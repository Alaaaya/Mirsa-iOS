//
//  TendiesEngine.swift
//  AirCard-iOS
//
//  Engine for parsing, extracting, and flashing PosterBoard .tendies wallpapers.
//

import UIKit
import Foundation
import AirliftFFI
import ZIPFoundation

public final class TendiesEngine {
    public static let shared = TendiesEngine()

    public static var tendiesStorageDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("Tendies", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    // MARK: - Import & Parse

    public func importTendie(from sourceURL: URL) async throws -> TendieItem {
        let isSecurityScoped = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if isSecurityScoped {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        try validateArchive(sourceURL)
        let fileName = sourceURL.lastPathComponent
        let baseName = (fileName as NSString).deletingPathExtension
        let destinationURL = Self.tendiesStorageDirectory.appendingPathComponent(fileName)

        if sourceURL.standardizedFileURL.path != destinationURL.standardizedFileURL.path {
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try? FileManager.default.removeItem(at: destinationURL)
            }
            do {
                try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
            } catch {
                let fileData = try Data(contentsOf: sourceURL)
                try fileData.write(to: destinationURL, options: .atomic)
            }
        }

        guard FileManager.default.fileExists(atPath: destinationURL.path) else {
            throw NSError(
                domain: "TendiesEngine",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Failed to store wallpaper file at \(destinationURL.path)"]
            )
        }

        // Staging extraction to inspect contents
        let tempExtractDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("tendie_inspect_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempExtractDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempExtractDir)
        }

        try extractValidatedArchive(destinationURL, to: tempExtractDir)

        // Analyze file structure
        var isContainer = false
        var unsafeContainer = false
        var descriptorCount = 0
        var posterType: TendiePosterType = .collections

        let fileManager = FileManager.default
        let enumerator = fileManager.enumerator(
            at: tempExtractDir,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        )

        var candidateImages: [(url: URL, score: Int)] = []

        while let itemURL = enumerator?.nextObject() as? URL {
            let pathLower = itemURL.path.lowercased()
            let nameLower = itemURL.lastPathComponent.lowercased()

            if pathLower.contains("__macosx") || nameLower == ".ds_store" {
                continue
            }

            if pathLower.contains("/container/") || pathLower.hasSuffix("/container") {
                isContainer = true
                if nameLower.contains("pbfposterextensiondatastoresqlitedatabase.sqlite3") {
                    unsafeContainer = true
                }
            }

            // Image discovery
            let ext = itemURL.pathExtension.lowercased()
            if ["heic", "png", "jpg", "jpeg"].contains(ext) {
                var score = 10
                if pathLower.contains("proxy") || pathLower.contains("adjusted") {
                    score += 90
                } else if pathLower.contains("background") || pathLower.contains("settling") {
                    score += 70
                } else if pathLower.contains("preview") || pathLower.contains("thumb") {
                    score += 50
                } else if pathLower.contains("asset.resource") {
                    score += 40
                }
                candidateImages.append((itemURL, score))
            }
        }

        // Use findDescriptorsWithExtensions to get accurate descriptor count and poster type
        let foundDescriptors = findDescriptorsWithExtensions(in: tempExtractDir, defaultExt: "com.apple.WallpaperKit.CollectionsPoster")
        guard !foundDescriptors.isEmpty else { throw PosterBoardStore.failure("Archive contains no wallpaper descriptors.") }
        descriptorCount = foundDescriptors.count

        if let first = foundDescriptors.first {
            if first.ext == "com.apple.MercuryPoster" || first.ext == "com.apple.Posters.MercuryPosterApp" {
                posterType = .mercury
            } else if first.ext == "com.apple.PhotosUIPrivate.PhotosPosterProvider" {
                posterType = .suggestedPhotos
            } else {
                posterType = isContainer ? .container : .collections
            }
        } else if isContainer {
            posterType = .container
        }

        // Pick best preview image
        candidateImages.sort { $0.score > $1.score }
        var previewData: Data? = nil

        for candidate in candidateImages {
            if let img = UIImage(contentsOfFile: candidate.url.path) {
                let thumb = self.downsample(image: img, maxDimension: 600)
                if let jpeg = thumb.jpegData(compressionQuality: 0.85) {
                    previewData = jpeg
                    break
                }
            }
        }

        return TendieItem(
            name: baseName,
            fileName: fileName,
            relativePath: fileName,
            isContainer: isContainer,
            unsafeContainer: unsafeContainer,
            descriptorCount: descriptorCount,
            posterType: posterType,
            previewImageData: previewData,
            dateImported: Date(),
            isSelected: true
        )
    }

    /// Validate before either import or flash invokes the native ZIP extractor.
    func validateArchive(_ url: URL) throws {
        try validateEntries(Archive(url: url, accessMode: .read))
    }

    private func validateEntries(_ archive: Archive) throws {
        var total: UInt64 = 0, count = 0
        var paths = Set<String>()
        for entry in archive {
            count += 1
            let size = UInt64(entry.uncompressedSize)
            guard size <= 536_870_912, total <= 536_870_912 - size else {
                throw PosterBoardStore.failure("Oversized wallpaper archive.")
            }
            total += size
            let canonicalEntry = entry.type == .directory && entry.path.hasSuffix("/")
                ? String(entry.path.dropLast()) : entry.path
            let parts = canonicalEntry.split(separator: "/", omittingEmptySubsequences: false)
            guard !canonicalEntry.isEmpty, !parts.contains(""), !parts.contains(where: { $0.contains(":") }),
                  !entry.path.isEmpty, !entry.path.hasPrefix("/"), !entry.path.contains("\\"),
                  !entry.path.contains("\0"), !parts.contains(".."), !parts.contains("."),
                  entry.type == .file || entry.type == .directory,
                  paths.insert(canonicalEntry.precomposedStringWithCanonicalMapping.lowercased()).inserted, count <= 8192 else {
                throw PosterBoardStore.failure("Unsafe wallpaper archive.")
            }
        }
        guard count > 0 else { throw PosterBoardStore.failure("Empty wallpaper archive.") }
    }

    /// The validated parser also extracts, so native parser disagreements cannot
    /// turn a checked pathname into an unchecked filesystem write.
    func extractValidatedArchive(_ url: URL, to root: URL) throws {
        let archive = try Archive(url: url, accessMode: .read)
        try validateEntries(archive)
        let fm = FileManager.default
        var actualTotal: UInt64 = 0
        for entry in archive {
            let parts = entry.path.split(separator: "/")
            let hiddenJunk = parts.contains { part in
                part == "__MACOSX" || (part.hasPrefix(".") &&
                    part != ".com.apple.posterkit.provider.contents.configurableOptions.plist")
            }
            if hiddenJunk { continue }
            let target = root.appendingPathComponent(entry.path)
            if entry.type == .directory {
                try fm.createDirectory(at: target, withIntermediateDirectories: true)
                continue
            }
            try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            guard fm.createFile(atPath: target.path, contents: nil) else {
                throw PosterBoardStore.failure("Cannot create wallpaper file.")
            }
            let handle = try FileHandle(forWritingTo: target)
            defer { try? handle.close() }
            var actualSize: UInt64 = 0
            let checksum = try archive.extract(entry) { chunk in
                let next = UInt64(chunk.count)
                guard actualSize <= UInt64(entry.uncompressedSize),
                      next <= UInt64(entry.uncompressedSize) - actualSize,
                      actualTotal <= 536_870_912, next <= 536_870_912 - actualTotal else {
                    throw PosterBoardStore.failure("Oversized wallpaper data.")
                }
                actualSize += next
                actualTotal += next
                try handle.write(contentsOf: chunk)
            }
            guard actualSize == UInt64(entry.uncompressedSize), checksum == entry.checksum else {
                throw PosterBoardStore.failure("Wallpaper checksum mismatch.")
            }
        }
    }

    // MARK: - Downsample Thumbnail

    private func downsample(image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        let maxSide = max(size.width, size.height)
        guard maxSide > maxDimension else { return image }

        let scale = maxDimension / maxSide
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)

        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }

    // MARK: - Auto-detect PosterBoard Container

    public func detectPosterBoardContainer(pairingPath: String) async throws -> String {
        // Local package installation must remain local on offline/cellular.
        // Access/entitlement failure is not a tunnel or Wi-Fi problem.
        return try await Task.detached(priority: .userInitiated) {
            try PosterBoardStore.discover(cached: UserDefaults.standard.string(forKey: "aircard.posterboard_container"))
        }.value
    }

    // MARK: - Send Respring Signal via Tunnel

    public func sendRespringSignal(pairingPath: String) async -> Bool {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var outError: UnsafeMutablePointer<CChar>? = nil
                let rc = pairingPath.withCString { pC in
                    al_device_respring(pC, nil, nil, &outError)
                }
                if let p = outError {
                    al_string_free(p)
                }
                continuation.resume(returning: rc == 0)
            }
        }
    }

    // MARK: - Flash Tendies to Device

    public func flashTendies(
        items: [TendieItem],
        containerPath: String,
        resetProtections: Bool,
        pairingPath: String,
        log: @escaping (String) -> Void,
        progress: @escaping (Double) -> Void
    ) async throws {
        // Completion means byte-for-byte verified copy, not unobserved gallery registration.
        guard !items.isEmpty else { throw PosterBoardStore.failure("No wallpapers selected.") }
        let normalized = try PosterBoardStore.canonicalContainer(containerPath)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let lease = try PosterBoardLease(path: normalized, log: log)
                    defer { try? lease.close() }
                    try withExtendedLifetime(lease) {
                        let container = lease.effectiveURL
                        try PosterBoardStore.validateIdentity(container, lease: lease, log: log)
                        let fm = FileManager.default
                        let stage = fm.temporaryDirectory.appendingPathComponent("tendie_flash_" + UUID().uuidString)
                        try fm.createDirectory(at: stage, withIntermediateDirectories: true)
                        defer { try? fm.removeItem(at: stage) }
                        var all: [(url: URL, ext: String)] = []
                        for (index, item) in items.enumerated() {
                            try self.validateArchive(item.fileURL)
                            let folder = stage.appendingPathComponent(String(index))
                            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
                            try self.extractValidatedArchive(item.fileURL, to: folder)
                            let found = self.findDescriptorsWithExtensions(in: folder, defaultExt: item.posterType.extensionBundleId)
                            guard !found.isEmpty else { throw PosterBoardStore.failure("Archive contains no wallpaper descriptors.") }
                            // Each application owns fresh identities; the source archive stays immutable.
                            let prepared = stage.appendingPathComponent("prepared-" + String(index), isDirectory: true)
                            try fm.createDirectory(at: prepared, withIntermediateDirectories: true)
                            for descriptor in found {
                                let fresh = try self.prepareDescriptor(descriptor.url, in: prepared)
                                all.append((url: fresh, ext: descriptor.ext))
                            }
                            progress(Double(index + 1) / Double(items.count + 1))
                        }
                        let backupRoot = fm.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("TendiesBackups")
                        let copies = try PosterBoardStore.install(all, container: container, resetProtections: resetProtections,
                                                                 backupRoot: backupRoot, lease: lease, log: log)
                        log("Verified \(copies) descriptor copies. Gallery registration is not yet verified on this device.")
                        progress(1)
                    }
                    try lease.close()
                    continuation.resume()
                } catch { continuation.resume(throwing: error) }
            }
        }
    }

    /// Prepare an isolated new descriptor without changing the imported archive.
    /// Numeric wallpaper/provider identities are deliberately preserved together;
    /// only references to this descriptor's directory identity are replaced.
    func prepareDescriptor(_ source: URL, in stagingRoot: URL) throws -> URL {
        let fm = FileManager.default
        _ = try PosterBoardStore.manifest(source) // rejects every symlink, including hidden ones
        let oldID = source.lastPathComponent
        let newID = UUID().uuidString
        let destination = stagingRoot.appendingPathComponent(newID, isDirectory: true)
        try fm.createDirectory(at: destination, withIntermediateDirectories: false)
        do {
            var scanError: Error?
            guard let scan = fm.enumerator(at: source, includingPropertiesForKeys: [.isDirectoryKey],
                                           errorHandler: { _, error in scanError = error; return false }) else {
                throw PosterBoardStore.failure("Cannot enumerate wallpaper descriptor.")
            }
            for case let file as URL in scan {
                let name = file.lastPathComponent
                // This dot-prefixed Apple plist is functional, not Finder debris.
                let allowedHidden = name == ".com.apple.posterkit.provider.contents.configurableOptions.plist"
                if name == "__MACOSX" || (name.hasPrefix(".") && !allowedHidden) {
                    if (try file.resourceValues(forKeys: [.isDirectoryKey])).isDirectory == true { scan.skipDescendants() }
                    continue
                }
                let relative = String(file.path.dropFirst(source.path.count + 1))
                let target = destination.appendingPathComponent(relative)
                if (try file.resourceValues(forKeys: [.isDirectoryKey])).isDirectory == true {
                    try fm.createDirectory(at: target, withIntermediateDirectories: true)
                    continue
                }
                try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                let original = try Data(contentsOf: file)
                let bytes: Data
                if let object = try? PropertyListSerialization.propertyList(from: original, format: nil) {
                    let updated = remapDescriptorIdentity(object, oldID: oldID, newID: newID)
                    bytes = try PropertyListSerialization.data(fromPropertyList: updated, format: .binary, options: 0)
                } else if let text = String(data: original, encoding: .utf8) {
                    bytes = Data(remapDescriptorString(text, oldID: oldID, newID: newID).utf8)
                } else {
                    bytes = original
                }
                try bytes.write(to: target, options: .atomic)
            }
            if let scanError { throw scanError }
            _ = try PosterBoardStore.manifest(destination)
            return destination
        } catch {
            try? fm.removeItem(at: destination)
            throw error
        }
    }

    private func remapDescriptorString(_ value: String, oldID: String, newID: String) -> String {
        if value == oldID { return newID }
        // A UUID is unambiguous even embedded in archived URL strings. Do not
        // globally replace short package names/numbers in artwork or metadata.
        if UUID(uuidString: oldID) != nil {
            return value.replacingOccurrences(of: oldID, with: newID, options: .caseInsensitive)
        }
        return value.replacingOccurrences(of: "/" + oldID + "/", with: "/" + newID + "/")
    }

    private func remapDescriptorIdentity(_ object: Any, oldID: String, newID: String) -> Any {
        if let string = object as? String {
            return remapDescriptorString(string, oldID: oldID, newID: newID)
        }
        if let array = object as? [Any] {
            return array.map { remapDescriptorIdentity($0, oldID: oldID, newID: newID) }
        }
        if let dictionary = object as? [String: Any] {
            // Keyed-archive UIDs, numeric wallpaper IDs and all non-string values
            // survive unchanged. Never partially randomize Wallpaper.plist.
            return dictionary.mapValues { remapDescriptorIdentity($0, oldID: oldID, newID: newID) }
        }
        return object
    }

    // MARK: - Tree Writer Helper

    private func writeDirectoryTree(
        sourceBaseDir: URL,
        targetBaseDir: String,
        pairingPath: String,
        log: @escaping (String) -> Void
    ) async throws {
        let fileManager = FileManager.default

        // Gather all directories that contain files
        var dirsToWrite: Set<URL> = []
        if let enumerator = fileManager.enumerator(
            at: sourceBaseDir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) {
            while let itemURL = enumerator.nextObject() as? URL {
                let isDir = (try? itemURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                if !isDir {
                    dirsToWrite.insert(itemURL.deletingLastPathComponent())
                }
            }
        }

        // If no subfiles, write the source dir itself if not empty
        if dirsToWrite.isEmpty {
            let files = (try? fileManager.contentsOfDirectory(atPath: sourceBaseDir.path)) ?? []
            if !files.isEmpty {
                dirsToWrite.insert(sourceBaseDir)
            }
        }

        let canonicalSource = sourceBaseDir.resolvingSymlinksInPath().path

        for dir in dirsToWrite {
            let canonicalDir = dir.resolvingSymlinksInPath().path
            var relPath = ""
            if canonicalDir.hasPrefix(canonicalSource) {
                relPath = String(canonicalDir.dropFirst(canonicalSource.count))
                relPath = relPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            }

            let targetDir: String
            if relPath.isEmpty {
                targetDir = targetBaseDir
            } else {
                targetDir = "\(targetBaseDir)/\(relPath)"
            }

            log("  Writing to \(targetDir)…")

            var writeOk = false
            var errDesc: String? = nil

            await withCheckedContinuation { cont in
                DispatchQueue.global(qos: .userInitiated).async {
                    var outError: UnsafeMutablePointer<CChar>? = nil
                    let rc = pairingPath.withCString { pairC in
                        dir.path.withCString { srcC in
                            targetDir.withCString { tgtC in
                                al_exploit_write_dir(pairC, srcC, tgtC, { _, msg in
                                    guard let msg = msg else { return }
                                    let line = String(cString: msg)
                                    DispatchQueue.main.async {
                                        AppViewModel.shared?.tendiesFlashLog.append("    " + line)
                                    }
                                }, nil, &outError)
                            }
                        }
                    }
                    if let p = outError {
                        errDesc = String(cString: p)
                        al_string_free(p)
                    }
                    writeOk = (rc == 0)
                    cont.resume()
                }
            }

            if !writeOk {
                throw NSError(
                    domain: "TendiesEngine",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Failed to write directory: \(errDesc ?? "exploit error")"]
                )
            }
        }
    }

    // MARK: - Plist Identifier Randomization (Matches Nugget implementation)

    func updatePlistIdentifiers(in folderURL: URL, randomizedID: Int) {
        // If suggestion metadata exists, the descriptor is pre-packaged with matching
        // descriptorIdentifier and wallpaper identifiers (e.g. 7400.DYNAMIC <-> 7400).
        // Randomizing only Wallpaper.plist desynchronizes PosterKit's suggestion lookup!
        let suggestionMetadataURL = folderURL.appendingPathComponent("com.apple.posterkit.provider.identifierURL.suggestionMetadata.plist")
        if FileManager.default.fileExists(atPath: suggestionMetadataURL.path) {
            return
        }

        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: folderURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        while let fileURL = enumerator.nextObject() as? URL {
            let fileName = fileURL.lastPathComponent

            if fileName == "com.apple.posterkit.provider.descriptor.identifier" {
                // IMPORTANT: ONLY randomize if the file content is a pure integer!
                // For extensions like Mercury, Unity, Kaleidoscope, descriptor identifiers are
                // required string symbols (e.g. "v6x.colorA", "Unity2025")!
                // Overwriting them breaks extension lookup!
                if let content = try? String(contentsOf: fileURL, encoding: .utf8),
                   let _ = Int(content.trimmingCharacters(in: .whitespacesAndNewlines)) {
                    try? "\(randomizedID)".data(using: .utf8)?.write(to: fileURL)
                }
            } else if fileName == "com.apple.posterkit.provider.contents.userInfo" {
                if let data = try? Data(contentsOf: fileURL),
                   var plist = (try? PropertyListSerialization.propertyList(from: data, options: .mutableContainers, format: nil)) as? [String: Any],
                   plist["wallpaperRepresentingIdentifier"] != nil {
                    plist["wallpaperRepresentingIdentifier"] = randomizedID
                    if let updated = try? PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0) {
                        try? updated.write(to: fileURL)
                    }
                }
            } else if fileName.hasSuffix("Wallpaper.plist") {
                if let data = try? Data(contentsOf: fileURL),
                   var plist = (try? PropertyListSerialization.propertyList(from: data, options: .mutableContainers, format: nil)) as? [String: Any] {
                    plist["identifier"] = randomizedID
                    if let updated = try? PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0) {
                        try? updated.write(to: fileURL)
                    }
                }
            }
        }
    }

    // MARK: - Folder Injector Helper (Single Atomic Move via AirTraffic)

    private func injectDescriptorFolder(
        folderURL: URL,
        targetParentDir: String,
        destName: String,
        pairingPath: String,
        log: @escaping (String) -> Void
    ) async throws {
        log("  📦 Injecting '\(destName)' into \(targetParentDir)…")
        var errDesc: String? = nil
        let ok: Bool = await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                var outError: UnsafeMutablePointer<CChar>? = nil
                let rc = pairingPath.withCString { pairC in
                    folderURL.path.withCString { folderC in
                        targetParentDir.withCString { parentC in
                            destName.withCString { destC in
                                al_exploit_inject_folder(
                                    pairC,
                                    folderC,
                                    parentC,
                                    destC,
                                    { _, msg in
                                        guard let msg = msg else { return }
                                        let line = String(cString: msg)
                                        DispatchQueue.main.async {
                                            AppViewModel.shared?.tendiesFlashLog.append("    " + line)
                                        }
                                    },
                                    nil,
                                    &outError
                                )
                            }
                        }
                    }
                }
                if let p = outError {
                    errDesc = String(cString: p)
                    al_string_free(p)
                }
                cont.resume(returning: rc == 0)
            }
        }

        if !ok {
            throw NSError(
                domain: "TendiesEngine",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Failed to inject descriptor: \(errDesc ?? "exploit error")"]
            )
        }
    }

    // MARK: - Find Descriptors With Targeted Extensions

    func isDescriptorFolder(_ url: URL) -> Bool {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else { return false }
        let name = url.lastPathComponent
        if name.hasPrefix(".") || name == "__MACOSX" { return false }

        // Must not be the container root or Library itself
        let ignoredNames: Set<String> = [
            "container", "library", "application support", "prbposterextensiondatastore",
            "extensions", "descriptors", "ordered-descriptors",
            "mercury-descriptors", "mercurydescriptors", "video-descriptors", "videodescriptors"
        ]
        if ignoredNames.contains(name.lowercased()) {
            return false
        }

        // 1. Has "versions" directory
        let versions = url.appendingPathComponent("versions")
        if fm.fileExists(atPath: versions.path) { return true }

        // 2. Has "providerInfo.plist"
        let providerInfo = url.appendingPathComponent("providerInfo.plist")
        if fm.fileExists(atPath: providerInfo.path) { return true }

        // 3. Has "com.apple.posterkit.provider.descriptor.identifier"
        let descId = url.appendingPathComponent("com.apple.posterkit.provider.descriptor.identifier")
        if fm.fileExists(atPath: descId.path) { return true }

        // 4. Has "Wallpaper.plist"
        let wallpaper = url.appendingPathComponent("Wallpaper.plist")
        if fm.fileExists(atPath: wallpaper.path) { return true }

        // 5. Ends with .wallpaper
        if url.pathExtension.lowercased() == "wallpaper" { return true }

        return false
    }

    func determineExtension(for folderURL: URL, defaultExt: String) -> String {
        let pathLower = folderURL.path.lowercased()

        // 1. Check path components for .../Extensions/<bundleID>/descriptors/<desc>
        let components = folderURL.pathComponents
        for i in 0..<components.count {
            if components[i].lowercased() == "extensions", i + 1 < components.count {
                let cand = components[i + 1]
                if cand.contains(".") {
                    return cand
                }
            }
            if components[i].lowercased() == "descriptors", i > 0 {
                let cand = components[i - 1]
                if cand.contains(".") && !cand.lowercased().contains("store") {
                    return cand
                }
            }
        }

        // 2. Check metadata inside suggestionMetadata.plist if present
        let metadataURL = folderURL.appendingPathComponent("com.apple.posterkit.provider.identifierURL.suggestionMetadata.plist")
        if let data = try? Data(contentsOf: metadataURL),
           let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
           let objects = plist["$objects"] as? [Any] {
            for obj in objects {
                if let str = obj as? String {
                    if str.hasPrefix("com.apple.") && str.contains("Poster") {
                        return str
                    }
                }
            }
        }

        // 3. Check descriptor identifier content (e.g. "v6x.colorA" or "v5..." -> Mercury)
        let descIdURL = folderURL.appendingPathComponent("com.apple.posterkit.provider.descriptor.identifier")
        if let descId = try? String(contentsOf: descIdURL, encoding: .utf8) {
            let trimmed = descId.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("v6") || trimmed.hasPrefix("v5") || trimmed.hasPrefix("v4") || trimmed.contains(".color") {
                return "com.apple.MercuryPoster"
            }
        }

        // 4. Path string hints
        if pathLower.contains("mercury") {
            return "com.apple.MercuryPoster"
        }
        if pathLower.contains("video") || pathLower.contains("photo") {
            return "com.apple.PhotosUIPrivate.PhotosPosterProvider"
        }
        if pathLower.contains("collection") || pathLower.contains("wallpaperkit") {
            return "com.apple.WallpaperKit.CollectionsPoster"
        }
        if pathLower.contains("kaleidoscope") {
            return "com.apple.Posters.KaleidoscopePosterApp.KaleidoscopePoster"
        }
        if pathLower.contains("unity") {
            return "com.apple.Posters.UnityPosterApp.UnityPosterExtension"
        }

        return defaultExt
    }

    public func findDescriptorsWithExtensions(in rootURL: URL, defaultExt: String) -> [(ext: String, url: URL)] {
        let fileManager = FileManager.default
        var results: [(ext: String, url: URL)] = []

        if isDescriptorFolder(rootURL) {
            let ext = determineExtension(for: rootURL, defaultExt: defaultExt)
            return [(ext: ext, url: rootURL)]
        }

        // Recursive traversal to discover all descriptor directories
        guard let enumerator = fileManager.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        while let itemURL = enumerator.nextObject() as? URL {
            var isDir: ObjCBool = false
            guard fileManager.fileExists(atPath: itemURL.path, isDirectory: &isDir), isDir.boolValue else { continue }
            if itemURL.lastPathComponent.hasPrefix(".") || itemURL.lastPathComponent == "__MACOSX" {
                enumerator.skipDescendants()
                continue
            }

            if isDescriptorFolder(itemURL) {
                let ext = determineExtension(for: itemURL, defaultExt: defaultExt)
                results.append((ext: ext, url: itemURL))
                enumerator.skipDescendants() // Do not look for nested descriptors inside a descriptor folder
            }
        }

        return results
    }
}
