#!/bin/bash
# Validate the checked-in platform linker inputs without mutating sources.
# project.yml selects these for normal production and simulator builds too.
set -euo pipefail
sdk="${1:?expected iphoneos or iphonesimulator}"
case "$sdk" in iphoneos|iphonesimulator) ;; *) exit 2 ;; esac
root="$(cd "$(dirname "$0")/.." && pwd)"
python3 - "$root" "$sdk" <<'PY'
import hashlib, json, pathlib, shutil, sys
root=pathlib.Path(sys.argv[1]);sdk=sys.argv[2]
v=root/'vendor/PrivateKits';m=json.loads((v/'LinkerStubs/PROVENANCE.json').read_text())
out=root/'build'/('privatekits-sdk-'+sdk);out.mkdir(parents=True,exist_ok=True)
expected='arm64-ios-simulator' if sdk=='iphonesimulator' else 'arm64-ios'
selected=[entry for entry in m['files'] if entry['path'].startswith('LinkerStubs/'+sdk+'/')]
assert len(selected)==2
for entry in selected:
    p=v/entry['path'];b=p.read_bytes()
    assert hashlib.sha256(b).hexdigest()==entry['sha256'], 'Stub digest mismatch '+p.name
    data=json.loads(b)['main_library']
    assert expected in [t['target'] for t in data['target_info']], 'Wrong target '+p.name
    framework=p.stem
    assert data['install_names']==[{'name':'/System/Library/PrivateFrameworks/'+framework+'.framework/'+framework}]
    shutil.copyfile(p,out/p.name)
    print(entry['sha256'],entry['path'])
shutil.copyfile(v/'LinkerStubs/PROVENANCE.json',out/'PROVENANCE.json')
PY
