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
  self.assertIn('التحديث بدو واي فاي + LocalDevVPN',store)
  self.assertIn('realAppNetworkReady(vm, selfUpdate: true)',store)
  for file in ['ios-app/Apps/AppsStrings.swift','ios-app/Apps/MirsaTr.swift','ios-app/Apps/DeviceTools.swift']:
   text=read(file)
   self.assertNotIn('required to install',text)
   self.assertNotIn('مطلوب للتثبيت',text)
 def test_certificate_routes_are_always_ota(self):
  for file in ['CertificateInstall.swift', 'PersonalSigningOperation.swift']:
   code=read('ios-app/Apps/'+file)
   self.assertIn('CertificateOTA.install(', code)
   for forbidden in ['pairingFilePath(', 'installSigned(', 'OwnCertificateDevice.require()\n','NetworkStatus.summarize']:
    self.assertNotIn(forbidden, code)
  ota=read('ios-app/Apps/CertificateOTA.swift')
  self.assertIn('(try? OwnCertificateDevice.require()) ?? ""',ota)
  self.assertIn('CertificateInstall.retain(signed.url)',ota)
  self.assertIn('CertificateInstall.Failure.retained',ota)
  self.assertIn('install.scheme = "itms-services"',ota)
  signer=read('ios-app/Apps/PersonalCertificateView.swift')
  self.assertIn('"cached_only": true',signer)
 def test_import_menu_anchored_to_actual_button(self):
  apps=read('ios-app/Apps/AppsView.swift')
  home=read('ios-app/Apps/MirsaHomeScreen.swift')
  self.assertNotIn('showImportOptions',apps)
  self.assertIn('onImportLink: { showURLImport = true }',apps)
  self.assertIn('SwiftUI.Menu {',home)
  self.assertNotIn('Button(action: onImport)',home)
if __name__=='__main__': unittest.main()
