"""Fail-closed public release attestation. No publishing side effects."""
import hashlib, io, json, pathlib, plistlib, re, subprocess, urllib.request, zipfile

def validate(release, kb):
 assert release['tag_name'].removeprefix('v')==kb['version']=='2.0'
 assert re.fullmatch('[0-9a-f]{40}',kb['sourceCommit'])
 assert release['reviewedSourceCommit']==kb['sourceCommit']
 assert release.get('target_commitish',kb['sourceCommit'])==kb['sourceCommit']
 assert kb['knownIssuesReviewed'] is True
 assert len(kb['facts'])>=18
 assert kb['localizedUI']['sourceCommit']==kb['sourceCommit']
 assert kb['localizedUI']['version']==kb['version']
 assert set(kb['localizedUI']['labels'])=={'ar','en','ckb','kmr'}
 for labels in kb['localizedUI']['labels'].values():
  assert all(isinstance(v,str) and v.strip() for v in labels.values())
 for topic in ['navigation','free-account','connection','pairing','certificate','downloads-sources','precise','temp-cleanup','public-delete-caveat','app-store']:
  assert any(x['id']==topic for x in kb['facts']),topic
 issues={x['id']:x for x in kb['knownIssues']}
 assert issues['app-store-login']['availability']=='coming-soon'
 assert '2FA' in issues['app-store-login']['status']
 assert 'unavailable' in issues['app-store-login']['status']
 assert kb['releaseBoundary'].startswith('Public release is 2.0.')
 assert 'coming soon' in kb['releaseBoundary'].lower()
 s=json.dumps(kb,ensure_ascii=False)
 for forbidden in ['91f71c66','138.2.136.36','info@travel','owner-only','204 with no','no delivered code','Public 1.9','Proposed 2.0 fixes are NOT public']:
  assert forbidden not in s,forbidden

 assert re.fullmatch('[0-9a-f]{64}', release['sourceTreeSha256'])
 assert re.fullmatch('[0-9a-f]{64}', release['ipaSha256'])

def source_digest():
 names=subprocess.check_output(['git','ls-files','-z']).decode().split('\0')
 # Release plumbing/docs are not app code. Everything else is exact-byte bound.
 names=sorted(n for n in names if n and not n.startswith(('.github/','docs/','scripts/release/')))
 digest=hashlib.sha256()
 for name in names:
  content=subprocess.check_output(['git','show','HEAD:'+name])
  digest.update(name.encode()+b'\0'+hashlib.sha256(content).digest())
 return digest.hexdigest()

def validate_feed(feed, manifest):
 apps=[a for a in feed['apps'] if a['bundleIdentifier'] in ('com.alaa.mirsa','com.alaa.mirsa.setup')]
 assert apps and all(a['version']==manifest['tag_name'].removeprefix('v') for a in apps)
 for app in apps:
  assert all(v['version']==app['version'] for v in app.get('versions',[])[:1])

def remote_gate(feed, normal_ipa=None):
 apps=[a for a in feed['apps'] if a['bundleIdentifier']=='com.alaa.mirsa.setup']
 assert len(apps)==1
 version=apps[0]['version']
 # Existing 1.9 remains serviceable until the reviewed 2.0 cutover.
 if version=='1.9': return
 assert version=='2.0', 'New versions require a reviewed KB gate update'
 origin='https://github.com/Alaaaya/Mirsa-iOS/releases/download/'+version+'/'
 def load(name):
  with urllib.request.urlopen(origin+name,timeout=60) as r:return json.load(r)
 manifest=load('reviewed-release-manifest.json');kb=load('public-kb.json')
 validate(manifest,kb);validate_feed(feed,manifest)
 if normal_ipa is not None: assert hashlib.sha256(normal_ipa).hexdigest()==manifest['ipaSha256']

if __name__=='__main__':
 import argparse
 p=argparse.ArgumentParser();p.add_argument('mode',choices=['preflight','artifact']);p.add_argument('--ipa');a=p.parse_args()
 folder=pathlib.Path('docs/public-release')
 manifest=json.loads((folder/'reviewed-release-manifest.json').read_text());kb=json.loads((folder/'public-kb.json').read_text())
 # Hash is deliberately supplied AFTER the final source is reviewed, not a commit self-reference.
 assert manifest['sourceTreeSha256']==source_digest(), 'Unreviewed source tree'
 if a.mode=='preflight':
  staged=dict(manifest,ipaSha256='0'*64);validate(staged,kb)
 else:
  data=pathlib.Path(a.ipa).read_bytes()
  with zipfile.ZipFile(io.BytesIO(data)) as z:
   assert z.testzip() is None
   for n in z.namelist():
    if n=='Payload/Mirsa.app/Info.plist' or n.endswith('.appex/Info.plist'):
     assert plistlib.loads(z.read(n))['CFBundleShortVersionString']=='2.0'
  manifest['ipaSha256']=hashlib.sha256(data).hexdigest();validate(manifest,kb)
  out=pathlib.Path('build/release-attestation');out.mkdir(parents=True,exist_ok=True)
  (out/'reviewed-release-manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
  (out/'public-kb.json').write_text(json.dumps(kb,ensure_ascii=False,indent=2)+'\n')
