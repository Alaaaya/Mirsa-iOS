"""Source wiring regressions. These do not claim iPhone runtime acceptance."""
from pathlib import Path
import unittest
R=Path(__file__).resolve().parents[2]
def read(p): return (R/p).read_text()
class ChoiceFirstCellular(unittest.TestCase):
 def test_all_external_entries_choose_before_details(self):
  root=read('ios-app/ContentView.swift')
  self.assertIn('.onOpenURL',root);self.assertIn('.mirsaIncomingIPA',root)
  first=root.split('.sheet(item: $incoming,',1)[1].split('.sheet(item: $incomingProject',1)[0]
  self.assertIn('IncomingIPAChoiceSheet(',first)
  self.assertNotIn('IncomingIPAConfirmationSheet(',first)
  wrapper=read('ios-app/Apps/IncomingIPAChoiceSheet.swift')
  self.assertIn('InstallChoiceSheet(pending:',wrapper)
  self.assertIn('await store.importIPA(from: url)',wrapper)
  self.assertIn('explicitIncomingInstall = true',wrapper)
  self.assertIn('commitPending(to: location, vm: vm)',wrapper)
  self.assertIn('PersonalAppsLibrary.shared.add(current.originalIPA',wrapper)
 def test_original_routes_and_live_quota_preserved(self):
  choice=read('ios-app/Apps/AppsView.swift').split('struct InstallChoiceSheet:',1)[1]
  for required in ['dismissThen(.container)','dismissThen(.real)','store.slotsLeft','store.realLimit','a.appIDsAvailable','a.appIDsMax','IPAEditorView(pending: current','CertificateInstallSheet(pending: current','if let onPersonal','choice.cancel','.leftToRight']:
   self.assertIn(required,choice)
  self.assertNotIn('trailing: "1/3"',choice)
 def test_no_wifi_prerequisite(self):
  store=read('ios-app/Apps/AppsStore.swift')
  preflight=store.split('func networkReady(',1)[1].split('func realAppNetworkReady',1)[0]
  self.assertNotIn('.wifi',preflight)
  policy=read('ios-app/Apps/DeviceConnectionPolicy.swift')
  self.assertIn('tunnelRoute && hasPairing',policy)
  route=read('ios-app/NetworkStatus.swift')
  self.assertIn('realAppNetworkReady(vm)',store)
  self.assertIn('التثبيت الحقيقي بدو واي فاي + LocalDevVPN',store)
  for file in ['ios-app/Apps/AppsStrings.swift','ios-app/Apps/MirsaTr.swift','ios-app/Apps/DeviceTools.swift']:
   text=read(file)
   self.assertNotIn('required to install',text)
   self.assertNotIn('مطلوب للتثبيت',text)
 def test_ota_remains_cached_and_vpn_free(self):
  cert=read('ios-app/Apps/CertificateInstall.swift').split('/// Moves the signed IPA',1)[0]
  self.assertIn('OwnCertificateDevice.require()',cert)
  self.assertNotIn('pairingFilePath',cert)
  self.assertNotIn('MirsaInstallMode.ownCertificate',cert)
  self.assertNotIn('networkReady',cert)
  self.assertNotIn('installSigned',cert)
  wrapper=read('ios-app/Apps/IncomingIPAChoiceSheet.swift')
  self.assertNotIn('networkReady',wrapper)
  self.assertNotIn('.wifi',wrapper)
  self.assertNotIn('vpnUp',wrapper)
if __name__=='__main__': unittest.main()
