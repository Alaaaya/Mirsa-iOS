"""Source/release gates, not a substitute for physical drag gesture testing."""
from pathlib import Path
import json,re,unittest
R=Path(__file__).resolve().parents[2]
class Gate(unittest.TestCase):
 def test_removed_tools_have_no_screen_or_entrypoint(self):
  tools=(R/'ios-app/Apps/ToolsTab.swift').read_text()
  self.assertIn('case pairing, device',tools)
  self.assertIn('case .pairing: SetupPairingSheet(showsClose: false)',tools)
  self.assertIn('case .device: DeviceToolsView()',tools)
  for name in ['WalletCardsTab','PasscodeThemeTab','TendiesView']:
   for f in (R/'ios-app').rglob('*.swift'):
    self.assertNotIn(name,f.read_text(),str(f))
 def test_existing_titles_unchanged_in_all_languages(self):
  for f in ['ios-app/Apps/PersonalProjectDetailView.swift','ios-app/Apps/MirsaTr.swift']:
   old=json.loads((R/'scripts/tests/direct_title_baseline.json').read_text())[f]
   after=(R/f).read_text()
   # Includes the Arabic source title and both Kurdish localized titles.
   new=[x.strip() for x in after.splitlines() if '"Direct injection (main executable)"' in x]
   self.assertEqual(len(old),len(new))
   for a,b in zip(old,new):
    # Description changed, title arguments must stay byte-identical.
    self.assertEqual(a.split('), personalText(')[0],b.split('), personalText(')[0])
 def test_loader_brand_and_no_developer_note(self):
  detail=(R/'ios-app/Apps/PersonalProjectDetailView.swift').read_text()
  tr=(R/'ios-app/Apps/MirsaTr.swift').read_text()
  self.assertIn('"Off uses LoadControl (arm64 only)."', detail)
  self.assertIn('LoadControl (arm64 بس)',detail)
  self.assertEqual(tr.count('"Off uses LoadControl (arm64 only)."'),2)
  self.assertNotIn('untested on device',detail+tr)
  self.assertNotIn("Mirsa's own ordered loader",detail+tr)
  self.assertIn('تەنها arm64',tr);self.assertIn('tenê arm64',tr)
 def test_drag_has_no_context_or_tap_recognizer_in_edit_mode(self):
  source=(R/'ios-app/Apps/MirsaHomeScreen.swift').read_text()
  personal=(R/'ios-app/Apps/PersonalAppsHome.swift').read_text()
  self.assertIn('if editing { content } else { content.contextMenu',source)
  self.assertIn('if enabled { content.onTapGesture',source)
  for text in [source,personal]:
   self.assertIn('MirsaHomeContextMenu(editing: editing)',text)
   self.assertIn('MirsaEditLongPress(editing: editing)',text)
   self.assertIn('"Arrange apps"',text)
  self.assertIn('.draggable(itemID)',source)
  self.assertIn('onReorder(d)',source)
  self.assertIn('onOnto(d)',source)
 def test_stable_cache_keeps_decoded_icon_on_transient_failure(self):
  source=(R/'ios-app/Apps/MirsaHomeScreen.swift').read_text()
  self.assertIn('return previous?.image',source)
  self.assertIn('previous.revision == revision',source)
  self.assertNotIn('NSCache<NSString, UIImage>',source)
if __name__=='__main__':unittest.main()
