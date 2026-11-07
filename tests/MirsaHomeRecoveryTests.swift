import XCTest
import SwiftUI
@testable import Mirsa

@MainActor
final class MirsaHomeRecoveryTests: XCTestCase {
    func testBothHomesPersistReorderAndKeepFolderAndHiddenItems() throws {
        let name = "home-recovery-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        for namespace in ["main", "personal"] {
            let store = MirsaHomeLayoutStore(namespace: namespace, defaults: defaults)
            store.reconcile(visible: ["a", "b", "c", "d", "e"], all: ["a", "b", "c", "d", "e"])
            store.mutate { _ = $0.drop("app:d", onto: "app:e", newFolderID: "folder") }
            store.mutate { XCTAssertTrue($0.move("app:c", before: "app:a")) }
            let reloaded = MirsaHomeLayoutStore(namespace: namespace, defaults: defaults)
            XCTAssertEqual(reloaded.layout.items.map(\.id), ["app:c", "app:a", "app:b", "folder:folder"])
            reloaded.reconcile(visible: ["c", "a", "d", "e"], all: ["a", "b", "c", "d", "e"])
            XCTAssertEqual(reloaded.layout.folder("folder")?.appIDs, ["e", "d"])
            XCTAssertTrue(reloaded.layout.allAppIDs.contains("b"))
        }
    }

    func testDecodedIconSurvivesMissingFileAndChangesOnlyWithNewRevision() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
        defer { try? FileManager.default.removeItem(at: url) }
        func png(_ color: UIColor) -> Data {
            UIGraphicsImageRenderer(size: CGSize(width: 64, height: 64)).pngData { ctx in
                color.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
            }
        }
        let id = UUID().uuidString
        try png(.red).write(to: url)
        let first = try XCTUnwrap(MirsaIconCache.image(id: id, path: url.path))
        for _ in 0..<200 {
            XCTAssertTrue(MirsaIconCache.image(id: id, path: url.path) === first)
        }
        try FileManager.default.removeItem(at: url)
        XCTAssertTrue(MirsaIconCache.image(id: id, path: url.path) === first)
        try png(.blue).write(to: url)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(5)], ofItemAtPath: url.path)
        XCTAssertFalse(MirsaIconCache.image(id: id, path: url.path) === first)
    }
}
