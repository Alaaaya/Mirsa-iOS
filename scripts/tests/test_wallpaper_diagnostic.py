import pathlib
import unittest
R = pathlib.Path(__file__).resolve().parents[2]

class DiagnosticContractTests(unittest.TestCase):
    def test_process_restart_evidence_is_local_bounded_and_not_authority(self):
        r = R / "ios-app"
        journal = (r / "MirsaWallpaperJournal.swift").read_text()
        evidence = journal.split("enum MirsaWallpaperEvidence {", 1)[1]
        for token in ["maxEvents = 256", "maxLine = 2048", "maxBytes", "NSLock()", "options: .atomic", "st_nlink == 1", "HISTORY ", "session=", "uptime=", "build="]:
            self.assertIn(token, evidence)
        for token in ["URLSession", "removeItem(", "PosterBoardLease(", "grant("]:
            self.assertNotIn(token, evidence)
        vm = (r / "AppViewModel.swift").read_text()
        self.assertIn("tendiesFlashLog = MirsaWallpaperEvidence.restored()", vm)
        self.assertIn("MirsaWallpaperEvidence.captureVisible", vm)
        engine = (r / "TendiesEngine.swift").read_text().split("public func flashTendies(", 1)[1].split("func prepareDescriptor(", 1)[0]
        self.assertLess(engine.index('log("COPY INTENT'), engine.index("try MirsaPosterCopy.copyExclusive("))
        self.assertIn('context: "post-copy uuid="', engine)
        self.assertIn('log("COPY VERIFIED', engine)
        self.assertIn('log("INSTALL ERROR', engine)
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
        # Build 425: content/hash gate dropped; identity checks stay.
        journal=(R / "ios-app/MirsaWallpaperJournal.swift").read_text().split("static func delete(",1)[1].split("static func cleanup(",1)[0]
        self.assertNotIn("actual == record.expected",journal)
        self.assertNotIn("Descriptor content changed",journal)
        self.assertIn("record.device",journal)
        self.assertIn("record.inode",journal)
        self.assertIn("lease.permits(target)",journal)
if __name__ == "__main__": unittest.main()
