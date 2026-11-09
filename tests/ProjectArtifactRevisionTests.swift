import XCTest
@testable import Mirsa

final class ProjectArtifactRevisionTests: XCTestCase {
    func testEditsAndResetNeverReuseSignedArtifactAndStatePersists() throws {
        let suite = "ArtifactRevision-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let project = UUID()
        XCTAssertFalse(ProjectArtifactRevision.signedIsCurrent(project, defaults: defaults))
        let signed = ProjectArtifactRevision.current(project, defaults: defaults)
        ProjectArtifactRevision.record(signed, project: project, defaults: defaults)
        XCTAssertTrue(ProjectArtifactRevision.signedIsCurrent(project, defaults: defaults))
        let edited = ProjectArtifactRevision.invalidate(project, defaults: defaults)
        XCTAssertNotEqual(signed, edited)
        XCTAssertFalse(ProjectArtifactRevision.signedIsCurrent(project, defaults: defaults))
        // Resetting edits is itself another revision, not revival of signed bytes.
        let reset = ProjectArtifactRevision.invalidate(project, defaults: defaults)
        XCTAssertNotEqual(reset, signed)
        XCTAssertNotEqual(reset, edited)
        XCTAssertFalse(ProjectArtifactRevision.isCurrent(signed, project: project, defaults: defaults))
        let reopened = try XCTUnwrap(UserDefaults(suiteName: suite))
        XCTAssertFalse(ProjectArtifactRevision.signedIsCurrent(project, defaults: reopened))
        ProjectArtifactRevision.record(reset, project: project, defaults: reopened)
        XCTAssertTrue(ProjectArtifactRevision.signedIsCurrent(project, defaults: defaults))
        XCTAssertFalse(ProjectArtifactRevision.signedIsCurrent(UUID(), defaults: defaults))
    }

    func testLateSigningCompletionCannotBlessNewerDraft() throws {
        let suite = "ArtifactRace-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let project = UUID()
        let captured = ProjectArtifactRevision.current(project, defaults: defaults)
        ProjectArtifactRevision.invalidate(project, defaults: defaults)
        ProjectArtifactRevision.record(captured, project: project, defaults: defaults)
        XCTAssertFalse(ProjectArtifactRevision.signedIsCurrent(project, defaults: defaults))
    }
    @MainActor
    func testStartingAnotherProjectPreservesHistoricalArchiveAndSiblingFiles() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let historical = root.appendingPathComponent("historical.ipa")
        let sibling = root.appendingPathComponent("other-project.ipa")
        let bytes = Data("retained historical signed archive".utf8)
        try bytes.write(to: historical)
        try Data("unrelated archive".utf8).write(to: sibling)
        let firstProject = UUID()
        var prior = PersonalSigningOperation.State(id: UUID(), projectID: firstProject)
        prior.running = false
        prior.result = PersonalCertificateSigner.Result(url: historical,
            bundleIdentifierChanged: false, verification: .unknown)
        let operation = PersonalSigningOperation(initialState: prior)
        let otherProject = UUID()
        operation.beginState(id: UUID(), projectID: otherProject)
        XCTAssertEqual(operation.state?.projectID, otherProject)
        XCTAssertNil(operation.state?.result)
        XCTAssertEqual(try Data(contentsOf: historical), bytes)
        XCTAssertTrue(fm.fileExists(atPath: sibling.path))
        // Starting again for the original project must also preserve both files.
        operation.beginState(id: UUID(), projectID: firstProject)
        XCTAssertEqual(try Data(contentsOf: historical), bytes)
        XCTAssertTrue(fm.fileExists(atPath: sibling.path))
    }

}
