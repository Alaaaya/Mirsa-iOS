"""Offline source contracts and extracted-regex canaries, NOT a Swift/Xcode test substitute."""
import json
import pathlib
import re
import unittest
import urllib.parse

R = pathlib.Path(__file__).resolve().parents[2]
S = R / 'ios-app'
PRIVACY = (S / 'MirsaDiagnosticPrivacy.swift').read_text()
RULES = [(re.compile(p), replacement) for p, replacement in re.findall(r'\(#"(.*?)"#, "(.*?)"\)', PRIVACY)]


def extracted_regex_model(text):
    # Mirrors only normalizing/filtering semantics, executes the actual extracted regex text.
    if len(text.encode()) > 64 * 1024:
        return '[oversized diagnostic omitted]'
    text = text.replace(r'\/', '/')
    for _ in range(2):
        text = urllib.parse.unquote(text)
    text = re.sub(r'\\u([0-9a-fA-F]{4})', lambda m: chr(int(m[1], 16)), text)
    text = text.replace('\r\n', '\n').replace('\r', '\n')
    text = ''.join(c for c in text if c in '\n\t' or (ord(c) >= 32 and ord(c) != 127 and c not in '\u200b\u200c\u200d\ufeff'))
    for regex, replacement in RULES:
        text = regex.sub(replacement, text)
    return text[:2048]


class DiagnosticPrivacySourceTests(unittest.TestCase):
    def test_regex_canaries_and_idempotence(self):
        self.assertGreaterEqual(len(RULES), 15)
        secret = 'SyntheticFixturePrivate_OnlyTests_12345'
        canaries = [
            ('token=' + secret + ' code=403 count=25', secret),
            ('Authorization: Bearer ' + secret, secret),
            ('authorization=Basic shortCanary', 'shortCanary'),
            ('accountName=Fixture Person code=403 files=25', 'Fixture Person'),
            ('path="/private/var/mobile/Fixture Person/privatefile" errno=2 files=25', 'Fixture Person'),
            ('token%253D' + secret, secret),
            ('tok\u200ben=' + secret, secret),
            (r'path=\u002Fvar\u002Fmobile\u002FFixturePrivate code=403', 'FixturePrivate'),
            ('url https://example.invalid/private?secret=' + secret, 'example.invalid/private'),
            ('user_id=01020304-0506-4708-890a-0b0c0d0e0f10 code=2', '01020304'),
            ('address 192.168.50.42 code=2', '192.168.50.42'),
            ('email=fixture-person@example.invalid code=403', 'fixture-person'),
        ]
        for text, forbidden in canaries:
            with self.subTest(case=canaries.index((text, forbidden))):
                safe = extracted_regex_model(text)
                self.assertNotIn(forbidden, safe, 'Synthetic canary survived')
                self.assertEqual(safe, extracted_regex_model(safe))
        safe = extracted_regex_model('COPY VERIFIED path="/var/mobile/private folder" errno=2 files=25 code=403')
        for useful in ['COPY VERIFIED', 'errno=2', 'files=25', 'code=403']:
            self.assertIn(useful, safe)

    def test_all_retained_log_arrays_and_callback_sinks_are_filtered(self):
        vm = (S / 'AppViewModel.swift').read_text()
        for name in ['log', 'cardFlashLog', 'passthmFlashLog', 'tendiesFlashLog']:
            self.assertIn('@Published private var safe_' + name, vm)
        self.assertIn('MirsaDiagnosticPrivacy.appending(old:', vm)
        self.assertIn('sink(stream.line($0))', vm)
        evidence = (S / 'MirsaWallpaperJournal.swift').read_text().split('enum MirsaWallpaperEvidence {')[1]
        for token in ['MirsaDiagnosticPrivacy.lines(Array(', 'events = MirsaDiagnosticPrivacy.lines(events + [line])', 'static func restore(at url:', 'JSONEncoder().encode(events).write', 'log(MirsaDiagnosticPrivacy.line(line))']:
            self.assertIn(token, evidence)
        engine = (S / 'TendiesEngine.swift').read_text()
        self.assertIn('output(diagnosticStream.line(line))', engine)
        side = (S / 'Apps/SideloadService.swift').read_text()
        self.assertIn('diagnosticStream.line(InstallErrorText.sanitize', side)
        store = (S / 'Apps/AppsStore.swift').read_text()
        self.assertIn('legacyInstallDiagnostics = MirsaDiagnosticPrivacy.migrateInstallBreadcrumbs(ud)', store)
        self.assertNotIn('error = tr("Previous install stopped at', store)

    def test_display_clipboard_and_export_share_final_boundary(self):
        ui = (S / 'ContentView.swift').read_text().split('struct CompactLogView: View {')[1].split('// MARK: - Native Document Picker')[0]
        for token in ['private var safeLines: [String] { lines }', 'MirsaDiagnosticPrivacy.copy(lines', 'ForEach(Array(safeLines.enumerated())']:
            self.assertIn(token, ui)
        self.assertNotIn('lines.joined', ui)
        self.assertIn('write(formatted(input))', PRIVACY)
        self.assertIn('Data(formatted(input).utf8)', PRIVACY)
        self.assertIn('let begins = text.contains("-----BEGIN ")', PRIVACY)

    def test_failclosed_existing_server_entitlement_not_client_flag(self):
        access = (S / 'MirsaOwnerDiagnostics.swift').read_text()
        for token in ['session.expiresAt > Date()', 'ForgeClient.existingFixCredentials', 'ForgePreciseClient.capability(c)', 'revoke() // loading', 'attempt == generation', 'identity() == current', 'guard await refresh(), allowed', 'if access.allowed && scenePhase == .active', '@State private var expanded = false', 'access.invalidateIfIdentityChanged()', '.onDisappear { access.revoke()']:
            self.assertIn(token, access)
        for token in ['fixToken(', 'ForgePreciseStore.shared.enabled', '@AppStorage', 'SecureField', 'UserDefaults']:
            self.assertNotIn(token, access)
        management = (S / 'MirsaWallpaperManagementView.swift').read_text()
        before, after = management.split('MirsaOwnerDiagnostics(access: diagnosticAccess)', 1)
        self.assertNotIn('Button { inspect(rec)', before)
        self.assertIn('Section { extraTools() }', before)
        self.assertNotIn('extraTools()', after)
        self.assertIn('journalRows', after)
        for name in ['reconcile', 'deleteJournalItem', 'inspect']:
            fn = management.split('private func ' + name + '(', 1)[1].split('\n    private func ', 1)[0]
            self.assertIn('await diagnosticAccess.perform', fn)

    def test_actual_swift_tests_and_ci_selectors_exist(self):
        tests = (R / 'tests/MirsaDiagnosticPrivacyTests.swift').read_text()
        for name in ['testDisplayCopyAndExportUseIdenticalSanitizedFormatting', 'testHistoricalEvidenceIsSanitizedAndRewrittenAndNewAppendNeverPersistsRaw', 'testUnauthenticatedAndNonownerCannotPerformAnyDiagnosticAction', 'testLoadingCredentialChangeAndBackgroundFailClosed', 'testExplicitRevokeInvalidatesInFlightServerResponse']:
            self.assertIn('func ' + name, tests)
        workflow = (R / '.github/workflows/forge-validation.yml').read_text()
        self.assertIn('-only-testing:MirsaTests/MirsaDiagnosticPrivacyTests', workflow)
        self.assertIn('-only-testing:MirsaTests/MirsaDiagnosticAccessTests', workflow)
        ui = (R / 'uitests/MirsaStyleScreenshotsUITests.swift').read_text()
        self.assertIn('["ar", "en", "de", "kmr", "ckb"]', ui)
        self.assertIn('func testNonownerHasNoDiagnostics()', ui)

if __name__ == '__main__':
    unittest.main()
