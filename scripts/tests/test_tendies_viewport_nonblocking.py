"""Focused source guards. Native geometry/responsiveness remains a UI-test gate."""
import pathlib
import unittest
R = pathlib.Path(__file__).resolve().parents[2]

class TendiesViewportNonblockingTests(unittest.TestCase):
    def test_document_scan_does_no_copy_on_main_actor_and_coalesces(self):
        source = (R / "ios-app/AppViewModel.swift").read_text()
        scan = source.split("func scanDocumentsForTendies()", 1)[1].split("@discardableResult", 1)[0]
        worker = scan.split("Task.detached(priority: .utility)", 1)[1].split("}.value", 1)[0]
        self.assertIn("guard !tendiesScanRunning", scan)
        self.assertIn("defer { tendiesScanRunning = false }", scan)
        self.assertIn("fm.copyItem", worker)
        self.assertNotIn("copyItem", scan.split("Task.detached", 1)[0])
        self.assertLess(scan.index("}.value"), scan.index("let newURLs"))
        self.assertIn("catch { continue }", worker)

    def test_each_retained_tab_has_real_viewport_and_keeps_hidden_clip(self):
        host = (R / "ios-app/ContentView.swift").read_text().split("private func sixTab", 1)[1].split("var body:", 1)[0]
        for token in ["GeometryReader { viewport", ".frame(width: viewport.size.width, height: viewport.size.height)", ".clipped()", ".allowsHitTesting(on)", ".accessibilityHidden(!on)"]:
            self.assertIn(token, host)

    def test_background_geometry_is_physical_even_in_rtl(self):
        source = (R / "ios-app/Apps/MirsaStyle.swift").read_text()
        background = source.split("struct MirsaScreenAnchored", 1)[1].split("// MARK: - Floating", 1)[0]
        self.assertIn(".environment(\\.layoutDirection, .leftToRight)\n        .ignoresSafeArea()", background)
        dock = source.split("struct LiquidTabBar:", 1)[1].split("enum MirsaTabBarMetrics", 1)[0]
        self.assertNotIn("matchedGeometryEffect", dock)
        self.assertIn("if on", dock)

    def test_only_generated_titles_are_replaced_no_delete_authority_changed(self):
        source = (R / "ios-app/MirsaWallpaperManagementView.swift").read_text()
        title = source.split("private func cardTitle", 1)[1].split("private func thumb", 1)[0]
        self.assertIn('title.hasPrefix("Mirsa-")', title)
        self.assertIn("UUID(uuidString:", title)
        self.assertIn("fallbackName", title)
        self.assertIn(".disabled(disabled)", source)
        self.assertIn("guard !disabled", source)

if __name__ == "__main__":
    unittest.main()
