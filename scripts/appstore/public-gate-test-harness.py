#!/usr/bin/env python3
"""Extract the real dependency-free public gate, never substitute a test value."""
from pathlib import Path
import re
import sys

def extract_gate(source):
    declarations = re.findall(r'\benum\s+MirsaStoreAvailability\b', source)
    matches = list(re.finditer(
        r'^enum MirsaStoreAvailability \{\n'
        r'    static let publicLoginEnabled = (?:false|true)\n'
        r'\}', source, re.MULTILINE))
    if len(declarations) != 1 or len(matches) != 1:
        raise ValueError("Expected exactly one dependency-free MirsaStoreAvailability enum")
    return matches[0].group(0) + "\n"

def main():
    root = Path(__file__).resolve().parents[2]
    work = Path(sys.argv[1])
    gate = extract_gate((root / 'ios-app/Apps/StoreServerIdentity.swift').read_text())
    (work / 'Sources/MirsaStoreKit/StorePublicGate.swift').write_text(gate)
    test = (root / 'tests/StorePublicGateTests.swift').read_text()
    if test.count('@testable import Mirsa\n') != 1:
        raise ValueError("Expected exactly one production test module import")
    (work / 'Tests/MirsaStoreKitTests/StorePublicGateTests.swift').write_text(
        test.replace('@testable import Mirsa\n', '@testable import MirsaStoreKit\n'))
    print("Actual production public gate and unchanged gate test extracted")

if __name__ == '__main__':
    main()
