import XCTest
import SwiftUI
@testable import Mirsa

@MainActor
final class IncomingIPAChoiceTests: XCTestCase {
    private func pending() -> PendingImport {
        PendingImport(id: UUID(), originalIPA: URL(fileURLWithPath: "/fixture.ipa"),
            extractedApp: URL(fileURLWithPath: "/fixture.app"),
            workDir: URL(fileURLWithPath: "/fixture-work"),
            bundleID: "com.alaa.mirsa", name: "Mirsa", version: "1.3.2",
            icon: nil, wantsNotifications: false, hasExtensions: false, sizeBytes: 14_910_574)
    }

    func testOriginalChoiceDoesNotInstallOnPresentationAndKeepsDistinctRoutes() {
        let store = AppsStore.shared
        var routes: [AppLocation] = []
        var saved = false
        let sheet = InstallChoiceSheet(pending: pending(), store: store,
            onPersonal: { saved = true }, onChoose: { routes.append($0) })
        XCTAssertTrue(routes.isEmpty)
        XCTAssertFalse(saved)
        sheet.onChoose(.container)
        sheet.onChoose(.real)
        XCTAssertEqual(routes.map { $0.rawValue }, [AppLocation.container.rawValue, AppLocation.real.rawValue])
        sheet.onPersonal?()
        XCTAssertTrue(saved)
        XCTAssertEqual(store.slotsLeft, max(0, store.realLimit - store.slotsUsed))
    }

    func testOriginalChoiceScreenSnapshots() async throws {
        let old = AppLanguageStore.shared.current
        defer { AppLanguageStore.shared.set(old) }
        for language in [AppLanguage.arabic, .english] {
            AppLanguageStore.shared.set(language)
            let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
            let original = scene.windows.first(where: \.isKeyWindow)
            let window = UIWindow(windowScene: scene)
            window.frame = CGRect(x: 0, y: 0, width: 430, height: 932)
            let host = UIHostingController(rootView: InstallChoiceSheet(pending: pending(), store: AppsStore.shared,
                onPersonal: {}, onChoose: { _ in }))
            window.rootViewController = host
            window.makeKeyAndVisible()
            host.view.frame = window.bounds
            window.layoutIfNeeded()
            try await Task.sleep(nanoseconds: 500_000_000)
            let image = UIGraphicsImageRenderer(size: window.bounds.size).image { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            let attachment = XCTAttachment(image: image)
            attachment.name = "Mirsa-choice-first-\(language.rawValue)"
            attachment.lifetime = .keepAlways
            add(attachment)
            window.isHidden = true
            original?.makeKey()
        }
    }
}
