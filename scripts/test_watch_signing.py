"""Compile actual production preflight/policy and vendor signer against clean generated code.
No owner IPA, Apple code, runtime installation, or cryptographic CMS claims.
"""
import os, pathlib, subprocess, tempfile
root = pathlib.Path(__file__).resolve().parents[1]
editor = (root/"rust-core/src/ipa_editor.rs").read_text()
walk = editor[editor.index("pub(crate) fn walk("):editor.index("fn pack(")]
inspection = editor[editor.index("pub(crate) fn encryption_status("):editor.index("fn dylib_command(")]
prefix = """#![allow(dead_code)]
use std::{fs::{self,File}, path::{Path, PathBuf}, io::Read, collections::BTreeMap};
use plist::{Dictionary,Value};
type Result<T> = std::result::Result<T,String>;
fn err(e: impl std::fmt::Display)->String{e.to_string()}
#[derive(Default)] pub struct Options {remove_extensions:bool,remove_watch:bool,remove_app_clips:bool}
mod personal_sign {pub use crate::Options;}
pub fn matches_id(p:&str,id:&str)->bool {
 if let Some(s)=p.strip_suffix('*'){!s.contains('*')&&id.starts_with(s)}else{p==id}
}
"""
with tempfile.TemporaryDirectory(prefix="watch-signing-") as tmp:
    tmp = pathlib.Path(tmp)
    (tmp/"src").mkdir()
    (tmp/"Cargo.toml").write_text('''[package]
name="mirsa-watch-regression"
version="0.1.0"
edition="2024"
[dependencies]
plist="=1.10.1"
serde={version="1",features=["derive"]}
serde_json="1"
sha1="0.11"
sha2="0.11"
apple-codesign-quick={path="'''+str(root/"rust-core/vendor/apple-codesign-quick")+'''"}\n''')
    source = prefix + "mod ipa_editor {use super::*;const ENTRY_LIMIT:usize=100000;const IPA_EXECUTABLE_LIMIT:u64=1500000000;\n" + walk + inspection + "}\n"
    source += '#[path="'+str(root/"rust-core/src/personal_nested.rs")+'"] mod nested;\n'
    source += (root/"scripts/watch_signing_fixture.rs").read_text()
    (tmp/"src/lib.rs").write_text(source)
    env=os.environ.copy()
    env.setdefault("CARGO_PROFILE_DEV_DEBUG","0")
    subprocess.run(["cargo","test","--manifest-path",str(tmp/"Cargo.toml"),"--lib"],env=env,check=True)
