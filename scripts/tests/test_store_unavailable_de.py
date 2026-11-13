
import re,sys
FILES=['ios-app/Apps/AppStoreAccountView.swift','ios-app/Apps/ClassicAppStoreAccountView.swift']
def check(src):
    m=re.search(r'case "upstream_unavailable": return storeText\((.*)\)\n',src)
    if not m: return False
    b=m.group(1)
    return 'de: "Das Gerät' in b and 'ckb: "' in b and 'kmr: "' in b and b.count('"')>=10
def test_present():
    for f in FILES: assert check(open(f).read()), f
def test_negative_probe_detects_missing_german():
    s=open(FILES[0]).read()
    broken=re.sub(r'de: "Das Gerät[^"]*", ','',s)
    assert broken!=s and not check(broken)
if __name__=='__main__':
    test_present(); test_negative_probe_detects_missing_german(); print('ok')
