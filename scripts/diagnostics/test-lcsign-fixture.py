#!/usr/bin/env python3
"""Validate public LCSign test material with real entitlement preflight and signer.

No Apple trust, system installation or app-launch claim. Requires cargo and openssl.
Only the production read-only Mach-O functions are extracted to avoid unrelated iOS FFI.
"""
from pathlib import Path
import os
import subprocess
import tempfile
import zipfile

root = Path(__file__).resolve().parents[2]
fixture = root / "tests/Fixtures"
editor = (root / "rust-core/src/ipa_editor.rs").read_text()
encryption = editor[editor.index("pub(crate) fn encryption_status"):editor.index("pub(crate) fn unencrypted")]
nested = (root / "rust-core/src/personal_nested.rs").read_text()
entitlements = nested[nested.index("fn be("):nested.index("pub(super) fn file_error")]
entitlements = entitlements.replace("pub(super) fn read_entitlements", "pub(crate) fn read_entitlements")

with tempfile.TemporaryDirectory(prefix="lcsign-fixture-") as temporary:
    work = Path(temporary)
    (work / "src").mkdir()
    # Absolute source paths are only in the temporary manifest, never committed.
    vendor = root / "rust-core/vendor/apple-codesign-quick"
    import json
    (work / "Cargo.toml").write_text(
        '[package]\nname="lcsign_fixture_check"\nversion="0.1.0"\nedition="2021"\n'
        '[dependencies]\napple-codesign-quick={path=' + json.dumps(str(vendor)) + '}\nplist="=1.10.1"\n'
    )
    with zipfile.ZipFile(fixture / "LCSignSynthetic.ipa") as archive:
        # Fixed public repository fixture, never a user-supplied archive.
        assert set(archive.namelist()) == {"Payload/Fixture.app/Main", "Payload/Fixture.app/Info.plist"}
        archive.extractall(work)
    p12 = fixture / "LCSignSynthetic.p12"
    key_pem, cert_pem = work / "key.pem", work / "cert.pem"
    for output, selection in [(key_pem, "-nocerts"), (cert_pem, "-clcerts")]:
        args = ["openssl", "pkcs12", "-in", str(p12), "-passin", "pass:mirsa-test"]
        args += ["-nodes", selection] if selection == "-nocerts" else [selection, "-nokeys"]
        subprocess.run(args + ["-out", str(output)], check=True, capture_output=True)
    subprocess.run(["openssl", "pkey", "-in", str(key_pem), "-outform", "DER", "-out", str(work / "key.der")], check=True)
    subprocess.run(["openssl", "x509", "-in", str(cert_pem), "-outform", "DER", "-out", str(work / "cert.der")], check=True)
    harness = r"""
#![allow(dead_code)]
type Result<T> = std::result::Result<T,String>;
fn error(e: impl std::fmt::Display)->String{e.to_string()}
fn err(e: impl std::fmt::Display)->String{e.to_string()}
use plist::{Value,Dictionary};
"""
    harness += "mod ipa_editor { use super::*; " + encryption + "}\n" + entitlements
    harness += r"""
#[test] fn production_preflight_then_real_signer() {
    use apple_codesign_quick::{ProvisioningProfile,BundleSigningSettings,RustCryptoCmsSigner};
    let root=std::path::PathBuf::from(std::env::var("LCSIGN_FIXTURE_WORK").unwrap());
    let fixtures=std::path::PathBuf::from(std::env::var("LCSIGN_PUBLIC_FIXTURES").unwrap());
    let app=root.join("Payload/Fixture.app");
    let executable=app.join("Main");
    let before=std::fs::read(&executable).unwrap();
    assert!(read_entitlements(&before).unwrap().is_empty());
    // Preserve the production rejection which caught the previous bad fixture.
    let mut malformed=before.clone();
    malformed[16..20].copy_from_slice(&3u32.to_le_bytes());
    malformed[20..24].copy_from_slice(&240u32.to_le_bytes());
    malformed[256..260].copy_from_slice(&0x1du32.to_le_bytes());
    malformed[260..264].copy_from_slice(&16u32.to_le_bytes());
    malformed[264..268].copy_from_slice(&(before.len() as u32).to_le_bytes());
    assert!(read_entitlements(&malformed).is_err(), "An empty signature is not unsigned code");
    let profile_bytes=std::fs::read(fixtures.join("LCSignSynthetic.mobileprovision")).unwrap();
    let profile=ProvisioningProfile::parse(&profile_bytes).unwrap();
    let key=std::fs::read(root.join("key.der")).unwrap();
    let cert=std::fs::read(root.join("cert.der")).unwrap();
    assert!(profile.plist().get("DeveloperCertificates").unwrap().as_array().unwrap()
        .iter().any(|v| v.as_data()==Some(cert.as_slice())));
    let signer=RustCryptoCmsSigner::from_der(&key,&cert,profile.certificate_chain_der()).unwrap();
    let mut settings=BundleSigningSettings::new(profile.team_id().to_owned(),profile.entitlements().clone(),Some(&signer));
    settings.embedded_mobileprovision=Some(&profile_bytes);
    apple_codesign_quick::sign_bundle(&app,&settings).unwrap();
    let after=std::fs::read(&executable).unwrap();
    assert!(after.len()>before.len());
    assert!(!read_entitlements(&after).unwrap().is_empty());
}
"""
    (work / "src/lib.rs").write_text(harness)
    # personal_nested declares this module by path, so ship the production file next to lib.rs.
    (work / "src/signature_ranges.rs").write_text((root / "rust-core/src/signature_ranges.rs").read_text())
    env = dict(os.environ, LCSIGN_FIXTURE_WORK=str(work), LCSIGN_PUBLIC_FIXTURES=str(fixture))
    args = ["cargo", "test", "--manifest-path", str(work / "Cargo.toml")]
    if os.environ.get("MIRSA_OFFLINE") == "1":
        args.append("--offline")
    subprocess.run(args, env=env, check=True)
