#!/usr/bin/env python3
"""Compile exact production library graph/editor and its real parent helpers.
No Mach-O parser or tree validation stubs. Does not claim Swift/iOS validation.
"""
import os
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]

def function(text, name):
    at = text.index('fn ' + name + '(')
    start = text.rfind('\n', 0, at) + 1
    brace = text.index('{', at)
    depth, end = 1, brace + 1
    while depth:
        depth += (text[end] == '{') - (text[end] == '}')
        end += 1
    return text[start:end]


def main():
    source = ROOT / 'rust-core/src'
    parent = (source / 'ipa_editor.rs').read_text()
    targets = (source / 'tweak_targets.rs').read_text()
    with tempfile.TemporaryDirectory(prefix='mirsa-preinjected-') as tmp:
        work = Path(tmp)
        (work / 'src').mkdir()
        harness = '''#![allow(dead_code)]
use std::{collections::{BTreeMap,HashSet},fs::{self,File},io::Read,path::{Path,PathBuf,Component}};
type Result<T> = std::result::Result<T,String>;
const ENTRY_LIMIT:usize=100000;
const FILE_LIMIT:u64=512*1024*1024;
const TOTAL_LIMIT:u64=4*1024*1024*1024;
'''
        harness += '\n'.join(function(parent, n) for n in ['err','relative','walk','walk_depth','u32at','put32','read_macho'])
        harness += '\nmod tweak_targets {use super::*;\n' + function(targets, 'checked_tree') + '\n}\n'
        harness += '#[path="' + str(source / 'existing_libraries.rs') + '"] mod existing_libraries;\n'
        (work / 'src/lib.rs').write_text(harness)
        (work / 'Cargo.toml').write_text('''[package]
name="mirsa-preinjected-native"
version="0.1.0"
edition="2021"
[dependencies]
serde={version="1",features=["derive"]}
serde_json="1"
plist="=1.10.1"
apple-codesign-quick={path="''' + str(ROOT / 'rust-core/vendor/apple-codesign-quick') + '''"}
zip={version="=2.4.2",default-features=false,features=["deflate"]}
''')
        subprocess.run(['cargo','test','--manifest-path',str(work / 'Cargo.toml'),'--','--nocapture'], check=True,
                       env={**os.environ,'CARGO_PROFILE_TEST_DEBUG':'0'})
    view = (ROOT / 'ios-app/Apps/PersonalProjectDetailView.swift').read_text()
    card = (ROOT / 'ios-app/Apps/ExistingLibraryPlan.swift').read_text()
    assert view.count('ExistingLibrariesCard(') == 1
    assert view.index('ExistingLibrariesCard(') > view.index('private var tweaksCard:')
    assert 'if ids.isEmpty && existingLibraries.isEmpty' in view
    assert 'if row.lib.kind != "file"' in card
    for label in ['Already present','موجودة مسبقاً','Bereits vorhanden','پێشتر هەیە','Jixwe heyî']:
        assert label in card
    print('UI wiring and 5-locale contracts PASS (not native UI compilation)')

if __name__ == '__main__':
    main()
