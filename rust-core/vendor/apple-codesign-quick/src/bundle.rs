use crate::error::{CodeSignError, Result};
use crate::file_bytes::read_file_bytes;
use crate::macho::{DEFAULT_CMS_BLOB_RESERVATION, MachOSigningConfig, sign_macho_file};
use crate::signature::CmsSigner;
use plist::{Dictionary, Value};
use rayon::prelude::*;
use sha1::Digest as _;
use std::collections::BTreeMap;
use std::fs;
use std::path::{Path, PathBuf};

const FAIRPLAY_DIR: &str = "SC_Info";
const CODE_SIGNATURE_DIR: &str = "_CodeSignature";
const CODE_RESOURCES_FILE: &str = "CodeResources";

pub struct BundleSigningSettings<'a> {
    pub team_id: String,
    pub main_entitlements: Dictionary,
    pub entitlements_by_bundle_id: BTreeMap<String, Dictionary>,
    pub cms_signer: Option<&'a dyn CmsSigner>,
    /// Omit existing AND supplied profiles before resource collection, in every bundle.
    pub omit_embedded_mobileprovision: bool,
    pub embedded_mobileprovision: Option<&'a [u8]>,
    pub embedded_mobileprovisions_by_bundle_id: BTreeMap<String, &'a [u8]>,
    pub cms_blob_reservation: usize,
}

impl<'a> BundleSigningSettings<'a> {
    pub fn new(
        team_id: impl Into<String>,
        main_entitlements: Dictionary,
        cms_signer: Option<&'a dyn CmsSigner>,
    ) -> Self {
        Self {
            team_id: team_id.into(),
            main_entitlements,
            entitlements_by_bundle_id: BTreeMap::new(),
            cms_signer,
            omit_embedded_mobileprovision: false,
            embedded_mobileprovision: None,
            embedded_mobileprovisions_by_bundle_id: BTreeMap::new(),
            cms_blob_reservation: DEFAULT_CMS_BLOB_RESERVATION,
        }
    }
}

#[derive(Debug)]
pub struct Bundle {
    path: PathBuf,
    app_info: Dictionary,
}

impl Bundle {
    pub fn open(path: impl Into<PathBuf>) -> Result<Self> {
        let path = path.into();
        let info_path = path.join("Info.plist");
        if !info_path.exists() {
            return Err(CodeSignError::MissingInfoPlist(info_path));
        }

        let file =
            fs::File::open(&info_path).map_err(|source| CodeSignError::io(&info_path, source))?;
        let app_info = match Value::from_reader(file)? {
            Value::Dictionary(dict) => dict,
            _ => {
                return Err(CodeSignError::macho(
                    &info_path,
                    "Info.plist is not a dictionary",
                ));
            }
        };

        Ok(Self { path, app_info })
    }

    pub fn path(&self) -> &Path {
        &self.path
    }

    pub fn bundle_identifier(&self) -> Result<&str> {
        self.info_string("CFBundleIdentifier")
    }

    pub fn executable_name(&self) -> Result<&str> {
        self.info_string("CFBundleExecutable")
    }

    pub fn sign(&mut self, settings: &BundleSigningSettings<'_>) -> Result<CodeResourcesMaps> {
        self.sign_inner(settings, true)
    }

    fn sign_inner(
        &mut self,
        settings: &BundleSigningSettings<'_>,
        is_root: bool,
    ) -> Result<CodeResourcesMaps> {
        remove_fairplay_dir(&self.path)?;

        let bundle_id = self.bundle_identifier()?.to_string();
        let executable = self.executable_name()?.to_string();
        let sub_bundles = self.sub_bundles()?;
        let sub_bundles_for_hashing = sub_bundles.clone();

        let code_signature_dir = self.path.join(CODE_SIGNATURE_DIR);
        fs::create_dir_all(&code_signature_dir)
            .map_err(|source| CodeSignError::io(&code_signature_dir, source))?;

        let code_resources_path = code_signature_dir.join(CODE_RESOURCES_FILE);
        if code_resources_path.exists() {
            fs::remove_file(&code_resources_path)
                .map_err(|source| CodeSignError::io(&code_resources_path, source))?;
        }

        let info_data = encode_binary_plist(&self.app_info)?;
        let info_path = self.path.join("Info.plist");
        fs::write(&info_path, &info_data)
            .map_err(|source| CodeSignError::io(&info_path, source))?;
        let mobileprovision = settings
            .embedded_mobileprovisions_by_bundle_id
            .get(&bundle_id)
            .copied()
            .or_else(|| {
                if is_root {
                    settings.embedded_mobileprovision
                } else {
                    None
                }
            });
        let profile_path = self.path.join("embedded.mobileprovision");
        if settings.omit_embedded_mobileprovision {
            // Never mutate this after signing: both this envelope and its parent
            // must seal the actual final resource set. remove_file unlinks symlinks.
            match fs::remove_file(&profile_path) {
                Ok(()) => {},
                Err(source) if source.kind() == std::io::ErrorKind::NotFound => {},
                Err(source) => return Err(CodeSignError::io(&profile_path, source)),
            }
        } else if let Some(mobileprovision) = mobileprovision {
            fs::write(&profile_path, mobileprovision)
                .map_err(|source| CodeSignError::io(&profile_path, source))?;
        }

        let (sub_results, bundle_files) = rayon::join(
            || sign_sub_bundles(&self.path, sub_bundles, settings),
            || collect_own_bundle_files(&self.path, &executable, &sub_bundles_for_hashing),
        );
        let sub_results = sub_results?;
        let bundle_files = bundle_files?;
        sign_libraries(&bundle_files.libraries, settings)?;
        let resource_hashes = hash_resource_files(&self.path, &bundle_files.resource_files)?;

        let mut maps = CodeResourcesMaps::default();

        for sub in &sub_results {
            merge_sub_bundle_resources(&mut maps, &self.path, sub)?;
        }

        for hash in resource_hashes {
            maps.insert_hash(hash);
        }

        let code_resources = encode_code_resources(&maps)?;
        fs::write(&code_resources_path, &code_resources)
            .map_err(|source| CodeSignError::io(&code_resources_path, source))?;

        let empty_entitlements = Dictionary::new();
        let bundle_entitlements = settings
            .entitlements_by_bundle_id
            .get(&bundle_id)
            .or_else(|| is_root.then_some(&settings.main_entitlements))
            .unwrap_or(&empty_entitlements);

        let mut config = MachOSigningConfig::new(
            &bundle_id,
            &settings.team_id,
            bundle_entitlements,
            settings.cms_signer,
        );
        config.cms_blob_reservation = settings.cms_blob_reservation;
        config.info_plist = Some(&info_data);
        config.code_resources = Some(&code_resources);
        sign_macho_file(&self.path.join(&executable), &config)?;

        Ok(maps)
    }

    fn info_string(&self, key: &'static str) -> Result<&str> {
        self.app_info
            .get(key)
            .and_then(Value::as_string)
            .ok_or(CodeSignError::MissingInfoString(key))
    }

    fn sub_bundles(&self) -> Result<Vec<PathBuf>> {
        let mut bundles = Vec::new();
        for folder in ["Frameworks", "PlugIns", "Watch", "AppClips"] {
            let dir = self.path.join(folder);
            if !dir.exists() {
                continue;
            }

            for entry in fs::read_dir(&dir).map_err(|source| CodeSignError::io(&dir, source))? {
                let entry = entry.map_err(|source| CodeSignError::io(&dir, source))?;
                let path = entry.path();
                if entry
                    .file_type()
                    .map_err(|source| CodeSignError::io(&path, source))?
                    .is_dir()
                    && path.join("Info.plist").exists()
                {
                    bundles.push(path);
                }
            }
        }
        bundles.sort();
        Ok(bundles)
    }
}

#[derive(Debug)]
struct SubBundleResult {
    path: PathBuf,
    relative_root: String,
    executable: String,
    resources: CodeResourcesMaps,
}

#[derive(Clone, Debug)]
struct FileHash {
    relative_path: String,
    sha1: [u8; 20],
    sha256: [u8; 32],
    optional: bool,
}

#[derive(Debug)]
struct BundleFiles {
    resource_files: Vec<PathBuf>,
    libraries: Vec<PathBuf>,
}

fn merge_sub_bundle_resources(
    maps: &mut CodeResourcesMaps,
    parent_path: &Path,
    sub: &SubBundleResult,
) -> Result<()> {
    maps.merge_rerooted(&sub.relative_root, &sub.resources);
    maps.insert_hash(hash_bundle_file(
        parent_path,
        &sub.path.join(&sub.executable),
    )?);
    maps.insert_hash(hash_bundle_file(
        parent_path,
        &sub.path.join(CODE_SIGNATURE_DIR).join(CODE_RESOURCES_FILE),
    )?);
    Ok(())
}

#[derive(Clone, Debug, Default)]
pub struct CodeResourcesMaps {
    pub files: Dictionary,
    pub files2: Dictionary,
    hashes: Vec<FileHash>,
}

impl CodeResourcesMaps {
    fn insert_hash(&mut self, hash: FileHash) {
        self.hashes.push(hash.clone());
        let sha1 = hash.sha1.to_vec();
        if !omit_from_files(&hash.relative_path) {
            if hash.optional {
                let mut file = Dictionary::new();
                file.insert("hash".to_string(), Value::Data(sha1.clone()));
                file.insert("optional".to_string(), Value::Boolean(true));
                self.files
                    .insert(hash.relative_path.clone(), Value::Dictionary(file));
            } else {
                self.files
                    .insert(hash.relative_path.clone(), Value::Data(sha1.clone()));
            }
        }

        if !omit_from_files2(&hash.relative_path) {
            let mut file2 = Dictionary::new();
            file2.insert("hash".to_string(), Value::Data(sha1));
            file2.insert("hash2".to_string(), Value::Data(hash.sha256.to_vec()));
            if hash.optional {
                file2.insert("optional".to_string(), Value::Boolean(true));
            }
            self.files2
                .insert(hash.relative_path, Value::Dictionary(file2));
        }
    }

    fn merge_rerooted(&mut self, root: &str, other: &Self) {
        for hash in &other.hashes {
            let mut hash = hash.clone();
            hash.relative_path = join_relative(root, &hash.relative_path);
            self.insert_hash(hash);
        }
    }
}

fn omit_from_files(relative_path: &str) -> bool {
    relative_path.ends_with(".lproj/locversion.plist")
}

fn omit_from_files2(relative_path: &str) -> bool {
    omit_from_files(relative_path)
        || relative_path == "Info.plist"
        || relative_path == "PkgInfo"
        || relative_path == ".DS_Store"
        || relative_path.ends_with("/.DS_Store")
}

pub fn sign_bundle(path: impl Into<PathBuf>, settings: &BundleSigningSettings<'_>) -> Result<()> {
    let mut bundle = Bundle::open(path)?;
    bundle.sign(settings)?;
    Ok(())
}

fn sign_sub_bundles(
    root_path: &Path,
    sub_bundles: Vec<PathBuf>,
    settings: &BundleSigningSettings<'_>,
) -> Result<Vec<SubBundleResult>> {
    sub_bundles
        .into_par_iter()
        .map(|path| {
            let mut bundle = Bundle::open(&path)?;
            let result = bundle.sign_inner(settings, false)?;
            let relative_root = relative_path_string(root_path, &path)?;
            let executable = bundle.executable_name()?.to_string();
            Ok(SubBundleResult {
                path,
                relative_root,
                executable,
                resources: result,
            })
        })
        .collect()
}

fn collect_own_bundle_files(
    bundle_path: &Path,
    executable: &str,
    sub_bundles: &[PathBuf],
) -> Result<BundleFiles> {
    let mut resource_files = Vec::new();
    let mut libraries = Vec::new();

    walk_files_pruned(
        bundle_path,
        &mut |dir| !sub_bundles.iter().any(|sub_bundle| sub_bundle == dir),
        &mut |path| {
            let relative = relative_path_string(bundle_path, path)?;
            if path.extension().and_then(|value| value.to_str()) == Some("dylib") {
                libraries.push(path.to_path_buf());
            }
            if should_hash_resource(&relative, executable) {
                resource_files.push(path.to_path_buf());
            }
            Ok(())
        },
    )?;

    resource_files.sort();
    libraries.sort();

    Ok(BundleFiles {
        resource_files,
        libraries,
    })
}

fn is_macho_magic(bytes: &[u8]) -> bool {
    matches!(bytes.get(..4),
        Some([0xcf,0xfa,0xed,0xfe] | [0xfe,0xed,0xfa,0xcf]
        | [0xce,0xfa,0xed,0xfe] | [0xfe,0xed,0xfa,0xce]
        | [0xca,0xfe,0xba,0xbe] | [0xbe,0xba,0xfe,0xca]
        | [0xca,0xfe,0xba,0xbf] | [0xbf,0xba,0xfe,0xca]))
}
#[cfg(test)]
mod embedded_resource_tests {
    use super::*;
    #[test]
    fn non_macho_library_is_a_resource_not_a_signing_failure() {
        let dir = std::env::temp_dir().join(format!("mirsa-non-macho-{}", std::process::id()));
        fs::create_dir_all(&dir).unwrap();
        let path = dir.join("metadata.dylib");
        fs::write(&path, b"not a Mach-O resource").unwrap();
        let settings = BundleSigningSettings::new("TEAM", Dictionary::new(), None);
        sign_libraries(&[path.clone()], &settings).unwrap();
        assert_eq!(fs::read(&path).unwrap(), b"not a Mach-O resource");
        fs::remove_dir_all(&dir).unwrap();
    }
    #[test]
    fn malformed_macho_is_not_silently_skipped() {
        assert!(is_macho_magic(&[0xcf,0xfa,0xed,0xfe]));
        assert!(!is_macho_magic(b""));
        assert!(!is_macho_magic(b"plist resource"));
    }
}
fn sign_libraries(libraries: &[PathBuf], settings: &BundleSigningSettings<'_>) -> Result<()> {
    libraries
        .par_iter()
        .map(|path| {
            // A resource may end in .dylib without being executable code. Keep
            // it hashed as a resource, but never feed it to the Mach-O signer.
            let bytes = read_file_bytes(path)?;
            if !is_macho_magic(bytes.as_slice()) { return Ok(()); }
            drop(bytes);
            let identifier = path
                .file_name()
                .and_then(|value| value.to_str())
                .ok_or_else(|| CodeSignError::InvalidBundlePath(path.clone()))?;
            let entitlements = Dictionary::new();
            let mut config = MachOSigningConfig::new(
                identifier,
                &settings.team_id,
                &entitlements,
                settings.cms_signer,
            );
            config.cms_blob_reservation = settings.cms_blob_reservation;
            // Standalone dylibs have no process entitlements. Leave the
            // entitlement slot absent, as in the container library signer.
            config.omit_entitlements = true;
            sign_macho_file(path, &config)
        })
        .collect::<Result<Vec<_>>>()?;
    Ok(())
}

fn hash_resource_files(bundle_path: &Path, resource_files: &[PathBuf]) -> Result<Vec<FileHash>> {
    resource_files
        .par_iter()
        .map(|path| hash_bundle_file(bundle_path, path))
        .collect()
}

fn remove_fairplay_dir(bundle_path: &Path) -> Result<()> {
    let fairplay_path = bundle_path.join(FAIRPLAY_DIR);
    if fairplay_path.exists() {
        fs::remove_dir_all(&fairplay_path)
            .map_err(|source| CodeSignError::io(&fairplay_path, source))?;
    }
    Ok(())
}

fn walk_files_pruned(
    root: &Path,
    should_descend: &mut impl FnMut(&Path) -> bool,
    visitor: &mut impl FnMut(&Path) -> Result<()>,
) -> Result<()> {
    let mut stack = vec![root.to_path_buf()];
    while let Some(dir) = stack.pop() {
        for entry in fs::read_dir(&dir).map_err(|source| CodeSignError::io(&dir, source))? {
            let entry = entry.map_err(|source| CodeSignError::io(&dir, source))?;
            let path = entry.path();
            let file_type = entry
                .file_type()
                .map_err(|source| CodeSignError::io(&path, source))?;
            if file_type.is_dir() && should_descend(&path) {
                stack.push(path);
            } else if file_type.is_file() {
                visitor(&path)?;
            }
        }
    }
    Ok(())
}

fn should_hash_resource(relative: &str, executable: &str) -> bool {
    if relative == executable || relative.starts_with(FAIRPLAY_DIR) {
        return false;
    }

    for nested_root in ["Frameworks/", "PlugIns/", "Watch/", "AppClips/"] {
        if let Some(rest) = relative.strip_prefix(nested_root)
            && rest.contains('/')
        {
            return false;
        }
    }

    true
}

fn hash_bundle_file(bundle_path: &Path, path: &Path) -> Result<FileHash> {
    let relative_path = relative_path_string(bundle_path, path)?;
    let data = read_file_bytes(path)?;
    let (sha1, sha256) = hash_file_data(data.as_slice());
    Ok(FileHash {
        optional: relative_path.contains(".lproj"),
        relative_path,
        sha1,
        sha256,
    })
}

fn hash_file_data(data: &[u8]) -> ([u8; 20], [u8; 32]) {
    if data.len() >= 1024 * 1024 {
        rayon::join(
            || sha1::Sha1::digest(data).into(),
            || sha2::Sha256::digest(data).into(),
        )
    } else {
        (
            sha1::Sha1::digest(data).into(),
            sha2::Sha256::digest(data).into(),
        )
    }
}

fn encode_code_resources(maps: &CodeResourcesMaps) -> Result<Vec<u8>> {
    let mut code_resources = Dictionary::new();
    code_resources.insert("files".to_string(), Value::Dictionary(maps.files.clone()));
    code_resources.insert("files2".to_string(), Value::Dictionary(maps.files2.clone()));
    code_resources.insert("rules".to_string(), rules());
    code_resources.insert("rules2".to_string(), rules2());

    let mut data = Vec::new();
    plist::to_writer_xml(&mut data, &Value::Dictionary(code_resources))?;
    Ok(data)
}

fn rules() -> Value {
    let mut rules = Dictionary::new();
    rules.insert("^.*".to_string(), Value::Boolean(true));
    rules.insert(
        "^.*\\.lproj/".to_string(),
        weighted_rule([("optional", Value::Boolean(true))], 1000.0),
    );
    rules.insert(
        "^.*\\.lproj/locversion.plist$".to_string(),
        weighted_rule([("omit", Value::Boolean(true))], 1100.0),
    );
    rules.insert("^Base\\.lproj/".to_string(), weight_only_rule(1010.0));
    rules.insert("^version.plist$".to_string(), Value::Boolean(true));
    Value::Dictionary(rules)
}

fn rules2() -> Value {
    let mut rules = Dictionary::new();
    rules.insert(".*\\.dSYM($|/)".to_string(), weight_only_rule(11.0));
    rules.insert(
        "^(.*/)?\\.DS_Store$".to_string(),
        weighted_rule([("omit", Value::Boolean(true))], 2000.0),
    );
    rules.insert("^.*".to_string(), Value::Boolean(true));
    rules.insert(
        "^.*\\.lproj/".to_string(),
        weighted_rule([("optional", Value::Boolean(true))], 1000.0),
    );
    rules.insert(
        "^.*\\.lproj/locversion.plist$".to_string(),
        weighted_rule([("omit", Value::Boolean(true))], 1100.0),
    );
    rules.insert("^Base\\.lproj/".to_string(), weight_only_rule(1010.0));
    rules.insert(
        "^Info\\.plist$".to_string(),
        weighted_rule([("omit", Value::Boolean(true))], 20.0),
    );
    rules.insert(
        "^PkgInfo$".to_string(),
        weighted_rule([("omit", Value::Boolean(true))], 20.0),
    );
    rules.insert(
        "^embedded\\.provisionprofile$".to_string(),
        weight_only_rule(20.0),
    );
    rules.insert("^version\\.plist$".to_string(), weight_only_rule(20.0));
    Value::Dictionary(rules)
}

fn weighted_rule<const N: usize>(entries: [(&str, Value); N], weight: f64) -> Value {
    let mut dict = Dictionary::new();
    for (key, value) in entries {
        dict.insert(key.to_string(), value);
    }
    dict.insert("weight".to_string(), Value::Real(weight));
    Value::Dictionary(dict)
}

fn weight_only_rule(weight: f64) -> Value {
    weighted_rule::<0>([], weight)
}

fn encode_binary_plist(dict: &Dictionary) -> Result<Vec<u8>> {
    let mut data = Vec::new();
    plist::to_writer_binary(&mut data, &Value::Dictionary(dict.clone()))?;
    Ok(data)
}

fn relative_path_string(root: &Path, path: &Path) -> Result<String> {
    let relative = path
        .strip_prefix(root)
        .map_err(|_| CodeSignError::InvalidBundlePath(path.to_path_buf()))?;
    path_to_forward_slashes(relative)
}

fn path_to_forward_slashes(path: &Path) -> Result<String> {
    let mut parts = Vec::new();
    for component in path.components() {
        parts.push(
            component
                .as_os_str()
                .to_str()
                .ok_or_else(|| CodeSignError::InvalidBundlePath(path.to_path_buf()))?,
        );
    }
    Ok(parts.join("/"))
}

fn join_relative(root: &str, child: &str) -> String {
    if root.is_empty() {
        child.to_string()
    } else if child.is_empty() {
        root.to_string()
    } else {
        format!("{root}/{child}")
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    struct Fixture(std::path::PathBuf);
    impl Fixture {
        fn new() -> Self {
            let p = std::env::temp_dir().join(format!("mirsa-profile-{}-{}", std::process::id(),
                std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).unwrap().as_nanos()));
            fs::create_dir_all(&p).unwrap(); Self(p)
        }
        fn bundle(&self, relative: &str, id: &str) -> PathBuf {
            let p = self.0.join(relative); fs::create_dir_all(&p).unwrap();
            let mut info = Dictionary::new();
            info.insert("CFBundleIdentifier".into(), id.into());
            info.insert("CFBundleExecutable".into(), "Main".into());
            fs::write(p.join("Info.plist"), encode_binary_plist(&info).unwrap()).unwrap();
            // Minimal real arm64 Mach-O, signed by the production ad-hoc signer.
            let mut d = vec![0u8;512];
            fn u32w(d: &mut [u8], a: usize, v: u32) { d[a..a+4].copy_from_slice(&v.to_le_bytes()); }
            fn u64w(d: &mut [u8], a: usize, v: u64) { d[a..a+8].copy_from_slice(&v.to_le_bytes()); }
            for (a,v) in [(0,0xfeedfacf),(4,0x100000c),(12,2),(16,3),(20,160)] {u32w(&mut d,a,v);}
            for (a,name,off,size) in [(32,"__TEXT",0,512),(104,"__LINKEDIT",512,0)] {
                u32w(&mut d,a,0x19);u32w(&mut d,a+4,72);
                d[a+8..a+8+name.len()].copy_from_slice(name.as_bytes());
                u64w(&mut d,a+32,4096);u64w(&mut d,a+40,off);u64w(&mut d,a+48,size);
            }
            for (a,v) in [(176,0x1d),(180,16),(184,512)] {u32w(&mut d,a,v);}
            fs::write(p.join("Main"),d).unwrap();p
        }
    }
    impl Drop for Fixture {fn drop(&mut self){let _=fs::remove_dir_all(&self.0);}}

    fn assert_sealed_profile(bundle: &Path, expected: Option<&[u8]>) {
        let resources = Value::from_file(bundle.join("_CodeSignature/CodeResources")).unwrap();
        let files2 = resources.as_dictionary().unwrap()["files2"].as_dictionary().unwrap();
        let path = bundle.join("embedded.mobileprovision");
        if let Some(expected) = expected {
            assert_eq!(fs::read(path).unwrap(),expected);
            let entry=files2["embedded.mobileprovision"].as_dictionary().unwrap();
            assert_eq!(entry["hash2"].as_data().unwrap(),sha2::Sha256::digest(expected).as_slice());
        } else {
            assert!(!path.exists());assert!(!files2.contains_key("embedded.mobileprovision"));
        }
    }

    #[test]
    fn embedded_profile_default_replaces_old_and_seals_final_bytes() {
        let f=Fixture::new();let app=f.bundle("App.app","test.app");
        fs::write(app.join("embedded.mobileprovision"),b"old").unwrap();
        let mut settings=BundleSigningSettings::new("TEAM",Dictionary::new(),None);
        assert!(!settings.omit_embedded_mobileprovision);
        settings.embedded_mobileprovision=Some(b"selected");
        sign_bundle(&app,&settings).unwrap();assert_sealed_profile(&app,Some(b"selected"));
    }

    #[test]
    fn embedded_profile_omission_dominates_root_and_nested_maps_before_seal() {
        let f=Fixture::new();let app=f.bundle("App.app","test.app");
        let child=f.bundle("App.app/PlugIns/Widget.appex","test.widget");
        for p in [&app,&child] {fs::write(p.join("embedded.mobileprovision"),b"old").unwrap();}
        let mut settings=BundleSigningSettings::new("TEAM",Dictionary::new(),None);
        settings.omit_embedded_mobileprovision=true;
        settings.embedded_mobileprovision=Some(b"selected");
        settings.embedded_mobileprovisions_by_bundle_id.insert("test.widget".into(),b"nested");
        sign_bundle(&app,&settings).unwrap();
        assert_sealed_profile(&app,None);assert_sealed_profile(&child,None);
        let resources=Value::from_file(app.join("_CodeSignature/CodeResources")).unwrap();
        let files2=resources.as_dictionary().unwrap()["files2"].as_dictionary().unwrap();
        assert!(!files2.keys().any(|k|k.ends_with("embedded.mobileprovision")));
        let sealed=files2["PlugIns/Widget.appex/_CodeSignature/CodeResources"].as_dictionary().unwrap();
        let bytes=fs::read(child.join("_CodeSignature/CodeResources")).unwrap();
        assert_eq!(sealed["hash2"].as_data().unwrap(),sha2::Sha256::digest(&bytes).as_slice());
        // Re-sign is idempotent with absent profiles; no post-sign removal needed.
        sign_bundle(&app,&settings).unwrap();assert_sealed_profile(&app,None);
    }

    #[test]
    fn omission_preserves_watch_clip_and_framework_final_envelopes() {
        let f=Fixture::new();let app=f.bundle("App.app","test.app");
        let watch=f.bundle("App.app/Watch/Watch.app","test.watch");
        let clip=f.bundle("App.app/AppClips/Clip.app","test.clip");
        let framework=f.bundle("App.app/Frameworks/Helper.framework","test.framework");
        let mut settings=BundleSigningSettings::new("TEAM",Dictionary::new(),None);
        settings.omit_embedded_mobileprovision=true;
        settings.embedded_mobileprovision=Some(b"selected");
        // Match personal_sign's explicit deepest-first inventory, including
        // Watch and AppClips (not discovered recursively by this library).
        for bundle in [&watch,&clip,&framework,&app] {
            fs::write(bundle.join("embedded.mobileprovision"),b"old").unwrap();
        }
        for bundle in [&watch,&clip,&framework,&app] {
            sign_bundle(bundle,&settings).unwrap();
        }
        for bundle in [&watch,&clip,&framework,&app] {
            assert_sealed_profile(bundle,None);
        }
        let resources=Value::from_file(app.join("_CodeSignature/CodeResources")).unwrap();
        let files2=resources.as_dictionary().unwrap()["files2"].as_dictionary().unwrap();
        assert!(!files2.keys().any(|key|key.ends_with("embedded.mobileprovision")));
        for relative in ["Watch/Watch.app/_CodeSignature/CodeResources","AppClips/Clip.app/_CodeSignature/CodeResources"] {
            let sealed=files2[relative].as_dictionary().unwrap();
            let bytes=fs::read(app.join(relative)).unwrap();
            assert_eq!(sealed["hash2"].as_data().unwrap(),sha2::Sha256::digest(&bytes).as_slice());
        }
    }

    #[test]
    fn embedded_profile_absent_no_override_stays_absent() {
        let f=Fixture::new();let app=f.bundle("App.app","test.app");
        let settings=BundleSigningSettings::new("TEAM",Dictionary::new(),None);
        sign_bundle(&app,&settings).unwrap();assert_sealed_profile(&app,None);
    }

    #[test]
    fn embedded_profile_omission_rejects_directory_without_deleting_it() {
        let f=Fixture::new();let app=f.bundle("App.app","test.app");
        let dir=app.join("embedded.mobileprovision");fs::create_dir(&dir).unwrap();
        fs::write(dir.join("keep"),b"keep").unwrap();
        let mut settings=BundleSigningSettings::new("TEAM",Dictionary::new(),None);
        settings.omit_embedded_mobileprovision=true;
        assert!(sign_bundle(&app,&settings).is_err());assert!(dir.join("keep").exists());
    }

    #[cfg(unix)]
    #[test]
    fn embedded_profile_omission_unlinks_symlink_not_external_target() {
        let f=Fixture::new();let app=f.bundle("App.app","test.app");
        let target=f.0.join("outside");fs::write(&target,b"untouched").unwrap();
        std::os::unix::fs::symlink(&target,app.join("embedded.mobileprovision")).unwrap();
        let mut settings=BundleSigningSettings::new("TEAM",Dictionary::new(),None);
        settings.omit_embedded_mobileprovision=true;
        sign_bundle(&app,&settings).unwrap();assert_sealed_profile(&app,None);
        assert_eq!(fs::read(target).unwrap(),b"untouched");
    }

    fn test_hash(relative_path: &str) -> FileHash {
        FileHash {
            relative_path: relative_path.to_string(),
            sha1: [1; 20],
            sha256: [2; 32],
            optional: false,
        }
    }

    #[test]
    fn files2_omits_only_the_current_bundles_info_and_pkginfo() {
        let mut child = CodeResourcesMaps::default();
        child.insert_hash(test_hash("Info.plist"));
        child.insert_hash(test_hash("PkgInfo"));

        assert!(child.files.contains_key("Info.plist"));
        assert!(!child.files2.contains_key("Info.plist"));
        assert!(!child.files2.contains_key("PkgInfo"));

        let mut parent = CodeResourcesMaps::default();
        parent.merge_rerooted("PlugIns/Widget.appex", &child);

        assert!(
            parent
                .files2
                .contains_key("PlugIns/Widget.appex/Info.plist")
        );
        assert!(parent.files2.contains_key("PlugIns/Widget.appex/PkgInfo"));
    }

    #[test]
    fn direct_dylibs_are_hashed_from_their_final_signed_contents() {
        let test_root = std::env::temp_dir().join(format!(
            "apple-codesign-dylib-resources-{}-{}",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        let dylib = test_root.join("Frameworks/Patch.dylib");
        fs::create_dir_all(dylib.parent().unwrap()).unwrap();
        fs::write(&dylib, b"unsigned").unwrap();

        let bundle_files = collect_own_bundle_files(&test_root, "Main", &[]).unwrap();
        assert_eq!(bundle_files.libraries, vec![dylib.clone()]);
        assert_eq!(bundle_files.resource_files, vec![dylib.clone()]);

        fs::write(&dylib, b"signed").unwrap();
        let hashes = hash_resource_files(&test_root, &bundle_files.resource_files).unwrap();
        let expected_sha256: [u8; 32] = sha2::Sha256::digest(b"signed").into();
        assert_eq!(hashes[0].sha256, expected_sha256);

        fs::remove_dir_all(test_root).unwrap();
    }

    #[test]
    fn parent_seals_nested_bundle_code_resources() {
        let test_root = std::env::temp_dir().join(format!(
            "apple-codesign-nested-resources-{}-{}",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        let child_path = test_root.join("Frameworks/Example.framework");
        let signature_path = child_path.join(CODE_SIGNATURE_DIR);
        fs::create_dir_all(&signature_path).unwrap();
        fs::write(child_path.join("Example"), b"executable").unwrap();
        fs::write(signature_path.join(CODE_RESOURCES_FILE), b"resources").unwrap();

        let mut child_resources = CodeResourcesMaps::default();
        child_resources.insert_hash(test_hash("Resource.txt"));
        let child = SubBundleResult {
            path: child_path,
            relative_root: "Frameworks/Example.framework".to_string(),
            executable: "Example".to_string(),
            resources: child_resources,
        };
        let mut parent = CodeResourcesMaps::default();

        merge_sub_bundle_resources(&mut parent, &test_root, &child).unwrap();

        assert!(
            parent
                .files2
                .contains_key("Frameworks/Example.framework/Resource.txt")
        );
        assert!(
            parent
                .files2
                .contains_key("Frameworks/Example.framework/Example")
        );
        assert!(
            parent
                .files2
                .contains_key("Frameworks/Example.framework/_CodeSignature/CodeResources")
        );

        fs::remove_dir_all(test_root).unwrap();
    }
}
