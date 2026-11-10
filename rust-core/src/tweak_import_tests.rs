use super::*;
fn temp(label:&str)->PathBuf{
 static NEXT:std::sync::atomic::AtomicUsize=std::sync::atomic::AtomicUsize::new(0);
 let dir=std::env::temp_dir().join(format!("mirsa-zip20-{}-{}-{}",std::process::id(),NEXT.fetch_add(1,std::sync::atomic::Ordering::Relaxed),label));
 fs::create_dir_all(&dir).unwrap();dir
}
struct Cleanup(PathBuf);
impl Drop for Cleanup{fn drop(&mut self){let _=fs::remove_dir_all(&self.0);}}
fn payload()->Vec<u8>{
 let z=include_bytes!("../tests/fixtures/tweak-import/OwnerTikTokV4.zip");
 let mut zip=ZipArchive::new(Cursor::new(z)).unwrap();let mut bytes=Vec::new();zip.by_index(0).unwrap().read_to_end(&mut bytes).unwrap();bytes
}
fn archive(entries:Vec<(&str,Vec<u8>)>)->Vec<u8>{
 let mut zip=ZipWriter::new(Cursor::new(Vec::new()));
 for (name,data) in entries{
  zip.start_file(name,SimpleFileOptions::default().compression_method(zip::CompressionMethod::Stored)).unwrap();
  zip.write_all(&data).unwrap();
 }
 zip.finish().unwrap().into_inner()
}
fn run(bytes:&[u8],extension:&str)->(Cleanup,Result<Vec<Candidate>>){
 let root=temp(extension);let file=root.join(format!("input.{extension}"));fs::write(&file,bytes).unwrap();
 let result=prepare(&file,&root,&root.join("cancel")).and_then(|_|serde_json::from_slice(&fs::read(root.join("candidates.json")).unwrap()).map_err(err));
 if result.is_err(){assert!(!root.join("contents").exists());assert!(!root.join("candidates.json").exists());assert!(!root.join("deb-0").exists());}
 (Cleanup(root),result)
}
fn deb(entries:Vec<(&str,Vec<u8>)>)->Vec<u8>{
 let mut builder=tar::Builder::new(Vec::new());
 for (name,data) in entries{
  let mut h=tar::Header::new_gnu();h.set_size(data.len() as u64);h.set_mode(0o644);h.set_cksum();
  builder.append_data(&mut h,name,Cursor::new(data)).unwrap();
 }
 let bytes=builder.into_inner().unwrap();ar(&bytes)
}
fn ar(bytes:&[u8])->Vec<u8>{
 let mut result=b"!<arch>\n".to_vec();
 for (name,data) in [("debian-binary/",b"2.0\n".as_slice()),("data.tar/",bytes)]{
  let header=format!("{:<16}{:<12}{:<6}{:<6}{:<8}{:<10}\x60\n",name,0,0,0,100644,data.len());
  assert_eq!(header.len(),60);result.extend(header.as_bytes());result.extend(data);if data.len()%2!=0{result.push(b'\n')}
 }result
}
#[test]fn actual_owner_zip_preserves_fat_hash(){
 let (guard,result)=run(include_bytes!("../tests/fixtures/tweak-import/OwnerTikTokV4.zip"),"zip");let items=result.unwrap();assert_eq!(items.len(),1);
 assert_eq!(items[0].name,"Mirsa-TikTok-v4.dylib");assert_eq!(items[0].sha256,"8a8695e77cdce0be66ddf515de913c075eabd702dd8c7e8ca57e01e4c68b35f9");
 let bytes=fs::read(guard.0.join(&items[0].path)).unwrap();assert_eq!(&bytes[..4],&[0xca,0xfe,0xba,0xbe]);assert_eq!(bytes.len(),238256);assert_eq!(bytes,payload());
}
#[test]fn direct_deb_matches_zip_deb_and_keeps_other_libraries(){
 let code=payload();let d=deb(vec![("Library/MobileSubstrate/DynamicLibraries/One.dylib",code.clone()),("Library/MobileSubstrate/DynamicLibraries/Other.dylib",code.clone())]);
 let (_g,r)=run(&d,"deb");assert_eq!(r.unwrap().len(),2);
 let (_g,r)=run(&archive(vec![("One.dylib",code),("package.deb",d)]),"zip");
 let items=r.unwrap();assert_eq!(items.len(),2);assert_eq!(items.iter().find(|x|x.name=="One.dylib").unwrap().origin,"direct");
 assert!(items.iter().find(|x|x.name=="Other.dylib").unwrap().origin.starts_with("deb"));
}
#[test]fn different_payloads_remain_ambiguous_not_silently_removed(){
 let code=payload();let mut other=code.clone();other.push(0); // changes inert source hash, generic slice remains valid
 let d=deb(vec![("One.dylib",other)]);let (_g,r)=run(&archive(vec![("One.dylib",code),("pkg.deb",d)]),"zip");
 let items=r.unwrap();assert_eq!(items.len(),2);assert!(items.iter().all(|c|c.ambiguous));
}
#[test]fn multiple_selection_candidates_preserve_framework_bundle(){
 let code=payload();let plist=br#"<?xml version="1.0"?><plist version="1.0"><dict><key>CFBundleExecutable</key><string>Test</string></dict></plist>"#.to_vec();
 let (_g,r)=run(&archive(vec![("A.dylib",code.clone()),("Test.framework/Test",code),("Test.framework/Info.plist",plist),("Test.framework/Resources/hello.txt",b"kept".to_vec())]),"zip");
 let items=r.unwrap();assert_eq!(items.len(),2);assert!(items.iter().any(|x|x.kind=="framework"));assert!(!items.iter().any(|x|x.name=="Test"));
}
#[test]fn invalid_framework_and_extension_spoof_rejected(){
 for entries in [vec![("Test.framework/Test",payload())],vec![("Fake.dylib",b"not code".to_vec())],vec![("Fake.deb",b"not ar".to_vec())]]{let (_g,r)=run(&archive(entries),"zip");assert!(r.is_err());}
}
#[test]fn unsafe_paths_rejected_without_output(){
 for name in ["../escape.dylib","/abs.dylib","a\\b.dylib","%2e%2e/escape.dylib","C:/bad.dylib","a//bad.dylib","./x.dylib"]{
  let (_g,r)=run(&archive(vec![(name,payload())]),"zip");assert!(r.is_err(),"{name}");
 }
}
#[test]fn case_unicode_and_file_directory_conflicts_rejected(){
 for names in [("A.dylib","a.dylib"),("Straße.dylib","STRASSE.dylib"),("é.dylib","e\u{301}.dylib"),("dir","dir/child.dylib")]{
  let (_g,r)=run(&archive(vec![(names.0,payload()),(names.1,payload())]),"zip");assert!(r.is_err());
 }
}
#[test]fn encrypted_zip_crc_corruption_and_truncation_rejected(){
 let original=archive(vec![("A.dylib",payload())]);let mut encrypted=original.clone();
 for i in 0..encrypted.len()-8{
  if encrypted[i..i+4]==[0x50,0x4b,0x03,0x04]{encrypted[i+6]|=1}
  if encrypted[i..i+4]==[0x50,0x4b,0x01,0x02]{encrypted[i+8]|=1}
 }
 let mut corrupt=original.clone();corrupt[100]^=1;
 for bytes in [encrypted,corrupt,original[..original.len()-10].to_vec()] {let (_g,r)=run(&bytes,"zip");assert!(r.is_err());}
}
#[test]fn central_duplicate_is_not_hidden_by_library_map(){
 let mut bytes=archive(vec![("A.dylib",payload())]);
 let central=bytes.windows(4).position(|w|w==[0x50,0x4b,0x01,0x02]).unwrap();let end=bytes.len()-22;
 let record=bytes[central..end].to_vec();bytes.splice(end..end,record.clone());
 let end=bytes.len()-22;bytes[end+8..end+10].copy_from_slice(&2u16.to_le_bytes());bytes[end+10..end+12].copy_from_slice(&2u16.to_le_bytes());
 bytes[end+12..end+16].copy_from_slice(&((record.len()*2)as u32).to_le_bytes());
 let (_g,r)=run(&bytes,"zip");assert!(r.is_err());
}
#[test]fn symlink_zip_and_deb_hardlink_rejected(){
 let mut zip=ZipWriter::new(Cursor::new(Vec::new()));zip.add_symlink("A.dylib","/tmp/escape",SimpleFileOptions::default()).unwrap();
 let (_g,r)=run(&zip.finish().unwrap().into_inner(),"zip");assert!(r.is_err());
 for kind in [tar::EntryType::Link,tar::EntryType::Symlink]{
  let mut builder=tar::Builder::new(Vec::new());let mut h=tar::Header::new_gnu();h.set_size(0);h.set_mode(0o777);h.set_entry_type(kind);h.set_link_name("/tmp/escape").unwrap();h.set_cksum();builder.append_data(&mut h,"A.dylib",io::empty()).unwrap();
  let (_g,r)=run(&ar(&builder.into_inner().unwrap()),"deb");assert!(r.is_err());
 }
}
#[test]fn no_recursive_archives_or_ipa_auto_import(){
 for name in ["nested.zip","Other.ipa","random.txt"]{
  let (_g,r)=run(&archive(vec![(name,archive(vec![("inside.dylib",payload())]))]),"zip");assert!(r.is_err());
 }
}
#[test]fn limits_streaming_quota_cancellation_and_cleanup(){
 let dir=temp("budget");let _guard=Cleanup(dir.clone());let cancel=dir.join("cancel");let mut b=Budget{cancel:&cancel,bytes:EXPANDED-1,count:0};
 assert!(b.copy(&mut Cursor::new([1,2]),&mut io::sink(),2).is_err());
 let mut b=Budget{cancel:&cancel,bytes:0,count:COUNT};assert!(b.entry(0).is_err());
 let mut b=Budget{cancel:&cancel,bytes:0,count:0};assert!(b.entry(INPUT+1).is_err());
 assert!(b.copy(&mut Cursor::new([1,2]),&mut io::sink(),1).is_err());
 let input=dir.join("owner.zip");fs::write(&input,include_bytes!("../tests/fixtures/tweak-import/OwnerTikTokV4.zip")).unwrap();
 fs::write(&cancel,[]).unwrap();assert!(prepare(&input,&dir,&cancel).is_err());assert!(!dir.join("contents").exists());
 assert!(disk(&dir,u64::MAX).is_err());
}
#[test]fn compression_bomb_header_rejected(){
 let mut zip=ZipWriter::new(Cursor::new(Vec::new()));zip.start_file("bomb.dylib",SimpleFileOptions::default().compression_method(zip::CompressionMethod::Deflated)).unwrap();
 zip.write_all(&vec![0u8;2*1024*1024]).unwrap();let (_g,r)=run(&zip.finish().unwrap().into_inner(),"zip");assert!(r.is_err());
}

#[test]fn cancellation_is_checked_between_actual_stream_chunks(){
 let dir=temp("midstream");let _guard=Cleanup(dir.clone());let cancel=dir.join("cancel");
 struct CancelReader{cancel:PathBuf,read:bool}
 impl Read for CancelReader{fn read(&mut self,b:&mut [u8])->io::Result<usize>{
  if self.read{return Ok(0)} self.read=true;b[0]=1;fs::write(&self.cancel,[])?;Ok(1)
 }}
 let mut reader=CancelReader{cancel:cancel.clone(),read:false};let mut b=Budget{cancel:&cancel,bytes:0,count:0};
 let error=b.copy(&mut reader,&mut io::sink(),2).unwrap_err();assert_eq!(error,"tweak_import:cancelled");assert_eq!(b.bytes,1);
}
#[test]fn standalone_framework_uses_complete_snapshot_without_flattening(){
 let dir=temp("framework");let _guard=Cleanup(dir.clone());let root=dir.join("input/Sample.framework");fs::create_dir_all(root.join("Resources")).unwrap();
 fs::write(root.join("Sample"),payload()).unwrap();fs::write(root.join("Resources/keep.txt"),b"resource").unwrap();
 fs::write(root.join("Info.plist"),br#"<?xml version="1.0"?><plist version="1.0"><dict><key>CFBundleExecutable</key><string>Sample</string></dict></plist>"#).unwrap();
 prepare(&root,&dir,&dir.join("cancel")).unwrap();let items:Vec<Candidate>=serde_json::from_slice(&fs::read(dir.join("candidates.json")).unwrap()).unwrap();
 assert_eq!(items.len(),1);assert_eq!(items[0].kind,"framework");assert_eq!(fs::read(dir.join(&items[0].path).join("Resources/keep.txt")).unwrap(),b"resource");
}
