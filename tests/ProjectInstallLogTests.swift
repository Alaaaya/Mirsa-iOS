import XCTest
import SwiftUI
@testable import Mirsa

@MainActor
final class ProjectInstallLogTests: XCTestCase {
    func testLogRecordsOnlyRealStageChanges() {
        var state = PersonalSigningOperation.State(id: UUID(), projectID: UUID())
        XCTAssertEqual(state.log.count, 1)
        XCTAssertTrue(state.apply(.signing(completed: 1, total: 4)))
        let afterSign = state.log.count
        XCTAssertGreaterThan(afterSign, 1)
        XCTAssertFalse(state.apply(.signing(completed: 1, total: 4)))
        XCTAssertEqual(state.log.count, afterSign)
        XCTAssertTrue(state.apply(PersonalSigningEvent(stage: .packaging)))
        XCTAssertGreaterThan(state.log.count, afterSign)
        XCTAssertTrue(state.log.contains { $0.source == "Signer" })
    }
    func testStopIsIdempotentAndWaitsForCheckpoint() throws {
        let control = PersonalSigningControl()
        let state = PersonalSigningOperation.State(id: UUID(), projectID: UUID())
        let operation = PersonalSigningOperation(initialState: state, control: control)
        operation.stop()
        XCTAssertTrue(control.isCancelled)
        XCTAssertTrue(operation.running, "A request is not immediate cancellation")
        XCTAssertTrue(operation.state?.stoppedByUser == true)
        XCTAssertNil(operation.state?.error)
        let count = operation.state?.log.count
        operation.stop()
        XCTAssertEqual(operation.state?.log.count, count)
        XCTAssertThrowsError(try control.checkpoint())
        let next = PersonalSigningOperation.State(id: UUID(), projectID: state.projectID)
        XCTAssertFalse(next.stoppedByUser)
        XCTAssertNil(next.signedArchive, "Never offer the previous attempt's IPA as this attempt's output")
    }

    func testRealSignerCallbacksRenderEnglishLog() async throws {
        try await captureRealSigner(language: .english, stop: false)
    }
    func testRealSignerCallbacksRenderArabicLogAndCooperativeStop() async throws {
        try await captureRealSigner(language: .arabic, stop: true)
    }

    /// Executes the production Swift signer + Rust FFI with public synthetic test material.
    /// The screenshot is held at an actual bundle callback, not seeded log rows/timed progress.
    /// This is NOT Apple authorization or proof of system/device installation.
    private func captureRealSigner(language: AppLanguage, stop: Bool) async throws {
        let bundle = Bundle(for: Self.self)
        let input = try XCTUnwrap(bundle.url(forResource: "PersonalUIFixture", withExtension: "zip"))
        let material = PersonalIdentityVault.Material(
            p12: try Data(contentsOf: XCTUnwrap(bundle.url(forResource: "LCSignSynthetic", withExtension: "p12"))),
            password: "mirsa-test",
            profile: try Data(contentsOf: XCTUnwrap(bundle.url(forResource: "LCSignSynthetic", withExtension: "mobileprovision"))))
        let previousLanguage = AppLanguageStore.shared.current
        AppLanguageStore.shared.set(language)
        defer { AppLanguageStore.shared.set(previousLanguage) }
        let control = PersonalSigningControl()
        let state = PersonalSigningOperation.State(id: UUID(), projectID: UUID())
        let operation = PersonalSigningOperation(initialState: state, control: control)
        let reached = expectation(description: "Production signer reached a bundle callback")
        let release = DispatchSemaphore(value: 0)
        // Always release on failure as well, so no signer thread is stranded by an assertion.
        defer { release.signal() }
        var options = PersonalProjectOptions()
        options.bundleID = "com.test.app"
        let work = Task.detached { () -> Result<PersonalCertificateSigner.Result, Error> in
            do {
                var captured = false
                let result = try PersonalCertificateSigner.sign(ipa: input, material: material,
                    pairingPath: "", options: options, control: control) { event in
                    DispatchQueue.main.sync {
                        MainActor.assumeIsolated { _ = operation.record(event, id: state.id) }
                    }
                    if event.stage == .signing, event.completed > 0, !captured {
                        captured = true
                        reached.fulfill()
                        _ = release.wait(timeout: .now() + 30)
                    }
                }
                return .success(result)
            } catch { return .failure(error) }
        }
        await fulfillment(of: [reached], timeout: 20)
        XCTAssertEqual(operation.state?.stage, .signing)
        XCTAssertGreaterThan(operation.state?.completedUnits ?? 0, 0)
        XCTAssertTrue(operation.state?.log.contains { $0.source == "Signer" } == true)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let original = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 430, height: 932)
        defer { window.isHidden = true; original?.makeKey() }
        let host = UIHostingController(rootView: ProjectInstallLogView(signing: operation,
            projectID: state.projectID, appName: "Synthetic signing test", close: {}))
        window.rootViewController = host
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        // Let SwiftUI finish the real view layout; this does not generate any signer events.
        let laidOut = expectation(description: "SwiftUI layout")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { laidOut.fulfill() }
        await fulfillment(of: [laidOut], timeout: 3)
        host.view.layoutIfNeeded()
        attach(window, name: "LCSign-\(language.rawValue)-real-signer-callback-synthetic-not-installation")
        if stop {
            operation.stop()
            XCTAssertTrue(operation.running)
            XCTAssertTrue(control.isCancelled)
            XCTAssertThrowsError(try control.checkpoint())
            let stoppedLayout = expectation(description: "Stop request layout")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { stoppedLayout.fulfill() }
            await fulfillment(of: [stoppedLayout], timeout: 3)
            attach(window, name: "LCSign-ar-real-callback-stop-pending-checkpoint")
        }
        release.signal()
        let outcome = await work.value
        switch outcome {
        case .success(let result):
            defer { MirsaManagedTmp.end(result.url.deletingLastPathComponent()) }
            XCTAssertFalse(stop, "Stop must be observed at the next real signer checkpoint")
            XCTAssertGreaterThan((try? Data(contentsOf: result.url).count) ?? 0, 0)
            XCTAssertFalse(result.installed, "No system installer was invoked")
        case .failure(let error):
            XCTAssertTrue(stop, "Real signing failed before packaging: \(error.localizedDescription)")
        }
    }

    private func attach(_ window: UIWindow, name: String) {
        window.layoutIfNeeded()
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        XCTAssertEqual(image.size.width, 430)
        let attachment = XCTAttachment(image: image)
        attachment.name = name; attachment.lifetime = .keepAlways
        add(attachment)
    }
}
