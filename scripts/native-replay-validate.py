#!/usr/bin/env python3
import hashlib,json,pathlib,subprocess
P=pathlib.Path(__file__).resolve().parents[1]
BASE='a10f6e82f1b42e567955fb74ebfa0036f798f21b'
BASE_PINS={'ios-app/Apps/ForgeChat.swift': '65f500e6b8aa9af7719a6c6eb5a1f8ff0f2c3bcf8d1d23f940bc1dde1d3b4a1f', 'ios-app/Apps/ForgeChatArtifact.swift': 'fa8d14f7f8965a4685b4477245d61e73d7c63b876f54ac3ca9dc8fd5de12f600', 'ios-app/Apps/ForgeChatTimeline.swift': 'bb26c6085726d4312a13725147dd03e67c07bd1af19effceeba3a179834fe31b', 'ios-app/MirsaStyleShotHost.swift': '30c5a5b9b79d4ad39fa4c5e8fae2d6098a4ff62714c1547bc9412a99a58a6433', 'project.yml': '2726e013b4c7234dbba3ff01f54541b51ffa4ef1534fcf7ab82c50a3355e922a'}
EXPECTED=[{'hash': 'ffbcb6997b6edd2e5002f87ec27882f6637debbeb09a7fda531c49e709927dab', 'id': 'dbff8915-ac5b-cf1d-d18f-15f8fe42f7eb', 'resendOf': '2d6810e6-aee1-4527-bf80-512e5493eea4', 'name': 'النسخة (1) · MirsaFixture-v1.zip', 'revision': 1}, {'hash': 'e74644d2663d70d6d4f5258bf54aedf4bc0006ad8f753af9f2aa92ccfc5ab8ce', 'id': 'b60f6dbd-8fc2-18f0-604e-e8b0256c594b', 'resendOf': '2af147fd-1e18-4634-a1a2-de50be769af5', 'name': 'النسخة المصحّحة (2) · MirsaFixture-v2.zip', 'revision': 2}, {'hash': '3af5af9bb1d53c769ad41b0ac88e8c85947dbfebb8ae17c2ffefef5a52b548ac', 'id': '4cbc1806-0fad-c127-aa2b-8bfc79ae8889', 'resendOf': '9a80a808-94cc-4b28-8921-f518228de67b', 'name': 'النسخة المصحّحة (2) · MirsaFixture-v2.zip', 'revision': 2}, {'hash': 'e388d9fa49d699cc4a73a933d038d74d81ecbd10ffab48ac4797aa9c9cc80ab8', 'id': '9b17d95e-5a5e-dc69-55f4-90e3e5a9ba28', 'resendOf': '816c21cf-79f4-4a6d-847f-2b3ab6139222', 'name': 'النسخة المصحّحة (2) · MirsaFixture-v2.zip', 'revision': 2}, {'hash': '9a9b0c59a554be468cd0974809d21fa50035e54c2951712a4171c3ce2243027d', 'id': '862f84fa-1336-fc49-501b-37156563a5a8', 'resendOf': '7740dd32-f174-49e8-b8d7-0ba1074b4675', 'name': 'النسخة المصحّحة (2) · MirsaFixture-v2.zip', 'revision': 2}]
RESOURCE_SHA='60d884fc92ad2e569ffc2e47ab4c384b52d6031e7b4c36fff761a02e1fbf1656'
sha=lambda b:hashlib.sha256(b).hexdigest()
for n,h in BASE_PINS.items():
    assert sha(subprocess.check_output(['git','show',BASE+':'+n],cwd=P))==h,('base file changed',n)
    if n!='ios-app/Apps/ForgeChat.swift':
        assert sha((P/n).read_bytes())==h,('renderer or project changed',n)
raw=(P/'ios-app/NativeReplayFragments.json').read_bytes()
assert sha(raw)==RESOURCE_SHA
data=json.loads(raw);assert data['sourceVersion']==107 and len(data['cases'])==5
ids=[];resends=[]
for c,expected in zip(data['cases'],EXPECTED):
    m=c['message'];r=m['result'];a=r['artifact']
    canonical=json.dumps(m,ensure_ascii=False,sort_keys=True,separators=(',',':')).encode()
    assert sha(canonical)==c['fragmentSHA256']==expected['hash']
    assert m['id']==expected['id'] and r['resendOf']==expected['resendOf']
    assert a['name']==c['expectedFilename']==expected['name']
    assert r['deliveryRevision']==c['deliveryRevision']==expected['revision']
    assert a['kind']=='zip' and m['role']=='result'
    ids.append(m['id']);resends.append(r['resendOf'])
assert len(set(ids))==len(set(resends))==5
print('PASS five exact canonical captured fragments, unique message/resend IDs, approved base and unchanged renderer pins')
