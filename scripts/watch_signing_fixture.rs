
#[cfg(test)]
mod watch_regression {
 use super::*;
 use apple_codesign_quick::{BundleSigningSettings,CmsSigner,CmsSigningRequest,sign_bundle};
 use sha2::Digest;
 use std::sync::Mutex;
 fn le(d:&[u8],a:usize)->usize{u32::from_le_bytes(d[a..a+4].try_into().unwrap()) as usize}
 fn be(d:&[u8],a:usize)->usize{u32::from_be_bytes(d[a..a+4].try_into().unwrap()) as usize}
 fn put(d:&mut[u8],a:usize,v:u32){d[a..a+4].copy_from_slice(&v.to_le_bytes())}
 // No instructions or copyrighted executable data. Header padding is real,
 // LC_CODE_SIGNATURE absent until the production signer allocates it.
 fn thin(wide:bool,cryptid:u32)->Vec<u8>{
  let mut d=vec![0;545]; let h=if wide{32}else{28};let seg=if wide{72}else{56};
  put(&mut d,0,if wide{0xfeedfacf}else{0xfeedface});
  put(&mut d,4,if wide{0x0100000c}else{0x0200000c});
  put(&mut d,12,2);put(&mut d,16,3);
  put(&mut d,20,(seg*2+if wide{24}else{20}) as u32);
  for (i,name) in ["__TEXT","__LINKEDIT"].iter().enumerate(){
   let a=h+i*seg;put(&mut d,a,if wide{0x19}else{1});put(&mut d,a+4,seg as u32);
   d[a+8..a+8+name.len()].copy_from_slice(name.as_bytes());
   let (off,len)=if i==0{(0,512)}else{(512,33)};
   if wide{put(&mut d,a+32,16384);put(&mut d,a+40,off);put(&mut d,a+48,len)}
   else{put(&mut d,a+28,16384);put(&mut d,a+32,off);put(&mut d,a+36,len)}
  }
  let a=h+seg*2;put(&mut d,a,if wide{0x2c}else{0x21});
  put(&mut d,a+4,if wide{24}else{20});put(&mut d,a+8,384);
  put(&mut d,a+12,64);put(&mut d,a+16,cryptid);
  d[384..448].fill(0xa7);d[512..].fill(0x5b);d
 }
 fn fat(first:u32,second:u32)->Vec<u8>{
  let slices=[thin(true,first),thin(false,second)];let mut d=vec![0;8192+545];
  d[..4].copy_from_slice(&0xcafebabeu32.to_be_bytes());d[4..8].copy_from_slice(&2u32.to_be_bytes());
  for (i,s) in slices.iter().enumerate(){
   let a=8+i*20;let off=4096*(i+1);
   for (delta,v) in [(0,le(s,4) as u32),(4,0),(8,off as u32),(12,s.len() as u32),(16,12)]{
    d[a+delta..a+delta+4].copy_from_slice(&v.to_be_bytes());
   }
   d[off..off+s.len()].copy_from_slice(s);
  }d
 }
 fn slices(d:&[u8])->Vec<&[u8]>{
  if be(d,0)==0xcafebabe{(0..be(d,4)).map(|i|{
   let a=8+i*20; &d[be(d,a+8)..be(d,a+8)+be(d,a+12)]
  }).collect()}else{vec![d]}
 }
 fn commands(d:&[u8])->Vec<(usize,usize)>{
  let mut a=if le(d,0)==0xfeedfacf{32}else{28};
  (0..le(d,16)).map(|_|{let r=(le(d,a),a);a+=le(d,a+4);r}).collect()
 }
 fn blobs(d:&[u8])->BTreeMap<usize,&[u8]>{
  let a=commands(d).into_iter().find(|(k,_)|*k==0x1d).unwrap().1;
  let s=&d[le(d,a+8)..le(d,a+8)+le(d,a+12)];
  assert_eq!(be(s,0),0xfade0cc0);
  (0..be(s,8)).map(|i|{
   let k=be(s,12+i*8);let a=be(s,16+i*8);(k,&s[a..a+be(s,a+4)])
  }).collect()
 }
 fn digest(kind:u8,d:&[u8])->Vec<u8>{
  match kind{1=>sha1::Sha1::digest(d).to_vec(),2=>sha2::Sha256::digest(d).to_vec(),_=>panic!("unexpected hash")}
 }
 fn verify(d:&[u8],bundle:&Path,ent:&Dictionary){
  let parts=slices(d);assert!(!parts.is_empty());
  for s in parts{
   let b=blobs(s);let cms=b.get(&0x10000).expect("CMS missing");assert_eq!(&cms[8..],&[0x30,0]);
   let xml=&b[&5][8..];let parsed:Dictionary=plist::from_bytes(xml).unwrap();assert_eq!(&parsed,ent);
   let mut directories=0;
   for (k,cd) in &b{
    if *k!=0 && !(*k>=0x1000&&*k<0x1005){continue}
    directories+=1;assert_eq!(be(cd,0),0xfade0c02);
    let (ho,nc,limit,hs,ht,page)=(be(cd,16),be(cd,28),be(cd,32),cd[36] as usize,cd[37],1usize<<cd[39]);
    assert_eq!(nc,limit.div_ceil(page));
    for i in 0..nc{assert_eq!(&cd[ho+i*hs..ho+(i+1)*hs],digest(ht,&s[i*page..limit.min((i+1)*page)]))}
    for slot in 1..=be(cd,24){
     let data=match slot{
      1=>Some(fs::read(bundle.join("Info.plist")).unwrap()),
      3=>Some(fs::read(bundle.join("_CodeSignature/CodeResources")).unwrap()),
      2|5|7=>b.get(&slot).map(|v|v.to_vec()),_=>None};
     let want=data.map(|v|digest(ht,&v)).unwrap_or(vec![0;hs]);
     assert_eq!(&cd[ho-slot*hs..ho-(slot-1)*hs],want,"special slot {slot}");
    }
   }assert_eq!(directories,2,"every slice has SHA1 and SHA256 directories");
  }
 }
 struct TestCms(Mutex<Vec<String>>);
 impl CmsSigner for TestCms{
  fn sign(&self,r:CmsSigningRequest<'_>)->apple_codesign_quick::Result<Vec<u8>>{
   let cd=r.code_directories[0].bytes;let a=be(cd,20);let end=cd[a..].iter().position(|b|*b==0).unwrap()+a;
   self.0.lock().unwrap().push(String::from_utf8(cd[a..end].to_vec()).unwrap());Ok(vec![0x30,0])
  }
 }
 struct Fixture(PathBuf);
 impl Drop for Fixture{fn drop(&mut self){fs::remove_dir_all(&self.0).unwrap()}}
 fn fixture(second:u32)->Fixture{
  let f=Fixture(std::env::temp_dir().join(format!("clean-watch-{}-{}",std::process::id(),std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).unwrap().as_nanos())).join("Fixture.app"));
  for (rel,id,data) in [
   ("","com.fixture.ios",thin(true,0)),
   ("Watch/FixtureWatch.app","com.fixture.ios.watch",fat(0,second)),
   ("Watch/FixtureWatch.app/PlugIns/WatchExtension.appex","com.fixture.ios.watch.extension",thin(false,0)),
   ("AppClips/Clip.app","com.fixture.ios.clip",thin(true,0))]{
   let p=f.0.join(rel);fs::create_dir_all(&p).unwrap();
   let info=Dictionary::from_iter([("CFBundleIdentifier",Value::from(id)),("CFBundleExecutable",Value::from("Fixture"))]);
   Value::Dictionary(info).to_file_xml(p.join("Info.plist")).unwrap();
   fs::write(p.join("Fixture"),data).unwrap();fs::write(p.join("Resource.txt"),id).unwrap();
  }f
 }
 #[test] fn watch_encryption_warning_checks_cryptid_in_all_slices_not_range_length(){
  let f=fixture(0);let o=Options::default();
  let r=ipa_editor::signing_encryption(&f.0,&o).unwrap();assert!(!r.main_encrypted);assert_eq!(r.embedded_encrypted,0);
  let p=f.0.join("Watch/FixtureWatch.app/Fixture");fs::write(&p,fat(0,1)).unwrap();
  let r=ipa_editor::signing_encryption(&f.0,&o).unwrap();assert_eq!(r.embedded_encrypted,1);
  assert!(ipa_editor::unencrypted(&fs::read(&p).unwrap()).is_err(),"editing restriction");
  let mut bad=fat(1,0);put(&mut bad,8192+28+4,3);
  assert!(ipa_editor::encryption_status(&bad).is_err(),"encrypted first slice cannot hide corrupt second");
  assert!(nested::read_entitlements(&bad).is_err());
  fs::write(&p,bad).unwrap();assert!(ipa_editor::signing_encryption(&f.0,&o).is_err());
 }
 #[test] fn watch_nested_tree_signs_all_slices_profiles_entitlements_then_seals_final_bytes(){
  for encrypted in [0,1]{
   let f=fixture(encrypted);let o=Options::default();
   let nodes=nested::inventory(&f.0,&o).unwrap();assert_eq!(nodes.len(),4);
   let signer=TestCms(Mutex::new(vec![]));let mut settings=BundleSigningSettings::new("TEAM",Dictionary::new(),Some(&signer));
   let patterns=["TEAM.com.fixture.ios","TEAM.com.fixture.ios.watch","TEAM.com.fixture.ios.watch.extension","TEAM.com.fixture.ios.clip"];
   let profiles:Vec<_>=patterns.iter().map(|p|p.as_bytes()).collect();
   let mut original=BTreeMap::new();
   for n in &nodes{
    let d=fs::read(n.executable().unwrap()).unwrap();assert!(nested::read_entitlements(&d).unwrap().is_empty());
    let i=nested::select_profile(&patterns,&n.id).unwrap();
    let (ent,drop)=nested::constrain(&Dictionary::new(),&Dictionary::new(),"TEAM",&n.id,"TEAM",&BTreeMap::new(),true).unwrap();assert!(drop.is_empty());
    settings.entitlements_by_bundle_id.insert(n.id.clone(),ent);
    settings.embedded_mobileprovisions_by_bundle_id.insert(n.id.clone(),profiles[i]);
    original.insert(n.id.clone(),d);
   }
   // One recursive production call must discover Watch, its PlugIns and AppClips.
   sign_bundle(&f.0,&settings).unwrap();
   for n in &nodes{
    let d=fs::read(n.executable().unwrap()).unwrap();let before=slices(&original[&n.id]);let after=slices(&d);
    assert_eq!(before.len(),after.len());
    for (a,b) in before.iter().zip(after.iter()){
     assert_eq!(&a[384..448],&b[384..448]);assert_eq!(le(a,4),le(b,4));
     let enc=commands(a).into_iter().find(|(k,_)|*k==0x21||*k==0x2c).unwrap().1;
     assert_eq!(&a[enc..enc+le(a,enc+4)],&b[enc..enc+le(b,enc+4)]);
    }
    verify(&d,&n.path,&settings.entitlements_by_bundle_id[&n.id]);
    assert_eq!(nested::read_entitlements(&d).unwrap(),settings.entitlements_by_bundle_id[&n.id]);
    let i=nested::select_profile(&patterns,&n.id).unwrap();assert_eq!(fs::read(n.path.join("embedded.mobileprovision")).unwrap(),profiles[i]);
    let cr=Value::from_file(n.path.join("_CodeSignature/CodeResources")).unwrap();
    for (rel,v) in cr.as_dictionary().unwrap()["files2"].as_dictionary().unwrap(){
     let hash=v.as_dictionary().unwrap()["hash2"].as_data().unwrap();
     assert_eq!(hash,sha2::Sha256::digest(fs::read(n.path.join(rel)).unwrap()).as_slice(),"stale seal {rel}");
    }
   }
   let trace=signer.0.lock().unwrap();
   let ext=trace.iter().position(|s|s.ends_with(".extension")).unwrap();
   let watch=trace.iter().position(|s|s.ends_with(".watch")).unwrap();
   let root=trace.iter().position(|s|s=="com.fixture.ios").unwrap();
   assert!(ext<watch&&watch<root,"child signing before parent seal");
   let cr=Value::from_file(f.0.join("_CodeSignature/CodeResources")).unwrap();
   let files=cr.as_dictionary().unwrap()["files2"].as_dictionary().unwrap();
   for rel in ["Watch/FixtureWatch.app/Fixture","Watch/FixtureWatch.app/PlugIns/WatchExtension.appex/Fixture","Watch/FixtureWatch.app/PlugIns/WatchExtension.appex/Resource.txt","AppClips/Clip.app/Fixture"]{assert!(files.contains_key(rel),"missing nested seal {rel}")}
  }
 }
}
