#!/usr/bin/env python3
"""Compile actual imported-load modules with their actual parser, without iOS deps.
Uses serde/serde_json from Cargo's offline cache. Not a full FFI/device build.
"""
import os
from pathlib import Path
import subprocess
import tempfile

repo = Path(__file__).resolve().parents[1]
root = repo / 'rust-core/src'
with tempfile.TemporaryDirectory(prefix='mirsa-imported-harness-') as tmp:
    harness = Path(tmp)
    (harness / 'src').mkdir()
    (harness / 'Cargo.toml').write_text('''[package]
name="mirsa-imported-harness"
version="0.1.0"
edition="2021"
[dependencies]
serde={version="1",features=["derive"]}
serde_json="1"
''')
    source = (root / 'ipa_editor.rs').read_text()
    parts = ['''use std::{collections::{BTreeMap, HashSet},fs::{self,File},io::{self,Read},path::{Component,Path,PathBuf}};
type Result<T> = std::result::Result<T,String>;
const ENTRY_LIMIT:usize=100000;
fn err(e:impl std::fmt::Display)->String{e.to_string()}
''']
    for start, end in [('fn relative(', 'fn fresh_dir('),
                       ('pub(crate) fn walk(', 'fn pack('),
                       ('fn u32at(', '/// Read-only encryption inspection.'),
                       ('fn dylib_command(', 'fn write_commands('),
                       ('fn copy_tree(', 'fn framework_executable(')]:
        parts.append(source[source.index(start):source.index(end)])
    for module in ['fat_macho', 'imported_loads']:
        parts.append(f'#[path="{root / (module + ".rs")}"] mod {module};')
    (harness / 'src/lib.rs').write_text('\n'.join(parts))
    env = dict(os.environ, CARGO_PROFILE_DEV_DEBUG='0', CARGO_PROFILE_TEST_DEBUG='0')
    subprocess.run(['cargo', 'test', '--offline', '--manifest-path', str(harness / 'Cargo.toml')], env=env, check=True)
