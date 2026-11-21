"""Static regressions for the prerequisite alert, without touching network/services."""
import pathlib
import plistlib

root = pathlib.Path(__file__).resolve().parents[1]
store = (root / "ios-app/Apps/AppsStore.swift").read_text()
assert "localdevvpn" in plistlib.loads((root / "ios-app/Info.plist").read_bytes())["LSApplicationQueriesSchemes"]
assert 'URL(string: "localdevvpn://enable?scheme=mirsa")' in store
assert 'https://apps.apple.com/us/app/localdevvpn/id6755608044' in store
assert "canOpenURL(appURL)" in store and "if !opened" in store
assert "if error == nil { errorOffersLocalDevVPN = false;" in store
vpn = store.split("guard networkReady(vm) else {", 1)[1].split("return true", 1)[0]
assert "offersSettings: false" in vpn and "errorOffersLocalDevVPN = true" in vpn
wifi = store.split("case .needWiFi:", 1)[1].split("case .undetermined:", 1)[0]
assert "offersSettings: true" in wifi
for name in ["AppsView", "SetupView"]:
    view = (root / f"ios-app/Apps/{name}.swift").read_text()
    assert "if store.errorOffersLocalDevVPN {" in view
    assert "AppsStore.openLocalDevVPN(); store.error = nil" in view
    for label in ["Open LocalDevVPN", "فتح LocalDevVPN", "LocalDevVPN öffnen", "کردنەوەی LocalDevVPN", "LocalDevVPN veke"]:
        assert label in view
    assert 'Button(tr("Open Settings"' in view
assert 'Button(tr("Copy log"' in (root / "ios-app/Apps/AppsView.swift").read_text()
print("LocalDevVPN alert routing, 5 languages, fallback and existing actions PASS")

assert 'resumeAfterLocalDevVPN' in (root / 'ios-app/MirsaApp.swift').read_text()
assert 'for _ in 0..<12' in store
assert 'awaitingVPNReturn, !resumingVPN' in store
assert 'await retry?()' in store
export = (root / 'ios-app/Apps/IPAEditorService.swift').read_text()
assert 'file.path.hasPrefix(root.path + "/")' in export
assert '!relative.split(separator: "/").contains("..")' in export
card = (root / 'ios-app/Apps/ExistingLibraryPlan.swift').read_text()
assert 'ShareSheet(items: [exportURL])' in card
assert 'exportExistingLibrary(row.lib, from: sourceIPA)' in card
print("VPN callback, bounded retry, safe library export PASS")
