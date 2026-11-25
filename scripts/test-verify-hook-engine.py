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

def uleb(n):
    result = bytearray()
    while n > 127:
        result.append((n & 127) | 128); n >>= 7
    return bytes(result + bytes([n]))

def trie_fixture():
    nodes = [b'\x03\x00\x80\x10\x00' for _ in NAMES]
    offsets = [0] * len(nodes)
    for _ in range(8):
        root = b'\0' + bytes([len(nodes)]) + b''.join(
            ('_' + name).encode() + b'\0' + uleb(offset)
            for name, offset in zip(NAMES, offsets))
        pos = len(root); new_offsets = []
        for node in nodes:
            new_offsets.append(pos); pos += len(node)
        if offsets == new_offsets: return root + b''.join(nodes)
        offsets = new_offsets
    raise AssertionError('fixture offsets did not converge')

def fixture():
    strings = bytearray(b'\0')
    symbols = bytearray()
    for name in NAMES:
        symbols += struct.pack('<IBBHQ',len(strings),0xF,1,0,2048)
        strings += ('_'+name).encode()+b'\0'
    install=b'@rpath/CydiaSubstrate.framework/CydiaSubstrate\0'
    size=(24+len(install)+7)&~7
    ident=struct.pack('<IIIIII',0xD,size,24,0,0,0)+install+b'\0'*(size-24-len(install))
    build=struct.pack('<IIIIII',0x32,24,2,0x120000,0x120000,0)
    symoff=4096
    stroff=symoff+len(symbols)
    trie = trie_fixture()
    trieoff=stroff+len(strings)
    sigoff=trieoff+len(trie)
    symtab=struct.pack('<IIIIII',2,24,symoff,len(NAMES),stroff,len(strings))
    sig=struct.pack('<IIII',0x1D,16,sigoff,16)
    export=struct.pack('<IIII',0x80000033,16,trieoff,len(trie))
    segment=bytearray(152)
    struct.pack_into('<II',segment,0,0x19,152)
    segment[8:14]=b'__TEXT'
    struct.pack_into('<QQQQIIII',segment,24,0,4096,0,4096,5,5,1,0)
    segment[72:78]=b'__text';segment[88:94]=b'__TEXT'
    struct.pack_into('<QQIIIIIIII',segment,104,2048,16,2048,2,0,0,0x80000400,0,0,0)
    commands=bytes(segment)+ident+build+symtab+export+sig
    header=struct.pack('<IIIIIIII',0xFEEDFACF,0x100000C,0,6,6,len(commands),0,0)
    return bytearray(header+commands+b'\0'*(4096-32-len(commands))+symbols+strings+trie+b'\0'*16)

class VerifyTests(unittest.TestCase):
    def check(self, data, valid=False, info=None, reason=None):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp); (root/'scripts').mkdir()
            shutil.copyfile(SCRIPT, root/'scripts/verify-hook-engine.py')
            fw=root/'hook-engine/dist/CydiaSubstrate.framework';fw.mkdir(parents=True)
            (fw/'CydiaSubstrate').write_bytes(data)
            (fw/'Info.plist').write_bytes(plistlib.dumps(info or {'CFBundleExecutable':'CydiaSubstrate','CFBundlePackageType':'FMWK'}))
            p=subprocess.run([sys.executable,str(root/'scripts/verify-hook-engine.py')],capture_output=True)
            self.assertEqual(p.returncode==0, valid, p.stderr.decode())
            if reason: self.assertIn(reason, p.stderr.decode())
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
        d=fixture();at=d.index(struct.pack('<II',0x32,24));struct.pack_into('<I',d,at+8,7);self.check(d)
    def test_missing_export(self):
        d=fixture();at=d.index(b'_MSHookFunction');d[at+1]=ord('Z');self.check(d)
    def test_private_external_is_not_public(self):
        d=fixture()
        for i in range(len(NAMES)): d[4096+i*16+4] |= 0x10
        self.check(d)
    def test_nlist_without_dyld_binding(self):
        d=fixture(); at=d.index(b'_MSHookFunction',d.index(b'_substitute_hook_functions')+1)
        d[at+1]=ord('Z');self.check(d)
    def test_reexport_is_not_local_binding(self):
        d=fixture(); at=d.index(b'\x03\x00\x80\x10\x00',4096);d[at+1]=8;self.check(d)
    def test_missing_trie(self):
        d=fixture();at=d.index(struct.pack('<II',0x80000033,16));struct.pack_into('<I',d,at,0x31);self.check(d)
    def test_cyclic_trie(self):
        d=fixture();at=d.index(b'_MSHookMessageEx',d.index(b'_substitute_hook_functions')+1)
        stop=d.index(0,at);d[stop+1]=0;self.check(d)
    def test_export_address_out_of_range(self):
        d=fixture();at=d.index(b'\x03\x00\x80\x10\x00',4096)
        d[at+2:at+4]=b'\xff\x7f';self.check(d)
    def test_nlist_address_mismatch(self):
        d=fixture();struct.pack_into('<Q',d,4096+8,2049);self.check(d)
    def test_nonexecutable_function(self):
        d=fixture();struct.pack_into('<I',d,32+60,1);self.check(d)
    def test_ambiguous_sibling_edges(self):
        d=fixture()
        # Make a second edge a prefix of the first with the same allocated span.
        first=d.index(b'_MSHookMessageEx',d.index(b'_substitute_hook_functions')+1)
        second=d.index(b'_MSHookFunction',first+1)
        d[second:second+15]=b'_MSHookMessageE'+b'\0'
        self.check(d,reason='ambiguous sibling export edges')
    def test_truncated_signature(self): self.check(fixture()[:-1])
    def test_wrong_plist(self): self.check(fixture(),info={'CFBundleExecutable':'Other','CFBundlePackageType':'FMWK'})
    def test_oversized_commands(self):
        d=fixture();struct.pack_into('<I',d,20,len(d)+1024);self.check(d)

if __name__=='__main__': unittest.main()
