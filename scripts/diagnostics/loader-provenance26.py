#!/usr/bin/env python3
"""Compare a signed loader to its literal engine source, allowing signature fields only."""
import struct,hashlib

def layout(data):
    assert data[:4]==bytes.fromhex('cffaedfe')
    count,total=struct.unpack_from('<II',data,16)
    commands=[];first=[];signature=None;offset=32
    for _ in range(count):
        command,size=struct.unpack_from('<II',data,offset)
        assert size>=8 and size%8==0 and offset+size<=len(data)
        body=bytearray(data[offset:offset+size])
        if command==0x1d:
            assert size==16 and signature is None
            signature=struct.unpack_from('<II',body,8)
        else:
            if command==0x19:
                if body[8:24].rstrip(b'\0')==b'__LINKEDIT':
                    struct.pack_into('<Q',body,32,0) # signature-dependent vm size
                    struct.pack_into('<Q',body,48,0) # signature-dependent file size
                sections=struct.unpack_from('<I',body,64)[0]
                assert size==72+80*sections
                for index in range(sections):
                    sectionOffset=struct.unpack_from('<I',body,72+80*index+48)[0]
                    if sectionOffset: first.append(sectionOffset)
            commands.append(bytes(body))
        offset+=size
    assert offset==32+total and first
    start=min(first)
    assert not any(data[offset:start]),'Unexpected nonzero load-command padding'
    header=bytearray(data[:32])
    struct.pack_into('<II',header,16,len(commands),sum(map(len,commands)))
    return bytes(header)+b''.join(commands),start,signature

def verify(unsigned,signed):
    sourceHeader,sourceStart,sourceSignature=layout(unsigned)
    signedHeader,signedStart,signedSignature=layout(signed)
    assert sourceSignature is None,'Expected literal unsigned checked-in loader'
    assert signedSignature is not None,'Exported loader missing signature'
    offset,size=signedSignature
    assert signedHeader==sourceHeader and signedStart==sourceStart,'Loader load commands differ beyond signature-only fields'
    assert offset>=len(unsigned) and offset+size==len(signed)
    assert not any(signed[len(unsigned):offset]),'New non-signature bytes after literal loader'
    assert signed[sourceStart:len(unsigned)]==unsigned[sourceStart:],'Literal engine loader code/data changed'
    return {'literalSHA256':hashlib.sha256(unsigned).hexdigest(),'signedSHA256':hashlib.sha256(signed).hexdigest(),'literalCodeAndDataVerified':True,'signatureOffset':offset,'signatureSize':size}
