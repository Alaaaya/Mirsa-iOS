"""2.6 keeps video first in the same section and verifies actual copy destinations."""
import pathlib
import unittest

R = pathlib.Path(__file__).resolve().parents[2]

class VideoWallpaperTests(unittest.TestCase):
    def test_video_before_tendies_in_one_section(self):
        view = (R / "ios-app/TendiesView.swift").read_text()
        self.assertLess(view.index("OriginalVideoWallpaperBlock("), view.index("WallpaperMakerSection("))
        tools = (R / "ios-app/Apps/ToolsTab.swift").read_text()
        self.assertIn("case .wallpapers: TendiesView()", tools)
        self.assertNotIn("videoWallpaper", tools)

    def test_no_unverified_transport_success_or_cache_reset(self):
        engine = (R / "ios-app/TendiesEngine.swift").read_text()
        self.assertIn("PosterBoardStore.install(", engine)
        self.assertNotIn("FileComplete", engine)
        store = (R / "ios-app/PosterBoardStore.swift").read_text()
        self.assertIn("manifest(destination) == expected", store)
        self.assertIn('preferences["PBF_LOCALE_DID_CHANGE"] = false', store)
        self.assertIn('"galleryRegistrationVerified": false', store)
        self.assertNotIn("removeItem(at: container)", store)

    def test_scoped_strategies_never_enable_library_parent_rename(self):
        source = (R / "ios-app/PosterBoardAccess.m").read_text()
        for label in ["class13-traversal", "class7-symlink", "class2-stage", "class2-subpath", "class12-geod-traversal"]:
            self.assertIn(label, source)
        self.assertIn('CFSTR("com.apple.security.application-groups")', source)
        self.assertIn('CFSTR("get-task-allow")', source)
        self.assertNotIn('group.com.kamui.escape', source)
        self.assertNotIn('removeItem', source)
        self.assertNotIn('class2_parent', source)
        self.assertIn('transport staging is not destination verification', source)
        self.assertIn('backup retained', source)

    def test_layout_bounds_viewport_and_tests_actual_bars(self):
        view = (R / "ios-app/TendiesView.swift").read_text()
        self.assertIn('.safeAreaInset(edge: .bottom', view)
        self.assertIn('anchor: .center', view)
        self.assertNotIn('Button(selectedAll ? "Deselect All"', view)
        self.assertNotIn('posterType.rawValue', view)
        tests = (R / "uitests/MirsaStyleScreenshotsUITests.swift").read_text()
        self.assertIn('for theme in ["liquid", "classic"]', tests)
        self.assertIn('app.tabBars.firstMatch', tests)
        self.assertIn('respring.frame.maxY, wallpaperVisibleBottom', tests)
        self.assertIn('MirsaWallpaperFlashLogFixture', tests)
        self.assertIn('PosterBoardAccessSafetyTests', (R / ".github/workflows/forge-validation.yml").read_text())

    def test_upgrade_advances_live_25(self):
        guard = (R / "scripts/verify_release_upgrade.py").read_text()
        self.assertIn('== "2.6"', guard)
        self.assertIn('previous = "6.1.1"', guard)
        self.assertIn('> 401', guard)
        self.assertIn('MIRSA_VERSION: "2.6"', (R / ".github/workflows/unsigned-ipa.yml").read_text())

if __name__ == "__main__":
    unittest.main()
