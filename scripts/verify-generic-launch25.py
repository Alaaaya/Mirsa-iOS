#!/usr/bin/env python3
"""Launch ONLY the own-code CI host after the actual production signing route.
The original, strict-codesign-verified ARM64 device archives remain immutable.
A private extracted copy has ONLY LC_BUILD_VERSION platform 2 changed to 7 and
ad-hoc signing renewed for simulator execution of the identical ARM64 code.
This is a platform-adapted native launch gate, NOT real-device validation and
NOT a claim that the unmodified device signature can run on the simulator.
"""
import hashlib,json,pathlib,plistlib,struct,subprocess,sys,tempfile,zipfile
root=pathlib.Path(sys.argv[1]);device=sys.argv[2];proof={}
def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()
def run(*args):
    try:
        return subprocess.run(args,check=True,text=True,capture_output=True,timeout=60).stdout
    except subprocess.CalledProcessError as error:
        # Only our authored, credential-free launch fixtures run through this helper.
        print(error.stdout or '',file=sys.stderr,flush=True)
        print(error.stderr or '',file=sys.stderr,flush=True)
        raise
for mode in ('DIRECT','LOADER','HOOK'):
    ipa=root/('GENERIC-'+mode+'.ipa');original=sha(ipa)
    attempt=json.loads(ipa.with_suffix('.ipa.mirsa-attempt.json').read_bytes())
    assert attempt['outputSHA256']==original and len(attempt['componentSHA256'])==1
    with tempfile.TemporaryDirectory(prefix='mirsa-owned-launch25-') as directory,zipfile.ZipFile(ipa) as archive:
        names=archive.namelist();assert len(names)==len(set(names))
        for name in names:
            p=pathlib.PurePosixPath(name)
            assert not p.is_absolute() and '..' not in p.parts and '\\' not in name
        archive.extractall(directory)
        # zipfile intentionally drops Unix execute bits; restore the archived modes.
        # This changes no signed file bytes and must happen before native launch.
        for entry in archive.infolist():
            if not entry.is_dir():
                file_mode=(entry.external_attr >> 16) & 0o777
                if file_mode: (pathlib.Path(directory)/entry.filename).chmod(file_mode)
        app=pathlib.Path(directory)/'Payload/GenericLaunch25.app'
        assert list((pathlib.Path(directory)/'Payload').glob('*.app'))==[app]
        info=plistlib.loads((app/'Info.plist').read_bytes())
        assert info['CFBundleExecutable']=='GenericLaunch25' and info['CFBundleIdentifier']=='com.mirsa.ci.genericlaunch25'
        run('codesign','--verify','--deep','--strict',str(app))
        marker=app/'Frameworks'/('GenericHookMarker25.dylib' if mode=='HOOK' else 'GenericMarker25.dylib')
        assert marker.is_file()
        loader=app/'Frameworks/MirsaLoader.dylib'
        assert loader.exists()==(mode!='DIRECT')
        engine=app/'Frameworks/CydiaSubstrate.framework/CydiaSubstrate'
        assert engine.exists()==(mode=='HOOK')
        binaries=[];changes=[]
        for path in sorted(app.rglob('*')):
            assert not path.is_symlink()
            if not path.is_file(): continue
            data=bytearray(path.read_bytes())
            if data[:4]!=b'\xcf\xfa\xed\xfe': continue
            assert struct.unpack_from('<I',data,4)[0]==0x100000c
            offset=32;platforms=0;old=sha(path)
            for _ in range(struct.unpack_from('<I',data,16)[0]):
                cmd,size=struct.unpack_from('<II',data,offset)
                assert size>=8 and offset+size<=len(data)
                if cmd==0x32:
                    assert struct.unpack_from('<I',data,offset+8)[0]==2
                    struct.pack_into('<I',data,offset+8,7);platforms+=1
                offset+=size
            assert platforms==1,'Expected own modern ARM64 iOS fixture'
            path.write_bytes(data);binaries.append(path)
            changes.append({'path':str(path.relative_to(app)),'originalDeviceBinarySHA256':old,'adaptation':'LC_BUILD_VERSION platform 2 to 7 only, then ad-hoc signature renewal'})
        # Sign inner code before outer bundle, never touch the original signed archive.
        for binary in binaries:
            if binary!=app/'GenericLaunch25': run('codesign','--force','--sign','-','--timestamp=none',str(binary))
        run('codesign','--force','--sign','-','--timestamp=none',str(app))
        run('codesign','--verify','--deep','--strict',str(app))
        result=run('xcrun','simctl','spawn',device,str(app/'GenericLaunch25'),'hook' if mode=='HOOK' else 'plain')
        assert 'MIRSA_GENERIC_PRODUCTION_LAUNCH25 PASS' in result
        assert sha(ipa)==original
        proof[mode]={'deviceArchiveSHA256':original,'attemptID':attempt['attemptID'],'originalDeviceSignatureVerified':True,'originalArchiveUnmodified':True,'platformAdaptedNativeLaunch':True,'realDeviceVerified':False,'codeChanges':changes,'marker':result.strip()}
        print(mode+': actual production injection/sign/pack, exact archive evidence, native constructor'+(' and Objective-C hook' if mode=='HOOK' else '')+' launch passed (platform-adapted own CI host)')
(root/'generic-launch-verification.json').write_text(json.dumps(proof,indent=2))
