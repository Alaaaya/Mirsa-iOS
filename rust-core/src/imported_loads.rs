//! Imported dependencies are not assumed to be injected tweaks. Copy-on-edit,
//! in-place command compaction only; no executable code is ever loaded.
use super::*;
use serde::{Deserialize, Serialize};
#[derive(Deserialize)]
pub(super) struct Edit {
    owner: String,
    #[serde(default)] remove: Vec<String>,
    #[serde(default)] order: Vec<String>,
    #[serde(default)] delete_files: bool,
}
#[derive(Serialize)]
struct Entry {
    owner: String, main_owner: bool, slice: usize, subtype: u32,
    load_path: String, weak: bool, resolved_path: Option<String>,
}
fn visible(c: &Command) -> bool {
    matches!(c.kind,0xc|0x80000018|0x8000001f|0x80000023|0x20)
        && c.name.as_ref().is_some_and(|n| !n.starts_with("/System/Library/") && !n.starts_with("/usr/lib/"))
}
fn main_path(app: &Path, executable: &str) -> Result<PathBuf> {
    let rel=relative(executable)?;
    if rel.components().count()!=1 {return Err("Invalid main executable".into())}
    let p=app.join(rel); if !p.is_file(){return Err("Missing main executable".into())} Ok(p)
}
fn owners(app: &Path, executable: &str) -> Result<Vec<PathBuf>> {
    let main=main_path(app,executable)?;
    let mut files=Vec::new();walk(app,&mut files)?;
    let mut out=vec![main.clone()];
    for p in files {
        if p==main || !p.is_file(){continue}
        let mut h=[0;4];if File::open(&p).map_err(err)?.read_exact(&mut h).is_err(){continue}
        if matches!(h,[0xcf,0xfa,0xed,0xfe]|[0xca,0xfe,0xba,0xbe]|[0xbe,0xba,0xfe,0xca]|[0xca,0xfe,0xba,0xbf]|[0xbf,0xba,0xfe,0xca]) {
            out.push(p);
        }
    }
    out.sort();Ok(out)
}
fn resolved(app: &Path, owner: &Path, load: &str) -> Option<String> {
    // Direct anchors have no ambiguous runpath search semantics.
    let p=if let Some(r)=load.strip_prefix("@executable_path/"){app.join(r)}
        else if let Some(r)=load.strip_prefix("@loader_path/"){owner.parent()?.join(r)}
        else {return None};
    let p=fs::canonicalize(p).ok()?;
    if !p.starts_with(app)||!p.is_file(){return None}
    Some(p.strip_prefix(app).ok()?.to_str()?.to_owned())
}
fn rpaths(m: &Mach, app: &Path, owner: &Path) -> Result<Vec<PathBuf>> {
    let mut out=Vec::new();
    for c in m.commands.iter().filter(|c|c.kind==0x8000001c) {
        let at=u32at(&c.data,8)? as usize;
        if at<12 || at>=c.data.len(){return Err("Invalid LC_RPATH offset".into())}
        let raw=&c.data[at..];let len=raw.iter().position(|&b|b==0).ok_or("Unterminated LC_RPATH")?;
        let name=std::str::from_utf8(&raw[..len]).map_err(err)?;
        let p=if let Some(r)=name.strip_prefix("@executable_path/"){app.join(r)}
            else if name=="@executable_path"{app.to_path_buf()}
            else if let Some(r)=name.strip_prefix("@loader_path/"){owner.parent().ok_or("Missing owner parent")?.join(r)}
            else if name=="@loader_path"{owner.parent().ok_or("Missing owner parent")?.to_path_buf()}
            else {continue};
        if let Ok(p)=fs::canonicalize(p){if p.starts_with(app)&&p.is_dir(){out.push(p)}}
    }Ok(out)
}
fn resolve_rpath(app:&Path,load:&str,paths:&[PathBuf])->Option<String>{
    let tail=load.strip_prefix("@rpath/")?;let mut matches=HashSet::new();
    for base in paths{if let Ok(p)=fs::canonicalize(base.join(tail)){if p.starts_with(app)&&p.is_file(){matches.insert(p);}}}
    if matches.len()!=1{return None}Some(matches.into_iter().next()?.strip_prefix(app).ok()?.to_str()?.to_owned())
}
fn entries(app: &Path, executable: &str) -> Result<Vec<Entry>> {
    let app=fs::canonicalize(app).map_err(err)?;
    let main=main_path(&app,executable)?;
    let main_bytes=read_macho(&main)?;
    let mut main_paths=Vec::new();
    for (a,b) in fat_macho::arm64_ranges(&main_bytes)? {main_paths.extend(rpaths(&macho_subtype(main_bytes[a..b].to_vec(),false,true)?,&app,&main)?)}
    let mut out=Vec::new();let mut budget=0usize;
    for owner in owners(&app,executable)? {
        let bytes=read_macho(&owner)?;budget=budget.checked_add(bytes.len()).ok_or("Inspection overflow")?;
        if budget>512*1024*1024{return Err("Inspection code budget exceeded".into())}
        let ranges=match fat_macho::arm64_ranges(&bytes){
            Err(e) if e=="FAT binary has no arm64 slices" || e=="Unsupported thin architecture" => continue,
            other => other?,
        };
        for (slice,(a,b)) in ranges.into_iter().enumerate(){
            let m=macho_subtype(bytes[a..b].to_vec(),false,true)?;
            let mut paths=rpaths(&m,&app,&owner)?;paths.extend(main_paths.clone());
            for c in m.commands.iter().filter(|c|visible(c)) {
                let load=c.name.clone().unwrap();
                out.push(Entry{owner:owner.strip_prefix(&app).map_err(err)?.to_str().ok_or("Invalid owner")?.into(),main_owner:owner==main,slice,subtype:m.subtype,resolved_path:resolved(&app,&owner,&load).or_else(||resolve_rpath(&app,&load,&paths)),load_path:load,weak:c.kind==0x80000018});
            }
        }
    } Ok(out)
}
pub(super) fn report(app: &Path, executable: &str, output: &Path) -> Result<()> {
    let list=entries(app,executable)?;
    fs::write(output,serde_json::to_vec(&serde_json::json!({"version":1,"entries":list,"warning":"Imported dependencies may be vendor frameworks, not injections. Unresolved paths are not missing-file proof. Unsupported architectures are not listed. File removal is opt-in and conservative; edits require re-signing."})).map_err(err)?).map_err(err)
}
fn patch(bytes: &[u8], edit: &Edit) -> Result<Vec<u8>> {
    let mut result=bytes.to_vec();
    let mut expected=None;
    for (a,b) in fat_macho::arm64_ranges(bytes)? {
        let mut m=macho_subtype(bytes[a..b].to_vec(),false,true)?;
        // Dylib order is also a symbol-binding ordinal namespace. Without a
        // verified dyld rebind implementation changing it could silently bind
        // symbols to the wrong framework. Reject such binaries, never corrupt.
        if !edit.remove.is_empty() || !edit.order.is_empty() {
            for c in &m.commands {
                let has_ordinals = match c.kind {
                    0x22 | 0x80000022 => [20,28,36].iter().any(|&o| u32at(&c.data,o).unwrap_or(1)!=0),
                    0x80000034 => u32at(&c.data,12)? != 0,
                    0x2 => u32at(&c.data,12)? != 0,
                    0xb => [28,52,60,68,76].iter().any(|&o| u32at(&c.data,o).unwrap_or(1)!=0),
                    _ => false,
                };
                if has_ordinals {return Err("Dependency editing requires dyld ordinal rebinding for this binary; safe editing is not yet supported".into())}
            }
        }
        let names:Vec<_>=m.commands.iter().filter(|c|visible(c)).map(|c|c.name.clone().unwrap()).collect();
        if names.iter().collect::<HashSet<_>>().len()!=names.len(){return Err("Ambiguous duplicate dependency commands".into())}
        if expected.as_ref().is_some_and(|n|n!=&names){return Err("Arm64 slice dependency lists differ; refusing inconsistent edit".into())}expected=Some(names.clone());
        if edit.remove.iter().collect::<HashSet<_>>().len()!=edit.remove.len() || edit.remove.iter().any(|n|!names.contains(n)){return Err("Unknown or duplicate removal".into())}
        m.commands.retain(|c| !visible(c)||!edit.remove.contains(c.name.as_ref().unwrap()));
        if !edit.order.is_empty(){
            let remaining:Vec<_>=m.commands.iter().filter(|c|visible(c)).collect();
            if edit.order.len()!=remaining.len() || edit.order.iter().collect::<HashSet<_>>().len()!=remaining.len() || remaining.iter().any(|c|!edit.order.contains(c.name.as_ref().unwrap())) {return Err("Order must list every remaining dependency exactly once".into())}
            let ordered:Vec<_>=edit.order.iter().map(|n|remaining.iter().find(|c|c.name.as_ref()==Some(n)).unwrap().data.clone()).collect();
            let mut it=ordered.into_iter();for c in &mut m.commands{if visible(c){c.data=it.next().unwrap()}}
        }
        let old_end=32+u32at(&m.data,20)? as usize;
        let size:usize=m.commands.iter().map(|c|c.data.len()).sum();
        if size+32>old_end{return Err("Command expansion forbidden".into())}
        m.data[32..old_end].fill(0);let mut at=32;
        for c in &m.commands{m.data[at..at+c.data.len()].copy_from_slice(&c.data);at+=c.data.len()}
        put32(&mut m.data,16,m.commands.len() as u32);put32(&mut m.data,20,size as u32);
        // Validate reconstructed table before writing any working-copy bytes.
        macho_subtype(m.data.clone(),false,true)?;result[a..b].copy_from_slice(&m.data);
    } Ok(result)
}
pub(super) fn edit_copy(input: &Path, executable: &str, output: &Path, edits: &[Edit]) -> Result<()> {
    let app=fs::canonicalize(input).map_err(err)?;
    if output.exists(){return Err("Working copy must not exist".into())}
    let parent=fs::canonicalize(output.parent().ok_or("Invalid working path")?).map_err(err)?;
    if parent.starts_with(&app){return Err("Working copy must be outside original".into())}
    // Validate all owners, every architecture and all edit requests before copying.
    let before=entries(&app,executable)?;
    let allowed=owners(&app,executable)?;let mut seen=HashSet::new();let mut patches=Vec::new();
    let mut delete_candidates=HashSet::new();
    for edit in edits.iter().filter(|e|e.delete_files){for e in before.iter().filter(|e|e.owner==edit.owner && edit.remove.contains(&e.load_path)){
        if let Some(p)=&e.resolved_path{if Path::new(p).extension().and_then(|s|s.to_str())==Some("dylib"){delete_candidates.insert(p.clone());}}
    }}
    // A non-arm64 owner may still reference a target. Never delete in that case.
    let all_arm64=allowed.iter().all(|p|read_macho(p).ok().and_then(|d|{
        let ranges=fat_macho::arm64_ranges(&d).ok()?;
        if d.get(..4)==Some(&[0xcf,0xfa,0xed,0xfe]) {return Some(true)}
        let n=fat_macho::word(&d,4,false,matches!(d.get(..4),Some([0xbe,0xba,0xfe,0xca]|[0xbf,0xba,0xfe,0xca]))).ok()?;
        Some(n as usize==ranges.len())
    })==Some(true));
    for edit in edits {
        let rel=relative(&edit.owner)?;
        if !seen.insert(rel.clone()){return Err("Duplicate edited owner".into())}
        let p=app.join(&rel);
        if !allowed.contains(&p){return Err("Owner is not a contained Mach-O executable".into())}
        patches.push((rel,patch(&read_macho(&p)?,edit)?));
    }
    // create_dir (not create_dir_all) ensures we only clean up an owned new copy.
    fs::create_dir(output).map_err(err)?;
    let result=(||{
        for e in fs::read_dir(&app).map_err(err)? {
            let e=e.map_err(err)?;copy_tree(&e.path(),&output.join(e.file_name()))?;
        }
        for (rel,data) in patches{fs::write(output.join(rel),data).map_err(err)?}
        let after=entries(output,executable)?;
        if all_arm64 && after.iter().all(|e|e.resolved_path.is_some()) {
            for target in delete_candidates {
                if app.join(&target)!=main_path(&app,executable)? && allowed.contains(&app.join(&target)) && !after.iter().any(|e|e.resolved_path.as_ref()==Some(&target)) {
                    let rel=relative(&target)?;let p=output.join(rel);
                    if fs::symlink_metadata(&p).map_err(err)?.is_file(){fs::remove_file(p).map_err(err)?}
                }
            }
        }
        Ok(())})();
    if result.is_err(){let _=fs::remove_dir_all(output);}result
}
#[cfg(test)]
mod tests {
    use super::*;
    fn fixture(sub:u32, loads:&[&str])->Vec<u8>{
        let mut d=vec![0;4096];put32(&mut d,0,0xfeedfacf);put32(&mut d,4,0x100000c);put32(&mut d,8,sub);put32(&mut d,12,2);
        put32(&mut d,32,0x19);put32(&mut d,36,152);d[80..88].copy_from_slice(&4096u64.to_le_bytes());put32(&mut d,96,1);d[144..152].copy_from_slice(&16u64.to_le_bytes());put32(&mut d,152,1024);
        let mut at=184;for name in loads{let c=dylib_command(0xc,name,None).unwrap();d[at..at+c.len()].copy_from_slice(&c);at+=c.len()}
        put32(&mut d,16,1+loads.len() as u32);put32(&mut d,20,(at-32) as u32);d
    }
    fn names(d:&[u8])->Vec<String>{macho_subtype(d.to_vec(),false,true).unwrap().commands.iter().filter(|c|visible(c)).map(|c|c.name.clone().unwrap()).collect()}
    #[test]fn fat_reorder_remove_preserves_all_slices_system_and_offsets(){
        let loads=["@rpath/A.dylib","/usr/lib/libz.dylib","@rpath/B.dylib","@rpath/C.dylib"];
        for wide in [false,true]{for le in [false,true]{
            let original=fat_macho::tests::fat(&[fixture(0,&loads),fixture(2,&loads)],wide,le);
            let edit=Edit{owner:"Main".into(),remove:vec![loads[0].into()],order:vec![loads[3].into(),loads[2].into()],delete_files:false};
            let out=patch(&original,&edit).unwrap();assert_eq!(out.len(),original.len());
            for (a,b) in fat_macho::arm64_ranges(&out).unwrap(){assert_eq!(names(&out[a..b]),vec![loads[3],loads[2]]);assert_eq!(&out[a+1024..b],&original[a+1024..b]);let m=macho_subtype(out[a..b].to_vec(),false,true).unwrap();assert!(m.commands.iter().any(|c|c.name.as_deref()==Some(loads[1])))}
        }}
    }
    #[test]fn ordinal_bearing_payloads_fail_closed(){
        for (kind,size,count_at) in [(0x80000022,48,20),(0x80000034,16,12),(0x2,24,12),(0xb,80,28)] {
            let mut d=fixture(0,&["@rpath/A"]);let at=32+u32at(&d,20).unwrap() as usize;
            put32(&mut d,at,kind);put32(&mut d,at+4,size);put32(&mut d,at+count_at,1);
            // Proper on-disk payload for parser validation.
            match kind {0x80000022=>put32(&mut d,at+16,2048),0x80000034=>put32(&mut d,at+8,2048),0x2=>put32(&mut d,at+8,2048),_=>{}}
            put32(&mut d,16,3);put32(&mut d,20,(at+size as usize-32) as u32);
            let edit=Edit{owner:"Main".into(),remove:vec!["@rpath/A".into()],order:vec![],delete_files:false};
            let failure=patch(&d,&edit).unwrap_err();assert!(failure.contains("ordinal rebinding"),"{kind:x} {failure}");
        }
    }
    #[test]fn contained_rpaths_opt_in_unreferenced_file_delete_and_shared_retention(){
        let root=std::env::temp_dir().join(format!("imported-rpaths-{}",std::process::id()));let _=fs::remove_dir_all(&root);let app=root.join("Original.app");fs::create_dir_all(app.join("Frameworks")).unwrap();
        let load="@rpath/A.dylib";let mut d=fixture(0,&[load]);let at=32+u32at(&d,20).unwrap() as usize;
        let name=b"@executable_path/Frameworks\0";let size=(12+name.len()+7)&!7;put32(&mut d,at,0x8000001c);put32(&mut d,at+4,size as u32);put32(&mut d,at+8,12);d[at+12..at+12+name.len()].copy_from_slice(name);put32(&mut d,16,3);put32(&mut d,20,(at+size-32) as u32);
        fs::write(app.join("Main"),&d).unwrap();fs::write(app.join("Frameworks/A.dylib"),fixture(0,&[])).unwrap();
        assert_eq!(entries(&app,"Main").unwrap()[0].resolved_path.as_deref(),Some("Frameworks/A.dylib"));
        let edit=Edit{owner:"Main".into(),remove:vec![load.into()],order:vec![],delete_files:true};let work=root.join("Deleted.app");edit_copy(&app,"Main",&work,&[edit]).unwrap();assert!(!work.join("Frameworks/A.dylib").exists());assert!(app.join("Frameworks/A.dylib").exists());
        fs::write(app.join("Frameworks/B.dylib"),fixture(0,&["@executable_path/Frameworks/A.dylib"])).unwrap();let work=root.join("Shared.app");let edit=Edit{owner:"Main".into(),remove:vec![load.into()],order:vec![],delete_files:true};edit_copy(&app,"Main",&work,&[edit]).unwrap();assert!(work.join("Frameworks/A.dylib").exists());fs::remove_dir_all(root).unwrap();
    }
    #[test]fn malformed_and_mismatched_slices_reject(){
        let e=Edit{owner:"Main".into(),remove:vec!["@rpath/A".into()],order:vec![],delete_files:false};
        let mut bad=fixture(0,&["@rpath/A"]);put32(&mut bad,36,7);assert!(patch(&bad,&e).is_err());
        let fat=fat_macho::tests::fat(&[fixture(0,&["@rpath/A"]),fixture(2,&["@rpath/B"])],false,false);assert!(patch(&fat,&e).is_err());
        let duplicate=fixture(0,&["@rpath/A","@rpath/A"]);assert!(patch(&duplicate,&e).is_err());
    }
    #[test]fn main_framework_shared_owner_copy_reset_and_containment(){
        let root=std::env::temp_dir().join(format!("imported-loads-{}",std::process::id()));let _=fs::remove_dir_all(&root);fs::create_dir_all(root.join("Original.app/Frameworks/V.framework")).unwrap();let app=root.join("Original.app");
        let load="@executable_path/Frameworks/Shared.dylib";let original=fixture(0,&[load]);fs::write(app.join("Main"),&original).unwrap();fs::write(app.join("Frameworks/V.framework/V"),fixture(0,&[load])).unwrap();fs::write(app.join("Frameworks/Shared.dylib"),fixture(0,&[])).unwrap();
        let report=entries(&app,"Main").unwrap();assert_eq!(report.len(),2);assert!(report.iter().all(|e|e.resolved_path.as_deref()==Some("Frameworks/Shared.dylib")));assert_eq!(report.iter().filter(|e|e.main_owner).count(),1);
        let edit=Edit{owner:"Main".into(),remove:vec![load.into()],order:vec![],delete_files:false};let work=root.join("Work.app");edit_copy(&app,"Main",&work,&[edit]).unwrap();assert_eq!(fs::read(app.join("Main")).unwrap(),original);assert!(work.join("Frameworks/Shared.dylib").exists());assert_eq!(entries(&work,"Main").unwrap().len(),1);
        let reset=root.join("Reset.app");edit_copy(&app,"Main",&reset,&[]).unwrap();assert_eq!(fs::read(reset.join("Main")).unwrap(),original);
        assert!(edit_copy(&app,"Main",&root.join("Bad.app"),&[Edit{owner:"../outside".into(),remove:vec![],order:vec![],delete_files:false}]).is_err());assert!(!root.join("Bad.app").exists());assert!(resolved(&app,&app.join("Main"),"@rpath/Unknown").is_none());fs::remove_dir_all(root).unwrap();
    }
}
