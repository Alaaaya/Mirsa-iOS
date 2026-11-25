//! Package Mirsa's clean-room compatibility shim, never a user-supplied engine.
//! C hooks rebind imported pointers only; this does not provide inline hooking.
use super::*;
const BINARY: &[u8] = include_bytes!(concat!(env!("CARGO_MANIFEST_DIR"), "/../hook-engine/dist/CydiaSubstrate.framework/CydiaSubstrate"));
const INFO: &[u8] = include_bytes!(concat!(env!("CARGO_MANIFEST_DIR"), "/../hook-engine/dist/CydiaSubstrate.framework/Info.plist"));
const LICENSE: &[u8] = include_bytes!(concat!(env!("CARGO_MANIFEST_DIR"), "/../hook-engine/LICENSE"));
pub(super) const DEPENDENCY: &str = "@rpath/CydiaSubstrate.framework/CydiaSubstrate";
const FRAMEWORK: &str = "CydiaSubstrate.framework";

pub(super) fn alias(dep: &str) -> bool {
    let base = dep.rsplit('/').next().unwrap_or("").to_ascii_lowercase();
    matches!(base.as_str(), "cydiasubstrate" | "substrate" | "libsubstrate.dylib" |
        "ellekit" | "libellekit.dylib" | "libhooker" | "libhooker.dylib" |
        "substitute" | "libsubstitute.dylib")
}
fn validate(binary: &[u8], info: &[u8]) -> Result<()> {
    if binary.is_empty() || info.is_empty() { return Err("Embedded Mirsa hook engine is unavailable".into()); }
    let m = macho(binary.to_vec(), true)?;
    // A host/simulator build must never enter an edited device IPA.
    if u32at(binary, 0)? != 0xfeedfacf || !m.commands.iter().any(|c|
        (c.kind == 0x32 && c.data.len() >= 24 && u32at(&c.data, 8) == Ok(2)) ||
        (c.kind == 0x25 && c.data.len() >= 16)) {
        return Err("Embedded Mirsa hook engine must target ARM64 iOS devices".into());
    }
    if m.commands.iter().any(|c| c.kind != 0xd && c.name.as_deref().is_some_and(|s| !system_dependency(s))) {
        return Err("Embedded Mirsa hook engine has external dependencies".into());
    }
    let p = plist::Value::from_reader(Cursor::new(info)).map_err(err)?;
    let d = p.as_dictionary().ok_or("Invalid hook engine Info.plist")?;
    if d.get("CFBundleExecutable").and_then(|v| v.as_string()) != Some("CydiaSubstrate") ||
        d.get("CFBundlePackageType").and_then(|v| v.as_string()) != Some("FMWK") {
        return Err("Invalid hook engine framework metadata".into());
    }
    Ok(())
}
// nlist_64 is bounded by macho()'s LC_SYMTAB checks. Use dependency
// ordinals, never a blanket MS/ObjC namespace blacklist.
fn symbols(m: &Mach) -> Result<Vec<(String,u8,u16)>> {
    let table=m.commands.iter().find(|c|c.kind==0x2).ok_or("Cannot verify hook engine imports: missing symbol table")?;
    let start=u32at(&table.data,8)? as usize;let count=u32at(&table.data,12)? as usize;
    let strings=u32at(&table.data,16)? as usize;let size=u32at(&table.data,20)? as usize;
    if count>1_000_000 {return Err("Hook symbol table exceeds safe limit".into())}
    let names=m.data.get(strings..strings.checked_add(size).ok_or("Symbol string overflow")?).ok_or("Invalid symbol strings")?;
    let mut out=Vec::new();
    for index in 0..count {
        let at=start+index*16;let name=u32at(&m.data,at)? as usize;
        let kind=m.data[at+4];if kind&0xe0!=0 {continue}
        let raw=names.get(name..).ok_or("Invalid hook symbol name offset")?;
        let end=raw.iter().take(4097).position(|b|*b==0).ok_or("Invalid hook symbol name")?;
        let desc=u16::from_le_bytes(m.data[at+6..at+8].try_into().map_err(err)?);
        out.push((std::str::from_utf8(&raw[..end]).map_err(err)?.into(),kind,desc));
    }
    Ok(out)
}
fn known_hook_namespace(symbol: &str) -> bool {
    let s=symbol.strip_prefix('_').unwrap_or(symbol);
    ["MSHook", "MSFindSymbol", "MSGetImage", "MSImageAddress", "MSCloseImage", "LH", "LBHook", "EK", "substitute_", "MirsaHook"].iter().any(|p|s.starts_with(p))
}
pub(super) fn validate_imports(m: &Mach) -> Result<()> {
    let loads:Vec<_>=m.commands.iter().filter(|c|matches!(c.kind,0xc|0x80000018|0x8000001f|0x80000023|0x20)).collect();
    let ordinals:HashSet<_>=loads.iter().enumerate().filter(|(_,c)|c.name.as_deref().is_some_and(alias)).map(|(i,_)|i+1).collect();
    if ordinals.is_empty() {return Ok(())}
    let engine=macho(BINARY.to_vec(),true)?;
    let exports:HashSet<_>=symbols(&engine)?.into_iter().filter(|(_,kind,_)|kind&1!=0 && kind&0x10==0 && kind&0xe==0xe).map(|(s,_,_)|s).collect();
    if exports.is_empty() {return Err("Embedded hook engine has no verifiable exports".into())}
    for (symbol,kind,desc) in symbols(m)? {
        if kind&0xe!=0 || kind&1==0 {continue}
        let ordinal=(desc>>8) as usize;
        if (ordinals.contains(&ordinal) || ((ordinal==0 || ordinal>=0xfd) && known_hook_namespace(&symbol))) && !exports.contains(&symbol) {
            return Err(format!("Unsupported hook engine API: {symbol}. Mirsa supports Objective-C replacement and imported-pointer rebinding only."));
        }
    }
    Ok(())
}
fn scope_identifier(scope: &Path) -> String {
    use sha2::{Digest,Sha256};
    let outer = scope.ancestors().filter(|p| p.extension().and_then(|s|s.to_str()) == Some("app")).last().unwrap_or(scope);
    let relative = scope.strip_prefix(outer).unwrap_or(Path::new(""));
    let digest = Sha256::digest(relative.to_string_lossy().as_bytes());
    let suffix:String=digest[..12].iter().map(|v|format!("{v:02x}")).collect();
    format!("com.mirsa.hook.scope{suffix}")
}
/// Exact code identity with only appended signer signature/header-size changes.
/// Never trusts Info.plist markers, filenames, UUIDs or a text-section hash alone.
fn owned_binary(data: &[u8]) -> Result<bool> {
    let original = macho(BINARY.to_vec(),true)?;
    let actual = macho(data.to_vec(),true)?;
    if data.get(..16)!=BINARY.get(..16) || data.get(24..32)!=BINARY.get(24..32) {return Ok(false)}
    let linkedit=|c:&Command| c.kind==0x19 && c.data.get(8..24)==Some(b"__LINKEDIT\0\0\0\0\0\0".as_slice());
    let old=original.commands.iter().find(|c|linkedit(c)).ok_or("Missing embedded hook engine linkedit")?;
    let baseline_signatures:Vec<_>=original.commands.iter().filter(|c|c.kind==0x1d).collect();
    if baseline_signatures.len()>1 {return Err("Invalid embedded hook engine signatures".into())}
    let payload_end=if let Some(c)=baseline_signatures.first(){u32at(&c.data,8)? as usize}else{BINARY.len()};
    if payload_end>BINARY.len() {return Err("Invalid embedded hook signature offset".into())}
    let mut signatures=Vec::new();let mut normalized=Vec::new();
    for c in &actual.commands {
        if c.kind==0x1d {signatures.push(c);continue}
        let mut bytes=c.data.clone();
        if linkedit(c) {
            if bytes.len()!=72 {return Ok(false)}
            let off=u64at(&bytes,40)?;let size=u64at(&bytes,48)?;let vm=u64at(&bytes,32)?;
            if off.checked_add(size)!=Some(data.len() as u64) || vm<size || vm>size.checked_add(16383).ok_or("Linkedit overflow")? {return Ok(false)}
            bytes[32..40].copy_from_slice(&old.data[32..40]);bytes[48..56].copy_from_slice(&old.data[48..56]);
        }
        normalized.push(bytes);
    }
    if signatures.len()>1 || normalized!=original.commands.iter().filter(|c|c.kind!=0x1d).map(|c|c.data.clone()).collect::<Vec<_>>() {return Ok(false)}
    let old_end=32+u32at(BINARY,20)? as usize;let new_end=32+u32at(data,20)? as usize;
    let end=old_end.max(new_end);
    if end>payload_end || end>data.len() || BINARY[old_end..end].iter().any(|b|*b!=0) || data[new_end..end].iter().any(|b|*b!=0) || data.get(end..payload_end)!=Some(&BINARY[end..payload_end]) {return Ok(false)}
    if let Some(c)=signatures.first() {
        if c.data.len()!=16 {return Ok(false)}
        let off=u32at(&c.data,8)? as usize;let size=u32at(&c.data,12)? as usize;
        if off<payload_end || off.checked_add(size)!=Some(data.len()) || size==0 || data[payload_end..off].iter().any(|b|*b!=0) {return Ok(false)}
    } else if data.len()!=payload_end {return Ok(false)}
    Ok(true)
}
pub(super) fn stage(scope: &Path) -> Result<PathBuf> {
    validate(BINARY, INFO)?;
    let frameworks = scope.join("Frameworks");
    for entry in fs::read_dir(&frameworks).map_err(err)? {
        let name = entry.map_err(err)?.file_name();
        if name.to_string_lossy().eq_ignore_ascii_case(FRAMEWORK) && name != FRAMEWORK {
            return Err("Case-colliding hook engine destination".into());
        }
    }
    let dir = frameworks.join(FRAMEWORK);
    if fs::symlink_metadata(&dir).is_ok() {
        tweak_targets::checked_tree(&dir)?;
        if !owned_binary(&fs::read(dir.join("CydiaSubstrate")).map_err(err)?).unwrap_or(false) {
            return Err("Existing CydiaSubstrate.framework conflicts with Mirsa hook engine".into());
        }
        // Signers may serialize metadata differently. Verify code first, then
        // validate only the framework ABI fields, not mutable signing metadata.
        let p=plist::Value::from_file(dir.join("Info.plist")).map_err(err)?;
        let d=p.as_dictionary().ok_or("Invalid existing hook engine metadata")?;
        if d.get("CFBundleExecutable").and_then(|v|v.as_string())!=Some("CydiaSubstrate") || d.get("CFBundlePackageType").and_then(|v|v.as_string())!=Some("FMWK") {
            return Err("Existing hook engine metadata conflicts".into());
        }
    } else {
        fs::create_dir(&dir).map_err(err)?;
        checked_write(Cursor::new(BINARY), &dir.join("CydiaSubstrate"), BINARY.len() as u64, 0o755)?;
    }
    let mut info=plist::Value::from_reader(Cursor::new(INFO)).map_err(err)?;
    info.as_dictionary_mut().ok_or("Invalid hook engine Info.plist")?.insert("CFBundleIdentifier".into(),plist::Value::String(scope_identifier(scope)));
    info.to_file_xml(dir.join("Info.plist")).map_err(err)?;
    fs::write(dir.join("LICENSE"),LICENSE).map_err(err)?;
    fs::canonicalize(dir.join("CydiaSubstrate")).map_err(err)
}
/// Each importing image owns a loader-relative runpath, including nested frameworks.
pub(super) fn runpath(from: &Path, scope: &Path) -> Result<Vec<u8>> {
    let path = relative_loader(from, &scope.join("Frameworks").join("placeholder"));
    let path = path.strip_suffix("/placeholder").ok_or("Invalid hook engine runpath")?;
    let size = (12 + path.len() + 1 + 7) & !7;
    let mut c = vec![0; size];
    put32(&mut c, 0, 0x8000001c); put32(&mut c, 4, size as u32); put32(&mut c, 8, 12);
    c[12..12 + path.len()].copy_from_slice(path.as_bytes());
    Ok(c)
}
/// Load-control's validation accepts only our exact runpath dependency here.
pub(super) fn resolve(scope: &Path, dep: &str) -> Result<PathBuf> {
    if dep != DEPENDENCY { return Err("Unresolved hook engine dependency".into()); }
    let p = fs::canonicalize(scope.join("Frameworks").join(FRAMEWORK).join("CydiaSubstrate")).map_err(err)?;
    if !p.starts_with(scope) { return Err("Hook engine escapes selected bundle".into()); }
    Ok(p)
}

#[cfg(test)]
mod tests {
    use super::*;
    fn fixture(kind: u32) -> Vec<u8> {
        let mut d = vec![0; 8192];
        for (o,v) in [(0,0xfeedfacf),(4,0x100000c),(12,kind),(16,1),(20,152),(32,0x19),(36,152),(96,1),(152,4096)] {put32(&mut d,o,v)}
        d[80..88].copy_from_slice(&8192u64.to_le_bytes());
        d[144..152].copy_from_slice(&16u64.to_le_bytes()); d
    }
    fn bundle(p: &Path, ex: &str, kind: u32) {
        fs::create_dir_all(p).unwrap(); fs::write(p.join(ex),fixture(kind)).unwrap();
        let mut d=plist::Dictionary::new();d.insert("CFBundleExecutable".into(),plist::Value::String(ex.into()));
        plist::Value::Dictionary(d).to_file_xml(p.join("Info.plist")).unwrap();
    }
    fn source(p: &Path, alias: &str, kind: u32) {
        let m=macho(fixture(6),true).unwrap();let mut cs:Vec<_>=m.commands.iter().map(|c|c.data.clone()).collect();
        let mut load=dylib_command(kind,alias,None).unwrap();
        // Preserve timestamps/version metadata, not just the command kind.
        put32(&mut load,12,1234);put32(&mut load,16,0x90000);put32(&mut load,20,0x80000);
        cs.push(load);
        let mut symtab=vec![0;24];put32(&mut symtab,0,2);put32(&mut symtab,4,24);cs.push(symtab);
        cs.push(dylib_command(0xc,"/usr/lib/libobjc.A.dylib",None).unwrap());
        fs::write(p,write_commands(m,cs).unwrap()).unwrap();
    }
    fn item(lib: &Path, target: &str, loader: bool) -> tweak_targets::Injection {
        serde_json::from_value(serde_json::json!({"id":target,"library":lib,"target":target,"method":if loader{"load_control"}else{"direct"}})).unwrap()
    }
    #[test]
    fn known_aliases_only_and_invalid_resource_fails_closed() {
        for s in ["/usr/lib/libsubstrate.dylib","/var/jb/usr/lib/libellekit.dylib","@rpath/libhooker.dylib","/usr/lib/libsubstitute.dylib","@rpath/ElleKit.framework/ElleKit"] {assert!(alias(s),"{s}");}
        for s in ["/System/Library/Frameworks/Foundation.framework/Foundation","/usr/lib/libobjc.A.dylib","@rpath/MySubstrateHelper.dylib","@rpath/libhooker_extra.dylib"] {assert!(!alias(s),"{s}");}
        assert!(validate(&[],INFO).is_err());assert!(validate(BINARY,&[]).is_err());
        let mut bad=BINARY.to_vec();put32(&mut bad,4,0x1000007);assert!(validate(&bad,INFO).is_err());
        let m=macho(BINARY.to_vec(),true).unwrap();
        let mut cs:Vec<_>=m.commands.iter().map(|c|c.data.clone()).collect();
        let platform=cs.iter_mut().find(|c|u32at(c,0)==Ok(0x32)).expect("engine must contain build version");
        put32(platform,8,7); // ARM64 simulator is not a device binary.
        assert!(validate(&write_commands(m,cs).unwrap(),INFO).is_err());
    }
    #[test]
    fn four_aliases_preserve_weak_reexport_and_unrelated_commands() {
        for (i,alias) in ["/Library/Frameworks/CydiaSubstrate.framework/CydiaSubstrate","/usr/lib/libellekit.dylib","/usr/lib/libhooker.dylib","/usr/lib/libsubstitute.dylib"].iter().enumerate() {
            for kind in [0xc,0x80000018,0x8000001f,0x80000023,0x20] {
                let temp=tempfile::tempdir().unwrap();let app=temp.path().join("A.app");bundle(&app,"Main",2);
                let lib=temp.path().join(format!("T{i}.dylib"));source(&lib,alias,kind);
                let original=fs::read(&lib).unwrap();
                tweak_targets::inject_plan(&app,&[item(&lib,"Main",false)],&[],false,false).unwrap();
                let m=macho(read_macho(&app.join("Frameworks").join(lib.file_name().unwrap())).unwrap(),true).unwrap();
                let cmd=m.commands.iter().find(|c|c.name.as_deref()==Some(DEPENDENCY)).unwrap();
                assert_eq!(cmd.kind,kind);assert_eq!(u32at(&cmd.data,12).unwrap(),1234);assert_eq!(u32at(&cmd.data,16).unwrap(),0x10000);assert_eq!(u32at(&cmd.data,20).unwrap(),0x10000);
                assert!(m.commands.iter().any(|c|c.name.as_deref()==Some("/usr/lib/libobjc.A.dylib")));
                assert!(m.commands.iter().any(|c|c.data==runpath(&app.join("Frameworks/T.dylib"),&app).unwrap()));
                assert_eq!(fs::read(app.join("Frameworks/CydiaSubstrate.framework/CydiaSubstrate")).unwrap(),BINARY);
                assert_eq!(fs::read(&lib).unwrap(),original);
            }
        }
    }
    #[test]
    fn nested_framework_extension_and_loader_get_local_engine_and_runpath() {
        for loader in [false,true] {
            let temp=tempfile::tempdir().unwrap();let app=temp.path().join("A.app");bundle(&app,"Main",2);
            bundle(&app.join("PlugIns/X.appex"),"X",2);bundle(&app.join("Frameworks/F.framework"),"F",6);
            let lib=temp.path().join("T.framework");bundle(&lib,"T",6);source(&lib.join("T"),"/usr/lib/libsubstrate.dylib",0xc);
            let targets:Vec<_>=if loader {vec!["Main","PlugIns/X.appex/X"]}else{vec!["Main","PlugIns/X.appex/X","Frameworks/F.framework/F"]};
            let items:Vec<_>=targets.iter().map(|t|item(&lib,t,loader)).collect();
            tweak_targets::inject_plan(&app,&items,&[],false,false).unwrap();
            for t in targets {
                let scope=app.join(t).parent().unwrap().to_owned();
                let patched=scope.join("Frameworks/T.framework/T");let m=macho(read_macho(&patched).unwrap(),true).unwrap();
                assert!(m.commands.iter().any(|c|c.data==runpath(&patched,&scope).unwrap()));
                assert!(scope.join("Frameworks/CydiaSubstrate.framework/Info.plist").is_file());
                assert_eq!(dependencies(&patched).unwrap()[0],DEPENDENCY);
            }
        }
    }
    #[test]
    fn transitive_deb_style_libraries_get_engine_without_touching_unrelated_code() {
        let temp=tempfile::tempdir().unwrap();let app=temp.path().join("A.app");bundle(&app,"Main",2);
        let a=temp.path().join("A.dylib");source(&a,"@rpath/B.dylib",0xc);
        let b=temp.path().join("B.dylib");source(&b,"/usr/lib/libsubstitute.dylib",0xc);
        inject(&app,"Main",&[b.to_string_lossy().into(),a.to_string_lossy().into()],false).unwrap();
        assert!(dependencies(&app.join("Frameworks/A.dylib")).unwrap().contains(&"@loader_path/B.dylib".to_string()));
        assert!(dependencies(&app.join("Frameworks/B.dylib")).unwrap().contains(&DEPENDENCY.to_string()));
    }
    #[test]
    fn foreign_engine_collision_rolls_back_and_unrelated_import_has_no_engine() {
        let temp=tempfile::tempdir().unwrap();let app=temp.path().join("A.app");bundle(&app,"Main",2);
        let lib=temp.path().join("T.dylib");source(&lib,"/usr/lib/libsubstrate.dylib",0xc);
        let dir=app.join("Frameworks/CydiaSubstrate.framework");bundle(&dir,"CydiaSubstrate",6);
        let original=fs::read(app.join("Main")).unwrap();let foreign=fs::read(dir.join("CydiaSubstrate")).unwrap();
        assert!(tweak_targets::inject_plan(&app,&[item(&lib,"Main",false)],&[],false,false).unwrap_err().contains("conflicts"));
        assert_eq!(fs::read(app.join("Main")).unwrap(),original);assert_eq!(fs::read(dir.join("CydiaSubstrate")).unwrap(),foreign);
        fs::remove_dir_all(app.join("Frameworks")).unwrap();source(&lib,"/usr/lib/libobjc.A.dylib",0xc);
        tweak_targets::inject_plan(&app,&[item(&lib,"Main",false)],&[],false,false).unwrap();assert!(!dir.exists());
    }
    fn add_undefined(path: &Path, name: &str, ordinal: u8) {
        let m=macho(read_macho(path).unwrap(),true).unwrap();let mut commands:Vec<_>=m.commands.iter().map(|c|c.data.clone()).collect();
        let table=commands.iter_mut().find(|c|u32at(c,0)==Ok(2)).unwrap();
        put32(table,8,6000);put32(table,12,1);put32(table,16,6100);put32(table,20,(name.len()+2) as u32);
        let mut bytes=write_commands(m,commands).unwrap();
        put32(&mut bytes,6000,1);bytes[6004]=1;bytes[6006..6008].copy_from_slice(&((ordinal as u16)<<8).to_le_bytes());
        bytes[6100]=0;bytes[6101..6101+name.len()].copy_from_slice(name.as_bytes());bytes[6101+name.len()]=0;
        fs::write(path,bytes).unwrap();
    }
    #[test]
    fn unsupported_engine_bound_imports_fail_but_system_ms_and_objc_are_not_blacklisted() {
        for name in ["_MSHookClassPair","_EKUndocumentedHook","_OBJC_CLASS_$_MissingEngineClass","_rebind_symbols"] {
            let temp=tempfile::tempdir().unwrap();let app=temp.path().join("A.app");bundle(&app,"Main",2);
            let lib=temp.path().join("T.dylib");source(&lib,"/usr/lib/libsubstrate.dylib",0xc);add_undefined(&lib,name,1);
            let before=fs::read(app.join("Main")).unwrap();
            assert!(tweak_targets::inject_plan(&app,&[item(&lib,"Main",false)],&[],false,false).unwrap_err().contains("Unsupported hook engine API"));
            assert_eq!(fs::read(app.join("Main")).unwrap(),before);assert!(!app.join("Frameworks").exists());
        }
        for (name,ordinal) in [("_MSHookMessageEx",1),("_MSGenericSystemSymbol",2),("_OBJC_CLASS_$_NSObject",2)] {
            let temp=tempfile::tempdir().unwrap();let app=temp.path().join("A.app");bundle(&app,"Main",2);
            let lib=temp.path().join("T.dylib");source(&lib,"/usr/lib/libsubstrate.dylib",0xc);add_undefined(&lib,name,ordinal);
            tweak_targets::inject_plan(&app,&[item(&lib,"Main",false)],&[],false,false).unwrap();
        }
    }
    #[test]
    fn signed_engine_identity_reimport_and_scope_ids_are_stable_and_unique() {
        assert!(owned_binary(BINARY).unwrap());
        let entitlements=plist::Dictionary::new();
        let config=apple_codesign_quick::MachOSigningConfig::new("com.mirsa.hook.test","TEAM",&entitlements,None);
        let signed=apple_codesign_quick::sign_macho_data(Path::new("CydiaSubstrate"),BINARY,&config).unwrap();
        assert!(owned_binary(&signed).unwrap());
        let signed_again=apple_codesign_quick::sign_macho_data(Path::new("CydiaSubstrate"),&signed,&config).unwrap();
        assert!(owned_binary(&signed_again).unwrap());
        let mut tampered=signed.clone();tampered[16384]^=1;assert!(!owned_binary(&tampered).unwrap());
        let temp=tempfile::tempdir().unwrap();let app=temp.path().join("A.app");bundle(&app,"Main",2);fs::create_dir(app.join("Frameworks")).unwrap();
        let engine=stage(&app).unwrap();fs::write(&engine,&signed).unwrap();
        let mut info=plist::Value::from_file(engine.parent().unwrap().join("Info.plist")).unwrap();
        info.as_dictionary_mut().unwrap().insert("DTPlatformBuild".into(),plist::Value::String("signer metadata".into()));
        info.to_file_binary(engine.parent().unwrap().join("Info.plist")).unwrap();
        stage(&app).unwrap();assert_eq!(fs::read(engine).unwrap(),signed);
        assert_eq!(scope_identifier(Path::new("/tmp/.mirsa-plan-11.app")),scope_identifier(Path::new("/tmp/.mirsa-plan-22.app")));
        assert_eq!(scope_identifier(Path::new("/tmp/.mirsa-plan-11.app/PlugIns/X.appex")),scope_identifier(Path::new("/tmp/.mirsa-plan-22.app/PlugIns/X.appex")));
        let ids:HashSet<_>=["A.app","A.app/PlugIns/X.appex","A.app/Frameworks/F.framework","A.app/Frameworks"].iter().map(|s|scope_identifier(Path::new(s))).collect();assert_eq!(ids.len(),4);
    }

}
