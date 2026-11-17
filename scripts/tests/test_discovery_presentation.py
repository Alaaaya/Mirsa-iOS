"""Source-only global search contract. Native behavior tests run on macOS."""
from pathlib import Path
import unittest
ROOT = Path(__file__).resolve().parents[2]
class DiscoveryPresentationTests(unittest.TestCase):
    def test_sources_only(self):
        view = (ROOT / "ios-app/Discovery/DiscoveryView.swift").read_text()
        for removed in ["AppleMetadata", "WebBackend", "DiscoveryEngine.run", "webSettings",
                        "showWeb", 'systemName: "network"', "DiscoveryIPAVerifier",
                        "DiscoveryDownloader", "Telegram", "SafeMetadataHTTP"]:
            self.assertNotIn(removed, view)
        for required in ["await sources.loadMissing()", "sources.visibleSources.flatMap",
                         "app.name.localizedCaseInsensitiveContains(term)",
                         "RepoAppRow(app: match.app", "store.failures", "store.results"]:
            self.assertIn(required, view)
        self.assertNotIn(".prefix(", view)
        self.assertNotIn("if SourcesStore.shared.apps.isEmpty", view)
if __name__ == "__main__":
    unittest.main()
