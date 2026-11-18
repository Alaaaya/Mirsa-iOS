#!/usr/bin/env python3
"""Compile actual nested signing policy + actual signing option decoder offline.
File traversal/encryption stubs are deliberately not exercised. Not an iOS sign/install test.
"""
import os
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
source = (root / "rust-core/src/personal_sign.rs").read_text()
options = source[source.index("fn default_preserve_app_groups()"):source.index("\nstruct Profile {")]
harness = """
#![allow(dead_code)]
OPTIONS
pub fn matches_id(pattern: &str,id:&str)->bool {
    if let Some(prefix)=pattern.strip_suffix('*') { !prefix.contains('*') && id.starts_with(prefix) } else { pattern==id }
}
mod ipa_editor {
    pub fn walk(_: &std::path::Path,_: &mut Vec<std::path::PathBuf>)->Result<(),String> { unimplemented!("not exercised by policy tests") }
    pub fn encryption_status(_: &[u8])->Result<(),String> { unimplemented!("not exercised by policy tests") }
}
#[path="NESTED"]
mod nested;
#[test] fn preserve_option_defaults_on_and_accepts_explicit_off() {
    assert!(Options::default().preserve_app_groups);
    assert!(serde_json::from_str::<Options>("{}").unwrap().preserve_app_groups);
    assert!(!serde_json::from_str::<Options>(r#"{"preserve_app_groups":false}"#).unwrap().preserve_app_groups);
}
""".replace("OPTIONS", options).replace("NESTED", str(root / "rust-core/src/personal_nested.rs"))
with tempfile.TemporaryDirectory(prefix="mirsa-appgroups-") as tmp:
    p = Path(tmp)
    (p / "src").mkdir()
    (p / "Cargo.toml").write_text("""[package]
name="mirsa_cert_appgroup_policy"
version="0.1.0"
edition="2021"
[dependencies]
plist="=1.10.1"
serde_json="1"
serde={version="1",features=["derive"]}
""")
    (p / "src/lib.rs").write_text(harness)
    subprocess.run(["cargo", "test", "--offline", "--manifest-path", str(p / "Cargo.toml")], check=True)
