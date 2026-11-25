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
export_range = None
for _ in range(u32(16)):
    cmd, size = struct.unpack_from('<II', data, offset)
    assert size >= 8 and size % 8 == 0 and offset + size <= end
    if cmd == 0xD:
        start = offset + u32(offset + 8)
        assert offset + 24 <= start < offset + size
        stop = data.index(b'\0', start, offset + size)
        install_name = data[start:stop].decode()
    elif cmd in (0x22, 0x80000022):
        assert size >= 48
        export_range = struct.unpack_from('<II', data, offset + 40)
    elif cmd == 0x80000033:
        assert size >= 16
        export_range = struct.unpack_from('<II', data, offset + 8)
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
    if kind & 0xF0 or not kind & 1 or kind & 0x0E != 0x0E:
        continue
    assert strx < strsize
    start = stroff + strx
    name = data[start:data.index(b'\0', start, stroff + strsize)].decode()
    exports.add(name)
required = {'_MSHookMessageEx', '_MSHookFunction', '_MSFindSymbol', '_MSGetImageByName', '_LHHookFunctions', '_LBHookMessage', '_substitute_hook_functions'}
assert not required - exports, f'missing public nlist definitions {required - exports}'

# nlist definitions alone do not establish dyld bindings. Read the actual export
# trie, rejecting reexports, resolvers, private definitions and malformed edges.
assert export_range is not None, 'engine dyld export trie missing'
base, length = export_range
assert length and base + length <= len(data), 'invalid export trie range'
trie = data[base:base + length]
def uleb(pos, limit):
    value = 0
    for shift in range(0, 70, 7):
        assert pos < limit, 'truncated export trie ULEB'
        byte = trie[pos]
        pos += 1
        assert shift < 63 or byte < 2, 'export trie ULEB overflow'
        value |= (byte & 0x7f) << shift
        if not byte & 0x80:
            return value, pos
    raise AssertionError('oversized export trie ULEB')

public = set()
pending = [(0, '', frozenset())]
visited = 0
while pending:
    pos, prefix, ancestors = pending.pop()
    assert pos < len(trie) and pos not in ancestors, 'export trie cycle/bad offset'
    assert len(prefix) <= 4096, 'export trie name too long'
    ancestors = ancestors | {pos}
    visited += 1
    assert visited <= 100000, 'export trie exceeds review bound'
    terminal, pos = uleb(pos, len(trie))
    terminal_end = pos + terminal
    assert terminal_end < len(trie), 'truncated export terminal'
    if terminal:
        flags, cursor = uleb(pos, terminal_end)
        if flags == 0:  # regular, locally defined, no resolver or reexport
            address, cursor = uleb(cursor, terminal_end)
            assert cursor == terminal_end and address, 'invalid function export'
            public.add(prefix)
    pos = terminal_end
    children = trie[pos]
    pos += 1
    for _ in range(children):
        stop = trie.index(b'\0', pos)
        assert stop > pos, 'empty export edge'
        edge = trie[pos:stop].decode()
        child, pos = uleb(stop + 1, len(trie))
        pending.append((child, prefix + edge, ancestors))
assert not required - public, f'missing actual dyld exports {required - public}'
info = plistlib.loads((framework / 'Info.plist').read_bytes())
assert info['CFBundleExecutable'] == 'CydiaSubstrate'
assert info['CFBundlePackageType'] == 'FMWK'
print(f'ARM64 iOS shim verified, {len(public)} dyld exports, signed resource, correct install name')
