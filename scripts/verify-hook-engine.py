#!/usr/bin/env python3
"""Fail closed on packaging a wrong-platform or incomplete hook-engine resource."""
from pathlib import Path
import plistlib
import struct

root = Path(__file__).resolve().parents[1]
framework = root / 'hook-engine/dist/CydiaSubstrate.framework'
data = (framework / 'CydiaSubstrate').read_bytes()

def u32(offset):
    return struct.unpack_from('<I', data, offset)[0]

assert len(data) >= 32 and u32(0) == 0xFEEDFACF, 'expected thin 64-bit Mach-O'
assert u32(4) == 0x0100000C, 'engine must target ARM64'
assert u32(12) == 6, 'engine must be a dynamic library'
end = 32 + u32(20)
assert end <= len(data)
offset = 32
symtab = None
install_name = None
platform = None
signature = False
for _ in range(u32(16)):
    cmd, size = struct.unpack_from('<II', data, offset)
    assert size >= 8 and size % 8 == 0 and offset + size <= end
    if cmd == 0xD:
        start = offset + u32(offset + 8)
        assert offset + 24 <= start < offset + size
        stop = data.index(b'\0', start, offset + size)
        install_name = data[start:stop].decode()
    elif cmd == 2:
        symtab = struct.unpack_from('<IIII', data, offset + 8)
    elif cmd == 0x32:
        platform = u32(offset + 8)
    elif cmd == 0x25:
        platform = 2  # LC_VERSION_MIN_IPHONEOS
    elif cmd in (0x21, 0x2C):
        assert u32(offset + 16) == 0, 'resource is encrypted'
    elif cmd == 0x1D:
        start, length = struct.unpack_from('<II', data, offset + 8)
        assert length and start + length <= len(data), 'invalid signature range'
        signature = True
    offset += size
assert offset == end
assert install_name == '@rpath/CydiaSubstrate.framework/CydiaSubstrate', install_name
assert platform == 2, f'not an iOS-device engine (platform {platform})'
assert signature, 'device engine requires a replaceable ad-hoc signature'
assert symtab is not None, 'engine symbol table missing'
symoff, count, stroff, strsize = symtab
assert symoff + count * 16 <= len(data) and stroff + strsize <= len(data)
exports = set()
for i in range(count):
    strx, kind, section, desc, value = struct.unpack_from('<IBBHQ', data, symoff + i * 16)
    if kind & 0xE0 or not kind & 1 or kind & 0x0E == 0:
        continue
    assert strx < strsize
    start = stroff + strx
    name = data[start:data.index(b'\0', start, stroff + strsize)].decode()
    exports.add(name)
required = {'_MSHookMessageEx', '_MSHookFunction', '_MSFindSymbol', '_MSGetImageByName', '_LHHookFunctions', '_LBHookMessage', '_substitute_hook_functions'}
assert not required - exports, f'missing compatibility exports {required - exports}'
info = plistlib.loads((framework / 'Info.plist').read_bytes())
assert info['CFBundleExecutable'] == 'CydiaSubstrate'
assert info['CFBundlePackageType'] == 'FMWK'
print(f'ARM64 iOS shim verified, {len(exports)} exports, signed resource, correct install name')
