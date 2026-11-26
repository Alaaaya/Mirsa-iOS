#!/usr/bin/env python3
"""Execute only SHA-pinned Mirsa-authored Alaa/MirsaHookTest in our own UIKit host.
The real production-signed device archives are verified and never modified.
Only private copies adapt device platform metadata and renew ad-hoc signatures.
This is native simulator execution, not a physical-device or Drift launch claim.
"""
import hashlib,json,pathlib,plistlib,shutil,stat,struct,subprocess,sys,tempfile,zipfile
import argparse
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('root',type=pathlib.Path)
parser.add_argument('device')
parser.add_argument('--only-alaa',action='store_true',help='Private same-payload diagnostic cell only; never the final release gate')
parser.add_argument('--background',action='store_true')
parser.add_argument('--translation',action='store_true')
args=parser.parse_args()
assert args.only_alaa or not (args.background or args.translation), 'Optional features require the explicit matrix cell mode'
root=args.root;device=args.device;proof={}
expected={'ALAA':('Alaa','04afc06b8a95d5ef1761bfa221bd1386f8762452970226d3c1ff64a4642d6565','علاء'),
          'HOOK':('MirsaHookTest','58e1161b49abb5ff332d6d9a368ab2d04c83a67d904b4cd5e92360b807b88997','مرسى شغال ✅')}
if args.only_alaa: expected={key:value for key,value in expected.items() if key=='ALAA'}
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
def strong_loads(data):
    assert data[:4]==b'\xcf\xfa\xed\xfe' and struct.unpack_from('<I',data,4)[0]==0x100000c
    end=32+struct.unpack_from('<I',data,20)[0]
    assert end<=len(data)
    offset=32;result=[]
    for _ in range(struct.unpack_from('<I',data,16)[0]):
        command,size=struct.unpack_from('<II',data,offset)
        assert size>=8 and size%8==0 and offset+size<=end
        if command==0xc:
            assert size>=24
            at=struct.unpack_from('<I',data,offset+8)[0]
            assert 24<=at<size
            value=data[offset+at:offset+size]
            assert b'\0' in value
            result.append(value.split(b'\0',1)[0].decode('utf-8'))
        offset+=size
    assert offset==end
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
        mainLoads=strong_loads((app/info['CFBundleExecutable']).read_bytes())
        for enabled,library in [(args.background,'MirsaBackground'),(args.translation,'MirsaTranslate')]:
            assert (app/'Frameworks'/(library+'.dylib')).is_file()==enabled
            assert mainLoads.count('@loader_path/Frameworks/'+library+'.dylib')==int(enabled)
        assert (app/'MirsaBackgroundNotifications.plist').is_file()==args.background
        assert (app/'Frameworks/MirsaTranslations.json').is_file()==args.translation
        loadOrder=[]
        assert mainLoads.count('@loader_path/Frameworks/MirsaLoader.dylib')==1
        loadOrder=(app/'Frameworks/MirsaLoadOrder.txt').read_text().splitlines()
        assert loadOrder==[name+'.dylib']
        binaries=[];changes=[]
        allowed={'ExactLaunch25','Frameworks/'+name+'.dylib','Frameworks/MirsaLoader.dylib'}
        if mode=='HOOK': allowed.add('Frameworks/CydiaSubstrate.framework/CydiaSubstrate')
        if args.background: allowed.add('Frameworks/MirsaBackground.dylib')
        if args.translation: allowed.add('Frameworks/MirsaTranslate.dylib')
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
        run('xcrun','simctl','install',device,str(app),timeout=180)
        launchError=None
        try:
            launched=subprocess.run(('xcrun','simctl','launch','--terminate-running-process','--console-pty',device,info['CFBundleIdentifier'],mode),check=True,text=True,capture_output=True,timeout=45)
        except (subprocess.TimeoutExpired,subprocess.CalledProcessError) as error:
            launchError=error;launched=error
        def text(value): return value.decode('utf-8',errors='replace') if isinstance(value,bytes) else (value or '')
        result=text(launched.stdout)+text(launched.stderr)
        if launchError: result+='\nLAUNCH_TOOL_FAILURE '+str(launchError)+'\n'
        (root/('exact-'+mode+'-launch.log')).write_text(result)
        if launchError or 'MIRSA_EXACT_HOOK25 PASS '+mode+' '+title not in result:
            # Passive diagnostics only. Never load the payload or synthesize activation.
            for diagnosticArgs,suffix in [
                (('xcrun','simctl','io',device,'screenshot',str(root/('exact-'+mode+'-failure.png'))),'screenshot'),
                (('xcrun','simctl','spawn',device,'log','show','--last','2m','--style','compact','--predicate','process == "ExactLaunch25"'),'system')]:
                try:
                    evidence=subprocess.run(diagnosticArgs,text=True,capture_output=True,timeout=20)
                    (root/('exact-'+mode+'-'+suffix+'-launch.log')).write_text((evidence.stdout or '')+(evidence.stderr or ''))
                except (OSError,subprocess.TimeoutExpired) as error:
                    (root/('exact-'+mode+'-'+suffix+'-launch.log')).write_text(str(error))
        assert launchError is None,result
        assert 'MIRSA_EXACT_HOOK25 PASS '+mode+' '+title in result,result
        if args.only_alaa:
            requiredImages=['/Frameworks/Alaa.dylib','/Frameworks/MirsaLoader.dylib']
            if args.background: requiredImages.append('/Frameworks/MirsaBackground.dylib')
            if args.translation: requiredImages.append('/Frameworks/MirsaTranslate.dylib')
            for image in requiredImages:
                assert any('EXACT_DIAGNOSTIC26 success image ' in line and line.endswith(image) for line in result.splitlines()), 'Missing per-process successful image evidence: '+image
        container=pathlib.Path(run('xcrun','simctl','get_app_container',device,info['CFBundleIdentifier'],'data').strip())
        sourcePNG=container/'Documents/exact-alert.png'
        assert sourcePNG.is_file() and sourcePNG.read_bytes().startswith(b'\x89PNG\r\n\x1a\n')
        screenshot=root/('exact-'+mode+'-Arabic-alert.png');shutil.copyfile(sourcePNG,screenshot)
        assert sha(ipa)==original
        proof[mode]={'sourceDylib':name+'.dylib','sourceDylibSHA256':sourceSHA,'deviceArchiveSHA256':original,
            'attemptID':attempt['attemptID'],'originalMainLC_LOAD_DYLIB':mainLoads,'originalLoaderOrder':loadOrder,'originalDeviceSignatureVerified':True,'originalArchiveUnmodified':True,
            'backgroundEnabled':args.background,'translationEnabled':args.translation,
            'platformAdaptedNativeUIKitLaunch':True,'realDeviceVerified':False,'DriftLaunched':False,
            'metadataAdapted':['CFBundleSupportedPlatforms','DTPlatformName'],'codeChanges':changes,
            'actualArabicAlertTitle':title,'actualArabicAlertPNG':screenshot.name,'actualArabicAlertPNGSHA256':sha(screenshot),
            'marker':result.strip()}
        print(mode+': exact SHA-pinned source payload, real production sign/pack, strict original signatures and actual Arabic UIKit alert passed in platform-adapted own host')
(root/'exact-hook-launch-verification.json').write_text(json.dumps(proof,indent=2,ensure_ascii=False))
