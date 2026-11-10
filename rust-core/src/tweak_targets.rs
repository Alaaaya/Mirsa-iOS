//! Explicit, bounded per-target injection. No host execution of package code.
use super::*;
use serde::Serialize;
#[derive(Serialize)]
pub(super) struct Target { pub id: String, pub kind: String, pub label: String }
#[derive(Deserialize,Clone)]
pub(super) struct Injection {
 pub(super) id: String, pub(super) library: String, pub(super) target: String,
 #[serde(default)] pub(super) method: Option<String>,
 #[serde(default)] targets: Vec<String>,
 #[serde(default, alias="sharedTarget")] shared_target: Option<String>,
}
fn json(out: &Path, value: &impl Serialize)->Result<()> { fs::write(out,serde_json::to_vec(value).map_err(err)?).map_err(err) }
fn executable(bundle:&Path)->Result<String>{
 let value=plist::Value::from_file(bundle.join("Info.plist")).map_err(err)?;
 let s=value.as_dictionary().and_then(|d|d.get("CFBundleExecutable")).and_then(|v|v.as_string()).ok_or("Bundle missing executable")?;
 if relative(s)?.components().count()!=1 {return Err("Invalid bundle executable".into())} Ok(s.into())
}
pub(super) fn targets(app:&Path)->Result<Vec<Target>>{
 checked_tree(app)?;let app=fs::canonicalize(app).map_err(err)?;
 let mut files=Vec::new();walk(&app,&mut files)?;
 let main=executable(&app)?;
 let mut result=Vec::new();
 for p in std::iter::once(app.clone()).chain(files.into_iter().filter(|p|p.is_dir() && matches!(p.extension().and_then(|s|s.to_str()),Some("appex"|"framework")))) {
  let ex=executable(&p)?;let path=p.join(&ex);
  macho(read_macho(&path)?,p.extension().and_then(|s|s.to_str())==Some("framework"))?;
  let id=path.strip_prefix(&app).map_err(err)?.to_str().ok_or("Non UTF8 target")?.to_owned();
  result.push(Target{id,kind:if p==app{"main"}else if p.extension().and_then(|s|s.to_str())==Some("appex"){"extension"}else{"framework"}.into(),label:ex});
 }
 result.sort_by(|a,b|a.id.cmp(&b.id));
 if !result.iter().any(|t|t.id==main){return Err("Missing main target".into())} Ok(result)
}
pub(super) fn list_targets(app:&Path,out:&Path)->Result<()> {json(out,&targets(app)?)}
pub(super) fn package_roots(root:&Path,out:&Path)->Result<()> {
 checked_tree(root)?;
 if fs::symlink_metadata(root).map_err(err)?.file_type().is_symlink(){return Err("Package root cannot be a symlink".into())}
 let mut files=Vec::new();walk(root,&mut files)?;
 let mut total=0u64;
 for p in &files {let m=fs::symlink_metadata(p).map_err(err)?;if m.is_file(){total=total.checked_add(m.len()).ok_or("Package size overflow")?;if m.len()>FILE_LIMIT||total>TOTAL_LIMIT{return Err("Package root size limit exceeded".into())}}}
 let mut result=Vec::new();let mut names=HashSet::new();
 for p in files {
  let rel=p.strip_prefix(root).map_err(err)?;
  if rel.ancestors().skip(1).any(|p|p.extension().and_then(|s|s.to_str())==Some("framework")){continue}
  let kind=match p.extension().and_then(|s|s.to_str()){Some("dylib") if p.is_file()=>"dylib",Some("framework") if p.is_dir()=>"framework",_=>continue};
  let id=rel.to_str().ok_or("Non UTF8 package path")?.to_owned();relative(&id)?;
  if !names.insert(id.to_lowercase()){return Err("Case colliding package roots".into())}
  let code=if kind=="framework"{p.join(framework_executable(&p)?)}else{p.clone()};macho(read_macho(&code)?,true)?;
  result.push(serde_json::json!({"id":id,"path":id,"kind":kind}));
 }
 result.sort_by(|a,b|a["id"].as_str().cmp(&b["id"].as_str()));json(out,&result)
}
fn inject_plan_inner(app:&Path,items:&[Injection],order:&[String],loader:bool,first:bool)->Result<()> {
 if items.is_empty() || items.len()>64 || order.len()>4096{return Err("Injection plan exceeds limits or is empty".into())}
 let available=targets(app)?;let mut ids=HashSet::new();let mut groups:BTreeMap<(String,bool),Vec<String>>=BTreeMap::new();let mut destinations=HashSet::new();
 let mut group_sequence=Vec::new();
 let mut sorted=items.to_vec();
 sorted.sort_by(|a,b|order.iter().position(|x|x==&a.id).unwrap_or(usize::MAX).cmp(&order.iter().position(|x|x==&b.id).unwrap_or(usize::MAX)).then(a.id.cmp(&b.id)));
 for item in sorted {
  if item.id.is_empty() || item.id.len()>4096 || !ids.insert(item.id){return Err("Duplicate or invalid stable tweak id".into())}
  let method=item.method.as_deref().unwrap_or(if loader{"load_control"}else{"direct"});
  if !matches!(method,"direct"|"load_control"|"shared_library"|"separate_extension"){return Err("unknown_injection_method".into())}
  let selected=if item.targets.is_empty(){vec![item.target.clone()]}else{item.targets.clone()};
  if selected.is_empty()||selected.len()>65{return Err("invalid_process_selection".into())}
  let mut unique=HashSet::new();
  for id in &selected {if !unique.insert(id){return Err("duplicate_process_target".into())} if !available.iter().any(|t|t.id==*id){return Err("unknown_process_target".into())}}
  if method=="direct" && selected.len()!=1{return Err("direct_requires_single_target".into())}
  if matches!(method,"load_control"|"separate_extension") && selected.iter().any(|id|available.iter().any(|t|t.id==*id&&t.kind=="framework")){return Err("method_requires_process_targets".into())}
  if method=="separate_extension" && !selected.iter().any(|id|available.iter().any(|t|t.id==*id&&t.kind=="extension")){return Err("separate_extension_requires_extension".into())}
  let resolved=if method=="shared_library" {
   let candidates=super::injection_methods::shared_candidates(app,&selected)?;
   let id=if let Some(requested)=&item.shared_target{if !candidates.contains(requested){return Err("shared_target_not_common_dependency".into())}requested.clone()}else{if candidates.len()!=1{return Err("shared_target_ambiguous_or_unavailable".into())}candidates[0].clone()};
   vec![id]
  }else{selected};
  let source=Path::new(&item.library);let code=if source.extension().and_then(|s|s.to_str())==Some("framework"){source.join(framework_executable(source)?)}else{source.to_path_buf()};
  macho(read_macho(&code)?,true)?;
  let name=source.file_name().and_then(|s|s.to_str()).ok_or("Invalid tweak name")?;
  for target_id in resolved {
   let target=available.iter().find(|t|t.id==target_id);
   if method=="load_control" && target.is_none_or(|t|t.kind=="framework"){return Err("loader_requires_process_target".into())}
   let parent=Path::new(&target_id).parent().ok_or("Invalid target")?;
   let destination=parent.join("Frameworks").join(name);
   let key=destination.to_string_lossy().to_lowercase();
   if !destinations.insert(key){return Err("Tweak destination filename collision for selected target; rename library first".into())}
   let dir=app.join(parent).join("Frameworks");
   if dir.exists(){for e in fs::read_dir(&dir).map_err(err)?{if e.map_err(err)?.file_name().to_string_lossy().eq_ignore_ascii_case(name){return Err("Existing target Frameworks filename collision".into())}}}
   let key=(target_id,method=="load_control");
   if !groups.contains_key(&key){group_sequence.push(key.clone());}
   else if group_sequence.iter().rev().find(|k|k.0==key.0)!=Some(&key) {
    return Err("loader_order_interleaved_with_direct_is_unsupported".into());
   }
   groups.entry(key).or_default().push(item.library.clone());
  }
 }

 // Work on caller-owned disposable app copy. Existing signer signs nested libraries
 // before hashing resources and enclosing frameworks/extensions before outer app.
 // Preserve first encounter ordering of method groups. A prepend pass is
 // executed in reverse so the final Mach-O command sequence stays ordered.
 if first {group_sequence.reverse();}
 for (id,use_loader) in group_sequence {
  let libraries=groups.remove(&(id.clone(),use_loader)).ok_or("Missing injection group")?;
  let is_library=available.iter().find(|t|t.id==id).is_none_or(|t|t.kind=="framework");
  let target=app.join(&id);let scope=target.parent().ok_or("Missing target parent")?;
  if use_loader {load_control::inject_loader_scoped(app,scope,target.file_name().and_then(|s|s.to_str()).ok_or("Invalid target")?,&libraries,first)?}else{
   // Scope is the selected bundle, not the outer app. Cross-bundle dependencies
   // therefore fail closed instead of silently using another extension's code.
   if is_library {
    for lib in &libraries {let src=Path::new(lib);let code=if src.extension().and_then(|s|s.to_str())==Some("framework"){src.join(framework_executable(src)?)}else{src.to_owned()};for dep in dependencies(&code)?{if dep.starts_with("@executable_path/"){return Err("Framework target cannot resolve executable-relative tweak dependencies".into())}}}
   }
   inject_scoped(scope,target.file_name().and_then(|s|s.to_str()).ok_or("Invalid target")?,&libraries,first,true)?;
  }
 }
 Ok(())
}
/// Transactional private sibling copy. No original app mutations on validation or
/// injection error. Rename rollback handles commit failure. Caller must serialize
/// edits to its app workspace; this is not a cross-process filesystem lock.
pub(super) fn inject_plan(app:&Path,items:&[Injection],order:&[String],loader:bool,first:bool)->Result<()> {
 if items.is_empty()||items.len()>64||order.len()>4096{return Err("Injection plan exceeds limits or is empty".into())}
 use std::sync::atomic::{AtomicU64,Ordering};static NEXT:AtomicU64=AtomicU64::new(0);
 if fs::symlink_metadata(app).map_err(err)?.file_type().is_symlink(){return Err("App root cannot be a symlink".into())}
 let app=fs::canonicalize(app).map_err(err)?;let parent=app.parent().ok_or("Invalid app path")?;
 let suffix=format!("{}-{}",std::process::id(),NEXT.fetch_add(1,Ordering::Relaxed));
 let temp=parent.join(format!(".mirsa-plan-{suffix}.app"));let backup=parent.join(format!(".mirsa-backup-{suffix}.app"));
 if temp.exists()||backup.exists(){return Err("Plan transaction collision".into())}
 let result=(||{
  checked_tree(&app)?;copy_tree(&app,&temp)?;
  // Snapshot selected libraries so validation and edits never revisit caller paths.
  let imports=parent.join(format!(".mirsa-imports-{suffix}"));fs::create_dir(&imports).map_err(err)?;
  let work=(||{let mut snapshots=Vec::new();for(i,item)in items.iter().enumerate(){let source=Path::new(&item.library);checked_tree(source)?;let slot=imports.join(i.to_string());fs::create_dir(&slot).map_err(err)?;let name=source.file_name().ok_or("Invalid library filename")?;let dest=slot.join(name);copy_tree(source,&dest)?;let mut copy=item.clone();copy.library=dest.to_string_lossy().into();snapshots.push(copy)}inject_plan_inner(&temp,&snapshots,order,loader,first)})();
  let _=fs::remove_dir_all(&imports);work?;
  // Recheck original immediately before swap; reject new symlinks/case aliases.
  checked_tree(&app)?;fs::rename(&app,&backup).map_err(err)?;
  if let Err(e)=fs::rename(&temp,&app){let restore=fs::rename(&backup,&app);return Err(format!("Plan commit failed: {e}; rollback: {restore:?}"))}
  let _=fs::remove_dir_all(&backup);Ok(())
 })();if result.is_err(){let _=fs::remove_dir_all(&temp);}result
}
pub(super) fn checked_tree(root:&Path)->Result<()> {
 let m=fs::symlink_metadata(root).map_err(err)?;if m.file_type().is_symlink()||!(m.is_file()||m.is_dir()){return Err("Links or special files not supported".into())}
 if m.is_file(){if m.len()>FILE_LIMIT{return Err("Library too large".into())}return Ok(())}
 let mut files=Vec::new();walk(root,&mut files)?;let mut names=BTreeMap::new();let mut total=0u64;
 for p in files {let rel=p.strip_prefix(root).map_err(err)?.to_str().ok_or("Non UTF8 tree path")?.to_owned();relative(&rel)?;if names.insert(rel.to_lowercase(),rel).is_some(){return Err("Case aliased tree path".into())}let m=fs::symlink_metadata(&p).map_err(err)?;if m.is_file(){total=total.checked_add(m.len()).ok_or("Tree size overflow")?;if m.len()>FILE_LIMIT||total>TOTAL_LIMIT{return Err("Tree resource limit".into())}}}Ok(())
}
#[cfg(test)]mod tests{
 use super::*;
 fn fixture(kind:u32)->Vec<u8>{let mut d=vec![0;4096];for(o,v)in[(0,0xfeedfacf),(4,0x100000c),(12,kind),(16,1),(20,152),(32,0x19),(36,152),(96,1),(152,1024)]{put32(&mut d,o,v)}d[80..88].copy_from_slice(&4096u64.to_le_bytes());d[144..152].copy_from_slice(&16u64.to_le_bytes());d}
 fn bundle(p:&Path,exe:&str,kind:u32){fs::create_dir_all(p).unwrap();fs::write(p.join(exe),fixture(kind)).unwrap();let mut d=plist::Dictionary::new();d.insert("CFBundleExecutable".into(),plist::Value::String(exe.into()));plist::Value::Dictionary(d).to_file_xml(p.join("Info.plist")).unwrap()}
 fn setup(tag:&str)->(PathBuf,PathBuf){let p=std::env::temp_dir().join(format!("mirsa-targets-{}-{tag}",std::process::id()));let _=fs::remove_dir_all(&p);let app=p.join("A.app");bundle(&app,"Main",2);(p,app)}
 fn item(id:&str,lib:&Path,target:&str)->Injection{Injection{id:id.into(),library:lib.to_string_lossy().into(),target:target.into(),method:None,targets:Vec::new(),shared_target:None}}
 #[test]fn mixed_targets_and_stable_order(){let(p,a)=setup("mixed");bundle(&a.join("PlugIns/X.appex"),"X",2);bundle(&a.join("Frameworks/F.framework"),"F",6);for n in["A","B","C","D"]{fs::write(p.join(format!("{n}.dylib")),fixture(6)).unwrap()}
 let items=vec![item("a",&p.join("A.dylib"),"Main"),item("b",&p.join("B.dylib"),"Main"),item("c",&p.join("C.dylib"),"PlugIns/X.appex/X"),item("d",&p.join("D.dylib"),"Frameworks/F.framework/F")];
 inject_plan(&a,&items,&["missing".into(),"b".into()],false,false).unwrap();let deps=dependencies(&a.join("Main")).unwrap();assert!(deps[0].ends_with("B.dylib"));assert!(deps[1].ends_with("A.dylib"));assert!(dependencies(&a.join("PlugIns/X.appex/X")).unwrap()[0].ends_with("C.dylib"));assert!(dependencies(&a.join("Frameworks/F.framework/F")).unwrap()[0].ends_with("D.dylib"));fs::remove_dir_all(p).unwrap();}
 #[test]fn unsupported_and_duplicate_fail(){let(p,a)=setup("reject");bundle(&a.join("PlugIns/X.appex"),"X",2);let lib=p.join("T.dylib");fs::write(&lib,fixture(6)).unwrap();let mut bad=item("a",&lib,"PlugIns/X.appex/X");bad.method=Some("nonsense".into());assert!(inject_plan(&a,&[bad],&[],true,false).is_err());assert!(inject_plan(&a,&[item("a",&lib,"Main"),item("a",&lib,"Main")],&[],false,false).is_err());assert!(inject_plan(&a,&[item("a",&lib,"../outside")],&[],false,false).is_err());let mut d=fixture(6);put32(&mut d,8,2);fs::write(&lib,d).unwrap();assert!(inject_plan(&a,&[item("a",&lib,"Main")],&[],false,false).is_err());fs::remove_dir_all(p).unwrap();}
 #[test]fn roots_separate_same_basename_and_symlink_reject(){let(p,_)=setup("roots");let r=p.join("pkg");fs::create_dir_all(r.join("a")).unwrap();fs::create_dir_all(r.join("b")).unwrap();for n in["a/T.dylib","b/T.dylib"]{fs::write(r.join(n),fixture(6)).unwrap()}let out=p.join("roots.json");package_roots(&r,&out).unwrap();let v:serde_json::Value=serde_json::from_slice(&fs::read(&out).unwrap()).unwrap();assert_eq!(v[0]["id"],"a/T.dylib");assert_eq!(v[1]["id"],"b/T.dylib");#[cfg(unix)]{std::os::unix::fs::symlink("/tmp",r.join("escape")).unwrap();assert!(package_roots(&r,&out).is_err());}fs::remove_dir_all(p).unwrap();}
 #[test]fn missing_dependency_and_colliding_roots_fail(){let(p,a)=setup("deps");let l=p.join("A.dylib");let m=macho(fixture(6),true).unwrap();let mut cs:Vec<_>=m.commands.iter().map(|c|c.data.clone()).collect();cs.push(dylib_command(0xc,"@rpath/Missing.dylib",None).unwrap());fs::write(&l,write_commands(m,cs).unwrap()).unwrap();assert!(inject_plan(&a,&[item("a",&l,"Main")],&[],false,false).is_err());fs::remove_dir_all(p).unwrap();}
 #[test]fn transaction_rolls_back_after_late_failure(){let(p,a)=setup("transaction");bundle(&a.join("PlugIns/Z.appex"),"Z",2);let good=p.join("Good.dylib");let bad=p.join("Bad.dylib");fs::write(&good,fixture(6)).unwrap();let m=macho(fixture(6),true).unwrap();let mut cs:Vec<_>=m.commands.iter().map(|c|c.data.clone()).collect();cs.push(dylib_command(0xc,"@rpath/DoesNotExist.dylib",None).unwrap());fs::write(&bad,write_commands(m,cs).unwrap()).unwrap();let before=fs::read(a.join("Main")).unwrap();assert!(inject_plan(&a,&[item("good",&good,"Main"),item("bad",&bad,"PlugIns/Z.appex/Z")],&[],false,false).is_err());assert_eq!(fs::read(a.join("Main")).unwrap(),before);assert!(!a.join("Frameworks").exists());assert!(!a.join("PlugIns/Z.appex/Frameworks").exists());assert!(!fs::read_dir(&p).unwrap().any(|e|e.unwrap().file_name().to_string_lossy().starts_with(".mirsa-")));fs::remove_dir_all(p).unwrap();}
 #[test]fn target_tree_case_alias_and_symlink_reject(){let(p,a)=setup("alias");fs::create_dir(a.join("Foo")).unwrap();
 // APFS on macOS runners is case-insensitive: it rejects the alias at creation.
 // Case-sensitive volumes must instead reject both entries in our tree validator.
 match fs::create_dir(a.join("foo")) {
  Ok(()) => { assert!(targets(&a).is_err()); fs::remove_dir(a.join("foo")).unwrap(); }
  Err(e) => { assert_eq!(e.kind(),std::io::ErrorKind::AlreadyExists); assert_eq!(fs::canonicalize(a.join("Foo")).unwrap(),fs::canonicalize(a.join("foo")).unwrap()); }
 }
 fs::remove_dir(a.join("Foo")).unwrap();#[cfg(unix)]{std::os::unix::fs::symlink("/tmp",a.join("escape")).unwrap();assert!(targets(&a).is_err());}fs::remove_dir_all(p).unwrap();}

 #[test]fn identical_names_different_bundles_are_supported(){let(p,a)=setup("same-name");bundle(&a.join("PlugIns/X.appex"),"X",2);bundle(&a.join("Frameworks/F.framework"),"F",6);let lib=p.join("T.dylib");fs::write(&lib,fixture(6)).unwrap();inject_plan(&a,&[item("a",&lib,"Main"),item("b",&lib,"PlugIns/X.appex/X"),item("c",&lib,"Frameworks/F.framework/F")],&[],false,false).unwrap();for ex in["Main","PlugIns/X.appex/X","Frameworks/F.framework/F"]{assert!(dependencies(&a.join(ex)).unwrap()[0].ends_with("T.dylib"))}fs::remove_dir_all(p).unwrap();}

 fn method_item(id:&str,lib:&Path,method:&str,processes:&[&str])->Injection {
  let mut i=item(id,lib,processes[0]);i.method=Some(method.into());i.targets=processes.iter().map(|s|s.to_string()).collect();i
 }
 fn add_load(path:&Path,dep:&str) {
  let m=macho(read_macho(path).unwrap(),false).unwrap();
  let mut cs:Vec<_>=m.commands.iter().map(|c|c.data.clone()).collect();
  cs.push(dylib_command(0xc,dep,None).unwrap());fs::write(path,write_commands(m,cs).unwrap()).unwrap();
 }
 fn add_rpath(path:&Path,dep:&str) {
  let m=macho(read_macho(path).unwrap(),false).unwrap();
  let mut cs:Vec<_>=m.commands.iter().map(|c|c.data.clone()).collect();
  let size=(12+dep.len()+1+7)&!7;let mut c=vec![0;size];
  put32(&mut c,0,0x8000001c);put32(&mut c,4,size as u32);put32(&mut c,8,12);
  c[12..12+dep.len()].copy_from_slice(dep.as_bytes());cs.push(c);
  fs::write(path,write_commands(m,cs).unwrap()).unwrap();
 }
 fn shared_setup(tag:&str)->(PathBuf,PathBuf,PathBuf) {
  let(p,a)=setup(tag);bundle(&a.join("PlugIns/X.appex"),"X",2);
  fs::create_dir_all(a.join("Frameworks")).unwrap();
  fs::write(a.join("Frameworks/Shared.dylib"),fixture(6)).unwrap();
  add_load(&a.join("Main"),"@loader_path/Frameworks/Shared.dylib");
  add_load(&a.join("PlugIns/X.appex/X"),"@loader_path/../../Frameworks/Shared.dylib");
  let lib=p.join("Tweak.dylib");fs::write(&lib,fixture(6)).unwrap();(p,a,lib)
 }
 #[test] fn method_json_legacy_defaults_and_independent_choices() {
  let(p,a)=setup("methods-json");let l=p.join("T.dylib");fs::write(&l,fixture(6)).unwrap();
  let legacy:Injection=serde_json::from_value(serde_json::json!({"id":"legacy","library":l,"target":"Main"})).unwrap();assert!(legacy.method.is_none());
  let explicit=method_item("direct",&l,"direct",&["Main"]);
  inject_plan(&a,&[explicit],&[],true,false).unwrap();
  assert!(!a.join("Frameworks/MirsaLoader.dylib").exists());
  assert_eq!(dependencies(&a.join("Main")).unwrap(),vec!["@loader_path/Frameworks/T.dylib"]);fs::remove_dir_all(p).unwrap();
 }
 #[test] fn extension_scoped_loader_uses_own_resources_and_signable_nested_layout() {
  let(p,a)=setup("extension-loader");bundle(&a.join("PlugIns/X.appex"),"X",2);
  let l=p.join("T.dylib");fs::write(&l,fixture(6)).unwrap();let original=fs::read(a.join("Main")).unwrap();
  inject_plan(&a,&[method_item("x",&l,"load_control",&["PlugIns/X.appex/X"])],&[],false,false).unwrap();
  assert_eq!(fs::read(a.join("Main")).unwrap(),original);
  let local=a.join("PlugIns/X.appex/Frameworks");
  assert_eq!(fs::read_to_string(local.join("MirsaLoadOrder.txt")).unwrap(),"T.dylib\n".replace("\n","
"));
  assert!(local.join("MirsaLoader.dylib").is_file());assert!(!a.join("Frameworks").exists());
  assert_eq!(dependencies(&a.join("PlugIns/X.appex/X")).unwrap(),vec!["@loader_path/Frameworks/MirsaLoader.dylib"]);
  // Layout preserves existing signer traversal: library < appex < outer app.
  assert!(local.join("T.dylib").starts_with(a.join("PlugIns/X.appex")));fs::remove_dir_all(p).unwrap();
 }
 #[test] fn separate_extension_main_and_multiple_extensions_each_get_exact_copy() {
  let(p,a)=setup("separate");for n in ["X","Y"]{bundle(&a.join(format!("PlugIns/{n}.appex")),n,2)}
  let l=p.join("T.dylib");fs::write(&l,fixture(6)).unwrap();
  inject_plan(&a,&[method_item("all",&l,"separate_extension",&["Main","PlugIns/X.appex/X","PlugIns/Y.appex/Y"])],&[],true,false).unwrap();
  for target in ["Main","PlugIns/X.appex/X","PlugIns/Y.appex/Y"] {
   assert_eq!(dependencies(&a.join(target)).unwrap(),vec!["@loader_path/Frameworks/T.dylib"]);
   assert!(!a.join(target).parent().unwrap().join("Frameworks/MirsaLoader.dylib").exists());
  }fs::remove_dir_all(p).unwrap();
 }
 #[test] fn mixed_per_component_direct_and_loader_preserve_order_and_original_hooks() {
  let(p,a)=setup("mixed-method");add_load(&a.join("Main"),"/usr/lib/libSystem.B.dylib");
  let mut items=Vec::new();
  for(n,method)in [("A","direct"),("B","load_control"),("C","load_control")] {
   let l=p.join(format!("{n}.dylib"));fs::write(&l,fixture(6)).unwrap();items.push(method_item(n,&l,method,&["Main"]));
  }
  inject_plan(&a,&items,&["C".into(),"B".into(),"A".into()],false,false).unwrap();
  assert_eq!(fs::read_to_string(a.join("Frameworks/MirsaLoadOrder.txt")).unwrap(),"C.dylib
B.dylib
");
  assert_eq!(dependencies(&a.join("Main")).unwrap(),vec!["/usr/lib/libSystem.B.dylib","@loader_path/Frameworks/MirsaLoader.dylib","@loader_path/Frameworks/A.dylib"]);fs::remove_dir_all(p).unwrap();
 }
 #[test] fn shared_actual_identity_injected_once_preserves_processes_and_original_library_data() {
  let(p,a,l)=shared_setup("shared-once");let main=fs::read(a.join("Main")).unwrap();let ext=fs::read(a.join("PlugIns/X.appex/X")).unwrap();
  let mut original=fs::read(a.join("Frameworks/Shared.dylib")).unwrap();original[2000..2008].copy_from_slice(b"ORIGINAL");fs::write(a.join("Frameworks/Shared.dylib"),&original).unwrap();
  let ids=super::super::injection_methods::shared_candidates(&a,&["Main".into(),"PlugIns/X.appex/X".into()]).unwrap();assert_eq!(ids,vec!["Frameworks/Shared.dylib"]);
  inject_plan(&a,&[method_item("shared",&l,"shared_library",&["Main","PlugIns/X.appex/X"])],&[],false,false).unwrap();
  assert_eq!(fs::read(a.join("Main")).unwrap(),main);assert_eq!(fs::read(a.join("PlugIns/X.appex/X")).unwrap(),ext);
  assert_eq!(&fs::read(a.join("Frameworks/Shared.dylib")).unwrap()[2000..2008],b"ORIGINAL");
  assert_eq!(dependencies(&a.join("Frameworks/Shared.dylib")).unwrap(),vec!["@loader_path/Frameworks/Tweak.dylib"]);
  assert!(a.join("Frameworks/Frameworks/Tweak.dylib").exists());assert!(!a.join("PlugIns/X.appex/Frameworks").exists());fs::remove_dir_all(p).unwrap();
 }
 #[test] fn shared_local_runpaths_are_resolved_without_basename_inference() {
  let(p,a)=setup("rpaths");bundle(&a.join("PlugIns/X.appex"),"X",2);fs::create_dir_all(a.join("Frameworks")).unwrap();fs::write(a.join("Frameworks/S.dylib"),fixture(6)).unwrap();
  for (id,rpath) in [("Main","@loader_path/Frameworks"),("PlugIns/X.appex/X","@loader_path/../../Frameworks")] {
   add_rpath(&a.join(id),rpath);add_load(&a.join(id),"@rpath/S.dylib");
  }
  assert_eq!(super::super::injection_methods::shared_candidates(&a,&["Main".into(),"PlugIns/X.appex/X".into()]).unwrap(),vec!["Frameworks/S.dylib"]);
  fs::remove_dir_all(p).unwrap();
 }
 #[test] fn shared_same_basename_different_identity_no_common_and_unresolved_fail_closed() {
  let(p,a,_)=shared_setup("no-common");let ext=a.join("PlugIns/X.appex");fs::create_dir_all(ext.join("Frameworks")).unwrap();fs::write(ext.join("Frameworks/Shared.dylib"),fixture(6)).unwrap();fs::write(ext.join("X"),fixture(2)).unwrap();add_load(&ext.join("X"),"@loader_path/Frameworks/Shared.dylib");
  let selected=vec!["Main".into(),"PlugIns/X.appex/X".into()];
  assert_eq!(super::super::injection_methods::shared_candidates(&a,&selected).unwrap_err(),"shared_no_common_dependency");
  add_load(&a.join("Main"),"@rpath/Unknown.dylib");
  assert!(super::super::injection_methods::shared_candidates(&a,&selected).unwrap_err().contains("unresolved"));fs::remove_dir_all(p).unwrap();
 }
 #[test] fn shared_multiple_candidates_require_explicit_stable_identity() {
  let(p,a,l)=shared_setup("ambiguous");
  fs::write(a.join("Frameworks/Other.dylib"),fixture(6)).unwrap();
  add_load(&a.join("Main"),"@loader_path/Frameworks/Other.dylib");add_load(&a.join("PlugIns/X.appex/X"),"@loader_path/../../Frameworks/Other.dylib");
  let mut i=method_item("s",&l,"shared_library",&["Main","PlugIns/X.appex/X"]);
  let before=fs::read(a.join("Main")).unwrap();assert!(inject_plan(&a,&[i.clone()],&[],false,false).unwrap_err().contains("ambiguous"));assert_eq!(fs::read(a.join("Main")).unwrap(),before);
  i.shared_target=Some("Frameworks/Other.dylib".into());inject_plan(&a,&[i],&[],false,false).unwrap();
  assert!(dependencies(&a.join("Frameworks/Shared.dylib")).unwrap().is_empty());assert!(!dependencies(&a.join("Frameworks/Other.dylib")).unwrap().is_empty());fs::remove_dir_all(p).unwrap();
 }
 #[test] fn shared_ambiguous_rpaths_and_inherited_rpaths_are_disabled() {
  let(p,a,_)=shared_setup("rpath-ambiguous");fs::create_dir_all(a.join("Other")).unwrap();fs::write(a.join("Other/Shared.dylib"),fixture(6)).unwrap();
  fs::write(a.join("Main"),fixture(2)).unwrap();add_rpath(&a.join("Main"),"@loader_path/Frameworks");add_rpath(&a.join("Main"),"@loader_path/Other");add_load(&a.join("Main"),"@rpath/Shared.dylib");
  assert!(super::super::injection_methods::shared_candidates(&a,&["Main".into(),"PlugIns/X.appex/X".into()]).unwrap_err().contains("unresolved"));
  fs::remove_dir_all(p).unwrap();
 }
 #[test] fn shared_arm64e_fat_encrypted_and_non_dylib_rejected_without_mutation() {
  for variant in ["arm64e","fat","encrypted","executable"] {
   let(p,a,l)=shared_setup(&format!("abi-{variant}"));let file=a.join("Frameworks/Shared.dylib");
   let mut d=fixture(6);
   match variant {
    "arm64e"=>put32(&mut d,8,2),
    "fat"=>d=super::super::fat_macho::tests::fat(&[d],false,false),
    "encrypted"=>{let m=macho(d,true).unwrap();let mut cs:Vec<_>=m.commands.iter().map(|c|c.data.clone()).collect();let mut c=vec![0;24];put32(&mut c,0,0x2c);put32(&mut c,4,24);put32(&mut c,16,1);cs.push(c);d=write_commands(m,cs).unwrap()},
    _=>put32(&mut d,12,2)
   }
   fs::write(&file,&d).unwrap();let main=fs::read(a.join("Main")).unwrap();
   assert!(inject_plan(&a,&[method_item("s",&l,"shared_library",&["Main","PlugIns/X.appex/X"])],&[],false,false).is_err(),"{variant}");
   assert_eq!(fs::read(file).unwrap(),d);assert_eq!(fs::read(a.join("Main")).unwrap(),main);fs::remove_dir_all(p).unwrap();
  }
 }
 #[test] fn shared_cycle_and_executable_relative_library_context_fail_closed() {
  for context in [false,true] {
   let(p,a,_)=shared_setup(if context{"shared-context"}else{"shared-cycle"});
   add_load(&a.join("Frameworks/Shared.dylib"),if context{"@executable_path/Frameworks/Shared.dylib"}else{"@loader_path/Shared.dylib"});
   let e=super::super::injection_methods::shared_candidates(&a,&["Main".into(),"PlugIns/X.appex/X".into()]).unwrap_err();
   assert!(e.contains(if context{"unresolved"}else{"cycle"}));fs::remove_dir_all(p).unwrap();
  }
 }
 #[test] fn capabilities_without_extensions_disable_methods_with_reason_and_no_writes() {
  let(p,a)=setup("capabilities");let original=fs::read(a.join("Main")).unwrap();let out=p.join("cap.json");super::super::injection_methods::capabilities(&a,&out).unwrap();
  let v:serde_json::Value=serde_json::from_slice(&fs::read(out).unwrap()).unwrap();
  assert_eq!(v["sharedCandidates"],serde_json::json!([]));assert!(v["sharedDisabledReason"].as_str().unwrap().contains("requires"));
  assert_eq!(v["methods"][3]["enabled"],false);assert_eq!(v["methods"][3]["reason"],"no_extensions");
  assert_eq!(fs::read(a.join("Main")).unwrap(),original);fs::remove_dir_all(p).unwrap();
 }
 #[test] fn switching_reconstructs_pristine_export_no_stale_owned_artifacts_or_original_deletion() {
  let(p,a,l)=shared_setup("switch");let pristine=p.join("Pristine.app");copy_tree(&a,&pristine).unwrap();
  let original=fs::read(a.join("Frameworks/Shared.dylib")).unwrap();
  inject_plan(&a,&[method_item("t",&l,"load_control",&["Main","PlugIns/X.appex/X"])],&[],false,false).unwrap();
  assert!(a.join("Frameworks/MirsaLoader.dylib").exists());
  // This is the production export lifecycle: a fresh extraction from immutable
  // source each time. Never infer ownership of an original app hook by filename.
  fs::remove_dir_all(&a).unwrap();copy_tree(&pristine,&a).unwrap();
  inject_plan(&a,&[method_item("t",&l,"shared_library",&["Main","PlugIns/X.appex/X"])],&[],false,false).unwrap();
  assert!(!a.join("Frameworks/MirsaLoader.dylib").exists());assert!(!a.join("PlugIns/X.appex/Frameworks").exists());
  assert_eq!(fs::read(pristine.join("Frameworks/Shared.dylib")).unwrap(),original);
  assert!(dependencies(&a.join("Main")).unwrap()[0].ends_with("Shared.dylib"));
  // Applying to an already mutated export fails instead of deleting unknown data.
  let snapshot=fs::read(a.join("Frameworks/Shared.dylib")).unwrap();
  assert!(inject_plan(&a,&[method_item("t",&l,"shared_library",&["Main","PlugIns/X.appex/X"])],&[],false,false).is_err());
  assert_eq!(fs::read(a.join("Frameworks/Shared.dylib")).unwrap(),snapshot);fs::remove_dir_all(p).unwrap();
 }
 #[test] fn method_duplicate_and_escape_selection_preserve_original_on_failure() {
  let(p,a,l)=shared_setup("method-invalid");let original=fs::read(a.join("Main")).unwrap();
  for selected in [vec!["Main","Main"],vec!["Main","../escape"],vec!["Main"]] {
   let i=method_item("s",&l,"shared_library",&selected);assert!(inject_plan(&a,&[i],&[],false,false).is_err());assert_eq!(fs::read(a.join("Main")).unwrap(),original);
  }
  let mut i=method_item("s",&l,"shared_library",&["Main","PlugIns/X.appex/X"]);i.shared_target=Some("../escape".into());assert!(inject_plan(&a,&[i],&[],false,false).is_err());fs::remove_dir_all(p).unwrap();
 }

 #[test] fn weak_edges_do_not_prove_common_dependency() {
  let(p,a,_)=shared_setup("weak-common");fs::write(a.join("PlugIns/X.appex/X"),fixture(2)).unwrap();
  let file=a.join("PlugIns/X.appex/X");let m=macho(read_macho(&file).unwrap(),false).unwrap();
  let mut cs:Vec<_>=m.commands.iter().map(|c|c.data.clone()).collect();
  cs.push(dylib_command(0x80000018,"@loader_path/../../Frameworks/Shared.dylib",None).unwrap());fs::write(file,write_commands(m,cs).unwrap()).unwrap();
  assert!(super::super::injection_methods::shared_candidates(&a,&["Main".into(),"PlugIns/X.appex/X".into()]).unwrap_err().contains("no_common"));fs::remove_dir_all(p).unwrap();
 }
 #[test] fn shared_subset_ignores_unselected_extension_and_component_caps_use_actual_dryrun() {
  let(p,a,l)=shared_setup("subset");bundle(&a.join("PlugIns/Y.appex"),"Y",2);
  let selected=method_item("t",&l,"shared_library",&["Main","PlugIns/X.appex/X"]);
  assert!(super::super::injection_methods::shared_candidates(&a,&["Main".into(),"PlugIns/X.appex/X".into(),"PlugIns/Y.appex/Y".into()]).is_err());
  let original=fs::read(a.join("Main")).unwrap();let out=p.join("caps.json");
  super::super::injection_methods::capabilities_for(&a,&[selected],&out).unwrap();
  let v:serde_json::Value=serde_json::from_slice(&fs::read(out).unwrap()).unwrap();
  assert_eq!(v["methods"][2]["enabled"],false);assert_eq!(v["components"][0]["methods"][2]["enabled"],true);
  assert_eq!(v["components"][0]["methods"][0]["enabled"],false);
  assert_eq!(fs::read(a.join("Main")).unwrap(),original);assert!(!a.join("Frameworks/Frameworks").exists());
  fs::remove_dir_all(p).unwrap();
 }
 #[test] fn interleaved_loader_direct_order_fails_transactionally_instead_of_silently_reordering() {
  let(p,a)=setup("interleaved");let mut items=Vec::new();
  for(n,method)in [("A","load_control"),("B","direct"),("C","load_control")] {
   let l=p.join(format!("{n}.dylib"));fs::write(&l,fixture(6)).unwrap();items.push(method_item(n,&l,method,&["Main"]));
  }
  let original=fs::read(a.join("Main")).unwrap();
  assert!(inject_plan(&a,&items,&[],false,false).unwrap_err().contains("interleaved"));
  assert_eq!(fs::read(a.join("Main")).unwrap(),original);assert!(!a.join("Frameworks").exists());fs::remove_dir_all(p).unwrap();
 }

}
