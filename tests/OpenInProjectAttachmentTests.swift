import XCTest
import SwiftUI
import UIKit
@testable import Mirsa

/// Runs the production snapshot, Rust importer, draft transaction and real sheet.
/// These tests do not claim Telegram/provider permission or physical-device coverage.
@MainActor
final class OpenInProjectAttachmentTests: XCTestCase {
    private var temporary: URL!
    private var savedItems: [IPATweak] = []
    private var projects: [PersonalLibraryApp] = []
    override func setUpWithError() throws {
        temporary = FileManager.default.temporaryDirectory.appendingPathComponent("attach-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws {
        for item in savedItems { try? IPATweakLibrary.shared.delete(item) }
        for app in projects { try? PersonalAppsLibrary.shared.delete(app) }
        try? FileManager.default.removeItem(at: temporary)
    }
    private func ownerZIP() throws -> URL {
        try XCTUnwrap(Bundle(for: Self.self).url(forResource: "OwnerTikTokV4", withExtension: "zip"))
    }
    private func code() throws -> Data {
        let zip = try ZipReader(data: Data(contentsOf: ownerZIP()))
        let entry = try XCTUnwrap(zip.entries.first { $0.name.hasSuffix(".dylib") })
        return try zip.read(entry, length: entry.uncompressedSize)
    }
    private func input(_ name: String, _ bytes: Data) throws -> URL {
        let file = temporary.appendingPathComponent(name)
        try bytes.write(to: file)
        return file
    }
    private func imported(_ url: URL) async throws -> IPATweak {
        let item = try await IPATweakLibrary.shared.addFile(url, allowSelection: true)
        savedItems.append(item)
        return item
    }
    private func project() async throws -> PersonalLibraryApp {
        let fixture = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "PersonalUIFixture", withExtension: "zip"))
        let file = try input(UUID().uuidString + ".ipa", Data(contentsOf: fixture))
        var added: PersonalLibraryApp?
        try await PersonalAppsLibrary.shared.add(file, signed: false) { added = $0 }
        let app = try XCTUnwrap(added)
        projects.append(app)
        return app
    }
    func testForeignFileRoutingPreservesIPAAndRejectsRemoteAndFramework() {
        for ext in ["dylib", "DEB", "zip"] { XCTAssertTrue(OpenInTweak.accepts(URL(fileURLWithPath: "/example." + ext))) }
        for ext in ["ipa", "framework", "txt"] { XCTAssertFalse(OpenInTweak.accepts(URL(fileURLWithPath: "/example." + ext))) }
        XCTAssertFalse(OpenInTweak.accepts(URL(string: "https://example.invalid/a.zip")!))
    }
    func testReadOnlyStagingRetainsNameAndSurvivesProviderDeletionThenCleans() throws {
        let bytes = try code()
        let file = try input("BHTikTokPlus.dylib", bytes)
        let copy = try OpenInTweak.snapshot(file)
        defer { OpenInTweak.remove(copy) }
        XCTAssertEqual(copy.lastPathComponent, file.lastPathComponent)
        XCTAssertEqual(try Data(contentsOf: file), bytes)
        try FileManager.default.removeItem(at: file)
        XCTAssertEqual(try Data(contentsOf: copy), bytes)
        OpenInTweak.remove(copy)
        XCTAssertFalse(FileManager.default.fileExists(atPath: copy.path))
    }
    func testStagingRejectsLinksDirectoriesEmptyAndOversize() throws {
        let valid = try input("valid.dylib", code())
        XCTAssertThrowsError(try OpenInTweak.snapshot(valid, maxBytes: 1), "A provider file cannot exceed its queued reservation")
        let link = temporary.appendingPathComponent("linked.dylib")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: valid)
        XCTAssertThrowsError(try OpenInTweak.snapshot(link))
        let dir = temporary.appendingPathComponent("folder.zip")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: false)
        XCTAssertThrowsError(try OpenInTweak.snapshot(dir))
        XCTAssertThrowsError(try OpenInTweak.snapshot(input("empty.deb", Data())))
        let large = try input("oversize.zip", Data([0]))
        let handle = try FileHandle(forWritingTo: large)
        try handle.truncate(atOffset: UInt64(128 * 1024 * 1024 + 1))
        try handle.close()
        XCTAssertThrowsError(try OpenInTweak.snapshot(large))
    }
    func testDylibImportUsesSecureProductionValidator() async throws {
        let item = try await imported(input("Example.dylib", code()))
        XCTAssertEqual(item.roots.count, 1)
        let stored = IPATweakLibrary.root.appendingPathComponent(item.id.uuidString).appendingPathComponent(item.roots[0])
        XCTAssertEqual(try Data(contentsOf: stored), try code())
        do {
            _ = try await imported(input("spoof.dylib", Data("not executable".utf8)))
            XCTFail("Invalid Mach-O must fail before it becomes a library item")
        } catch {}
    }
    func testDebAndZipUseSameSecureImporterAndSameTweakDylibWins() async throws {
        let bytes = try code()
        let deb = ForgeDeb.build(name: "Example", bundleID: "com.example.tweak", dylib: bytes)
        let package = try await imported(input("package.deb", deb))
        XCTAssertEqual(package.roots.count, 1)
        let tree = temporary.appendingPathComponent("bundle")
        try FileManager.default.createDirectory(at: tree, withIntermediateDirectories: false)
        try bytes.write(to: tree.appendingPathComponent("Example.dylib"))
        try deb.write(to: tree.appendingPathComponent("package.deb"))
        let archive = temporary.appendingPathComponent("bundle.zip")
        try BundleZipWriter.write(tree: tree, rootName: "bundle", to: archive)
        let zip = try await imported(archive)
        XCTAssertEqual(zip.roots.count, 1, "Only identical identity AND bytes may dedupe the package copy")
        XCTAssertTrue(zip.roots[0].hasSuffix("Example.dylib"))
    }
    func testMultipleCandidatesWaitForExplicitSelectionAndCancellationCleans() async throws {
        let tree = temporary.appendingPathComponent("multiple")
        try FileManager.default.createDirectory(at: tree, withIntermediateDirectories: false)
        for name in ["First.dylib", "Second.dylib"] { try code().write(to: tree.appendingPathComponent(name)) }
        let archive = temporary.appendingPathComponent("multiple.zip")
        try BundleZipWriter.write(tree: tree, rootName: "multiple", to: archive)
        let before = IPATweakLibrary.shared.items.map(\.id)
        let operation = Task { try await IPATweakLibrary.shared.addFile(archive, allowSelection: true) }
        defer { operation.cancel(); IPATweakLibrary.shared.cancelImport() }
        for _ in 0..<1000 {
            if IPATweakLibrary.shared.pendingImport != nil { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        let choice = try XCTUnwrap(IPATweakLibrary.shared.pendingImport)
        XCTAssertEqual(choice.candidates.count, 2)
        IPATweakLibrary.shared.finishImportSelection(nil)
        do { _ = try await operation.value; XCTFail("Cancel may not commit") } catch is CancellationError {} catch { XCTFail("\(error)") }
        XCTAssertEqual(IPATweakLibrary.shared.items.map(\.id), before)
        XCTAssertNil(IPATweakLibrary.shared.pendingImport)
        XCTAssertFalse(IPATweakLibrary.shared.importing)
    }
    func testMultiProjectAttachmentPreservesDraftOptionsAndCountsActualComponents() async throws {
        let one = try await project(), two = try await project()
        let item = try await imported(input("Example.dylib", code()))
        var before = try ProjectAttachmentStore.draft(one)
        before.name = "Edited name"
        before.fileSharing = true
        before.workspaceNote = "Keep my edits"
        try JSONEncoder().encode(before).write(to: PersonalAppsLibrary.shared.draftURL(one), options: .atomic)
        for app in [one, two] { try await ProjectAttachmentStore.attach([item], to: app) }
        let after = try ProjectAttachmentStore.draft(one)
        XCTAssertEqual(after.name, before.name)
        XCTAssertTrue(after.fileSharing)
        XCTAssertEqual(after.workspaceNote, before.workspaceNote)
        for app in [one, two] {
            let draft = try ProjectAttachmentStore.draft(app)
            XCTAssertEqual(draft.tweakIDs, [item.id])
            XCTAssertEqual(ProjectAttachmentStore.components(draft, items: IPATweakLibrary.shared.items).count, 1)
        }
    }
    func testPerProjectDuplicateIsIdempotentAndConflictingPayloadDoesNotWrite() async throws {
        let app = try await project()
        let first = try await imported(input("Same.dylib", code()))
        try await ProjectAttachmentStore.attach([first], to: app)
        let before = try ProjectAttachmentStore.draft(app)
        try await ProjectAttachmentStore.attach([first], to: app)
        XCTAssertEqual(try ProjectAttachmentStore.draft(app), before, "A repeat must not exclude the original component")
        let duplicate = try await imported(input("Same.dylib", code()))
        try await ProjectAttachmentStore.attach([duplicate], to: app)
        XCTAssertEqual(ProjectAttachmentStore.components(try ProjectAttachmentStore.draft(app), items: IPATweakLibrary.shared.items).count, 1)
        var changed = try code(); changed.append(0)
        let collision = try await imported(input("Same.dylib", changed))
        let file = PersonalAppsLibrary.shared.draftURL(app)
        let bytes = try Data(contentsOf: file)
        do { try await ProjectAttachmentStore.attach([collision], to: app); XCTFail("Conflicting identity must fail") } catch {}
        XCTAssertEqual(try Data(contentsOf: file), bytes, "Failed transaction may not partially mutate the project")
    }
    func testPendingEditorFlushBeforeAttachmentKeepsLatestEdits() async throws {
        let app = try await project()
        let item = try await imported(input("Latest.dylib", code()))
        let writer = PersonalProjectDraftWriter(delay: 5_000_000_000)
        var draft = try ProjectAttachmentStore.draft(app)
        draft.bundleID = "com.example.latest"
        writer.schedule(draft, to: PersonalAppsLibrary.shared.draftURL(app))
        try await ProjectAttachmentStore.attach([item], to: app)
        XCTAssertEqual(try ProjectAttachmentStore.draft(app).bundleID, draft.bundleID)
        writer.flush()
        XCTAssertEqual(try ProjectAttachmentStore.draft(app).tweakIDs, [item.id])
    }
    func testOneFailedProjectDoesNotUndoSuccessfulProject() async throws {
        let one = try await project(), two = try await project()
        let item = try await imported(input("Partial.dylib", code()))
        let corrupted = Data("unreadable draft".utf8)
        try corrupted.write(to: PersonalAppsLibrary.shared.draftURL(two))
        try await ProjectAttachmentStore.attach([item], to: one)
        do { try await ProjectAttachmentStore.attach([item], to: two); XCTFail("Unreadable draft must fail closed") } catch {}
        XCTAssertEqual(try ProjectAttachmentStore.draft(one).tweakIDs, [item.id])
        XCTAssertEqual(try Data(contentsOf: PersonalAppsLibrary.shared.draftURL(two)), corrupted)
    }
    func testRealSheetSmallAndLargeScreensPreserveLTRAndMetadata() async throws {
        let app = try await project()
        let item = try await imported(input("Screenshot.dylib", code()))
        try await ProjectAttachmentStore.attach([item], to: app)
        let input = OpenInProjectCoordinator.Input(file: nil, name: "BHTikTokPlus.dylib", error: nil, source: URL(fileURLWithPath: "/fixture.dylib"))
        for size in [CGSize(width: 375, height: 667), CGSize(width: 430, height: 932)] {
            let host = UIHostingController(rootView: OpenInProjectAttachmentSheet(input: input, finish: {}))
            let window = UIWindow(frame: CGRect(origin: .zero, size: size))
            window.rootViewController = host
            window.makeKeyAndVisible()
            try await Task.sleep(nanoseconds: 700_000_000)
            host.view.layoutIfNeeded()
            let image = UIGraphicsImageRenderer(size: size).image { _ in
                host.view.drawHierarchy(in: CGRect(origin: .zero, size: size), afterScreenUpdates: true)
            }
            let shot = XCTAttachment(image: image)
            shot.name = "OpenIn-actual-projects-LTR-\(Int(size.width))x\(Int(size.height))"
            shot.lifetime = .keepAlways
            add(shot)
            XCTAssertNotNil(host.view)
            window.isHidden = true
        }
        XCTAssertEqual(try ProjectAttachmentStore.draft(app).bundleID, app.bundleID)
    }
}
