#!/usr/bin/env python3
"""The native fixtures and embedded loader must satisfy modern dyld UUID checks."""
from pathlib import Path
import struct
root = Path(__file__).resolve().parents[1]
for name in ("loader/MirsaLoader.dylib", "tests/fixtures/generic-injection25/GenericMarker25.dylib", "tests/fixtures/generic-injection25/GenericHookMarker25.dylib"):
    data = (root / name).read_bytes()
    assert data[:4] == bytes.fromhex("cffaedfe")
    offset = 32
    uuids = []
    for _ in range(struct.unpack_from("<I", data, 16)[0]):
        command, size = struct.unpack_from("<II", data, offset)
        assert size >= 8 and size % 8 == 0 and offset + size <= len(data)
        if command == 0x1b:
            assert size == 24
            uuids.append(data[offset + 8:offset + size])
        offset += size
    assert len(uuids) == 1 and any(uuids[0]), name + " must have exactly one nonzero LC_UUID"
    print(name + ": nonzero LC_UUID verified")
