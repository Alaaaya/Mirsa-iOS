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

    def test_upgrade_advances_live_25(self):
        guard = (R / "scripts/verify_release_upgrade.py").read_text()
        self.assertIn('== "2.6"', guard)
        self.assertIn('previous = "6.1.1"', guard)
        self.assertIn('> 401', guard)
        self.assertIn('MIRSA_VERSION: "2.6"', (R / ".github/workflows/unsigned-ipa.yml").read_text())

if __name__ == "__main__":
    unittest.main()
