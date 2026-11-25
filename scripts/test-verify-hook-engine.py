#!/usr/bin/env python3
"""Unit-test the resource verifier with synthetic, inert Mach-O headers."""
from pathlib import Path
import plistlib
import shutil
import struct
import subprocess
import sys
import tempfile
import unittest

SCRIPT = Path(__file__).with_name('verify-hook-engine.py')
NAMES = ['MSHookMessageEx','MSHookFunction','MSFindSymbol','MSGetImageByName','LHHookFunctions','LBHookMessage','substitute_hook_functions']

def fixture():
    strings = bytearray(b'\0')
    symbols = bytearray()
    for name in NAMES:
        symbols += struct.pack('<IBBHQ',len(strings),0xF,1,0,4096)
        strings += ('_'+name).encode()+b'\0'
    install=b'@rpath/CydiaSubstrate.framework/CydiaSubstrate\0'
    size=(24+len(install)+7)&~7
    ident=struct.pack('<IIIIII',0xD,size,24,0,0,0)+install+b'\0'*(size-24-len(install))
    build=struct.pack('<IIIIII',0x32,24,2,0x120000,0x120000,0)
    symoff=4096
    stroff=symoff+len(symbols)
    sigoff=stroff+len(strings)
    symtab=struct.pack('<IIIIII',2,24,symoff,len(NAMES),stroff,len(strings))
    sig=struct.pack('<IIII',0x1D,16,sigoff,16)
    commands=ident+build+symtab+sig
    header=struct.pack('<IIIIIIII',0xFEEDFACF,0x100000C,0,6,4,len(commands),0,0)
    return bytearray(header+commands+b'\0'*(4096-32-len(commands))+symbols+strings+b'\0'*16)

class VerifyTests(unittest.TestCase):
    def check(self, data, valid=False, info=None):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp); (root/'scripts').mkdir()
            shutil.copyfile(SCRIPT, root/'scripts/verify-hook-engine.py')
            fw=root/'hook-engine/dist/CydiaSubstrate.framework';fw.mkdir(parents=True)
            (fw/'CydiaSubstrate').write_bytes(data)
            (fw/'Info.plist').write_bytes(plistlib.dumps(info or {'CFBundleExecutable':'CydiaSubstrate','CFBundlePackageType':'FMWK'}))
            p=subprocess.run([sys.executable,str(root/'scripts/verify-hook-engine.py')],capture_output=True)
            self.assertEqual(p.returncode==0, valid, p.stderr.decode())
    def test_valid_header(self): self.check(fixture(), True)
    def test_bad_magic(self):
        d=fixture();struct.pack_into('<I',d,0,0);self.check(d)
    def test_wrong_cpu(self):
        d=fixture();struct.pack_into('<I',d,4,0x1000007);self.check(d)
    def test_not_library(self):
        d=fixture();struct.pack_into('<I',d,12,2);self.check(d)
    def test_wrong_install_name(self):
        d=fixture();at=d.index(b'@rpath');d[at]=ord('X');self.check(d)
    def test_simulator_not_device(self):
        d=fixture();size=struct.unpack_from('<I',d,36)[0];struct.pack_into('<I',d,32+size+8,7);self.check(d)
    def test_missing_export(self):
        d=fixture();at=d.index(b'_MSHookFunction');d[at+1]=ord('Z');self.check(d)
    def test_truncated_signature(self): self.check(fixture()[:-1])
    def test_wrong_plist(self): self.check(fixture(),info={'CFBundleExecutable':'Other','CFBundlePackageType':'FMWK'})
    def test_oversized_commands(self):
        d=fixture();struct.pack_into('<I',d,20,len(d)+1024);self.check(d)

if __name__=='__main__': unittest.main()
