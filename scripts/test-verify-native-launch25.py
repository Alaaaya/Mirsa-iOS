#!/usr/bin/env python3
"""Exercise actual launch-verifier control flow with inert archives and mocked OS tools.
These tests do NOT establish Apple signature validity or native execution.
"""
import hashlib,json,pathlib,plistlib,runpy,struct,subprocess,sys,tempfile,unittest,zipfile
from unittest.mock import patch

SCRIPTS=pathlib.Path(__file__).parent
PNG=b'\x89PNG\r\n\x1a\n'+b'inert-unit-test'
def binary(load=None):
    command=struct.pack('<IIIIII',0x32,24,2,0,0,0)
    count=1
    if load:
        body=load.encode()+b'\0';size=(24+len(body)+7)&~7
        command+=struct.pack('<IIIIII',0xc,size,24,0,0,0)+body+b'\0'*(size-24-len(body));count+=1
    return struct.pack('<IIIIIIII',0xfeedfacf,0x100000c,0,2,count,len(command),0,0)+command

class LaunchVerifierTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root=pathlib.Path(self.tmp.name)
        self.container=self.root/'container'
        (self.container/'Documents').mkdir(parents=True)
        (self.container/'Documents/exact-alert.png').write_bytes(PNG)

    def archives(self, exact=False, wrong=None):
        modes=('ALAA','HOOK') if exact else ('DIRECT','LOADER','HOOK')
        for mode in modes:
            name=('Alaa' if mode=='ALAA' else 'MirsaHookTest') if exact else ('GenericHookMarker25' if mode=='HOOK' else 'GenericMarker25')
            host='ExactLaunch25' if exact else 'GenericLaunch25'
            files={'Info.plist':plistlib.dumps(dict(CFBundleExecutable=host,CFBundleIdentifier='com.mirsa.ci.'+('exactlaunch25' if exact else 'genericlaunch25'))),
                   host:binary('@loader_path/Frameworks/'+(name+'.dylib' if mode=='DIRECT' else 'MirsaLoader.dylib')),'Frameworks/'+name+'.dylib':binary()}
            if mode!='DIRECT':
                files['Frameworks/MirsaLoader.dylib']=binary()
                files['Frameworks/MirsaLoadOrder.txt']=(name+'.dylib\n').encode()
            if mode=='HOOK':files['Frameworks/CydiaSubstrate.framework/CydiaSubstrate']=binary()
            if wrong==mode:
                key='Frameworks/CydiaSubstrate.framework/CydiaSubstrate' if exact else 'Frameworks/MirsaLoader.dylib'
                if key in files:del files[key]
                else:files[key]=binary()
            ipa=self.root/(('EXACT-' if exact else 'GENERIC-')+mode+'.ipa')
            with zipfile.ZipFile(ipa,'w') as archive:
                for member,body in files.items():
                    entry=zipfile.ZipInfo('Payload/'+host+'.app/'+member)
                    entry.external_attr=(0o100644 if member=='Info.plist' else 0o100755)<<16
                    archive.writestr(entry,body)
            sourceSHA={'ALAA':'04afc06b8a95d5ef1761bfa221bd1386f8762452970226d3c1ff64a4642d6565',
                       'HOOK':'58e1161b49abb5ff332d6d9a368ab2d04c83a67d904b4cd5e92360b807b88997'}.get(mode,'inert')
            ipa.with_suffix('.ipa.mirsa-attempt.json').write_text(json.dumps(dict(outputSHA256=hashlib.sha256(ipa.read_bytes()).hexdigest(),
                 componentSHA256={'component':sourceSHA},selectedComponentIDs=['exact:'+name],attemptID=mode)))

    def execute(self, exact=False, reject_apple=False, reject_marker=False, script=None):
        script=script or SCRIPTS/('verify-exact-hook-launch25.py' if exact else 'verify-generic-launch25.py')
        def command(args,**kwargs):
            self.assertTrue(kwargs['check'])
            if args[0]=='codesign':
                self.assertIn('--strict',args) if '--verify' in args else self.assertIn('--force',args)
                if reject_apple:raise subprocess.CalledProcessError(1,args)
                target=pathlib.Path(args[-1])
                executable=target/('ExactLaunch25' if exact else 'GenericLaunch25') if target.is_dir() else target
                self.assertEqual(executable.stat().st_mode&0o777,0o755)
                return subprocess.CompletedProcess(args,0,stdout='')
            self.assertEqual(args[:2],('xcrun','simctl'))
            output=''
            if args[2]=='spawn':
                self.assertEqual(args[-1],'hook' if 'HOOK' in self.current_mode(args) else 'plain')
                output='MIRSA_GENERIC_PRODUCTION_LAUNCH25 PASS'
            elif args[2]=='launch':
                mode=args[-1]
                self.assertIn(mode,('ALAA','HOOK'))
                output='MIRSA_EXACT_HOOK25 PASS '+mode+' '+('علاء' if mode=='ALAA' else 'مرسى شغال ✅')
            elif args[2]=='get_app_container':output=str(self.container)
            else:self.assertEqual(args[2],'install')
            return subprocess.CompletedProcess(args,0,stdout='bad marker' if reject_marker else output)
        with patch.object(sys,'argv',[str(script),str(self.root),'owned-sim']),patch('subprocess.run',side_effect=command) as calls:
            runpy.run_path(str(script),run_name='__main__')
        return calls

    def current_mode(self,args):
        # The loaded marker distinguishes HOOK without relying on the script's loop variable.
        app=pathlib.Path(args[-2]).parent
        return 'HOOK' if (app/'Frameworks/GenericHookMarker25.dylib').exists() else 'PLAIN'

    def assert_modes(self,exact=False):
        modes={'ALAA','HOOK'} if exact else {'DIRECT','LOADER','HOOK'}
        file=self.root/('exact-hook-launch-verification.json' if exact else 'generic-launch-verification.json')
        proof=json.loads(file.read_text())
        self.assertEqual(set(proof),modes)
        for mode,item in proof.items():
            self.assertEqual(item['attemptID'],mode)
            self.assertTrue(item['originalDeviceSignatureVerified'])
            self.assertTrue(item['originalArchiveUnmodified'])
            self.assertFalse(item['realDeviceVerified'])
            self.assertEqual(hashlib.sha256((self.root/(('EXACT-' if exact else 'GENERIC-')+mode+'.ipa')).read_bytes()).hexdigest(),item['deviceArchiveSHA256'])
            if exact:self.assertEqual(item['actualArabicAlertPNG'],'exact-'+mode+'-Arabic-alert.png')

    def test_generic_modes_survive_archived_permissions(self):
        self.archives();calls=self.execute();self.assert_modes()
        self.assertEqual(sum(c.args[0][0]=='codesign' and '--strict' in c.args[0] for c in calls.call_args_list),6)

    def test_exact_modes_survive_archived_permissions(self):
        self.archives(True);calls=self.execute(True);self.assert_modes(True)
        self.assertEqual(sum(c.args[0][0]=='codesign' and '--strict' in c.args[0] for c in calls.call_args_list),4)

    def mutate_archive(self,exact,member,value):
        mode='ALAA' if exact else 'DIRECT'
        host='ExactLaunch25' if exact else 'GenericLaunch25'
        ipa=self.root/(('EXACT-' if exact else 'GENERIC-')+mode+'.ipa')
        with zipfile.ZipFile(ipa) as archive:
            files=[(entry,archive.read(entry.filename)) for entry in archive.infolist()]
        with zipfile.ZipFile(ipa,'w') as archive:
            for entry,body in files:
                archive.writestr(entry,value if entry.filename=='Payload/'+host+'.app/'+member else body)
        sidecar=ipa.with_suffix('.ipa.mirsa-attempt.json')
        attempt=json.loads(sidecar.read_bytes());attempt['outputSHA256']=hashlib.sha256(ipa.read_bytes()).hexdigest()
        sidecar.write_text(json.dumps(attempt))

    def test_missing_main_load_rejected_before_launch(self):
        for exact in (False,True):
            with self.subTest(exact=exact):
                self.archives(exact)
                self.mutate_archive(exact,'ExactLaunch25' if exact else 'GenericLaunch25',binary())
                with self.assertRaises(AssertionError):self.execute(exact)

    def test_wrong_main_load_rejected_before_launch(self):
        for exact in (False,True):
            with self.subTest(exact=exact):
                self.archives(exact)
                self.mutate_archive(exact,'ExactLaunch25' if exact else 'GenericLaunch25',binary('@loader_path/Frameworks/Other.dylib'))
                with self.assertRaises(AssertionError):self.execute(exact)

    def test_wrong_exact_loader_manifest_rejected(self):
        self.archives(True)
        self.mutate_archive(True,'Frameworks/MirsaLoadOrder.txt',b'Other.dylib\n')
        with self.assertRaises(AssertionError):self.execute(True)

    def test_generic_wrong_loader_rejected(self):
        self.archives(wrong='DIRECT')
        with self.assertRaises(AssertionError):self.execute()

    def test_exact_missing_hook_engine_rejected(self):
        self.archives(True,wrong='HOOK')
        with self.assertRaises(AssertionError):self.execute(True)

    def test_strict_apple_errors_not_ignored(self):
        for exact in (False,True):
            with self.subTest(exact=exact):
                self.archives(exact)
                with self.assertRaises(subprocess.CalledProcessError):self.execute(exact,reject_apple=True)

    def test_failed_native_marker_not_ignored(self):
        for exact in (False,True):
            with self.subTest(exact=exact):
                self.archives(exact)
                with self.assertRaises(AssertionError):self.execute(exact,reject_marker=True)

    def test_original_shadowing_mutation_rejected_in_both_scripts(self):
        for exact in (False,True):
            with self.subTest(exact=exact):
                self.archives(exact)
                source=SCRIPTS/('verify-exact-hook-launch25.py' if exact else 'verify-generic-launch25.py')
                mutated=self.root/'mutated.py'
                mutated.write_text(source.read_text().replace('file_mode','mode'))
                with self.assertRaises(AssertionError):self.execute(exact,script=mutated)

if __name__=='__main__':unittest.main()
