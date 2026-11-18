import XCTest
import UIKit
import ZIPFoundation
@testable import Mirsa

@MainActor
final class TendieEditProjectTests: XCTestCase {
    private func image(_ c: UIColor) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 120, height: 240)).image { c.setFill(); $0.fill(CGRect(x: 0, y: 0, width: 120, height: 240)) }
    }
    private func layers() -> [WallpaperPhotoLayer] {
        var a = WallpaperPhotoLayer(image: image(.red), role: .background)
        var b = WallpaperPhotoLayer(image: image(.blue), role: .foreground)
        a.zoom = 1.5; a.x = 0.25; b.cutoutEnabled = false; b.scene = .lock; b.appearance = .dark; b.homeOffsetX = 0.5
        return [a, b]
    }

    func testProjectRoundTripKeepsEveryOption() throws {
        var fx = PhotoWallpaper.Effects(floating: true)
        fx.motion = .left; fx.particles = .snow; fx.particleDirection = .rising; fx.spin = true; fx.blur = true; fx.blend = .screen
        let name = "RoundTrip-\(UUID().uuidString).tendies"
        try TendieProjectStore.save(layers: layers(), crop: false, depth: true, effects: fx, forFileName: name)
        let load = try TendieProjectStore.loadProject(forFileName: name)
        XCTAssertEqual(load.effects, fx)
        XCTAssertFalse(load.crop); XCTAssertTrue(load.depth); XCTAssertFalse(load.effectsUnknown)
        XCTAssertEqual(load.layers.count, 2)
        XCTAssertEqual(load.layers[0].zoom, 1.5); XCTAssertEqual(load.layers[0].x, 0.25)
        XCTAssertEqual(load.layers[1].scene, .lock); XCTAssertEqual(load.layers[1].appearance, .dark)
        XCTAssertEqual(load.layers[1].homeOffsetX, 0.5); XCTAssertFalse(load.layers[1].cutoutEnabled)
        XCTAssertEqual(load.layers.map(\.role), [.background, .foreground])
        // Saving again must not compound anything: originals are stored as given.
        try TendieProjectStore.save(layers: load.layers, crop: load.crop, depth: load.depth, effects: load.effects, forFileName: name)
        XCTAssertEqual(try TendieProjectStore.loadProject(forFileName: name).effects, fx)
        TendieProjectStore.prune(keeping: [])
        XCTAssertFalse(TendieProjectStore.hasProject(forFileName: name))
    }

    func testMissingProjectIsNotEditable() {
        XCTAssertThrowsError(try TendieProjectStore.loadProject(forFileName: "nope-\(UUID().uuidString)")) {
            XCTAssertEqual($0 as? TendieEditError, .notEditable)
        }
    }

    func testLegacyArchiveLoadsLayers() throws {
        let url = try PhotoWallpaper.makeArchive(layers: layers(), screenAspect: 0.46, depth: true,
                                                 effects: PhotoWallpaper.Effects(floating: true))
        defer { try? FileManager.default.removeItem(at: url) }
        let load = try TendieProjectStore.loadLegacyArchive(url)
        XCTAssertEqual(load.layers.count, 2)
        XCTAssertEqual(Set(load.layers.map(\.role)), [.background, .foreground])
        XCTAssertTrue(load.effectsUnknown)
    }

    func testForeignAndUnsafeArchivesAreNotEditable() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let foreign = dir.appendingPathComponent("foreign.tendies")
        let archive = try Archive(url: foreign, accessMode: .create)
        let data = Data("hello".utf8)
        try archive.addEntry(with: "readme.txt", type: .file, uncompressedSize: Int64(data.count)) { pos, size in
            data.subdata(in: Int(pos)..<Int(pos) + size)
        }
        XCTAssertThrowsError(try TendieProjectStore.loadLegacyArchive(foreign))
        let traversal = dir.appendingPathComponent("trav.tendies")
        let t = try Archive(url: traversal, accessMode: .create)
        try t.addEntry(with: "../evil.txt", type: .file, uncompressedSize: Int64(data.count)) { pos, size in
            data.subdata(in: Int(pos)..<Int(pos) + size)
        }
        XCTAssertThrowsError(try TendieProjectStore.loadLegacyArchive(traversal))
        XCTAssertThrowsError(try TendieProjectStore.loadLegacyArchive(dir.appendingPathComponent("missing.tendies")))
    }

    func testReplaceKeepsSingleRowSameIdentity() async throws {
        let vm = AppViewModel()
        let first = try PhotoWallpaper.makeArchive(layers: layers(), screenAspect: 0.46)
        let ids = await vm.importTendieFiles(urls: [first])
        XCTAssertEqual(ids.count, 1)
        var item = try XCTUnwrap(vm.tendieItems.first { $0.id == ids[0] })
        item.isSelected = false
        let index = try XCTUnwrap(vm.tendieItems.firstIndex { $0.id == item.id })
        vm.tendieItems[index].isSelected = false
        let before = vm.tendieItems.count
        let second = try PhotoWallpaper.makeArchive(layers: layers(), screenAspect: 0.46, depth: true,
                                                    effects: PhotoWallpaper.Effects(floating: true))
        let ok = await vm.replaceTendie(item: item, with: second)
        XCTAssertTrue(ok)
        XCTAssertEqual(vm.tendieItems.count, before)
        let after = try XCTUnwrap(vm.tendieItems.first { $0.fileName == item.fileName })
        XCTAssertEqual(after.id, item.id); XCTAssertFalse(after.isSelected)
        XCTAssertTrue(FileManager.default.fileExists(atPath: after.fileURL.path))
        vm.deleteTendie(item: after)
    }

    func testDocumentsReimportPreservesCurrentIdentityAndSelection() async throws {
        let vm = AppViewModel()
        let archive = try PhotoWallpaper.makeArchive(layers: layers(), screenAspect: 0.46)
        defer { try? FileManager.default.removeItem(at: archive) }
        let ids = await vm.importTendieFiles(urls: [archive])
        let id = try XCTUnwrap(ids.first)
        let index = try XCTUnwrap(vm.tendieItems.firstIndex { $0.id == id })
        vm.tendieItems[index].name = "My edited wallpaper"
        vm.tendieItems[index].isSelected = false
        let original = vm.tendieItems[index]
        defer { vm.deleteTendie(item: original) }
        // The scanner imports a stored URL after its detached discovery returns.
        let rescanned = await vm.importTendieFiles(urls: [original.fileURL])
        XCTAssertEqual(rescanned, [id])
        let current = try XCTUnwrap(vm.tendieItems.first { $0.id == id })
        XCTAssertEqual(current.name, original.name)
        XCTAssertFalse(current.isSelected)
        XCTAssertEqual(vm.tendieItems.filter { $0.fileName == original.fileName }.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: current.fileURL.path))
    }

    func testRejectedSameNameImportDoesNotOverwriteWorkingArchive() async throws {
        let vm = AppViewModel()
        let archive = try PhotoWallpaper.makeArchive(layers: layers(), screenAspect: 0.46)
        defer { try? FileManager.default.removeItem(at: archive) }
        let ids = await vm.importTendieFiles(urls: [archive])
        let item = try XCTUnwrap(vm.tendieItems.first { $0.id == ids.first })
        defer { vm.deleteTendie(item: item) }
        let before = try Data(contentsOf: item.fileURL)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let rejected = root.appendingPathComponent(item.fileName)
        let zip = try Archive(url: rejected, accessMode: .create)
        let data = Data("No wallpaper descriptor".utf8)
        try zip.addEntry(with: "readme.txt", type: .file, uncompressedSize: Int64(data.count)) { pos, size in
            data.subdata(in: Int(pos)..<Int(pos) + size)
        }
        do {
            _ = try await TendiesEngine.shared.importTendie(from: rejected)
            XCTFail("A descriptor-free archive must be rejected")
        } catch { }
        XCTAssertEqual(try Data(contentsOf: item.fileURL), before)
        let replaced = await vm.replaceTendie(item: item, with: rejected)
        XCTAssertFalse(replaced)
        XCTAssertEqual(try Data(contentsOf: item.fileURL), before)
    }

    func testReplacingDeletedRowDoesNotResurrectFile() async throws {
        let vm = AppViewModel()
        let archive = try PhotoWallpaper.makeArchive(layers: layers(), screenAspect: 0.46)
        defer { try? FileManager.default.removeItem(at: archive) }
        let ids = await vm.importTendieFiles(urls: [archive])
        let item = try XCTUnwrap(vm.tendieItems.first { $0.id == ids.first })
        vm.deleteTendie(item: item)
        let replacement = try PhotoWallpaper.makeArchive(layers: layers(), screenAspect: 0.46, depth: true)
        defer { try? FileManager.default.removeItem(at: replacement) }
        let replaced = await vm.replaceTendie(item: item, with: replacement)
        XCTAssertFalse(replaced)
        XCTAssertFalse(vm.tendieItems.contains { $0.id == item.id })
        XCTAssertFalse(FileManager.default.fileExists(atPath: item.fileURL.path))
    }

    func testStringsExistInAllFiveLanguages() {
        for key in [WallpaperMakerStrings.Key.editing, .editHelp, .editCancel, .saveEdit, .editLegacy, .editSaved, .editButton, .notEditable] {
            let all = WallpaperMakerStrings.values[key]
            XCTAssertEqual(all?.count, 5)
            XCTAssertTrue(all?.allSatisfy { !$0.isEmpty } ?? false)
        }
    }
}
