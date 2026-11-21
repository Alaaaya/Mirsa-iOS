import XCTest
import SwiftUI
import Combine
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

    #if DEBUG
    /// Runs the real operation and CertificateOTA path through signing and persistent retention.
    /// Requests Stop at retention, so the next production checkpoint fails before ANY network/OTA.
    /// This is genuine retained-output/terminal UI, never a successful installation claim.
    func testRealOTARetainedArchiveStopRendersTerminalAndShare() async throws {
        let bundle = Bundle(for: Self.self)
        let input = try XCTUnwrap(bundle.url(forResource: "LCSignSynthetic", withExtension: "ipa"))
        let material = PersonalIdentityVault.Material(
            p12: try Data(contentsOf: XCTUnwrap(bundle.url(forResource: "LCSignSynthetic", withExtension: "p12"))),
            password: "mirsa-test",
            profile: try Data(contentsOf: XCTUnwrap(bundle.url(forResource: "LCSignSynthetic", withExtension: "mobileprovision"))))
        let previousLanguage = AppLanguageStore.shared.current
        AppLanguageStore.shared.set(.arabic)
        defer { AppLanguageStore.shared.set(previousLanguage) }
        let operation = PersonalSigningOperation()
        let projectID = UUID()
        let ended = expectation(description: "Real OTA operation settled after retained-output stop")
        var settled = false
        let observation = operation.$state.sink { state in
            if state?.running == false, !settled { settled = true; ended.fulfill() }
        }
        defer { observation.cancel(); operation.didRetainArchiveForTesting = nil }
        operation.didRetainArchiveForTesting = { [weak operation] in operation?.stop() }
        var options = PersonalProjectOptions()
        options.bundleID = "com.test.app"
        operation.start(projectID: projectID, title: "Synthetic signing test", input: input,
                        material: material, pairingPath: "", options: options)
        await fulfillment(of: [ended], timeout: 120)
        let state = try XCTUnwrap(operation.state)
        XCTAssertFalse(state.running)
        XCTAssertTrue(state.stoppedByUser)
        XCTAssertEqual(state.stage, .failed, "A stopped operation must never claim installed/completed")
        XCTAssertEqual(state.error, "تم الإيقاف.")
        XCTAssertTrue(state.log.contains { $0.source == "Signer" })
        XCTAssertFalse(state.log.contains { $0.source == "Installer" }, "Stop before network/OTA")
        let archive = try XCTUnwrap(state.signedArchive)
        defer {
            try? FileManager.default.removeItem(at: archive.deletingLastPathComponent())
            UserDefaults.standard.removeObject(forKey: "mirsa.project.signed." + projectID.uuidString)
        }
        XCTAssertGreaterThan(try Data(contentsOf: archive).count, 0)
        XCTAssertNotEqual(archive, input)
        XCTAssertTrue(archive.path.contains("MirsaSignedExports"))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let original = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 430, height: 932)
        defer { window.isHidden = true; original?.makeKey() }
        let host = UIHostingController(rootView: ProjectInstallLogView(signing: operation,
            projectID: projectID, appName: "Synthetic signing test", close: {}))
        window.rootViewController = host; window.makeKeyAndVisible(); window.layoutIfNeeded()
        let layout = expectation(description: "Real terminal view layout")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { layout.fulfill() }
        await fulfillment(of: [layout], timeout: 3)
        attach(window, name: "LCSign-ar-real-OTA-retained-stop-terminal-not-installation")
        // Render the exact production share component with the actual retained signed bytes.
        // This verifies the component, not a tap on the log's Share button.
        let share = UIHostingController(rootView: PersonalSignedShare(url: archive))
        host.present(share, animated: false)
        let shareLayout = expectation(description: "Retained signed archive share view")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { shareLayout.fulfill() }
        await fulfillment(of: [shareLayout], timeout: 3)
        attach(window, name: "LCSign-ar-real-retained-IPA-share-component-not-button-tap")
        share.dismiss(animated: false)
    }

    #endif

    /// Executes the production Swift signer + Rust FFI with public synthetic test material.
    /// The screenshot is held at an actual bundle callback, not seeded log rows/timed progress.
    /// This is NOT Apple authorization or proof of system/device installation.
    private func captureRealSigner(language: AppLanguage, stop: Bool) async throws {
        let bundle = Bundle(for: Self.self)
        let input = try XCTUnwrap(bundle.url(forResource: "LCSignSynthetic", withExtension: "ipa"))
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
                        _ = release.wait(timeout: .now() + 60)
                    }
                }
                return .success(result)
            } catch { return .failure(error) }
        }
        await fulfillment(of: [reached], timeout: 120)
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
            guard case SideloadError.message(let reason) = error else {
                return XCTFail("Expected the real cancellation checkpoint, got \(error)")
            }
            XCTAssertEqual(reason, "انتهى وقت الخلفية. افتح Mirsa وجرّب التوقيع من جديد.",
                           "An unrelated signer error must not pass the cooperative-stop test")
            XCTAssertTrue(control.isCancelled)
            XCTAssertEqual(operation.state?.stage, .signing, "Cancellation must precede packaging")
            XCTAssertNil(operation.state?.signedArchive, "Stopped signing must not expose an export")
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
