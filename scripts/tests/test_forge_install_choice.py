from pathlib import Path
import unittest
ROOT = Path(__file__).resolve().parents[2]
class ForgeInstallChoiceTests(unittest.TestCase):
    def test_both_injected_ipas_use_existing_incoming_flow(self):
        source = (ROOT / "ios-app/Apps/ForgeView.swift").read_text()
        for operation in ("inject", "injectInspector"):
            self.assertIn(f"let ipa = try await store.{operation}(id); NotificationCenter.default.post(name: .mirsaIncomingIPA, object: ipa)", source)
            self.assertNotIn(f"shareURL = try await store.{operation}(id)", source)
    def test_dylib_and_deb_remain_share_actions(self):
        source = (ROOT / "ios-app/Apps/ForgeView.swift").read_text()
        self.assertIn("shareURL = try await store.exportDylib(id)", source)
        self.assertIn("shareURL = try await store.exportDeb(d)", source)
    def test_existing_receiver_owns_snapshot_and_choice(self):
        source = (ROOT / "ios-app/ContentView.swift").read_text()
        receiver = source.split(".onReceive(NotificationCenter.default.publisher(for: .mirsaIncomingIPA))", 1)[1]
        self.assertIn("OpenInIPA.snapshot(file)", receiver)
        self.assertIn("IncomingIPAChoiceSheet(url: item.url", receiver)
if __name__ == "__main__": unittest.main()
