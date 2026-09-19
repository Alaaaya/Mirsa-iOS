//
//  TendiesEngine.swift
//  AirCard-iOS
//
//  Engine for parsing, extracting, and flashing PosterBoard .tendies wallpapers.
//

import UIKit
import Foundation
import AirliftFFI

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

        let extractRC = destinationURL.path.withCString { arcC in
            tempExtractDir.path.withCString { dstC in
                al_zip_extract_all(arcC, dstC)
            }
        }

        guard extractRC == 0 else {
            throw NSError(
                domain: "TendiesEngine",
                code: Int(extractRC),
                userInfo: [NSLocalizedDescriptionKey: "Failed to extract .tendies zip archive (code \(extractRC))"]
            )
        }

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
                posterType = .container
                if nameLower.contains("pbfposterextensiondatastoresqlitedatabase.sqlite3") {
                    unsafeContainer = true
                }
            }

            if pathLower.contains("descriptor") || pathLower.contains("descriptors") {
                if pathLower.contains("video") || pathLower.contains("photos") {
                    posterType = .suggestedPhotos
                } else if pathLower.contains("mercury") {
                    posterType = .mercury
                } else if posterType != .container {
                    posterType = .collections
                }
            }

            // Count descriptors by finding .wallpaper or sub-descriptor folders
            if nameLower.hasSuffix(".wallpaper") || nameLower == "wallpaper.plist" {
                descriptorCount += 1
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

        if descriptorCount == 0 {
            descriptorCount = 1
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
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var outContainer: UnsafeMutablePointer<CChar>? = nil
                var outError: UnsafeMutablePointer<CChar>? = nil

                let rc = pairingPath.withCString { pairC in
                    "com.apple.PosterBoard".withCString { bundleC in
                        al_find_app_container(pairC, bundleC, nil, nil, &outContainer, &outError)
                    }
                }

                if rc == 0, let p = outContainer {
                    let containerStr = String(cString: p)
                    al_string_free(p)
                    continuation.resume(returning: containerStr)
                } else {
                    let errStr = outError.flatMap { p in
                        let s = String(cString: p)
                        al_string_free(p)
                        return s
                    } ?? "Failed to find PosterBoard container"
                    continuation.resume(throwing: NSError(
                        domain: "TendiesEngine",
                        code: Int(rc),
                        userInfo: [NSLocalizedDescriptionKey: errStr]
                    ))
                }
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
        guard !items.isEmpty else {
            log("⚠️ No wallpapers selected to flash")
            return
        }

        var normalizedContainer = containerPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalizedContainer.hasSuffix("/") {
            normalizedContainer = String(normalizedContainer.dropLast())
        }
        if normalizedContainer.isEmpty {
            throw NSError(
                domain: "TendiesEngine",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "PosterBoard Container path is required."]
            )
        }

        let majorVer = ProcessInfo.processInfo.operatingSystemVersion.majorVersion
        let structVersion = (majorVer <= 16) ? 59 : 61
        let versionsToWrite: [Int] = (majorVer >= 17) ? [61, 59] : [59]

        log("🚀 Starting PosterBoard injection into \(normalizedContainer)")
        log("ℹ️ Target PosterBoard structure version: \(structVersion) (iOS \(majorVer))")

        let totalItems = Double(items.count)

        for (itemIndex, item) in items.enumerated() {
            log("\n📦 [\(itemIndex + 1)/\(items.count)] Processing '\(item.name)'…")

            let tempStageDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("tendie_flash_\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: tempStageDir, withIntermediateDirectories: true)
            defer {
                try? FileManager.default.removeItem(at: tempStageDir)
            }

            let extractRC = item.fileURL.path.withCString { arcC in
                tempStageDir.path.withCString { dstC in
                    al_zip_extract_all(arcC, dstC)
                }
            }
            guard extractRC == 0 else {
                log("❌ Failed to extract '\(item.name)'")
                continue
            }

            if item.isContainer {
                log("  📁 Packaging App Container structure…")
                let containerFolder = tempStageDir.appendingPathComponent("container")
                let srcDir = FileManager.default.fileExists(atPath: containerFolder.path) ? containerFolder : tempStageDir

                try await writeDirectoryTree(
                    sourceBaseDir: srcDir,
                    targetBaseDir: normalizedContainer,
                    pairingPath: pairingPath,
                    log: log
                )
            } else {
                log("  🖼 Packaging Poster Descriptors…")
                let descriptorFolders = findDescriptorFolders(in: tempStageDir)

                if descriptorFolders.isEmpty {
                    log("  ⚠️ No descriptor directory found, flashing root contents…")
                    for sVer in versionsToWrite {
                        let targetDescDir = "\(normalizedContainer)/Library/Application Support/PRBPosterExtensionDataStore/\(sVer)/Extensions/\(item.posterType.extensionBundleId)/descriptors/\(UUID().uuidString.uppercased())"
                        try await writeDirectoryTree(
                            sourceBaseDir: tempStageDir,
                            targetBaseDir: targetDescDir,
                            pairingPath: pairingPath,
                            log: log
                        )
                    }
                } else {
                    for descURL in descriptorFolders {
                        let newUUID = UUID().uuidString.uppercased()
                        let randomizedID = Int.random(in: 10000...99999)
                        log("  ✨ Descriptor \(newUUID) (ID: \(randomizedID))…")

                        // Update plist identifiers to prevent overlapping
                        updatePlistIdentifiers(in: descURL, randomizedID: randomizedID)

                        for sVer in versionsToWrite {
                            let targetDescDir = "\(normalizedContainer)/Library/Application Support/PRBPosterExtensionDataStore/\(sVer)/Extensions/\(item.posterType.extensionBundleId)/descriptors/\(newUUID)"
                            try await writeDirectoryTree(
                                sourceBaseDir: descURL,
                                targetBaseDir: targetDescDir,
                                pairingPath: pairingPath,
                                log: log
                            )
                        }
                    }
                }
            }

            progress(Double(itemIndex + 1) / (totalItems + (resetProtections ? 1 : 0)))
        }

        // Reset file protections if requested
        if resetProtections {
            log("\n🔄 Forcing PosterBoard cache refresh and file protections reset…")
            let stagePrefDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("tendie_pref_\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: stagePrefDir, withIntermediateDirectories: true)
            defer {
                try? FileManager.default.removeItem(at: stagePrefDir)
            }

            let prefPlistURL = stagePrefDir.appendingPathComponent("com.apple.PosterBoard.unprotectedUserDefaults.plist")
            let prefDict: [String: Any] = [
                "PBF_RESET_FILE_PROTECTIONS": true,
                "PBF_LOCALE_DID_CHANGE": false
            ]
            let plistData = try PropertyListSerialization.data(fromPropertyList: prefDict, format: .binary, options: 0)
            try plistData.write(to: prefPlistURL)

            let targetPrefDir = "\(normalizedContainer)/Library/Preferences"
            try await writeDirectoryTree(
                sourceBaseDir: stagePrefDir,
                targetBaseDir: targetPrefDir,
                pairingPath: pairingPath,
                log: log
            )

            // Also write to mobile global preferences for system daemon lookup
            let mobilePrefDir = "/var/mobile/Library/Preferences"
            try? await writeDirectoryTree(
                sourceBaseDir: stagePrefDir,
                targetBaseDir: mobilePrefDir,
                pairingPath: pairingPath,
                log: log
            )
            log("✅ PosterBoard preferences staged for reload")
        }

        progress(1.0)
        log("\n🎉 All wallpapers injected successfully! Open Lock Screen settings or long-press lockscreen to choose your new wallpaper.")
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

        for dir in dirsToWrite {
            var relPath = dir.path.replacingOccurrences(of: sourceBaseDir.path, with: "")
            relPath = relPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))

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

    // MARK: - Find Descriptors

    private func findDescriptorFolders(in rootURL: URL) -> [URL] {
        var results: [URL] = []
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        while let itemURL = enumerator.nextObject() as? URL {
            let nameLower = itemURL.lastPathComponent.lowercased()
            if nameLower == "descriptor" || nameLower == "descriptors" || nameLower.hasSuffix("descriptor") {
                // Get immediate children of this descriptor folder
                if let children = try? fileManager.contentsOfDirectory(at: itemURL, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) {
                    let subdirs = children.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false }
                    if !subdirs.isEmpty {
                        results.append(contentsOf: subdirs)
                    } else {
                        results.append(itemURL)
                    }
                }
            }
        }
        return results
    }

    // MARK: - Plist Identifier Randomization

    private func updatePlistIdentifiers(in folderURL: URL, randomizedID: Int) {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: folderURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        while let fileURL = enumerator.nextObject() as? URL {
            let fileName = fileURL.lastPathComponent

            if fileName == "com.apple.posterkit.provider.descriptor.identifier" {
                try? "\(randomizedID)".data(using: .utf8)?.write(to: fileURL)
            } else if fileName == "com.apple.posterkit.provider.contents.userInfo" {
                if let data = try? Data(contentsOf: fileURL),
                   var plist = (try? PropertyListSerialization.propertyList(from: data, options: .mutableContainers, format: nil)) as? [String: Any] {
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
}
