#!/usr/bin/env python3
"""Run the production Rust append injector, never execute an imported application.
An optional local Mach-O path is private input and is not uploaded or committed.
"""
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
swift = (ROOT / 'ios-app/Apps/RuntimeArabicTranslation.swift').read_text()
assert 'libraries: [dylib], newFirst: false' in swift
assert 'libraries: [dylib], newFirst: true' not in swift
with tempfile.TemporaryDirectory(prefix='mirsa-translation-ordinals26-') as tmp:
    work = Path(tmp) / 'crate'
    work.mkdir()
    (Path(tmp) / 'hook-engine').symlink_to(ROOT / 'hook-engine', target_is_directory=True)
    (work / 'src').mkdir()
    source = (ROOT / 'rust-core/src/ipa_editor.rs').read_text().split('#[derive(Deserialize)]\nstruct Request {', 1)[0]
    source = re.sub(r'#\[path\s*=\s*"([^"]+)"\]', lambda m: '#[path = "' + str(ROOT / 'rust-core/src' / m[1]) + '"]', source.replace('//!', '//'))
    main = r'''
fn ordinal_names(m: &Mach) -> Vec<String> {
    m.commands.iter().filter(|c| matches!(c.kind, 0xc|0x18|0x80000018|0x1f|0x8000001f|0x23|0x80000023|0x20))
        .map(|c| c.name.clone().expect("dependency name")).collect()
}
fn check(original: Vec<u8>, root: &Path, library: &str, label: &str) {
    fs::create_dir_all(root).unwrap();
    let app = root.join("Host.app"); fs::create_dir_all(&app).unwrap();
    let before = macho(original.clone(), false).unwrap();
    let prior = ordinal_names(&before);
    assert!(!prior.is_empty());
    fs::write(app.join("Main"), &original).unwrap();
    inject(&app, "Main", &[library.to_string()], false).unwrap();
    let bytes = fs::read(app.join("Main")).unwrap();
    let after = macho(bytes.clone(), false).unwrap();
    assert_eq!(after.commands.len(), before.commands.len()+1);
    // Stronger than comparing just LC_LOAD_DYLIB: preserve EVERY original
    // command byte, including weak/reexport/upward/lazy dependencies and bind metadata.
    for (a,b) in before.commands.iter().zip(&after.commands) {assert_eq!(a.data,b.data);}
    let mut expected = prior.clone(); expected.push("@loader_path/Frameworks/MirsaTranslate.dylib".into());
    assert_eq!(ordinal_names(&after),expected);
    // No relocation or ordinal rebinding anywhere in __LINKEDIT or section data.
    assert_eq!(&original[before.first_data..],&bytes[before.first_data..]);
    // Negative control: the old prepend path changes every original ordinal.
    fs::remove_dir_all(app.join("Frameworks")).unwrap();
    fs::write(app.join("Main"), &original).unwrap();
    inject(&app, "Main", &[library.to_string()], true).unwrap();
    let old = macho(fs::read(app.join("Main")).unwrap(), false).unwrap();
    let shifted = ordinal_names(&old);
    assert_eq!(&shifted[1..], &prior[..]);
    assert_ne!(shifted[0], prior[0]);
    println!("{label}: {} original dependencies and {} load commands preserved byte-for-byte; new translation last; old prepend shifts ordinals (negative control)",prior.len(),before.commands.len());
}
fn main() {
    let args: Vec<_> = std::env::args().collect();
    let root = Path::new(&args[1]); let library = &args[2];
    let mut d = vec![0u8;8192];
    put32(&mut d,0,0xfeedfacf);put32(&mut d,4,0x0100000c);put32(&mut d,12,2);
    put32(&mut d,16,1);put32(&mut d,20,152);
    put32(&mut d,32,0x19);put32(&mut d,36,152);
    d[40..46].copy_from_slice(b"__TEXT");
    d[80..88].copy_from_slice(&8192u64.to_le_bytes());put32(&mut d,96,1);
    d[144..152].copy_from_slice(&16u64.to_le_bytes());put32(&mut d,152,4096);
    let m=macho(d,false).unwrap();let mut commands:Vec<_>=m.commands.iter().map(|c|c.data.clone()).collect();
    for (i,kind) in [0xc,0x80000018,0x8000001f,0x80000023,0x20].iter().enumerate(){
        commands.push(dylib_command(*kind,&format!("/usr/lib/libOrdinal{i}.dylib"),None).unwrap());
    }
    check(write_commands(m,commands).unwrap().to_vec(),&root.join("synthetic"),library,"all-dependency-kinds");
    if let Some(path)=args.get(3){check(fs::read(path).unwrap(),&root.join("private"),library,"private-static-Mach-O");}
}
'''
    (work/'src/main.rs').write_text('#![allow(dead_code,unused_imports)]\nmod personal_sign { pub struct Options { pub remove_extensions:bool, pub remove_watch:bool, pub remove_app_clips:bool } }\n'+source+main)
    (work/'Cargo.toml').write_text('''[package]
name="mirsa-translation-ordinal-regression26"
version="0.1.0"
edition="2021"
[dependencies]
serde={version="1",features=["derive"]}
serde_json="1"
libc="0.2"
memmap2="=0.9.12"
tempfile="3"
plist={version="=1.10.1",features=["enable_unstable_features_that_may_break_with_minor_version_bumps"]}
zip={version="=2.4.2",default-features=false,features=["deflate"]}
sha2="0.10"
caseless="0.2"
unicode-normalization="0.1"
tar="0.4"
flate2="1"
lzma-rust2={version="0.22",default-features=false,features=["std","xz"]}
''')
    subprocess.run(['cargo','run','--quiet','--manifest-path',str(work/'Cargo.toml'),'--',str(work/'fixtures'),str(ROOT/'ios-app/RuntimeTranslationAssets/MirsaTranslate.dylib'),*sys.argv[1:]],check=True,env={**os.environ,'CARGO_PROFILE_DEV_DEBUG':'0','CARGO_TARGET_DIR':os.environ.get('MIRSA_ORDINAL_TEST_TARGET',str(work/'target'))})
