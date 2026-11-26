#!/usr/bin/env python3
"""Execute only SHA-pinned Mirsa-authored Alaa/MirsaHookTest in our own UIKit host.
The real production-signed device archives are verified and never modified.
Only private copies adapt device platform metadata and renew ad-hoc signatures.
This is native simulator execution, not a physical-device or Drift launch claim.
"""
import hashlib,json,pathlib,plistlib,shutil,stat,struct,subprocess,sys,tempfile,zipfile
root=pathlib.Path(sys.argv[1]);device=sys.argv[2];proof={}
expected={'ALAA':('Alaa','04afc06b8a95d5ef1761bfa221bd1386f8762452970226d3c1ff64a4642d6565','علاء'),
          'HOOK':('MirsaHookTest','58e1161b49abb5ff332d6d9a368ab2d04c83a67d904b4cd5e92360b807b88997','مرسى شغال ✅')}
def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()
def run(*args,timeout=60): return subprocess.run(args,check=True,text=True,capture_output=True,timeout=timeout).stdout
def commands(data):
    assert data[:4]==b'\xcf\xfa\xed\xfe' and struct.unpack_from('<I',data,4)[0]==0x100000c
    offset=32;result=[]
    for _ in range(struct.unpack_from('<I',data,16)[0]):
        command,size=struct.unpack_from('<II',data,offset)
        assert size>=8 and offset+size<=len(data)
        result.append((offset,command,size));offset+=size
    return result
for mode,(name,sourceSHA,title) in expected.items():
    ipa=root/('EXACT-'+mode+'.ipa');original=sha(ipa)
    attempt=json.loads(ipa.with_suffix('.ipa.mirsa-attempt.json').read_bytes())
    assert attempt['outputSHA256']==original and list(attempt['componentSHA256'].values())==[sourceSHA]
    assert attempt['selectedComponentIDs']==['exact:'+name]
    with tempfile.TemporaryDirectory(prefix='mirsa-exact-owned25-') as directory,zipfile.ZipFile(ipa) as archive:
        names=archive.namelist();assert len(names)==len(set(names))
        for entry in archive.infolist():
            p=pathlib.PurePosixPath(entry.filename)
            assert not p.is_absolute() and '..' not in p.parts and '\\' not in entry.filename
            assert not stat.S_ISLNK(entry.external_attr>>16) and entry.file_size<64*1024*1024
        archive.extractall(directory)
        # zipfile intentionally drops Unix execute bits; restore the archived modes.
        # This changes no signed file bytes and must happen before native launch.
        for entry in archive.infolist():
            if not entry.is_dir():
                file_mode=(entry.external_attr >> 16) & 0o777
                if file_mode: (pathlib.Path(directory)/entry.filename).chmod(file_mode)
        app=pathlib.Path(directory)/'Payload/ExactLaunch25.app'
        assert list((pathlib.Path(directory)/'Payload').glob('*.app'))==[app]
        info=plistlib.loads((app/'Info.plist').read_bytes())
        assert info['CFBundleExecutable']=='ExactLaunch25' and info['CFBundleIdentifier']=='com.mirsa.ci.exactlaunch25'
        run('codesign','--verify','--deep','--strict',str(app))
        assert (app/'Frameworks'/ (name+'.dylib')).is_file() and (app/'Frameworks/MirsaLoader.dylib').is_file()
        engine=app/'Frameworks/CydiaSubstrate.framework/CydiaSubstrate'
        assert engine.is_file()==(mode=='HOOK')
        binaries=[];changes=[]
        allowed={'ExactLaunch25','Frameworks/'+name+'.dylib','Frameworks/MirsaLoader.dylib'}
        if mode=='HOOK': allowed.add('Frameworks/CydiaSubstrate.framework/CydiaSubstrate')
        for path in sorted(app.rglob('*')):
            assert not path.is_symlink()
            if not path.is_file(): continue
            data=bytearray(path.read_bytes())
            if data[:4]!=b'\xcf\xfa\xed\xfe': continue
            relative=str(path.relative_to(app));assert relative in allowed
            old=sha(path);platforms=0
            for offset,command,size in commands(data):
                if command==0x32:
                    assert struct.unpack_from('<I',data,offset+8)[0]==2
                    struct.pack_into('<I',data,offset+8,7);platforms+=1
            assert platforms==1
            path.write_bytes(data);binaries.append(path)
            changes.append({'path':relative,'originalDeviceBinarySHA256':old,'adaptation':'LC_BUILD_VERSION 2 to 7 and ad-hoc signature renewal'})
        assert set(str(path.relative_to(app)) for path in binaries)==allowed
        info['CFBundleSupportedPlatforms']=['iPhoneSimulator'];info['DTPlatformName']='iphonesimulator'
        (app/'Info.plist').write_bytes(plistlib.dumps(info))
        for binary in binaries:
            if binary!=app/'ExactLaunch25': run('codesign','--force','--sign','-','--timestamp=none',str(binary))
        run('codesign','--force','--sign','-','--timestamp=none',str(app))
        run('codesign','--verify','--deep','--strict',str(app))
        run('xcrun','simctl','install',device,str(app))
        result=run('xcrun','simctl','launch','--terminate-running-process','--console-pty',device,info['CFBundleIdentifier'],mode,timeout=45)
        assert 'MIRSA_EXACT_HOOK25 PASS '+mode+' '+title in result,result
        container=pathlib.Path(run('xcrun','simctl','get_app_container',device,info['CFBundleIdentifier'],'data').strip())
        sourcePNG=container/'Documents/exact-alert.png'
        assert sourcePNG.is_file() and sourcePNG.read_bytes().startswith(b'\x89PNG\r\n\x1a\n')
        screenshot=root/('exact-'+mode+'-Arabic-alert.png');shutil.copyfile(sourcePNG,screenshot)
        assert sha(ipa)==original
        proof[mode]={'sourceDylib':name+'.dylib','sourceDylibSHA256':sourceSHA,'deviceArchiveSHA256':original,
            'attemptID':attempt['attemptID'],'originalDeviceSignatureVerified':True,'originalArchiveUnmodified':True,
            'platformAdaptedNativeUIKitLaunch':True,'realDeviceVerified':False,'DriftLaunched':False,
            'metadataAdapted':['CFBundleSupportedPlatforms','DTPlatformName'],'codeChanges':changes,
            'actualArabicAlertTitle':title,'actualArabicAlertPNG':screenshot.name,'actualArabicAlertPNGSHA256':sha(screenshot),
            'marker':result.strip()}
        print(mode+': exact SHA-pinned source payload, real production sign/pack, strict original signatures and actual Arabic UIKit alert passed in platform-adapted own host')
(root/'exact-hook-launch-verification.json').write_text(json.dumps(proof,indent=2,ensure_ascii=False))
