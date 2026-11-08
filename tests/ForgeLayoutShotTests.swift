import XCTest
import SwiftUI
import UIKit
@testable import Mirsa

@MainActor final class ForgeLayoutShotTests: XCTestCase {
    func testForgeProjectScreenshots() async throws {
        let dir = "/tmp/shots"; try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let label = ProcessInfo.processInfo.environment["SHOT_LABEL"] ?? "x"
        let settings = [ForgeSetting(key: "a", title: "Hide ads", default: true), ForgeSetting(key: "b", title: "Unlock premium", default: false)]
        var vs: [ForgeVersion] = []
        for i in 1...4 { vs.append(ForgeVersion(prompt: "Remove ads and unlock premium features v\(i)", code: "%hook Foo\n- (BOOL)isPro { return YES; }\n%end", settings: settings, explain: "Hooks Foo isPro to return YES so premium is unlocked.", builtWithValues: i < 4 ? ["a": true] : nil)) }
        let p = ForgeProject(name: "Lyfta", bundleID: "com.lyfta.app", appName: "Lyfta", appVersion: "1.0", executable: "Lyfta", classes: ["Foo", "Bar"], versions: vs, current: vs.last?.id)
        ForgeStore.shared.projects = [p]
        func shot(_ view: some View, _ name: String) async {
            let host = UIHostingController(rootView: view.environment(\.colorScheme, .dark))
            let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
            let window = scene.map { UIWindow(windowScene: $0) } ?? UIWindow(frame: UIScreen.main.bounds)
            window.frame = UIScreen.main.bounds
            window.rootViewController = host; window.makeKeyAndVisible()
            host.view.frame = window.bounds; host.view.setNeedsLayout(); host.view.layoutIfNeeded()
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            let img = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in _ = window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
            try? img.pngData()?.write(to: URL(fileURLWithPath: "\(dir)/\(label)-\(name).png"))
            withExtendedLifetime(window) {}
            let a = XCTAttachment(image: img); a.name = name; a.lifetime = .keepAlways; add(a)
        }
        await shot(ZStack { Color(red: 0.05, green: 0.05, blue: 0.1).ignoresSafeArea(); ForgeProjectView(id: p.id) }, "project")
        await shot(ZStack { Color(red: 0.05, green: 0.05, blue: 0.1).ignoresSafeArea(); NavigationStack { ForgeView() } }, "list")
    }
}
