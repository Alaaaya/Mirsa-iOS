"""Source regression checks for moving, not duplicating, translation in Tools."""
import pathlib, unittest
ROOT = pathlib.Path(__file__).resolve().parents[2]

class TranslationToolsTabTests(unittest.TestCase):
    def test_existing_tab_order_and_ltr_preserved(self):
        tools = (ROOT / 'ios-app/Apps/ToolsTab.swift').read_text()
        self.assertIn('case pairing, device, tweaks, translate', tools)
        self.assertIn('case .translate: ForgeTranslateView()', tools)
        self.assertIn('.environment(\\.layoutDirection, .leftToRight)', (ROOT / 'ios-app/MirsaApp.swift').read_text())
        self.assertIn('tr("Translation", "الترجمة", ckb: "وەرگێڕان", kmr: "Wergerandin")', tools)

    def test_translation_card_moved_with_actions_intact(self):
        text = (ROOT / 'ios-app/Apps/ForgeView.swift').read_text()
        tweaks, translation = text.split('struct ForgeTranslateView: View', 1)
        translation = translation.split('struct ForgeProjectView', 1)[0]
        self.assertNotIn('IPAStringsTranslator', tweaks)
        self.assertNotIn('translateMode', text)
        for required in ['IPAStringsTranslator.targets', 'langs.contains(t.code)', 'langs.remove(t.code)', 'langs.insert(t.code)', '"Choose IPA", "اختر IPA"', 'IPAStringsTranslator.run(ipa: local, languages: chosen)', 'shareURL = r.output', 'ForgeShareSheet(url: $0.url)', 'r.strings', 'r.files']:
            self.assertIn(required, translation)
        self.assertIn('ForgeStore.inspect(ipa: local)', tweaks)
        self.assertIn('store.create(ipa: local, info: info)', tweaks)

if __name__ == '__main__':
    unittest.main()
