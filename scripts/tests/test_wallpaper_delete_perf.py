"""Offline contracts. Device speed must be measured with DELETE TIMING events."""
import pathlib
import unittest

R = pathlib.Path(__file__).resolve().parents[2]

class DeletePerformanceTests(unittest.TestCase):
    def test_reuses_only_live_exact_read_access_without_changing_delete_guards(self):
        source = (R / "ios-app/MirsaCustomWallpapers.swift").read_text()
        body = source.split("static func delete(_ requested: Item,", 1)[1]
        self.assertIn("reuseReadableAccess: true", body)
        for guard in ["guard requested.canDelete", "container == requested.container",
                      "fresh.device == requested.device", "fresh.inode == requested.inode",
                      "final.expected == fresh.expected", "final.paths == fresh.paths",
                      "try journals()", "lease.permits(target)", "last.st_ino",
                      "MirsaWallpaperJournal.absent(target)", "try lease.close()"]:
            self.assertIn(guard, body)
        self.assertEqual(body.count("try snapshot("), 1)
        self.assertEqual(body.count("try classify("), 2)
        lease = (R / "ios-app/PosterBoardStore.swift").read_text()
        self.assertIn("permits(url), PosterBoardStore.readableNode(url)", lease)
        self.assertIn("grantRelativeAccess(handle", lease)
        self.assertIn("O_RDONLY | O_NOFOLLOW | O_NONBLOCK", lease)

    def test_timing_is_monotonic_and_spans_each_expensive_phase(self):
        body = (R / "ios-app/MirsaCustomWallpapers.swift").read_text().split(
            "static func delete(_ requested: Item,", 1)[1]
        self.assertIn("ProcessInfo.processInfo.systemUptime - started", body)
        for phase in ["lock-acquired", "access-ready", "classified", "revalidated",
                      "removed-and-absence-verified", "lease-closed", "finished"]:
            self.assertIn('timing("' + phase + '"', body)
        self.assertLess(body.index('timing("classified"'), body.index('timing("revalidated"'))
        self.assertLess(body.index("removeItem(at: target)"), body.index('timing("removed-and-absence-verified"'))
        self.assertIn('defer { timing("finished") }', body)
        self.assertIn('lease?.grantRequests', body)
        self.assertIn('lease?.reusedReads', body)

    def test_visible_row_progress_clears_on_success_and_error(self):
        ui = (R / "ios-app/MirsaWallpaperManagementView.swift").read_text()
        self.assertIn('if deletingID == rec.id', ui)
        self.assertIn('ProgressView(t(.deleting))', ui)
        self.assertIn('wallpaper-delete-progress', ui)
        delete = ui.split("private func delete(_ rec:", 1)[1].split("private func cleanup", 1)[0]
        self.assertLess(delete.index("deletingID = rec.id"), delete.index("run("))
        callback = delete.split("done: { err in", 1)[1]
        self.assertLess(callback.index("deletingID = nil"), callback.index("if let err"))
        strings = (R / "ios-app/MirsaWallpaperActionStrings.swift").read_text()
        self.assertEqual(strings.split('.deleting: [', 1)[1].split(']', 1)[0].count('", '), 4)

if __name__ == "__main__":
    unittest.main()
