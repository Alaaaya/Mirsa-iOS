import plistlib,re,subprocess,unittest,pathlib
R=pathlib.Path(__file__).resolve().parents[2]
class T(unittest.TestCase):
    def test_setup_strip_disjoint(self):
        wf=(R/'.github/workflows/unsigned-ipa.yml').read_text()
        self.assertIn('mirsa-container',wf)
        d=plistlib.loads((R/'ios-app/Info.plist').read_bytes())
        sch=lambda ts:{s for t in ts for s in t.get('CFBundleURLSchemes',[])}
        normal=sch(d['CFBundleURLTypes'])
        self.assertIn('mirsa-container',normal)
        setup=sch([t for t in d['CFBundleURLTypes'] if 'mirsa-container' not in t.get('CFBundleURLSchemes',[])])
        self.assertTrue(normal-setup=={'mirsa-container'})
        self.assertNotIn('mirsa-container',setup)
if __name__=='__main__': unittest.main()
