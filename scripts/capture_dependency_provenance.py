#!/usr/bin/env python3
"""Retain exact runner resolution, never infer revisions from mutable tags."""
import hashlib, json, os, pathlib, shutil, subprocess
root = pathlib.Path.cwd()
out = root / 'build/dependency-provenance'
out.mkdir(parents=True, exist_ok=True)
lock = root / 'Mirsa.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved'
committed = root / 'Dependencies/Package.resolved'
assert json.loads(lock.read_text())['pins'] == json.loads(committed.read_text())['pins'], 'Device dependency pins drifted'
shutil.copy2(lock, out / 'Package.resolved')
states = list((root / 'build/DerivedData/SourcePackages').glob('workspace-state.json'))
assert len(states) == 1, 'Missing exact device workspace state'
shutil.copy2(states[0], out / 'workspace-state.json')
checkouts = {}
for checkout in sorted((root / 'build/DerivedData/SourcePackages/checkouts').iterdir()):
    if checkout.is_dir():
        revision = subprocess.check_output(['git', '-C', str(checkout), 'rev-parse', 'HEAD'], text=True).strip()
        checkouts[checkout.name.lower()] = revision
for pin in json.loads(lock.read_text())['pins']:
    assert pin['state']['revision'] in checkouts.values(), 'Pin missing from actual checkout ' + pin['identity']
receipt = dict(head=os.environ['GITHUB_SHA'], run=os.environ['GITHUB_RUN_ID'],
               checkouts=checkouts, lockSHA256=hashlib.sha256(lock.read_bytes()).hexdigest())
(out / 'receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')
