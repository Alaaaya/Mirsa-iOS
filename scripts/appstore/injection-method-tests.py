#!/usr/bin/env python3
"""Native tests of unchanged production editor/injection modules, no iOS runtime claim.
Only platform signing/FFI dispatch (after Request) is omitted. No injector/parser
stubs: all archive, Mach-O, target, graph and loader implementation is production.
"""
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
def main():
    with tempfile.TemporaryDirectory(prefix="mirsa-injection-method-") as tmp:
        work = Path(tmp)
        (work / "src").mkdir()
        source = (ROOT / "rust-core/src/ipa_editor.rs").read_text()
        source = source.split("#[derive(Deserialize)]\nstruct Request {", 1)[0]
        # Include source files verbatim by absolute path. The module's embedded
        # loader include_bytes remains anchored to its actual production file.
        source = source.replace("//!", "//")
        source = re.sub(r'#\[path\s*=\s*"([^"]+)"\]',
                        lambda m: '#[path = "' + str(ROOT / "rust-core/src" / m[1]) + '"]', source)
        (work / "src/lib.rs").write_text(
            '#![allow(dead_code,unused_imports)]\n'
            'mod personal_sign { pub struct Options { pub remove_extensions:bool, pub remove_watch:bool, pub remove_app_clips:bool } }\n'
            + source)
        (work / "Cargo.toml").write_text("""[package]
name = "mirsa-injection-method-native"
version = "0.1.0"
edition = "2021"
[dependencies]
serde = {version="1", features=["derive"]}
serde_json = "1"
libc = "0.2"
plist = {version="=1.10.1",features=["enable_unstable_features_that_may_break_with_minor_version_bumps"]}
zip = {version="=2.4.2",default-features=false,features=["deflate"]}
sha2 = "0.10"
caseless = "0.2"
unicode-normalization = "0.1"
tar = "0.4"
flate2 = "1"
lzma-rust2 = {version="0.22",default-features=false,features=["std","xz"]}
""")
        cargo = shutil.which("cargo") or str(Path.home() / ".cargo/bin/cargo")
        subprocess.run([cargo, "test", "--manifest-path", str(work / "Cargo.toml"),
                        "--", "--nocapture"], check=True,
                       env={**os.environ, "CARGO_TARGET_DIR": os.environ.get("MIRSA_INJECTION_TEST_TARGET", str(work / "target"))})
if __name__ == "__main__":
    main()
