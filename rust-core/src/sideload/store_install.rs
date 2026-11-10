//! "Encrypted apps": install an App Store IPA exactly as it is.
//!
//! The .ipa file is streamed byte for byte to the device's AFC PublicStaging
//! folder and handed to installation_proxy, the same way ideviceinstaller and
//! Finder install a purchased package: the package's own iTunesMetadata.plist
//! and SC_Info .sinf are passed as `iTunesMetadata` / `ApplicationSINF` client
//! options. Nothing is extracted, re-signed, patched or decrypted. iOS decides
//! whether the purchase (FairPlay) is valid for the device's Apple account.
//!
//! Reuses the sideloader's tunnel (`exploit::connect_tunnel`), the shared
//! install lock and the idevice AFC / installation_proxy clients (MIT).

use std::io::Read;
use std::path::{Path, PathBuf};

use idevice::afc::opcode::AfcFopenMode;
use idevice::afc::AfcClient;
use idevice::installation_proxy::InstallationProxyClient;
use idevice::{IdeviceService, RsdService};

use super::{install_lock, AppDeviceTunnel, Logger};
use crate::exploit;

const STAGING_DIR: &str = "PublicStaging";
const STAGING_FILE: &str = "PublicStaging/mirsa-encrypted.ipa";
const CHUNK: usize = 1024 * 1024;
const MAX_IPA_BYTES: u64 = 8 * 1024 * 1024 * 1024;
const MAX_META_BYTES: u64 = 4 * 1024 * 1024;

/// What the package carries for installation_proxy.
#[derive(Debug)]
pub(crate) struct StorePackage {
    pub bundle_id: String,
    pub name: String,
    pub version: String,
    pub itunes_metadata: Option<Vec<u8>>,
    pub sinf: Option<Vec<u8>>,
}

pub(crate) fn validate_store_ipa(path: &str) -> Result<PathBuf, String> {
    let p = PathBuf::from(path);
    if !p.is_absolute() {
        return Err("IPA path must be absolute".into());
    }
    let meta = std::fs::symlink_metadata(&p).map_err(|e| format!("Reading source app: {e}"))?;
    if meta.file_type().is_symlink() || !meta.is_file() {
        return Err("Reading source app: expected a real .ipa file".into());
    }
    if p.extension().and_then(|e| e.to_str()).map(|e| e.eq_ignore_ascii_case("ipa")) != Some(true) {
        return Err("Reading source app: the file must end in .ipa".into());
    }
    if meta.len() == 0 || meta.len() > MAX_IPA_BYTES {
        return Err("Reading source app: invalid size".into());
    }
    Ok(p)
}

fn read_entry<R: Read + std::io::Seek>(zip: &mut zip::ZipArchive<R>, name: &str) -> Result<Option<Vec<u8>>, String> {
    let mut file = match zip.by_name(name) {
        Ok(f) => f,
        Err(zip::result::ZipError::FileNotFound) => return Ok(None),
        Err(e) => return Err(format!("Reading source app: {e}")),
    };
    if file.size() > MAX_META_BYTES {
        return Err(format!("Reading source app: {name} is too large"));
    }
    let mut out = Vec::with_capacity(file.size() as usize);
    (&mut file).take(MAX_META_BYTES + 1).read_to_end(&mut out).map_err(|e| format!("Reading source app: {e}"))?;
    if out.len() as u64 > MAX_META_BYTES {
        return Err(format!("Reading source app: {name} is too large"));
    }
    Ok(Some(out))
}

/// Read-only look at the archive: Info.plist, iTunesMetadata.plist and the
/// main executable's .sinf. The archive itself is never modified.
pub(crate) fn inspect_store_ipa(path: &Path) -> Result<StorePackage, String> {
    let file = std::fs::File::open(path).map_err(|e| format!("Reading source app: {e}"))?;
    let mut zip = zip::ZipArchive::new(std::io::BufReader::new(file)).map_err(|e| format!("Reading source app: {e}"))?;
    let mut app_dir: Option<String> = None;
    for name in zip.file_names() {
        let mut parts = name.split('/');
        if parts.next() != Some("Payload") {
            continue;
        }
        if let Some(seg) = parts.next() {
            if seg.ends_with(".app") && !seg.contains("..") {
                match &app_dir {
                    None => app_dir = Some(seg.to_string()),
                    Some(existing) if existing != seg => return Err("Reading source app: more than one app in Payload".into()),
                    _ => {}
                }
            }
        }
    }
    let app = app_dir.ok_or_else(|| "Reading source app: no app found inside Payload".to_string())?;
    let info_bytes = read_entry(&mut zip, &format!("Payload/{app}/Info.plist"))?
        .ok_or_else(|| "Reading source app: Info.plist is missing".to_string())?;
    let info = plist::Value::from_reader(std::io::Cursor::new(&info_bytes))
        .ok()
        .and_then(|v| v.into_dictionary())
        .ok_or_else(|| "Reading source app: Info.plist could not be read".to_string())?;
    let s = |k: &str| info.get(k).and_then(|v| v.as_string()).unwrap_or_default().to_string();
    let bundle_id = s("CFBundleIdentifier");
    if bundle_id.is_empty() {
        return Err("Reading source app: no bundle identifier".into());
    }
    let executable = s("CFBundleExecutable");
    let mut name = s("CFBundleDisplayName");
    if name.is_empty() {
        name = s("CFBundleName");
    }
    let itunes_metadata = read_entry(&mut zip, "iTunesMetadata.plist")?;
    let sinf = if executable.is_empty() || executable.contains('/') {
        None
    } else {
        read_entry(&mut zip, &format!("Payload/{app}/SC_Info/{executable}.sinf"))?
    };
    Ok(StorePackage { bundle_id, name, version: s("CFBundleShortVersionString"), itunes_metadata, sinf })
}

/// ClientOptions exactly like ideviceinstaller uses for a purchased package.
pub(crate) fn client_options(pkg: &StorePackage) -> plist::Dictionary {
    let mut d = plist::Dictionary::new();
    d.insert("CFBundleIdentifier".into(), plist::Value::String(pkg.bundle_id.clone()));
    if let Some(m) = &pkg.itunes_metadata {
        d.insert("iTunesMetadata".into(), plist::Value::Data(m.clone()));
    }
    if let Some(s) = &pkg.sinf {
        d.insert("ApplicationSINF".into(), plist::Value::Data(s.clone()));
    }
    d
}

async fn upload(afc: &mut AfcClient, ipa: &Path, progress: &(impl Fn(f64, &str) + Send + Sync)) -> Result<(), String> {
    if afc.get_file_info(STAGING_DIR).await.is_err() {
        afc.mk_dir(STAGING_DIR).await.map_err(|e| format!("Install failed: {e}"))?;
    }
    let _ = afc.remove(STAGING_FILE).await;
    let total = std::fs::metadata(ipa).map(|m| m.len()).unwrap_or(1).max(1) as f64;
    let mut source = std::fs::File::open(ipa).map_err(|e| format!("Reading source app: {e}"))?;
    let mut fd = afc.open(STAGING_FILE, AfcFopenMode::WrOnly).await.map_err(|e| format!("Install failed: {e}"))?;
    let mut buf = vec![0u8; CHUNK];
    let mut sent: u64 = 0;
    loop {
        let n = source.read(&mut buf).map_err(|e| format!("Reading source app: {e}"))?;
        if n == 0 {
            break;
        }
        fd.write_entire(&buf[..n]).await.map_err(|e| format!("Install failed: {e}"))?;
        sent += n as u64;
        progress((sent as f64 / total * 0.7).min(0.7), "Installing");
    }
    fd.close().await.map_err(|e| format!("Install failed: {e}"))?;
    Ok(())
}

async fn run_install(
    inst: &mut InstallationProxyClient,
    options: plist::Dictionary,
    progress: impl Fn(f64, &str) + Send + Sync + Clone + 'static,
) -> Result<(), String> {
    inst.install_with_callback(
        STAGING_FILE,
        Some(plist::Value::Dictionary(options)),
        |(pct, p)| async move {
            p(0.7 + 0.3 * (pct.min(100) as f64 / 100.0), "Installing");
        },
        progress,
    )
    .await
    .map_err(|e| format!("Install failed: {e}"))
}

pub(crate) async fn install_store_ipa(
    pairing_path: String,
    ipa_path: String,
    logger: &Logger,
    progress: impl Fn(f64, &str) + Send + Sync + Clone + 'static,
) -> Result<serde_json::Value, String> {
    let _install_guard = install_lock().lock().await;
    let ipa = validate_store_ipa(&ipa_path)?;
    let pkg = inspect_store_ipa(&ipa)?;
    let options = client_options(&pkg);
    let pairing = std::fs::read(&pairing_path).map_err(|e| format!("Read pairing file: {e}"))?;
    progress(0.0, "Connecting");
    let tunnel = exploit::connect_tunnel(&pairing, logger).await?;
    match tunnel {
        AppDeviceTunnel::Rsd { mut adapter, mut handshake } => {
            let mut afc = AfcClient::connect_rsd(&mut adapter, &mut handshake)
                .await
                .map_err(|e| format!("Install failed: {e}"))?;
            upload(&mut afc, &ipa, &progress).await?;
            let mut inst = InstallationProxyClient::connect_rsd(&mut adapter, &mut handshake)
                .await
                .map_err(|e| format!("Install failed: {e}"))?;
            let res = run_install(&mut inst, options, progress.clone()).await;
            let _ = afc.remove(STAGING_FILE).await;
            res?;
        }
        AppDeviceTunnel::Lockdown { provider, .. } => {
            let mut afc = AfcClient::connect(&provider).await.map_err(|e| format!("Install failed: {e}"))?;
            upload(&mut afc, &ipa, &progress).await?;
            let mut inst = InstallationProxyClient::connect(&provider)
                .await
                .map_err(|e| format!("Install failed: {e}"))?;
            let res = run_install(&mut inst, options, progress.clone()).await;
            let _ = afc.remove(STAGING_FILE).await;
            res?;
        }
    }
    progress(1.0, "Done");
    Ok(serde_json::json!({
        "bundle_id": pkg.bundle_id,
        "name": pkg.name,
        "version": pkg.version,
        "has_sinf": pkg.sinf.is_some(),
        "has_itunes_metadata": pkg.itunes_metadata.is_some(),
    }))
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Write;
    use zip::write::SimpleFileOptions;

    fn tmp(n: &str) -> PathBuf {
        let d = std::env::temp_dir().join(format!("mirsa-store-{n}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&d);
        std::fs::create_dir_all(&d).unwrap();
        d
    }

    fn info_plist(bid: &str, exe: &str) -> Vec<u8> {
        let mut d = plist::Dictionary::new();
        d.insert("CFBundleIdentifier".into(), bid.into());
        d.insert("CFBundleExecutable".into(), exe.into());
        d.insert("CFBundleDisplayName".into(), "Sample".into());
        d.insert("CFBundleShortVersionString".into(), "4.2".into());
        let mut out = Vec::new();
        plist::Value::Dictionary(d).to_writer_xml(&mut out).unwrap();
        out
    }

    fn make_ipa(dir: &Path, with_meta: bool, with_sinf: bool) -> PathBuf {
        let path = dir.join("Store.ipa");
        let mut z = zip::ZipWriter::new(std::fs::File::create(&path).unwrap());
        let o = SimpleFileOptions::default();
        z.start_file("Payload/Sample.app/Info.plist", o).unwrap();
        z.write_all(&info_plist("com.example.sample", "Sample")).unwrap();
        z.start_file("Payload/Sample.app/Sample", o).unwrap();
        z.write_all(b"\xcf\xfa\xed\xfe").unwrap();
        if with_sinf {
            z.start_file("Payload/Sample.app/SC_Info/Sample.sinf", o).unwrap();
            z.write_all(b"SINFDATA").unwrap();
        }
        if with_meta {
            z.start_file("iTunesMetadata.plist", o).unwrap();
            z.write_all(b"<plist><dict/></plist>").unwrap();
        }
        z.finish().unwrap();
        path
    }

    #[test]
    fn reads_package_and_builds_options_without_modifying_file() {
        let d = tmp("ok");
        let ipa = make_ipa(&d, true, true);
        let before = std::fs::read(&ipa).unwrap();
        let pkg = inspect_store_ipa(&ipa).unwrap();
        assert_eq!(pkg.bundle_id, "com.example.sample");
        assert_eq!(pkg.version, "4.2");
        assert_eq!(pkg.sinf.as_deref(), Some(&b"SINFDATA"[..]));
        let opts = client_options(&pkg);
        assert!(opts.get("iTunesMetadata").and_then(|v| v.as_data()).is_some());
        assert_eq!(opts.get("ApplicationSINF").and_then(|v| v.as_data()), Some(&b"SINFDATA"[..]));
        assert!(opts.get("PackageType").is_none());
        assert_eq!(std::fs::read(&ipa).unwrap(), before);
        let _ = std::fs::remove_dir_all(&d);
    }

    #[test]
    fn missing_sinf_and_metadata_are_reported_not_invented() {
        let d = tmp("bare");
        let ipa = make_ipa(&d, false, false);
        let pkg = inspect_store_ipa(&ipa).unwrap();
        assert!(pkg.sinf.is_none() && pkg.itunes_metadata.is_none());
        let opts = client_options(&pkg);
        assert!(opts.get("ApplicationSINF").is_none() && opts.get("iTunesMetadata").is_none());
        let _ = std::fs::remove_dir_all(&d);
    }

    #[test]
    fn rejects_relative_and_non_ipa_paths() {
        assert!(validate_store_ipa("Store.ipa").is_err());
        let d = tmp("bad");
        let other = d.join("x.zip");
        std::fs::write(&other, b"x").unwrap();
        assert!(validate_store_ipa(other.to_str().unwrap()).is_err());
        let _ = std::fs::remove_dir_all(&d);
    }
}
