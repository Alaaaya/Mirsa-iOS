#!/usr/bin/env python3
"""Collect every immutable diagnostic cell. A failed baseline is evidence, never a skipped gate."""
import hashlib,importlib.util,json,pathlib,shutil,struct,subprocess,sys,zipfile

root=pathlib.Path(sys.argv[1]);device=sys.argv[2]
repository=pathlib.Path(__file__).resolve().parents[2]
results=[]
def sha(data): return hashlib.sha256(data).hexdigest()
def uuids(data):
    assert data[:4]==bytes.fromhex('cffaedfe')
    offset=32;values=[]
    for _ in range(struct.unpack_from('<I',data,16)[0]):
        command,size=struct.unpack_from('<II',data,offset)
        assert size>=8 and size%8==0 and offset+size<=len(data)
        if command==0x1b:
            assert size==24
            values.append(data[offset+8:offset+size].hex())
        offset+=size
    return values
manifest=json.loads((root/'frozen-inputs.json').read_text())
files=manifest['files']
frozen={'sourceIPA_SHA256':files['tests/fixtures/exact-hooks25/ExactLaunch25Fixture.ipa'],
        'AlaaSourceSHA256':files['tests/fixtures/exact-hooks25/Alaa.dylib'],
        'p12SHA256':files['tests/Fixtures/LCSignSynthetic.p12'],
        'profileSHA256':files['tests/Fixtures/LCSignSynthetic.mobileprovision']}
assert sha((root/'frozen-original.ipa').read_bytes())==frozen['sourceIPA_SHA256']
assert manifest['baseline']=='3191476ccb9c3640c2286015bd3741f357e20a3f'
assert manifest['candidate']==subprocess.check_output(['git','rev-parse','HEAD'],cwd=repository,text=True).strip()
spec=importlib.util.spec_from_file_location('loader_provenance',repository/'scripts/diagnostics/loader-provenance26.py')
loader=importlib.util.module_from_spec(spec);spec.loader.exec_module(loader)
for engine,cells in [('current',['off','background','translation','combined']),('released296',['off'])]:
    manifest=root/engine/'signing-outcomes.json'
    records=json.loads(manifest.read_text()) if manifest.exists() else []
    for cell in cells:
        result={'engine':engine,'cell':cell,'passed':False}
        out=root/('launch-'+engine+'-'+cell);out.mkdir(exist_ok=True)
        try:
            matching=[record for record in records if record['cell']==cell and record['engine']==engine]
            assert len(matching)==1,'Missing or duplicate signing outcome'
            record=matching[0]
            result['signing']=record
            inputs={key:record[key] for key in ['sourceIPA_SHA256','AlaaSourceSHA256','p12SHA256','profileSHA256']}
            assert inputs==frozen,'A/B inputs differ, comparison invalid'
            assert record['signingPassed'],'Production signing failed before native launch: '+record.get('error','unknown')
            original=root/engine/(cell+'.ipa')
            originalSHA=sha(original.read_bytes())
            assert originalSHA==record['signedIPA_SHA256']
            attempt=json.loads(original.with_suffix('.ipa.mirsa-attempt.json').read_text())
            assert attempt['sourceSHA256']==frozen['sourceIPA_SHA256']
            assert attempt['attemptID']==record['attemptID']
            target=out/'EXACT-ALAA.ipa'
            shutil.copyfile(original,target)
            shutil.copyfile(original.with_suffix('.ipa.mirsa-attempt.json'),target.with_suffix('.ipa.mirsa-attempt.json'))
            loaderPath='loader/MirsaLoader.dylib' if engine=='current' else 'release296/loader/MirsaLoader.dylib'
            literal=(repository/loaderPath).read_bytes()
            assert sha(literal)==files[loaderPath]
            with zipfile.ZipFile(target) as archive:
                result['literalLoader']=loader.verify(literal,archive.read('Payload/ExactLaunch25.app/Frameworks/MirsaLoader.dylib'))
                prefix='Payload/ExactLaunch25.app/Frameworks/'
                result['payloads']={}
                for library in ['Alaa','MirsaLoader','MirsaBackground','MirsaTranslate']:
                    path=prefix+library+'.dylib'
                    if path in archive.namelist():
                        data=archive.read(path)
                        result['payloads'][library]={'signedSHA256':sha(data),'LC_UUID':uuids(data)}
            command=[sys.executable,str(repository/'scripts/verify-exact-hook-launch25.py'),str(out),device,'--only-alaa']
            if record['background']: command.append('--background')
            if record['translation']: command.append('--translation')
            # Each run uninstalls ONLY the owned fixture. Clean defaults/permission state
            # are identical, and no consent or lifecycle event is fabricated.
            subprocess.run(['xcrun','simctl','uninstall',device,'com.mirsa.ci.exactlaunch25'],capture_output=True)
            native=subprocess.run(command,text=True,capture_output=True,timeout=360)
            (out/'native-verifier.log').write_text(native.stdout+native.stderr)
            result['verifierExitCode']=native.returncode
            assert sha(original.read_bytes())==originalSHA and sha(target.read_bytes())==originalSHA,'Original archive changed'
            assert native.returncode==0,'Strict original signature or exact native UIKit alert gate failed; read '+str(out/'native-verifier.log')
            proof=json.loads((out/'exact-hook-launch-verification.json').read_text())
            assert set(proof)=={'ALAA'} and proof['ALAA']['deviceArchiveSHA256']==originalSHA
            result['native']=proof['ALAA'];result['passed']=True
        except Exception as error:
            result['error']=str(error)
        results.append(result)
        (root/'same-payload-results.json').write_text(json.dumps({'description':'Released entire Rust engine and literal embedded loader vs candidate engine, common candidate Swift pipeline; private owned native host only','physicalDeviceVerified':False,'DriftLaunched':False,'inputs':frozen,'cells':results},indent=2,ensure_ascii=False))
        print(engine+'/'+cell+': '+('PASS' if result['passed'] else 'FAIL '+result.get('error','')))
assert len(results)==5
raise SystemExit(0 if all(result['passed'] for result in results) else 1)
