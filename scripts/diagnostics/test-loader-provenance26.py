#!/usr/bin/env python3
"""Inert byte tests only. These never establish signature or native launch validity."""
import importlib.util,pathlib,struct,unittest
path=pathlib.Path(__file__).with_name('loader-provenance26.py')
spec=importlib.util.spec_from_file_location('loader_provenance',path)
module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
source=(path.parents[2]/'loader/MirsaLoader.dylib').read_bytes()

def fake_signed(original):
    data=bytearray(original);count,total=struct.unpack_from('<II',data,16)
    offset=32
    for _ in range(count):
        command,size=struct.unpack_from('<II',data,offset)
        if command==0x19 and data[offset+8:offset+24].rstrip(b'\0')==b'__LINKEDIT':
            struct.pack_into('<Q',data,offset+32,4096)
            struct.pack_into('<Q',data,offset+48,struct.unpack_from('<Q',data,offset+48)[0]+16)
        offset+=size
    assert data[offset:offset+16]==b'\0'*16
    data[offset:offset+16]=struct.pack('<IIII',0x1d,16,len(original),16)
    struct.pack_into('<II',data,16,count+1,total+16)
    data+=b'inert-signature!'
    return bytes(data)

class LiteralLoaderTests(unittest.TestCase):
    def test_only_signature_command_and_linkedit_sizes_may_change(self):
        proof=module.verify(source,fake_signed(source))
        self.assertTrue(proof['literalCodeAndDataVerified'])
    def test_changed_code_rejected(self):
        signed=bytearray(fake_signed(source));_,offset,_=module.layout(source)
        signed[offset]^=1
        with self.assertRaises(AssertionError):module.verify(source,signed)
    def test_changed_loader_uuid_rejected(self):
        signed=bytearray(fake_signed(source));offset=32
        for _ in range(struct.unpack_from('<I',source,16)[0]):
            command,size=struct.unpack_from('<II',source,offset)
            if command==0x1b:
                signed[offset+8]^=1;break
            offset+=size
        else:self.fail('Current source requires UUID')
        with self.assertRaises(AssertionError):module.verify(source,signed)
    def test_unsigned_or_appended_bytes_rejected(self):
        with self.assertRaises(AssertionError):module.verify(source,source)
        with self.assertRaises(AssertionError):module.verify(source,fake_signed(source)+b'x')
    def test_header_padding_not_silently_discarded(self):
        signed=bytearray(fake_signed(source))
        total=struct.unpack_from('<I',signed,20)[0]
        signed[32+total]=1
        with self.assertRaises(AssertionError):module.verify(source,signed)

if __name__=='__main__':unittest.main()
