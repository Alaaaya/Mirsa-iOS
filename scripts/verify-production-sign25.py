#!/usr/bin/env python3
"""Verify actual production-signer outputs from own-code hosted tests, never user IPA execution."""
import hashlib,json,pathlib,plistlib,stat,struct,subprocess,sys,tempfile,zipfile
root=pathlib.Path(sys.argv[1]);proof={}
def loads(b):
 assert b[:4]==b'\xcf\xfa\xed\xfe' and struct.unpack_from('<I',b,4)[0]==0x100000c
 offset=32; result=[]; signature=False
 for _ in range(struct.unpack_from('<I',b,16)[0]):
  cmd,size=struct.unpack_from('<II',b,offset);assert size>=8 and offset+size<=len(b)
  if cmd in (12,0x80000018,0x8000001f):
   at=struct.unpack_from('<I',b,offset+8)[0];result.append(b[offset+at:offset+size].split(b'\0')[0].decode())
  if cmd==0x1d:
   at,n=struct.unpack_from('<II',b,offset+8);assert n>0 and at+n<=len(b);signature=True
  offset+=size
 assert signature,'Unsigned final executable'
 return result
for mode in ('ON','OFF'):
 file=root/(mode+'.ipa')
 with tempfile.TemporaryDirectory() as d, zipfile.ZipFile(file) as z:
  names=z.namelist();assert len(names)==len(set(names))
  for name in names:
   p=pathlib.PurePosixPath(name);assert not p.is_absolute() and '..' not in p.parts and '\\' not in name
  # Only own-code CI fixtures may be unpacked and verified here, never launched.
  for entry in z.infolist():
   assert not stat.S_ISLNK(entry.external_attr >> 16)
  z.extractall(d)
  # zipfile extracts regular files as 0644; verify the original archive modes.
  for entry in z.infolist():
   if not entry.is_dir():
    mode=(entry.external_attr >> 16) & 0o777
    if mode: (pathlib.Path(d)/entry.filename).chmod(mode)
  payload=pathlib.Path(d)/'Payload';apps=list(payload.glob('*.app'));assert len(apps)==1
  app=apps[0];info=plistlib.loads((app/'Info.plist').read_bytes());deps=loads((app/info['CFBundleExecutable']).read_bytes())
  rt=app/'Frameworks/MirsaTranslate.dylib';cfg=app/'Frameworks/MirsaTranslations.json'
  if mode=='ON':
   assert rt.is_file() and cfg.is_file() and (app/'Frameworks/MirsaBackground.dylib').is_file()
   assert deps.count('@loader_path/Frameworks/MirsaTranslate.dylib')==1
   assert deps.count('@loader_path/Frameworks/MirsaBackground.dylib')==1
   obj=json.loads(cfg.read_bytes());assert obj['translations']=={} and obj['online']['bundleId']==info['CFBundleIdentifier']
   assert obj['revision']==obj['online']['revision'] and obj['online']['token'].startswith('mrt1.')
  else:assert not rt.exists() and not cfg.exists() and not any('Mirsa' in dep for dep in deps)
  for binary in app.glob('Frameworks/*.dylib'):
   loads(binary.read_bytes());subprocess.run(['codesign','--verify','--strict','--verbose=4',str(binary)],check=True)
  subprocess.run(['codesign','--verify','--deep','--strict','--verbose=4',str(app)],check=True)
  proof[mode]={'sha256':hashlib.sha256(file.read_bytes()).hexdigest(),'loads':deps,'signatureVerified':True}
(root/'verification.json').write_text(json.dumps(proof,indent=2))
print('Production signed ON/OFF arm64 IPA resources, exact LC loads and strict codesign verified')
