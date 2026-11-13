#!/usr/bin/env python3
"""Compile the exact production importer and parent parsing helpers natively.
Avoid unrelated iOS transport/signing dependencies; no production code stubs.
The full device build separately compiles the real FFI dispatch and Swift UI.
"""
import pathlib, re, shutil, subprocess, tempfile, os
root = pathlib.Path(__file__).resolve().parents[2]
source = root / "rust-core/src"
with tempfile.TemporaryDirectory(prefix="mirsa-zip-tests-") as tmp:
    work = pathlib.Path(tmp)
    (work / "src").mkdir()
    text = (source / "ipa_editor.rs").read_text()
    start = text.index("use serde::Deserialize;")
    end = text.index("#[derive(Deserialize)]\nstruct Request")
    text = text[start:end]
    # Only platform signing aggregation is outside this test surface.
    start = text.index("pub(crate) fn signing_encryption(")
    brace = text.index("{", start)
    depth, i = 1, brace + 1
    while depth:
        depth += (text[i] == "{") - (text[i] == "}")
        i += 1
    text = text[:start] + text[i:]
    for name in ["fat_macho", "tweak_import"]:
        text += f'\n#[path="{source / (name + ".rs")}"] mod {name};\n'
    (work / "src/lib.rs").write_text(text)
    (work / "Cargo.toml").write_text(f"""[package]
name="mirsa-zip-import-tests"
version="0.1.0"
edition="2021"
[dependencies]
serde={{version="1",features=["derive"]}}
serde_json="1"
plist="=1.10.1"
zip={{version="=2.4.2",default-features=false,features=["deflate"]}}
tar="0.4"
flate2="1"
lzma-rust2={{version="0.22",default-features=false,features=["std","xz"]}}
sha2="0.10"
libc="0.2"
caseless="0.2"
unicode-normalization="0.1"
apple-codesign-quick={{path="{root / 'rust-core/vendor/apple-codesign-quick'}"}}
""")
    env = dict(os.environ, CARGO_PROFILE_TEST_DEBUG="0")
    # Reusable target path is caller-owned, never deletes anyone else's build.
    subprocess.run(["cargo","test","--manifest-path",str(work / "Cargo.toml"),"--lib","--","--nocapture"], check=True, env=env)
