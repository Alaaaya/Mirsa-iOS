//! Read-only provenance graph and conservative all-slice editing on disposable copies.
//! A bundled dependency is never claimed to be an injected tweak.
use super::*;
use serde::{Serialize, Deserialize};
#[derive(Serialize, Clone)]
#[serde(rename_all="camelCase")]
pub(super) struct Library {
    id: String, owner: String, load_path: String, kind: String,
    bundled_path: Option<String>, provenance: String, slices: Vec<String>,
}
#[derive(Deserialize, Clone, Default)]
pub(super) struct Edit { pub owner: String, #[serde(default)] pub removed: Vec<String>, #[serde(default)] pub order: Vec<String> }
#[derive(Clone)]
struct Cmd { at:usize, size:usize, kind:u32, name:Option<String> }
fn load(k:u32)->bool { matches!(k,0xc|0x18|0x80000018|0x1f|0x8000001f|0x20|0x23|0x80000023) }
fn system(s:&str)->bool { s.starts_with("/System/Library/") || s.starts_with("/usr/lib/") }
fn word(d:&[u8],at:usize,n:usize,le:bool)->Result<u64>{
 let s=d.get(at..at.checked_add(n).ok_or("Offset overflow")?).ok_or("Truncated binary")?;
 Ok(if le{s.iter().enumerate().fold(0,|v,(i,b)|v|((*b as u64)<<(8*i)))}else{s.iter().fold(0,|v,b|(v<<8)|*b as u64)})
}
fn ranges(d:&[u8])->Result<Vec<(usize,usize)>> {
 let magic=d.get(..4).ok_or("Truncated Mach-O")?;
 let (wide,le)=match magic { [0xca,0xfe,0xba,0xbe]=>(false,false),[0xbe,0xba,0xfe,0xca]=>(false,true),[0xca,0xfe,0xba,0xbf]=>(true,false),[0xbf,0xba,0xfe,0xca]=>(true,true),_=>return Ok(vec![(0,d.len())]) };
 let count=word(d,4,4,le)? as usize;let stride=if wide{32}else{20};
 if count==0||count>128||8+count*stride>d.len(){return Err("Invalid FAT table".into())}
 let mut result=Vec::new();let mut cpus=HashSet::new();
 for i in 0..count {
  let a=8+i*stride;let cpu=word(d,a,4,le)?;let sub=word(d,a+4,4,le)?;
  if !cpus.insert((cpu,sub)){return Err("Duplicate FAT architecture".into())}
  let off=word(d,a+8,if wide{8}else{4},le)?;let size=word(d,a+if wide{16}else{12},if wide{8}else{4},le)?;let align=word(d,a+if wide{24}else{16},4,le)?;
  let end=off.checked_add(size).ok_or("FAT range overflow")?;
  if off< (8+count*stride) as u64||size<28||end>d.len() as u64||align>31||off%(1<<align)!=0||result.iter().any(|&(a,b)|off<(b as u64)&&end>(a as u64)){return Err("Invalid FAT slice bounds".into())}
  if wide&&word(d,a+28,4,le)?!=0{return Err("Invalid FAT reserved field".into())}
  let s=&d[off as usize..end as usize];
  let (thin64,little)=match &s[..4]{[0xcf,0xfa,0xed,0xfe]=>(true,true),[0xfe,0xed,0xfa,0xcf]=>(true,false),[0xce,0xfa,0xed,0xfe]=>(false,true),[0xfe,0xed,0xfa,0xce]=>(false,false),_=>return Err("Invalid FAT slice magic".into())};
  if (thin64&&size<32)||word(s,4,4,little)?!=cpu||word(s,8,4,little)?!=sub{return Err("Mismatched FAT slice architecture".into())}
  result.push((off as usize,end as usize));
 } Ok(result)
}
fn commands(d:&[u8])->Result<Vec<Cmd>> {
 if d.len()<32||d[..4]!=[0xcf,0xfa,0xed,0xfe]{return Err("Only 64-bit little-endian Mach-O library editing is supported".into())}
 let n=u32at(d,16)? as usize;let end=32usize.checked_add(u32at(d,20)? as usize).ok_or("Command overflow")?;
 if n>65536||end>d.len(){return Err("Invalid load table".into())}
 let mut at=32;let mut out=Vec::new();
 for _ in 0..n {
  if at+8>end{return Err("Truncated load table".into())}let k=u32at(d,at)?;let size=u32at(d,at+4)? as usize;
  if size<8||size%8!=0||size>end-at{return Err("Invalid load command bounds".into())}
  let name=if load(k)||k==0x8000001c {
   let minimum=if load(k){24}else{12};if size<minimum{return Err("Short path command".into())}
   let off=u32at(d,at+8)? as usize;if off<minimum||off>=size{return Err("Invalid command path offset".into())}
   let raw=&d[at+off..at+size];let len=raw.iter().position(|&b|b==0).ok_or("Unterminated load path")?;
   if len==0||len>4096{return Err("Invalid load path length".into())}
   Some(std::str::from_utf8(&raw[..len]).map_err(err)?.to_owned())
  }else{None};out.push(Cmd{at,size,kind:k,name});at+=size;
 }
 if at!=end{return Err("Load command count mismatch".into())}Ok(out)
}
fn safe_join(root:&Path,base:&Path,s:&str)->Result<Option<PathBuf>> {
 if s.contains(['\\','\0'])||s.starts_with('/') {return Ok(None)}
 let mut p=base.to_path_buf();for c in Path::new(s).components(){match c{Component::Normal(v)=>p.push(v),Component::CurDir=>{},Component::ParentDir=>{if p==root||!p.pop(){return Ok(None)}},_=>return Ok(None)}}
 if !p.starts_with(root){return Ok(None)}
 if p.is_file(){let c=fs::canonicalize(&p).map_err(err)?;if !c.starts_with(root){return Err("Dependency escapes app".into())}Ok(Some(c))}else{Ok(None)}
}
fn resolve(root:&Path,owner:&Path,name:&str,cmds:&[Cmd])->Result<Option<String>> {
 let executable_base=owner.ancestors().find(|p|p.extension().and_then(|s|s.to_str())==Some("appex")).unwrap_or(root);
 let expand=|s:&str|->Result<Option<PathBuf>>{
  if let Some(s)=s.strip_prefix("@loader_path/"){safe_join(root,owner.parent().unwrap(),s)}else if let Some(s)=s.strip_prefix("@executable_path/"){safe_join(root,executable_base,s)}else{Ok(None)}
 };
 let mut candidates=Vec::new();
 if let Some(s)=name.strip_prefix("@rpath/") {
  for c in cmds.iter().filter(|c|c.kind==0x8000001c){
   let r=c.name.as_ref().unwrap();let joined=format!("{}/{}",r.trim_end_matches('/'),s);
   if let Some(p)=expand(&joined)?{candidates.push(p)}
  }
  // Inherited rpaths are not guessed. Unresolved dependencies protect files.
 }else if let Some(p)=expand(name)?{candidates.push(p)}
 candidates.sort();candidates.dedup();
 Ok(if candidates.len()==1{Some(candidates[0].strip_prefix(root).map_err(err)?.to_str().ok_or("Non UTF8 path")?.into())}else{None})
}
fn binaries(app:&Path)->Result<Vec<PathBuf>> {
 checked_tree(app)?;let mut files=Vec::new();walk(app,&mut files)?;
 let mut out=Vec::new();for p in files {if !p.is_file(){continue}let mut f=File::open(&p).map_err(err)?;let mut magic=[0;4];if f.read(&mut magic).map_err(err)?!=4{continue}
 if matches!(magic,[0xcf,0xfa,0xed,0xfe]|[0xca,0xfe,0xba,0xbe]|[0xbe,0xba,0xfe,0xca]|[0xca,0xfe,0xba,0xbf]|[0xbf,0xba,0xfe,0xca]){out.push(p)}
 }out.sort();Ok(out)
}
fn graph(app:&Path)->Result<Vec<Library>> {
 checked_tree(app)?;let app=fs::canonicalize(app).map_err(err)?;let mut out:Vec<Library>=Vec::new();
 for p in binaries(&app)? {
  let d=read_macho(&p)?;let owner=p.strip_prefix(&app).map_err(err)?.to_str().ok_or("Non UTF8 owner")?.to_owned();
  for (a,b) in ranges(&d)? {let s=&d[a..b];if s[..4]!=[0xcf,0xfa,0xed,0xfe]{continue}let cmds=commands(s)?;let arch=format!("{:x}:{:x}",u32at(s,4)?,u32at(s,8)?);
   for c in cmds.iter().filter(|c|load(c.kind)) {let name=c.name.as_ref().unwrap();if system(name){continue}let id=format!("{owner}|{name}");let resolved=resolve(&app,&p,name,&cmds)?;
    let index=out.iter().position(|l|l.id==id).unwrap_or(out.len());
    if index==out.len(){if out.len()>=32768{return Err("Dependency graph exceeds safe limits".into())}out.push(Library{id,owner:owner.clone(),load_path:name.clone(),kind:match c.kind{0xc=>"load",0x18|0x80000018=>"weak",0x1f|0x8000001f=>"reexport",0x20=>"lazy",_=>"upward"}.into(),bundled_path:resolved.clone(),provenance:if resolved.is_some(){"bundledDependency"}else{"unresolvedDependency"}.into(),slices:Vec::new()});}
    let entry=&mut out[index];
    if entry.bundled_path!=resolved {entry.bundled_path=None;entry.provenance="unresolvedDependency".into()}
    if !entry.slices.contains(&arch){entry.slices.push(arch.clone())}
   }
  }
 }Ok(out)
}
pub(super) fn inspect(app:&Path,out:&Path)->Result<()> {fs::write(out,serde_json::to_vec(&graph(app)?).map_err(err)?).map_err(err)}
fn mapped(old:u64,map:&[Option<u64>])->Result<u64>{
 if old==0{return Ok(0)}map.get(old as usize).copied().flatten().ok_or_else(||"This library still has linked symbols. Removing it would break the app; keep it or rebuild the app without this dependency.".into())
}
fn uleb(d:&[u8],at:&mut usize,end:usize)->Result<u64>{
 let mut v=0u64;for i in 0..10 {if *at>=end{return Err("Truncated ULEB".into())}let b=d[*at];*at+=1;if i==9&&b>1{return Err("ULEB overflow".into())}v|=((b&127)as u64)<<(i*7);if b&128==0{return Ok(v)}}Err("ULEB overflow".into())
}
fn replace_uleb(d:&mut[u8],start:usize,end:usize,v:u64)->Result<()> {
 let mut n=v;let mut out=Vec::new();loop{let b=(n&127)as u8;n>>=7;out.push(b|if n!=0{128}else{0});if n==0{break}}
 if out.len()!=end-start{return Err("Ordinal remap would resize binary metadata; this library order is unsupported".into())}d[start..end].copy_from_slice(&out);Ok(())
}
fn checked_region(d:&[u8],off:u32,len:u32,header:usize)->Result<(usize,usize)>{
 let a=off as usize;let b=a.checked_add(len as usize).ok_or("Metadata overflow")?;
 if len>0&&(a<header||b>d.len()){return Err("Invalid linked metadata bounds".into())}Ok((a,b))
}
fn bind(d:&mut[u8],a:usize,b:usize,map:&[Option<u64>])->Result<()> {
 let mut p=a;let mut current=Some(0u64);
 while p<b {let pos=p;let op=d[p];p+=1;match op&0xf0 {
  0x00=>{current=Some(0)},
  0x10=>{let old=(op&15)as u64;current=Some(old);let new=map.get(old as usize).copied().flatten().unwrap_or(0);if new>15{return Err("Ordinal needs larger bind opcode; reorder unsupported".into())}d[pos]=0x10|new as u8},
  0x20=>{let start=p;let old=uleb(d,&mut p,b)?;current=Some(old);let new=map.get(old as usize).copied().flatten().unwrap_or(0);replace_uleb(d,start,p,new)?},
  0x30=>{current=None}, // special negative ordinals are unchanged
  0x40=>{while p<b&&d[p]!=0{p+=1}if p==b{return Err("Unterminated bind symbol".into())}p+=1},
  0x50=>{},
  0x60=>{ // signed LEB addend, consumed with bounded continuation
   let start=p;while p<b {let x=d[p];p+=1;if x&128==0{break}if p-start>=10{return Err("Bind addend overflow".into())}}
   if p==start||d[p-1]&128!=0{return Err("Truncated bind addend".into())}
  },
  0x70|0x80=>{uleb(d,&mut p,b)?;},
  0x90|0xa0|0xb0|0xc0=>{if let Some(old)=current{mapped(old,map)?;}if matches!(op&0xf0,0xa0|0xc0){uleb(d,&mut p,b)?;}if op&0xf0==0xc0{uleb(d,&mut p,b)?;}},
  _=>return Err("Threaded or unknown dyld binding format cannot safely reorder libraries".into())
 }}Ok(())
}
fn exports(d:&mut[u8],a:usize,b:usize,map:&[Option<u64>])->Result<()> {
 if a==b{return Ok(())}let mut pending=vec![a];let mut seen=HashSet::new();
 while let Some(mut p)=pending.pop(){if !seen.insert(p){continue}if seen.len()>100000||p<a||p>=b{return Err("Invalid export trie".into())}
  let size=uleb(d,&mut p,b)? as usize;let end=p.checked_add(size).ok_or("Export overflow")?;if end>=b{return Err("Truncated export node".into())}
  if size>0 {let mut q=p;let flags=uleb(d,&mut q,end)?;if flags&8!=0 {let start=q;let old=uleb(d,&mut q,end)?;replace_uleb(d,start,q,mapped(old,map)?)?;}}
  p=end;let count=d[p];p+=1;for _ in 0..count{while p<b&&d[p]!=0{p+=1}if p>=b{return Err("Truncated export edge".into())}p+=1;let off=uleb(d,&mut p,b)?;let off=usize::try_from(off).map_err(err)?;pending.push(a.checked_add(off).ok_or("Export offset overflow")?);}
 }Ok(())
}
fn register(regions:&mut Vec<(usize,usize,u8)>,a:usize,b:usize,kind:u8)->Result<bool>{
 if a==b{return Ok(false)}
 if regions.contains(&(a,b,kind)){return Ok(false)}
 if regions.iter().any(|&(x,y,_)|a<y&&b>x){return Err("Overlapping ordinal metadata cannot safely be edited".into())}
 regions.push((a,b,kind));Ok(true)
}
fn ordinals(d:&mut[u8],cmds:&[Cmd],map:&[Option<u64>],header:usize)->Result<()> {
 let mut regions=Vec::new();
 for c in cmds {match c.kind {
  0x21|0x2c=>{if c.size<20||u32at(d,c.at+16)?!=0{return Err("Encrypted binary library editing is not supported".into())}},
  0x22|0x80000022=>{
   if c.size<48{return Err("Short dyld info".into())}
   for off in [16,24,32] {let(a,b)=checked_region(d,u32at(d,c.at+off)?,u32at(d,c.at+off+4)?,header)?;if register(&mut regions,a,b,1)?{bind(d,a,b,map)?;}}
   let(a,b)=checked_region(d,u32at(d,c.at+40)?,u32at(d,c.at+44)?,header)?;if register(&mut regions,a,b,2)?{exports(d,a,b,map)?;}
  },
  0x80000033=>{if c.size<16{return Err("Short export trie command".into())}let(a,b)=checked_region(d,u32at(d,c.at+8)?,u32at(d,c.at+12)?,header)?;if register(&mut regions,a,b,2)?{exports(d,a,b,map)?}},
  0x80000034=>{
   if c.size<16{return Err("Short chained fixups command".into())}
   let(a,b)=checked_region(d,u32at(d,c.at+8)?,u32at(d,c.at+12)?,header)?;
   if !register(&mut regions,a,b,3)?{continue}
   if b-a<28||u32at(d,a)?!=0{return Err("Unsupported chained fixups header".into())}
   let start=a.checked_add(u32at(d,a+8)? as usize).ok_or("Import overflow")?;let count=u32at(d,a+16)? as usize;let format=u32at(d,a+20)?;
   let stride=match format{1=>4,2=>8,3=>16,_=>return Err("Unsupported chained import format".into())};
   if start<a+28||count>1000000||start.checked_add(count*stride).ok_or("Import overflow")?>b{return Err("Chained imports outside metadata".into())}
   for i in 0..count{let p=start+i*stride;if format==3 {let raw=word(d,p,8,true)?;let old=(raw&65535) as u64;if old>0&&old<=0xfff0{let new=mapped(old as u64,map)?;if new>0xfff0{return Err("Chained ordinal overflow".into())}let v=(raw&!65535)|new;d[p..p+8].copy_from_slice(&v.to_le_bytes())}}
    else {let raw=u32at(d,p)?;let old=(raw&255) as u64;if old>0&&old<=0xf0{let new=mapped(old as u64,map)?;if new>0xf0{return Err("Chained ordinal overflow".into())}put32(d,p,(raw&!255)|new as u32)}}
   }
  },
  0x2=>{
   if c.size<24{return Err("Short symbol command".into())}let start=u32at(d,c.at+8)? as usize;let n=u32at(d,c.at+12)? as usize;
   if n>10000000||start.checked_add(n*16).ok_or("Symbol overflow")?>d.len()||(n>0&&start<header){return Err("Invalid symbol table".into())}
   if !register(&mut regions,start,start+n*16,4)?{continue}
   for i in 0..n{let p=start+i*16;let ty=d[p+4];if ty&0xe0!=0||!matches!(ty&0xe,0|0xc){continue}let old=d[p+7];if old>0&&old<0xfe {let new=mapped(old as u64,map)?;if new>=0xfe{return Err("Symbol ordinal overflow".into())}d[p+7]=new as u8}}
  },
  0x13|0x14|0x15|0x16=>return Err("Sub-library and umbrella linkage cannot safely reorder dependencies".into()),
  _=>{}
 }}Ok(())
}
fn rewrite(d:&[u8],edit:&Edit)->Result<Vec<u8>> {
 let cmds=commands(d)?;let old:Vec<_>=cmds.iter().filter(|c|load(c.kind)).collect();
 let names:HashSet<_>=old.iter().map(|c|c.name.as_ref().unwrap().as_str()).collect();
 if old.len()!=names.len(){return Err("Duplicate dependency load commands cannot safely be edited".into())}
 let removed:HashSet<_>=edit.removed.iter().map(String::as_str).collect();let order:HashSet<_>=edit.order.iter().map(String::as_str).collect();
 if removed.len()!=edit.removed.len()||order.len()!=edit.order.len()||removed.intersection(&order).next().is_some(){return Err("Duplicate or conflicting library edit".into())}
 let mut remaining:Vec<_>=old.iter().copied().filter(|c|!removed.contains(c.name.as_ref().unwrap().as_str())).collect();
 remaining.sort_by_key(|c|edit.order.iter().position(|n|Some(n)==c.name.as_ref()).unwrap_or(usize::MAX));
 let mut map=vec![Some(0)];for c in &old{map.push(remaining.iter().position(|r|r.at==c.at).map(|i|(i+1)as u64))}
 if map.iter().enumerate().all(|(i,v)|*v==Some(i as u64)){return Ok(d.to_vec())}
 let mut out=d.to_vec();let end=32+u32at(d,20)? as usize;ordinals(&mut out,&cmds,&map,end)?;
 let mut iter=remaining.into_iter();let mut packed=Vec::new();let mut count=0;
 for c in &cmds {let chosen=if load(c.kind){iter.next()}else{Some(c)};if let Some(c)=chosen{packed.extend_from_slice(&out[c.at..c.at+c.size]);count+=1}}
 out[32..end].fill(0);out[32..32+packed.len()].copy_from_slice(&packed);put32(&mut out,16,count);put32(&mut out,20,packed.len() as u32);Ok(out)
}
pub(super) fn apply(app:&Path,edits:&[Edit])->Result<()> {
 if edits.len()>4096{return Err("Too many library edits".into())}let original=graph(app)?;let app=fs::canonicalize(app).map_err(err)?;let mut owners=HashSet::new();let mut patches=BTreeMap::new();
 for edit in edits {
  if !owners.insert(&edit.owner)||edit.removed.len()+edit.order.len()>8192{return Err("Invalid library edits".into())}
  let rel=relative(&edit.owner)?;if rel.to_str()!=Some(edit.owner.as_str()){return Err("Noncanonical owner path".into())}
  for name in edit.removed.iter().chain(&edit.order){if !original.iter().any(|l|l.owner==edit.owner&&l.load_path==*name){return Err("Library edit references unknown or system dependency".into())}}
  if !original.iter().any(|l|l.owner==edit.owner){return Err("Unknown library owner".into())}
  let path=app.join(rel);let mut d=read_macho(&path)?;for(a,b)in ranges(&d)?{if d[a..a+4]!=[0xcf,0xfa,0xed,0xfe]{continue}let updated=rewrite(&d[a..b],edit)?;d[a..b].copy_from_slice(&updated)}patches.insert(path,d);
 }
 let mut candidates=HashSet::new();
 for l in &original {if edits.iter().any(|e|e.owner==l.owner&&e.removed.contains(&l.load_path)){if let Some(p)=&l.bundled_path{candidates.insert(p.clone());}}}
 // Validate the prospective reference graph on bytes before any write. Retain a
 // candidate whenever ANY unresolved reference exists: inherited rpaths/dlopen
 // cannot be proven absent. Only delete standalone dylibs, never framework trees.
 let mut retained=HashSet::new();let mut unresolved=false;
 for p in binaries(&app)? {let original_bytes=read_macho(&p)?;let d=patches.get(&p).unwrap_or(&original_bytes);for(a,b)in ranges(d)?{if d[a..a+4]!=[0xcf,0xfa,0xed,0xfe]{unresolved=true;continue}let cmds=commands(&d[a..b])?;for c in cmds.iter().filter(|c|load(c.kind)) {let n=c.name.as_ref().unwrap();if system(n){continue}match resolve(&app,&p,n,&cmds)?{Some(r)=>{retained.insert(r);},None=>unresolved=true}}}}
 let deletions:Vec<_>=candidates.into_iter().filter(|p|!unresolved&&!retained.contains(p)&&p.ends_with(".dylib")&&!p.split('/').any(|c|c.ends_with(".framework"))&&!patches.contains_key(&app.join(p))).collect();
 // All validation/remapping finishes before the first write. Caller discards the
 // entire disposable extraction on IO error. Framework resources and unresolved
 // or shared references are conservatively retained. Original IPA is untouched.
 for(p,d)in patches{fs::write(p,d).map_err(err)?}
 for p in deletions{fs::remove_file(app.join(p)).map_err(err)?}Ok(())
}
#[cfg(test)]
mod tests {
 use super::*;
 fn command(kind:u32,name:&str)->Vec<u8>{let size=(24+name.len()+1+7)&!7;let mut d=vec![0;size];put32(&mut d,0,kind);put32(&mut d,4,size as u32);put32(&mut d,8,24);d[24..24+name.len()].copy_from_slice(name.as_bytes());d}
 fn fixture(loads:&[(u32,&str)],meta:&[Vec<u8>])->Vec<u8>{let mut d=vec![0;4096];put32(&mut d,0,0xfeedfacf);put32(&mut d,4,0x100000c);put32(&mut d,12,2);let mut at=32;for c in loads.iter().map(|(k,n)|command(*k,n)).chain(meta.iter().cloned()){d[at..at+c.len()].copy_from_slice(&c);at+=c.len();}put32(&mut d,16,(loads.len()+meta.len())as u32);put32(&mut d,20,(at-32)as u32);d}
 fn cmd(kind:u32,size:usize)->Vec<u8>{let mut c=vec![0;size];put32(&mut c,0,kind);put32(&mut c,4,size as u32);c}
 fn names(d:&[u8])->Vec<String>{commands(d).unwrap().into_iter().filter(|c|load(c.kind)).map(|c|c.name.unwrap()).collect()}
 fn edit(remove:&[&str],order:&[&str])->Edit{Edit{owner:"Main".into(),removed:remove.iter().map(|s|s.to_string()).collect(),order:order.iter().map(|s|s.to_string()).collect()}}
 fn linked()->Vec<u8>{
  let mut dyld=cmd(0x80000022,48);put32(&mut dyld,16,1024);put32(&mut dyld,20,6);
  let mut sym=cmd(2,24);put32(&mut sym,8,1100);put32(&mut sym,12,1);
  let mut d=fixture(&[(0xc,"@rpath/Unused.dylib"),(0xc,"/usr/lib/libSystem.B.dylib"),(0x80000018,"@rpath/Feature.dylib")],&[dyld,sym]);
  d[1024..1030].copy_from_slice(&[0x12,0x40,b'x',0,0x90,0]);d[1104]=1;d[1107]=2;d
 }
 #[test] fn ordinary_classic_linked_dependency_remove_and_reorder_preserves_binding(){
  let d=linked();let r=rewrite(&d,&edit(&["@rpath/Unused.dylib"],&["@rpath/Feature.dylib"])).unwrap();
  assert_eq!(names(&r),vec!["@rpath/Feature.dylib","/usr/lib/libSystem.B.dylib"]);assert_eq!(r[1024],0x12);assert_eq!(r[1107],2);
  let r=rewrite(&d,&edit(&["@rpath/Unused.dylib"],&[])).unwrap();assert_eq!(r[1024],0x11);assert_eq!(r[1107],1);assert_eq!(d,linked());
  let err=rewrite(&d,&edit(&["/usr/lib/libSystem.B.dylib"],&[])).unwrap_err();assert!(err.contains("linked symbols"));
 }
 #[test] fn lazy_commands_are_counted_in_ordinals(){
  let mut d=linked();let c=commands(&d).unwrap();put32(&mut d,c[0].at,0x20);let r=rewrite(&d,&edit(&["@rpath/Unused.dylib"],&[])).unwrap();assert_eq!(r[1024],0x11);assert_eq!(r[1107],1);
 }
 fn chained(format:u32,ordinal:u32)->Vec<u8>{
  let owned:Vec<String>=(1..=130).map(|i|format!("@rpath/L{i}.dylib")).collect();let loads:Vec<_>=owned.iter().map(|s|(0xc,s.as_str())).collect();
  let mut c=cmd(0x80000034,16);put32(&mut c,8,12000);put32(&mut c,12,64);
  let mut d=fixture(&[],&[]);d.resize(16384,0);let mut all=Vec::new();for(k,n)in loads{all.extend(command(k,n))}all.extend(c);d[32..32+all.len()].copy_from_slice(&all);put32(&mut d,16,131);put32(&mut d,20,all.len()as u32);put32(&mut d,12008,28);put32(&mut d,12016,1);put32(&mut d,12020,format);put32(&mut d,12028,ordinal);d
 }
 #[test] fn chained_import_formats_remap_positive_128_and_special_ordinals(){
  for format in [1,2,3]{let d=chained(format,128);let r=rewrite(&d,&edit(&[],&["@rpath/L128.dylib"])).unwrap();assert_eq!(r[12028],1);assert!(rewrite(&d,&edit(&["@rpath/L128.dylib"],&[])).unwrap_err().contains("linked symbols"));
   let special=if format==3{0xffff}else{0xff};let d=chained(format,special);let r=rewrite(&d,&edit(&[],&["@rpath/L128.dylib"])).unwrap();assert_eq!(u32at(&r,12028).unwrap(),special);
  }
 }
 #[test] fn aliased_export_metadata_is_remapped_once_and_overlaps_rejected(){
  let mut a=cmd(0x80000022,48);put32(&mut a,40,1024);put32(&mut a,44,5);let mut b=cmd(0x80000033,16);put32(&mut b,8,1024);put32(&mut b,12,5);
  let mut d=fixture(&[(0xc,"A"),(0xc,"B")],&[a,b]);d[1024..1029].copy_from_slice(&[3,8,1,0,0]);let r=rewrite(&d,&edit(&[],&["B","A"])).unwrap();assert_eq!(r[1026],2);
  let c=commands(&d).unwrap();put32(&mut d,c[3].at+8,1025);assert!(rewrite(&d,&edit(&[],&["B","A"])).unwrap_err().contains("Overlapping"));
 }
 fn fat(slices:&[Vec<u8>])->Vec<u8>{let mut d=vec![0;4096];d[..4].copy_from_slice(&[0xca,0xfe,0xba,0xbe]);d[4..8].copy_from_slice(&(slices.len()as u32).to_be_bytes());for(i,s)in slices.iter().enumerate(){let a=8+i*20;let off=d.len();for(o,v)in [(0,0x100000c),(4,u32at(s,8).unwrap()),(8,off as u32),(12,s.len()as u32),(16,12)]{d[a+o..a+o+4].copy_from_slice(&v.to_be_bytes())}d.extend(s);d.resize((d.len()+4095)&!4095,0)}d}
 fn dir()->PathBuf{let p=std::env::temp_dir().join(format!("mirsa-existing-{}-{}",std::process::id(),std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).unwrap().as_nanos()));fs::create_dir_all(&p).unwrap();p}
 #[test] fn graph_all_fat_slices_framework_owners_shared_remove_and_reset(){
  let root=dir();fs::create_dir_all(root.join("Frameworks/F.framework")).unwrap();let one=fixture(&[(0xc,"@executable_path/Frameworks/Shared.dylib"),(0xc,"/usr/lib/libSystem.B.dylib")],&[]);let mut two=one.clone();put32(&mut two,8,2);let original=fat(&[one,two]);fs::write(root.join("Main"),&original).unwrap();fs::write(root.join("Frameworks/F.framework/F"),fixture(&[(0x8000001f,"@executable_path/Frameworks/Shared.dylib")],&[])).unwrap();fs::write(root.join("Frameworks/Shared.dylib"),fixture(&[],&[])).unwrap();
  let g=graph(&root).unwrap();assert_eq!(g.len(),2);assert_eq!(g.iter().find(|l|l.owner=="Main").unwrap().slices.len(),2);assert!(g.iter().all(|l|l.provenance=="bundledDependency"));
  apply(&root,&[edit(&["@executable_path/Frameworks/Shared.dylib"],&[])]).unwrap();assert!(root.join("Frameworks/Shared.dylib").exists());let d=fs::read(root.join("Main")).unwrap();for(a,b)in ranges(&d).unwrap(){assert_eq!(names(&d[a..b]),vec!["/usr/lib/libSystem.B.dylib"])}
  fs::write(root.join("Main"),&original).unwrap();apply(&root,&[]).unwrap();assert_eq!(fs::read(root.join("Main")).unwrap(),original);fs::remove_dir_all(root).unwrap();
 }
 #[test] fn unreferenced_standalone_deleted_but_unresolved_protects(){
  for unresolved in [false,true]{let root=dir();fs::create_dir(root.join("Frameworks")).unwrap();let mut loads=vec![(0xc,"@executable_path/Frameworks/Only.dylib")];if unresolved{loads.push((0xc,"@rpath/Mystery.dylib"))}fs::write(root.join("Main"),fixture(&loads,&[])).unwrap();fs::write(root.join("Frameworks/Only.dylib"),fixture(&[],&[])).unwrap();apply(&root,&[edit(&["@executable_path/Frameworks/Only.dylib"],&[])]).unwrap();assert_eq!(root.join("Frameworks/Only.dylib").exists(),unresolved);fs::remove_dir_all(root).unwrap();}
 }
 #[test] fn malformed_and_unsafe_edits_never_change_original(){
  let root=dir();let original=linked();fs::write(root.join("Main"),&original).unwrap();for e in [edit(&["/usr/lib/libSystem.B.dylib"],&[]),edit(&["unknown"],&[]),Edit{owner:"../Main".into(),..Edit::default()}]{assert!(apply(&root,&[e]).is_err());assert_eq!(fs::read(root.join("Main")).unwrap(),original)}
  let mut bad=original.clone();put32(&mut bad,36,u32::MAX);assert!(commands(&bad).is_err());let mut bad=fat(&[original.clone()]);bad[16..20].copy_from_slice(&0u32.to_be_bytes());assert!(ranges(&bad).is_err());
  #[cfg(unix)]{std::os::unix::fs::symlink(root.join("Main"),root.join("Link")).unwrap();assert!(graph(&root).is_err());}
  fs::remove_dir_all(root).unwrap();
 }
 #[test] fn threaded_bind_and_resize_fail_closed(){let mut d=linked();d[1024]=0xd0;assert!(rewrite(&d,&edit(&["@rpath/Unused.dylib"],&[])).unwrap_err().contains("Threaded"));assert!(replace_uleb(&mut [0;2],0,2,1).is_err());}
}
