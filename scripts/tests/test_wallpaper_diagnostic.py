import pathlib
import unittest
R = pathlib.Path(__file__).resolve().parents[2]

class DiagnosticContractTests(unittest.TestCase):
    def test_process_restart_evidence_is_local_bounded_and_not_authority(self):
        r = R / "ios-app"
        journal = (r / "MirsaWallpaperJournal.swift").read_text()
        evidence = journal.split("enum MirsaWallpaperEvidence {", 1)[1]
        for token in ["maxEvents = 256", "maxLine = 2048", "maxBytes", "NSLock()", "options: .atomic", "st_nlink == 1", "HISTORY ", "uptime=", "build="]:
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
        self.assertIn("ForEach(items.filter { $0.canDelete })", ui)
        self.assertIn("ForEach(items.filter { !$0.canDelete })", ui)
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
    def test_apple_plist_identity_hides_without_extra_list_io_or_delete_changes(self):
        s=(R / "ios-app/MirsaCustomWallpapers.swift").read_text()
        classifier=s.split("static func isAppleCatalog(",1)[1].split("static func metadataIdentifier",1)[0]
        self.assertIn('fam == "WWDC22", pid == "19662"', classifier)
        self.assertNotIn("contentsOfDirectory", classifier)
        self.assertNotIn("Data(contentsOf", classifier)
        listing=s.split("private static func list(lease:",1)[1].split("static func list(log:",1)[0]
        self.assertLess(listing.index("if info.apple"), listing.index("appleHidden += 1"))
        self.assertIn('continue', listing.split("if info.apple",1)[1].split("title = info.name",1)[0])
        self.assertIn("canDelete: false", listing)

    def test_diagnostic_wait_uses_shared_lock_before_opening_lease(self):
        s=(R / "ios-app/MirsaWallpaperDiagnostics.swift").read_text()
        wrapper=s.split("static func withInspectionAccess",1)[1].split("static func inspect(",1)[0]
        self.assertIn("MirsaWallpaperJournal.exclusiveWaiting", wrapper)
        self.assertIn("isCancelled: isCancelled", wrapper)
        inspect=s.split("static func inspect(",1)[1]
        self.assertLess(inspect.index("try withInspectionAccess"), inspect.index("PosterBoardLease("))
        self.assertIn("defer { try? lease.close() }", inspect)
        self.assertNotIn("lock.unlock()", inspect)

    def test_owner_gate_does_not_override_child_identifiers(self):
        ui = (R / "ios-app/MirsaWallpaperManagementView.swift").read_text()
        gate = (R / "ios-app/MirsaOwnerDiagnostics.swift").read_text()
        self.assertIn('MirsaOwnerDiagnostics(access: diagnosticAccess)', ui)
        self.assertIn('@State private var expanded = false', gate)
        self.assertIn('if access.allowed && scenePhase == .active', gate)
        self.assertIn('if expanded { content().environmentObject(access) }', gate)
        self.assertIn('.accessibilityIdentifier("owner-diagnostics")', gate)
        self.assertNotIn('wallpaper-tools', ui)
        self.assertNotIn('DisclosureGroup(', gate)
        tendies = (R / "ios-app/TendiesView.swift").read_text()
        self.assertIn('.accessibilityIdentifier("wallpaper-import")', tendies)
        self.assertIn('picker.view.accessibilityIdentifier = "wallpaper-document-picker"', tendies)

    def test_creation_cards_are_main_content_not_maintenance(self):
        ui = (R / "ios-app/TendiesView.swift").read_text()
        main = ui.split('mainContent: {', 1)[1].split('extraTools: {', 1)[0]
        tools = ui.split('extraTools: {', 1)[1].split('// Bound the actual Form viewport', 1)[0]
        for token in ['ForEach($vm.tendieItems)', 'wallpaper-import', 'OriginalVideoWallpaperBlock(', 'WallpaperMakerSection(']:
            self.assertIn(token, main)
            self.assertNotIn(token, tools)
        self.assertEqual(ui.count('.accessibilityIdentifier("wallpaper-respring")'), 1)
        self.assertIn('wallpaper-install-selected', main)
        self.assertIn('wallpaper-respring', main)
        self.assertNotIn('wallpaper-respring', tools)
        self.assertLess(main.index('wallpaper-install-selected'), main.index('wallpaper-respring'))
        self.assertIn('Task { await vm.flashSelectedTendies() }', ui)
        self.assertIn('if selectedCount >= 1 { installSelectedNow(); return }', ui)
        self.assertIn('Button { offerRespring() }', ui)
        for icon in ['"checklist"', '"square.3.layers.3d"']:
            self.assertIn(icon, main)
        self.assertIn('Text(vm.posterBoardContainer.isEmpty', tools)
        management = (R / "ios-app/MirsaWallpaperManagementView.swift").read_text()
        self.assertLess(management.index('mainContent()'), management.index('MirsaOwnerDiagnostics(access: diagnosticAccess)'))
        self.assertLess(management.index('Button { reload() }'), management.index('MirsaOwnerDiagnostics(access: diagnosticAccess)'))
        self.assertLess(management.index('Button { confirmCleanup = true }'), management.index('MirsaOwnerDiagnostics(access: diagnosticAccess)'))
        self.assertLess(management.index('Text(TendiesPageText.text(.yours))'), management.index('mainContent()'))

    def test_primary_install_requires_successfully_picked_ids(self):
        ui = (R / "ios-app/TendiesView.swift").read_text()
        primary = ui.split('// Two primary actions side by side.', 1)[1].split('Button { showCustomRequest', 1)[0]
        self.assertIn('installAfterPicking = true', primary)
        self.assertIn('pickedInstallIDs = []', primary)
        self.assertIn('showFilePicker = true', primary)
        self.assertNotIn('wallpaperPrompt = .install', primary)
        self.assertNotIn('.disabled(selectedCount == 0)', primary)
        presenter = ui.split('private func presentPickedInstall()', 1)[1].split('private func offerRespring()', 1)[0]
        self.assertIn('guard !showFilePicker, !pickedInstallIDs.isEmpty else { return }', presenter)
        self.assertLess(presenter.index('selectPickedInstallOnly()'), presenter.index('wallpaperPrompt = .install'))
        self.assertIn('pickedInstallIDs.contains(vm.tendieItems[index].id)', presenter)
        picker = ui.split('.sheet(isPresented: $showFilePicker', 1)[1].split('.sheet(isPresented: $showCustomRequest', 1)[0]
        self.assertIn('guard shouldInstall else { return }', picker)
        self.assertIn('pickedInstallIDs = Set(importedIDs)', picker)
        model = (R / "ios-app/AppViewModel.swift").read_text()
        importer = model.split('func importTendieFiles(', 1)[1].split('func deleteTendie(', 1)[0]
        self.assertIn('guard !urls.isEmpty else { return [] }', importer)
        self.assertEqual(importer.count('importedIDs.append(item.id)'), 1)
        self.assertLess(importer.index('try await TendiesEngine.shared.importTendie'), importer.index('importedIDs.append(item.id)'))
        self.assertNotIn('importedIDs.append', importer.split('} catch {', 1)[1])
        self.assertIn('return importedIDs', importer)

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
