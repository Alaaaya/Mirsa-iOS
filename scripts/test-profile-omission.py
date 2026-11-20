#!/usr/bin/env python3
"""Compile the actual option decoder and omission device-result policy.
This is not a device connection or signed IPA install test.
"""
from pathlib import Path
import os
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
source = (root / "rust-core/src/personal_sign.rs").read_text()
options = source[source.index("#[derive(Default, serde::Deserialize)]\npub(crate) struct Options"):source.index("\nstruct Profile {")]
verification = source[source.index("#[derive(Default, serde::Serialize)]"):source.index("pub(crate) fn profile_with_verification")]
policy = source[source.index("fn record_omitted_profile_install("):source.index("#[cfg(test)]\nmod tests {")]
with tempfile.TemporaryDirectory(prefix="mirsa-profile-omission-") as tmp:
    p = Path(tmp)
    (p / "src").mkdir()
    (p / "Cargo.toml").write_text("""[package]
name="mirsa_profile_omission_policy"
version="0.1.0"
edition="2021"
[dependencies]
serde_json="1"
serde={version="1",features=["derive"]}
""")
    defaults = """
#[cfg(test)] mod defaults {
    use super::*;
    #[test] fn omission_is_explicit_boolean_and_default_off() {
        assert!(!Options::default().omit_embedded_profile);
        assert!(!serde_json::from_str::<Options>("{}").unwrap().omit_embedded_profile);
        assert!(serde_json::from_str::<Options>(r#"{"omit_embedded_profile":true}"#).unwrap().omit_embedded_profile);
        for value in ["null","1",r#""true""#] {
            assert!(serde_json::from_str::<Options>(&format!(r#"{{"omit_embedded_profile":{value}}}"#)).is_err());
        }
    }
}
"""
    (p / "src/lib.rs").write_text("#![allow(dead_code)]\n" + options + verification + policy + defaults)
    args = ["cargo", "test", "--manifest-path", str(p / "Cargo.toml")]
    if os.environ.get("MIRSA_OFFLINE") == "1":
        args.append("--offline")
    subprocess.run(args, check=True)
