// Device-specific HTTPS identity. The CA signing key never leaves this function.
use rsa::{RsaPrivateKey, RsaPublicKey, pkcs1v15::SigningKey, pkcs8::{EncodePrivateKey, SubjectPublicKeyInfo}};
use sha2::Sha256;
use x509_cert::{builder::{Builder, CertificateBuilder, Profile}, der::{Encode, asn1::Ia5String}, ext::pkix::{SubjectAltName, ExtendedKeyUsage, name::GeneralName}, name::Name, serial_number::SerialNumber, time::Validity};
use isideload_p12_keystore::{KeyStore, KeyStoreEntry, PrivateKeyChain, PrivateKey, Certificate};
use base64::{Engine, engine::general_purpose::STANDARD};
use std::{str::FromStr, time::Duration};
pub fn generate(output: &str) -> Result<(), String> {
    generate_inner(output).map_err(|_| "Local HTTPS identity generation failed".to_string())
}
fn generate_inner(output: &str) -> Result<(), Box<dyn std::error::Error>> {
    let mut rng = rsa::rand_core::OsRng;
    let ca = RsaPrivateKey::new(&mut rng, 2048)?;
    let leaf = RsaPrivateKey::new(&mut rng, 2048)?;
    let signer = SigningKey::<Sha256>::new(ca);
    let root_name = Name::from_str("CN=Mirsa Local Install,O=Mirsa On Device")?;
    let root = CertificateBuilder::new(Profile::Root, SerialNumber::new(&[1])?,
        Validity::from_now(Duration::from_secs(365 * 86400))?, root_name.clone(),
        SubjectPublicKeyInfo::from_key(RsaPublicKey::from(signer.as_ref()))?, &signer)?.build()?;
    let mut builder = CertificateBuilder::new(Profile::Leaf { issuer: root_name,
        enable_key_agreement: false, enable_key_encipherment: true }, SerialNumber::new(&[2])?,
        Validity::from_now(Duration::from_secs(180 * 86400))?,
        Name::from_str("CN=mirsa.localtest.me,O=Mirsa On Device")?,
        SubjectPublicKeyInfo::from_key(RsaPublicKey::from(&leaf))?, &signer)?;
    builder.add_extension(&SubjectAltName(vec![GeneralName::DnsName(Ia5String::new("mirsa.localtest.me")?)]))?;
    builder.add_extension(&ExtendedKeyUsage(vec!["1.3.6.1.5.5.7.3.1".parse()?]))?;
    let leaf_der = builder.build()?.to_der()?;
    let root_der = root.to_der()?;
    let mut store = KeyStore::new();
    store.add_entry("mirsa-local", KeyStoreEntry::PrivateKeyChain(PrivateKeyChain::new("mirsa-local",
        PrivateKey::from_der(leaf.to_pkcs8_der()?.as_bytes())?,
        vec![Certificate::from_der(&leaf_der)?, Certificate::from_der(&root_der)?])));
    // Password protects the temporary import container; the container is placed in
    // ThisDeviceOnly keychain by Swift. Neither identity nor key is ever HTTP-served.
    let password = uuid::Uuid::new_v4().to_string();
    let p12 = store.writer(&password).write()?;
    let data = serde_json::to_vec(&serde_json::json!({
        "p12": STANDARD.encode(p12), "password": password, "root": STANDARD.encode(root_der),
        "expires": std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH)?.as_secs() + 179 * 86400
    }))?;
    std::fs::write(output, data)?;
    Ok(())
}
#[cfg(test)] mod tests {
    use super::*;
    #[test] fn isolated_valid_identity() {
        use x509_cert::der::Decode;
        let p = std::env::temp_dir().join(format!("mirsa-tls-{}.json", uuid::Uuid::new_v4()));
        generate(p.to_str().unwrap()).unwrap();
        let v: serde_json::Value = serde_json::from_slice(&std::fs::read(&p).unwrap()).unwrap();
        std::fs::remove_file(p).unwrap();
        let cert = x509_cert::Certificate::from_der(&STANDARD.decode(v["root"].as_str().unwrap()).unwrap()).unwrap();
        assert!(cert.tbs_certificate.subject.to_string().contains("Mirsa Local Install"));
        let store = KeyStore::from_pkcs12(&STANDARD.decode(v["p12"].as_str().unwrap()).unwrap(), v["password"].as_str().unwrap(), isideload_p12_keystore::Pkcs12ImportPolicy::Raw).unwrap();
        let (_, chain) = store.private_key_chain().unwrap();
        assert_eq!(chain.certs().len(), 2);
    }
}
