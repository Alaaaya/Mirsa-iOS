import pathlib, unittest, yaml, fnmatch
ROOT = pathlib.Path(__file__).resolve().parents[2]

class FixtureSourceBoundaryTests(unittest.TestCase):
    def test_owned_payload_sources_never_compile_into_test_runner(self):
        spec = yaml.safe_load((ROOT / "project.yml").read_text())
        sources = spec["targets"]["MirsaTests"]["sources"]
        scan = next(s for s in sources if s["path"] == "tests")
        for spelling in ("fixtures", "Fixtures"):
            for folder, file in (("exact-hooks25", "MirsaHookTest.m"), ("exact-hooks25", "Alaa.m"), ("exact-hooks25", "ExactLaunch25.m"), ("generic-injection25", "LaunchHost.m"), ("generic-injection25", "Marker.c")):
                relative = f"{spelling}/{folder}/{file}"
                self.assertTrue(any(fnmatch.fnmatchcase(relative, rule) for rule in scan["excludes"]), relative)
        for name in ("Alaa.dylib", "MirsaHookTest.dylib", "ExactLaunch25Fixture.ipa", "GenericLaunch25Fixture.ipa"):
            self.assertTrue(any(s["path"].endswith("/" + name) and s.get("buildPhase") == "resources" for s in sources), name)

if __name__ == "__main__":
    unittest.main()
