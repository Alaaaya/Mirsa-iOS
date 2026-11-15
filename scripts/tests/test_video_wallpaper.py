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

    def test_no_unverified_transport_success_or_preferences_mutations(self):
        engine = (R / "ios-app/TendiesEngine.swift").read_text()
        self.assertNotIn("PosterBoardStore.install(", engine)
        self.assertIn("MirsaPosterCopy.copyExclusive(", engine)
        self.assertNotIn("FileComplete", engine)
        copy = (R / "ios-app/MirsaPosterCopy.swift").read_text()
        self.assertIn("readback == expected", copy)
        self.assertIn("sourcePaths == targetPaths", copy)
        self.assertIn("verifyCopyAttributes(source: source, target: target)", copy)
        self.assertIn("errno == ENOENT", copy)
        self.assertIn("fm.copyItem(at: source, to: target)", copy)
        for source in [engine, copy, (R / "ios-app/PosterBoardStore.swift").read_text()]:
            self.assertNotIn('preferences["PBF_LOCALE_DID_CHANGE"] =', source)
            self.assertNotIn("unprotectedUserDefaults.original.plist", source)
            self.assertNotIn("removeItem(at: container)", source)
        self.assertIn("gallery unverified", engine)

    def test_local_discovery_never_falls_back_to_remote_transport(self):
        engine = (R / "ios-app/TendiesEngine.swift").read_text()
        discovery = engine.split("public func detectPosterBoardContainer", 1)[1].split("// MARK:", 1)[0]
        self.assertIn("MirsaPosterDiscovery.discover", discovery)
        self.assertIn("MirsaWallpaperJournal.exclusive", discovery)
        for forbidden in ["al_find_app_container", "withCheckedThrowingContinuation", "withCString", "Wi-Fi/LocalDevVPN"]:
            self.assertNotIn(forbidden, discovery)
        store = (R / "ios-app/PosterBoardStore.swift").read_text()
        providers = store.split("static func providers(", 1)[1].split("static func manifest(", 1)[0]
        self.assertIn('return ["com.apple.WallpaperKit.CollectionsPoster"]', providers)
        destination = (R / "ios-app/MirsaPosterCopy.swift").read_text().split("static func destination(", 1)[1].split("static func relativePaths(", 1)[0]
        self.assertNotIn("PosterBoardStore.layout(", destination)
        self.assertNotIn("createDirectory", destination)

    def test_journal_precedes_copy_and_delete_requires_exact_ownership(self):
        engine = (R / "ios-app/TendiesEngine.swift").read_text().split("public func flashTendies(", 1)[1]
        self.assertLess(engine.index("MirsaWallpaperJournal.save(record)"), engine.index("MirsaPosterCopy.copyExclusive("))
        self.assertLess(engine.index("MirsaPosterCopy.copyExclusive("), engine.index("record.copied = true"))
        source = (R / "ios-app/MirsaWallpaperJournal.swift").read_text()
        delete = source.split("static func delete(", 1)[1].split("static func cleanup(", 1)[0]
        removal = delete.index("removeItem(at: target)")
        for guard in ["record.container == requested.container", "record.relative == requested.relative",
                      "record.copied", "validateIdentity(", "grantTree(record", "UInt64(info.st_dev) == record.device",
                      "UInt64(info.st_ino) == record.inode", "actual == record.expected", "final.st_ino == info.st_ino",
                      "lease.permits(target)"]:
            self.assertLess(delete.index(guard), removal)
        self.assertLess(delete.index("try lease.close()"), delete.index("try removeJournal(record)"))
        cleanup = source.split("static func cleanup(", 1)[1]
        self.assertNotIn("removeItem(at: target)", cleanup)
        self.assertNotIn("removeItem(at: container)", cleanup)
        self.assertIn("let missing = try absent(target)", cleanup)
        self.assertIn("if missing { try removeJournal(record)", cleanup)
        self.assertLess(cleanup.index("try safeLocal(work)"), cleanup.index("removeItem(at: url)"))
        self.assertLess(cleanup.index("UUID(uuidString: url.lastPathComponent)"), cleanup.index("removeItem(at: url)"))
        self.assertLess(cleanup.index("MirsaPosterCopy.relativePaths(url)"), cleanup.index("removeItem(at: url)"))

    def test_refresh_is_single_local_webview_and_separately_confirmed(self):
        source = (R / "ios-app/MirsaWallpaperRespringView.swift").read_text()
        self.assertEqual(source.count("WKWebView(frame:"), 1)
        self.assertIn(".nonPersistent()", source)
        self.assertIn("func dismantleUIView", source)
        self.assertIn("uiView.stopLoading()", source)
        self.assertNotIn("uiView.reload()", source)
        self.assertNotIn("URLSession", source)
        self.assertNotIn("https://", source)
        view = (R / "ios-app/TendiesView.swift").read_text()
        self.assertEqual(view.count("MirsaWallpaperRespringView(event:"), 1)
        confirmation = view.split(".alert(ws(.respringTitle)", 1)[1].split("} message:", 1)[0]
        self.assertIn("Button(ws(.respringConfirm), role: .destructive)", confirmation)
        self.assertIn("let ok = respringArmed", confirmation)
        self.assertIn("respringArmed = false", confirmation)
        self.assertIn("showRespringOverlay = true", confirmation)
        self.assertIn("Button(ws(.respringLater), role: .cancel)", confirmation)

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

    def test_local_apply_is_once_only_and_respring_explicit(self):
        model = (R / "ios-app/AppViewModel.swift").read_text().split("func flashSelectedTendies()", 1)[1].split("func respringDevice()", 1)[0]
        self.assertIn("guard tendiesFlashPhase != .running", model)
        self.assertLess(model.index("tendiesFlashPhase = .running"), model.index("try await"))
        self.assertNotIn("triggerNeoSpring", model)
        engine = (R / "ios-app/TendiesEngine.swift").read_text()
        self.assertIn("checksum == entry.checksum", engine)
        self.assertNotIn("al_zip_extract_all", engine)
        self.assertIn("extractValidatedArchive", engine)

    def test_upgrade_advances_live_25(self):
        guard = (R / "scripts/verify_release_upgrade.py").read_text()
        self.assertIn('== "2.6"', guard)
        self.assertIn('previous = "6.1.1"', guard)
        self.assertIn('> 401', guard)
        self.assertIn('MIRSA_VERSION: "2.6"', (R / ".github/workflows/unsigned-ipa.yml").read_text())

if __name__ == "__main__":
    unittest.main()
