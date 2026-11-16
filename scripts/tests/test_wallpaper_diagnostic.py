import pathlib
import unittest
R = pathlib.Path(__file__).resolve().parents[2]

class DiagnosticContractTests(unittest.TestCase):
    def test_read_only_and_bounded(self):
        s = (R / "ios-app/MirsaWallpaperDiagnostics.swift").read_text()
        for prohibited in ["removeItem(", "moveItem(", "createDirectory(", "NSKeyedUnarchiver", "URLSession", "enumerator("]:
            self.assertNotIn(prohibited, s)
        for guard in ["openat(", "O_NOFOLLOW", "AT_SYMLINK_NOFOLLOW", "maxGrants", "deadline", "maxBytes", "reader.verify()"]:
            self.assertIn(guard, s)
        probe = s.split("static func catalogProbe(", 1)[1].split("static func inspect(", 1)[0]
        self.assertNotIn("grant(", probe)
        self.assertNotIn("names(", probe)
        self.assertNotIn("contentsOfDirectory", probe)
    def test_unknown_inspect_never_deletes(self):
        s = (R / "ios-app/MirsaCustomWallpapers.swift").read_text()
        listing = s.split("private static func list(lease:",1)[1].split("static func list(log:",1)[0]
        self.assertIn("canDelete: false", listing)
        self.assertNotIn("snapshot(", listing)
        self.assertNotIn("systemBaseline(", listing)
        self.assertNotIn("classify(", listing)
        delete = s.split("static func delete(",1)[1]
        self.assertLess(delete.index("guard requested.canDelete"), delete.index("removeItem("))
        ui = (R / "ios-app/MirsaWallpaperManagementView.swift").read_text()
        self.assertIn("if rec.canDelete {", ui)
        self.assertIn("if !rec.canDelete {", ui)
        self.assertIn("MirsaWallpaperDiagnostics.inspect", ui)
    def test_stale_reinstall_shares_lease_and_parent_identity(self):
        s = (R / "ios-app/MirsaWallpaperJournal.swift").read_text()
        body=s.split("static func archiveAbsentForReinstall(",1)[1].split("static func delete(",1)[0]
        for token in ["sameParent(originalParent, currentParent)", "try absent(target)", "archiveLocal(record, at: root, revalidate: revalidate)"]:
            self.assertIn(token,body)
        self.assertNotIn("removeItem(at: target)",body)
        local=s.split("static func archiveLocal(",1)[1].split("static func archiveAbsentForReinstall(",1)[0]
        self.assertEqual(local.count("try revalidate()"),2)
        self.assertIn("moveItem(at: destination, to: source)",local)
    def test_exact_diff_no_runtime_exception(self):
        s=(R / "ios-app/MirsaWallpaperDiagnostics.swift").read_text()
        for status in ["added","removed","modified","unobserved","unreadable","unchanged"]:
            self.assertIn('"'+status+'"',s)
        self.assertIn("expectedHash=",s)
        self.assertIn("actualHash=",s)
        self.assertNotIn("RuntimeSnapshotMetadata",s)
        self.assertNotIn("A5E53089",s)
        # No change to the original strict journal deletion check.
        journal=(R / "ios-app/MirsaWallpaperJournal.swift").read_text().split("static func delete(",1)[1].split("static func cleanup(",1)[0]
        self.assertIn("actual == record.expected",journal)
        self.assertIn("MirsaPosterCopy.typedPaths(target) == record.paths",journal)
if __name__ == "__main__": unittest.main()
