//! Inert bounded tweak import. Library parsers only; no subprocesses or code loading.
use super::*;
use serde::Serialize;
use sha2::{Digest,Sha256};
use unicode_normalization::UnicodeNormalization;
use std::io::Write;
const INPUT:u64=128*1024*1024;
const EXPANDED:u64=256*1024*1024;
const COUNT:usize=10_000;
const CANDIDATES:usize=256;
fn failure(code:&str)->String {format!("tweak_import:{code}")}
fn fold(s:&str)->String {caseless::default_case_fold_str(&s.nfc().collect::<String>()).nfc().collect()}
fn safe(name:&str)->Result<PathBuf>{
 if name.is_empty()||name.len()>4096||name.contains(['\\','\0',':','%'])||name.starts_with('/')||name.chars().any(|c|c.is_control()){
  return Err(failure("unsafe_path"))
 }
 let name=name.strip_suffix('/').unwrap_or(name);
 let parts:Vec<_>=name.split('/').collect();
 if parts.len()>64||parts.iter().any(|s|s.is_empty()||*s=="."||*s==".."){return Err(failure("unsafe_path"))}
 Ok(PathBuf::from(parts.join("/").nfc().collect::<String>()))
}
#[derive(Default)]
struct Paths {seen:HashSet<String>,spellings:BTreeMap<String,String>,files:HashSet<String>}
impl Paths{
 fn add(&mut self,p:&Path,dir:bool)->Result<()>{
  let s=p.to_str().ok_or_else(||failure("unsafe_path"))?;
  let key=fold(s);if !self.seen.insert(key.clone()){return Err(failure("collision"))}
  for parent in p.ancestors().filter(|p|!p.as_os_str().is_empty()){
   let value=parent.to_str().ok_or_else(||failure("unsafe_path"))?.to_owned();
   if let Some(old)=self.spellings.insert(fold(&value),value.clone()){if old!=value{return Err(failure("collision"))}}
  }
  if !dir{self.files.insert(key);} Ok(())
 }
 fn finish(&self)->Result<()>{
  for value in self.spellings.values(){
   if Path::new(value).ancestors().skip(1).any(|p|self.files.contains(&fold(&p.to_string_lossy()))){return Err(failure("collision"))}
  } Ok(())
 }
}
struct Budget<'a>{cancel:&'a Path,bytes:u64,count:usize}
impl Budget<'_>{
 fn check(&self)->Result<()> {if self.cancel.exists(){Err(failure("cancelled"))}else{Ok(())}}
 fn entry(&mut self,size:u64)->Result<()>{
  self.check()?;self.count+=1;
  if size>INPUT||self.count>COUNT{return Err(failure("limits"))} Ok(())
 }
 fn copy(&mut self,reader:&mut impl Read,out:&mut impl Write,declared:u64)->Result<()>{
  let mut size=0u64;let mut buffer=[0u8;65536];
  loop{
   self.check()?;let n=reader.read(&mut buffer).map_err(|_|failure("corrupt"))?;if n==0{break}
   size=size.checked_add(n as u64).ok_or_else(||failure("limits"))?;
   self.bytes=self.bytes.checked_add(n as u64).ok_or_else(||failure("limits"))?;
   if size>declared||size>INPUT||self.bytes>EXPANDED{return Err(failure("limits"))}
   out.write_all(&buffer[..n]).map_err(|_|failure("disk"))?;
  }
  if size!=declared{return Err(failure("corrupt"))}Ok(())
 }
}
fn disk(root:&Path,need:u64)->Result<()>{
 #[cfg(unix)]{
  let name=CString::new(root.to_string_lossy().as_bytes()).map_err(|_|failure("disk"))?;
  let mut stat=std::mem::MaybeUninit::<libc::statvfs>::uninit();
  if unsafe{libc::statvfs(name.as_ptr(),stat.as_mut_ptr())}!=0{return Err(failure("disk"))}
  let stat=unsafe{stat.assume_init()};let available=(stat.f_bavail as u64).saturating_mul(stat.f_frsize as u64);
  if available<need.saturating_add(16*1024*1024){return Err(failure("disk"))}
 }
 Ok(())
}
fn regular(path:&Path)->Result<u64>{
 let m=fs::symlink_metadata(path).map_err(|_|failure("unreadable"))?;
 if !m.is_file()||m.file_type().is_symlink(){return Err(failure("links"))}
 if m.len()>INPUT{return Err(failure("limits"))}Ok(m.len())
}
fn output_file(path:&Path)->Result<File>{
 if let Some(parent)=path.parent(){fs::create_dir_all(parent).map_err(|_|failure("disk"))?}
 fs::OpenOptions::new().write(true).create_new(true).open(path).map_err(|_|failure("collision"))
}
/// ZIP2 indexes duplicate central names by replacement. Independently walk ALL local
/// entries with the same maintained parser and compare exact central identities.
/// This rejects duplicate/hidden locals, encryption and mismatched directory records.
/// Streaming-data-descriptor ZIP variants unsupported by zip2 fail closed as corrupt.
fn zip_extract(input:&Path,dest:&Path,budget:&mut Budget)->Result<()>{
 let mut zip=ZipArchive::new(File::open(input).map_err(err)?).map_err(|_|failure("corrupt"))?;
 if zip.len()==0||zip.len()>COUNT||zip.offset()!=0{return Err(failure("limits"))}
 let mut paths=Paths::default();let mut declarations=BTreeMap::new();let mut total=0u64;let mut central=Vec::new();
 for i in 0..zip.len(){
  budget.check()?;
  let f=zip.by_index_raw(i).map_err(|_|failure("corrupt"))?;
  if f.encrypted(){return Err(failure("encrypted"))}
  // Account for every central record, including duplicates ZIP2's map hides.
  // Reject non-ASCII comments/Unicode metadata variants when raw lengths cannot
  // be represented faithfully by the parser; never guess offsets.
  if !f.comment().is_ascii(){return Err(failure("unsupported"))}
  central.push((f.central_header_start(),46+f.name_raw().len() as u64+f.extra_data().map_or(0,|x|x.len()) as u64+f.comment().len() as u64));
  let raw=std::str::from_utf8(f.name_raw()).map_err(|_|failure("unsafe_path"))?;
  let p=safe(raw)?;let mode=f.unix_mode().unwrap_or(0o100644);
  if !matches!(mode&0o170000,0|0o040000|0o100000)||f.is_symlink(){return Err(failure("links"))}
  if f.is_dir()&&f.size()!=0{return Err(failure("corrupt"))}
  paths.add(&p,f.is_dir())?;
  total=total.checked_add(f.size()).ok_or_else(||failure("limits"))?;
  if f.size()>INPUT||total>EXPANDED||f.size()>f.compressed_size().saturating_mul(200){return Err(failure("limits"))}
  declarations.insert(raw.to_owned(),(f.size(),f.crc32(),f.is_dir()));
 }
 paths.finish()?;
 central.sort();let mut end=zip.central_directory_start();
 for (start,len) in central{if start!=end{return Err(failure("collision"))}end=end.checked_add(len).ok_or_else(||failure("limits"))?;}
 let mut check=File::open(input).map_err(err)?;check.seek(SeekFrom::Start(end)).map_err(err)?;
 let mut signature=[0u8;4];check.read_exact(&mut signature).map_err(|_|failure("corrupt"))?;
 if signature!=[0x50,0x4b,0x05,0x06]{return Err(failure("collision"))}
 disk(dest,total.saturating_mul(2))?;
 // Preflight streams with an independent budget, so no header-only quota check.
 let mut local=File::open(input).map_err(err)?;let mut checked=HashSet::new();
 let mut scan=Budget{cancel:budget.cancel,bytes:0,count:0};
 loop{
  scan.check()?;
  let next=zip::read::read_zipfile_from_stream(&mut local).map_err(|_|failure("corrupt"))?;
  let Some(mut f)=next else{break};
  let raw=std::str::from_utf8(f.name_raw()).map_err(|_|failure("unsafe_path"))?.to_owned();
  if !checked.insert(raw.clone()){return Err(failure("collision"))}
  if declarations.get(&raw)!=Some(&(f.size(),f.crc32(),f.is_dir())){return Err(failure("corrupt"))}
  let size=f.size();scan.entry(size)?;scan.copy(&mut f,&mut io::sink(),size)?;
 }
 if checked.len()!=declarations.len(){return Err(failure("corrupt"))}
 for i in 0..zip.len(){
  budget.check()?;
  let mut f=zip.by_index(i).map_err(|_|failure("corrupt"))?;
  let p=safe(std::str::from_utf8(f.name_raw()).map_err(|_|failure("unsafe_path"))?)?;
  let out=dest.join(p);let size=f.size();budget.entry(size)?;
  if f.is_dir(){fs::create_dir_all(out).map_err(|_|failure("disk"))?}
  else{let mut file=output_file(&out)?;budget.copy(&mut f,&mut file,size)?;}
 } Ok(())
}
/// Uses the existing audited ar decoder and maintained tar/gzip/xz libraries.
/// Full tar stream is consumed (including end padding), bounded and cancellable.
fn deb_extract(input:&Path,dest:&Path,budget:&mut Budget)->Result<()>{
 regular(input)?;budget.check()?;
 let (name,data)=deb_data(input).map_err(|_|failure("corrupt"))?;
 let expanded_limit=INPUT.min((data.len() as u64).saturating_mul(200)).min(EXPANDED.saturating_sub(budget.bytes));
 let reader:Box<dyn Read>=match name.as_str(){
  "data.tar"=>Box::new(Cursor::new(data)),
  "data.tar.gz"=>Box::new(flate2::read::GzDecoder::new(Cursor::new(data))),
  "data.tar.xz"=>Box::new(lzma_rust2::XzReader::new_mem_limit(Cursor::new(data),false,64*1024)),
  _=>return Err(failure("compression"))
 };
 disk(dest.parent().ok_or_else(||failure("disk"))?,0)?;
 fs::create_dir(dest).map_err(|_|failure("disk"))?;
 let mut archive=tar::Archive::new(reader.take(expanded_limit+1));let mut paths=Paths::default();
 for entry in archive.entries().map_err(|_|failure("corrupt"))?{
  budget.check()?;let mut entry=entry.map_err(|_|failure("corrupt"))?;
  let raw=std::str::from_utf8(&entry.path_bytes()).map_err(|_|failure("unsafe_path"))?.to_owned();
  let kind=entry.header().entry_type();
  if (raw=="."||raw=="./")&&kind.is_dir(){continue}
  let clean=raw.strip_prefix("./").unwrap_or(&raw);let rel=safe(clean)?;
  if !kind.is_dir()&&!kind.is_file(){return Err(failure("links"))}
  paths.add(&rel,kind.is_dir())?;let size=entry.size();budget.entry(size)?;disk(dest,size)?;
  if kind.is_dir(){if size!=0{return Err(failure("corrupt"))}fs::create_dir_all(dest.join(rel)).map_err(|_|failure("disk"))?}
  else{let mut out=output_file(&dest.join(rel))?;budget.copy(&mut entry,&mut out,size)?;}
 }
 paths.finish()?;
 let mut reader=archive.into_inner();let mut buffer=[0u8;65536];
 // No unbounded trailing compressed bomb after the tar terminator.
 loop{budget.check()?;let n=reader.read(&mut buffer).map_err(|_|failure("corrupt"))?;if n==0{break}}
 if reader.limit()==0{return Err(failure("limits"))}
 Ok(())
}
#[derive(Serialize,Deserialize,Clone)]
pub(super) struct Candidate{
 pub id:String,pub path:String,pub name:String,pub kind:String,pub origin:String,
 pub sha256:String,pub identity:String,pub ambiguous:bool
}
fn fingerprint(root:&Path,budget:&mut Budget)->Result<String>{
 let mut files=Vec::new();
 if root.is_dir(){walk(root,&mut files)?;}else{files.push(root.to_owned())}
 files.sort();let mut digest=Sha256::new();let mut seen=Paths::default();
 for file in files{
  budget.check()?;let m=fs::symlink_metadata(&file).map_err(err)?;
  if m.file_type().is_symlink()||!(m.is_file()||m.is_dir()){return Err(failure("links"))}
  let rel=if file==root{root.file_name().unwrap().to_string_lossy().to_string()}else{file.strip_prefix(root).map_err(err)?.to_string_lossy().to_string()};
  let p=safe(&rel)?;seen.add(&p,m.is_dir())?;
  if root.is_dir(){digest.update(rel.as_bytes());digest.update([0]);}
  if m.is_file(){
   if m.len()>INPUT{return Err(failure("limits"))}
   let mut input=File::open(&file).map_err(err)?;let mut b=[0u8;65536];
   loop{budget.check()?;let n=input.read(&mut b).map_err(err)?;if n==0{break}digest.update(&b[..n]);}
  }
 }
 seen.finish()?;Ok(format!("{:x}",digest.finalize()))
}
fn candidates(root:&Path,session:&Path,origin:&str,budget:&mut Budget,result:&mut Vec<Candidate>)->Result<()>{
 let mut files=Vec::new();walk(root,&mut files)?;
 files.sort();
 for p in files{
  budget.check()?;
  let rel=p.strip_prefix(root).map_err(err)?;
  if rel.ancestors().skip(1).any(|p|p.extension().and_then(|s|s.to_str()).is_some_and(|s|s.eq_ignore_ascii_case("framework"))){continue}
  let ext=p.extension().and_then(|s|s.to_str()).unwrap_or("").to_lowercase();
  if !matches!(ext.as_str(),"dylib"|"framework"){continue}
  let code=if ext=="framework"&&p.is_dir(){p.join(framework_executable(&p).map_err(|_|failure("invalid_binary"))?)}else if ext=="dylib"&&p.is_file(){p.clone()}else{return Err(failure("invalid_binary"))};
  macho(read_macho(&code).map_err(|_|failure("invalid_binary"))?,true).map_err(|_|failure("invalid_binary"))?;
  let name=p.file_name().and_then(|s|s.to_str()).ok_or_else(||failure("unsafe_path"))?.to_owned();
  let id=p.strip_prefix(session).map_err(err)?.to_str().ok_or_else(||failure("unsafe_path"))?.to_owned();
  result.push(Candidate{id:id.clone(),path:id,name:name.clone(),kind:ext,origin:origin.into(),sha256:fingerprint(&p,budget)?,identity:fold(&name),ambiguous:false});
  if result.len()>CANDIDATES{return Err(failure("limits"))}
 } Ok(())
}
fn dedup(mut items:Vec<Candidate>)->Vec<Candidate>{
 // Direct code wins only an actual payload hash AND normalized install basename match.
 items.sort_by(|a,b|a.origin.starts_with("deb").cmp(&b.origin.starts_with("deb")).then(a.id.cmp(&b.id)));
 let mut seen=HashSet::new();
 items.retain(|c|seen.insert((c.kind.clone(),c.identity.clone(),c.sha256.clone())));
 for i in 0..items.len(){items[i].ambiguous=items.iter().enumerate().any(|(j,c)|i!=j&&c.identity==items[i].identity);}
 items
}
/// Caller owns a fresh managed session and a bounded snapshot at session/input.ext.
/// Every error removes all output, leaving snapshot/cancel for the owner to dispose.
pub(super) fn prepare(input:&Path,session:&Path,cancel:&Path)->Result<()>{
 let tree=session.join("contents");let manifests=session.join("candidates.json");
 if tree.exists()||manifests.exists(){return Err(failure("collision"))}
 let mut budget=Budget{cancel,bytes:0,count:0};
 let work=(||{
  budget.check()?;let size=if input.extension().and_then(|s|s.to_str()).is_some_and(|s|s.eq_ignore_ascii_case("framework")){0}else{regular(input)?};disk(session,size.saturating_mul(2))?;
  fs::create_dir(&tree).map_err(|_|failure("disk"))?;
  let ext=input.extension().and_then(|s|s.to_str()).unwrap_or("").to_lowercase();
  let mut result=Vec::new();
  match ext.as_str(){
   "zip"=>{
    zip_extract(input,&tree,&mut budget)?;
    candidates(&tree,session,"direct",&mut budget,&mut result)?;
    let mut entries=Vec::new();walk(&tree,&mut entries)?;
    let packages:Vec<_>=entries.into_iter().filter(|p|p.is_file()&&p.extension().and_then(|s|s.to_str()).is_some_and(|s|s.eq_ignore_ascii_case("deb"))&&!p.ancestors().any(|p|p.extension().and_then(|s|s.to_str()).is_some_and(|s|s.eq_ignore_ascii_case("framework")))).collect();
    for (i,p) in packages.iter().enumerate(){
     let out=session.join(format!("deb-{i}"));deb_extract(p,&out,&mut budget)?;
     candidates(&out,session,&format!("deb / {}",p.file_name().unwrap().to_string_lossy()),&mut budget,&mut result)?;
    }
   },
   "deb"=>{let out=session.join("deb-0");deb_extract(input,&out,&mut budget)?;candidates(&out,session,"deb",&mut budget,&mut result)?;},
   "framework"=>{candidates(input.parent().ok_or_else(||failure("unsafe_path"))?,session,"direct",&mut budget,&mut result)?;},
   "dylib"=>{
    // Snapshot name is preserved by Swift, including install basename.
    let out=tree.join(input.file_name().ok_or_else(||failure("unsafe_path"))?);safe(out.file_name().unwrap().to_str().ok_or_else(||failure("unsafe_path"))?)?;
    let mut f=File::open(input).map_err(err)?;let mut w=output_file(&out)?;budget.entry(size)?;budget.copy(&mut f,&mut w,size)?;
    candidates(&tree,session,"direct",&mut budget,&mut result)?;
   },
   _=>return Err(failure("unsupported"))
  }
  budget.check()?;let result=dedup(result);if result.is_empty(){return Err(failure("no_code"))}
  fs::write(&manifests,serde_json::to_vec(&result).map_err(err)?).map_err(|_|failure("disk"))
 })();
 if work.is_err(){
  let _=fs::remove_dir_all(&tree);let _=fs::remove_file(&manifests);
  if let Ok(entries)=fs::read_dir(session){for e in entries.flatten(){if e.file_name().to_string_lossy().starts_with("deb-"){let _=fs::remove_dir_all(e.path());}}}
 } work
}

#[cfg(test)]
#[path="tweak_import_tests.rs"]
mod tests;
