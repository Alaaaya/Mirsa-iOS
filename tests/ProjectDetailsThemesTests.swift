import Foundation
import SwiftUI
import XCTest
@testable import Mirsa

@MainActor
final class ProjectDetailsThemesTests: XCTestCase {
    private func src(_ name: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent("ios-app/Apps/" + name), encoding: .utf8)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: AppLanguageStore.key)
        UserDefaults.standard.removeObject(forKey: ProjectDetailsTheme.key)
        super.tearDown()
    }

    func testThemeKeyAndRawValuesAreStable() {
        XCTAssertEqual(ProjectDetailsTheme.key, "mirsa.projectDetailsTheme")
        XCTAssertEqual(ProjectDetailsTheme.allCases.map(\.rawValue),
                       ["classic", "obsidianGold", "aurora", "bento", "buildPipeline"])
        XCTAssertEqual(ProjectDetailsTab.allCases.map(\.rawValue), ["tweaks", "settings", "certificate", "versions", "files"])
    }

    func testClassicIsTheDefaultAndUnknownValuesFallBack() {
        XCTAssertEqual(ProjectDetailsTheme.fallback, .classic)
        XCTAssertEqual(ProjectDetailsTheme(stored: nil), .classic)
        XCTAssertEqual(ProjectDetailsTheme(stored: ""), .classic)
        XCTAssertEqual(ProjectDetailsTheme(stored: "no-such-theme"), .classic)
        XCTAssertEqual(ProjectDetailsTheme(stored: "bento"), .bento)
        UserDefaults.standard.removeObject(forKey: ProjectDetailsTheme.key)
        XCTAssertEqual(ProjectDetailsTheme.current, .classic)
        UserDefaults.standard.set("lightPearl", forKey: ProjectDetailsTheme.key)
        XCTAssertEqual(ProjectDetailsTheme.current, .classic)
        XCTAssertEqual(ProjectDetailsTheme(stored: "lightPearl"), .classic)
    }

    func testEveryThemeAndTabHasALocalizedNameInAllLanguages() {
        for language in AppLanguage.allCases {
            UserDefaults.standard.set(language.rawValue, forKey: AppLanguageStore.key)
            let titles = ProjectDetailsTheme.allCases.map(\.title)
            XCTAssertFalse(titles.contains(where: \.isEmpty), language.rawValue)
            XCTAssertEqual(Set(titles).count, titles.count, "theme names must be distinct in \(language.rawValue)")
            for tab in ProjectDetailsTab.allCases { XCTAssertFalse(tab.title.isEmpty, language.rawValue) }
            for step in ProjectPipelineStep.allCases { XCTAssertFalse(step.title.isEmpty, language.rawValue) }
            for method in InjectionMethod.allCases { XCTAssertFalse(ProjectThemeText.methodShort(method).isEmpty) }
            XCTAssertFalse(ProjectThemeText.menuTitle.isEmpty)
            XCTAssertFalse(ProjectThemeText.addTweak.isEmpty)
        }
        UserDefaults.standard.set(AppLanguage.arabic.rawValue, forKey: AppLanguageStore.key)
        XCTAssertEqual(ProjectDetailsTheme.classic.title, "الأساسي")
        UserDefaults.standard.set(AppLanguage.german.rawValue, forKey: AppLanguageStore.key)
        XCTAssertEqual(ProjectDetailsTheme.classic.title, "Klassisch")
    }

    func testNoThemeIsLightAndClassicStaysLeftToRight() {
        XCTAssertTrue(ProjectDetailsTheme.allCases.filter(\.isLight).isEmpty)
        XCTAssertEqual(ProjectDetailsTheme.bento.colorScheme, .dark)
        for language in AppLanguage.allCases {
            XCTAssertEqual(ProjectDetailsTheme.classic.layoutDirection(for: language), .leftToRight)
        }
        XCTAssertEqual(ProjectDetailsTheme.aurora.layoutDirection(for: .arabic), .rightToLeft)
        XCTAssertEqual(ProjectDetailsTheme.bento.layoutDirection(for: .sorani), .rightToLeft)
        XCTAssertEqual(ProjectDetailsTheme.obsidianGold.layoutDirection(for: .kurmanji), .leftToRight)
        XCTAssertEqual(ProjectDetailsTheme.buildPipeline.layoutDirection(for: .german), .leftToRight)
    }

    func testCertificateSummary() {
        let now = Date()
        XCTAssertEqual(ProjectCertificateState.evaluate(hasCertificate: false, verified: true, expiry: nil, now: now), .missing)
        XCTAssertEqual(ProjectCertificateState.evaluate(hasCertificate: true, verified: true, expiry: now.addingTimeInterval(86_400 * 10), now: now), .valid)
        XCTAssertEqual(ProjectCertificateState.evaluate(hasCertificate: true, verified: false, expiry: nil, now: now), .unverified)
        XCTAssertEqual(ProjectCertificateState.evaluate(hasCertificate: true, verified: true, expiry: now.addingTimeInterval(-60), now: now), .expired)
        XCTAssertEqual(ProjectCertificateState.daysLeft(until: now.addingTimeInterval(86_400 * 3 + 60), now: now), 3)
        XCTAssertEqual(ProjectCertificateState.daysLeft(until: now.addingTimeInterval(-86_400), now: now), 0)
        XCTAssertNil(ProjectCertificateState.daysLeft(until: nil, now: now))
    }

    /// Themes only change layout: presenters, tasks and the sign identifier exist once in the view source.
    func testPresentersAreAttachedOnceAndThemesShareTheSignIdentifier() throws {
        let s = try src("PersonalProjectDetailView.swift")
        func count(_ needle: String) -> Int { s.components(separatedBy: needle).count - 1 }
        XCTAssertTrue(s.contains("@AppStorage(ProjectDetailsTheme.key)"))
        XCTAssertEqual(count(".sheet(isPresented: $showCertificates"), 1)
        XCTAssertEqual(count(".sheet(isPresented: $pickingTweak)"), 1)
        XCTAssertEqual(count(".sheet(isPresented: $pickingEntitlements)"), 1)
        XCTAssertEqual(count(".sheet(isPresented: $sharing"), 1)
        XCTAssertEqual(count(".sheet(isPresented: $showProjectLogs)"), 1)
        XCTAssertEqual(count(".sheet(item: $workspace)"), 1)
        XCTAssertEqual(count(".sheet(item: $tweaks.pendingImport"), 1)
        XCTAssertEqual(count(".fileImporter("), 1)
        XCTAssertEqual(count(".photosPicker("), 1)
        XCTAssertEqual(count(".alert("), 1)
        XCTAssertEqual(count(".task {"), 1)
        // Classic bar + the shared themed button; only one of them is ever on screen.
        XCTAssertEqual(count("accessibilityIdentifier(\"mirsa.project.sign\")"), 2)
        XCTAssertEqual(count("accessibilityIdentifier(\"mirsa.project.editor-scroll\")"), 2)
        let theme = try src("ProjectDetailsTheme.swift")
        XCTAssertTrue(theme.contains("accessibilityIdentifier(\"mirsa.project.theme-menu\")"))
    }
}
