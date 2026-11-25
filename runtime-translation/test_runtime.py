#!/usr/bin/env python3
"""Source/packaging regression tests. Does not claim native execution."""
import json,re,struct,unittest
from pathlib import Path
class RuntimeTests(unittest.TestCase):
 def test_empty_generic_table(self):
  c=json.loads(Path("runtime-table.json").read_text())
  self.assertEqual(c["translations"],{});self.assertEqual(c["substrings"],{});self.assertEqual(c["regex"],[])
 def test_logger(self):
  s=Path("RuntimeTranslate.m").read_text();o=Path("Online.h").read_text()
  for token in ("O_NOFOLLOW","fchmod(fd,0600)","st.st_nlink==1","missingWaiting<16","1024*1024","SafePrefix(result,4096)"):
   self.assertIn(token,s)
  self.assertIn("CFStringIsSurrogateHighCharacter",o)
  self.assertIn("onlinePositive.count>=2048",Path("OnlineMerge.h").read_text())
 def test_online_bounds(self):
  s=Path("Online.h").read_text()
  for token in ("s.length>256","onlineWaiting>=128","batch.count>=16","chars+source.length>2048","150*NSEC_PER_MSEC","onlineIssued>=128","DISPATCH_QUEUE_SERIAL","timeoutInterval:5","body.length+d.length>1048576","done(nil)","timeIntervalSince1970+60","NSURLSessionConfiguration.ephemeralSessionConfiguration"):
   self.assertIn(token,s)
 def test_scoped_contract(self):
  s=Path("Online.h").read_text()
  for token in ('@"missing"','@"consent":@YES','@"items"','@"s%lu"','OnlineExpiry','@"mrt1'):
   # token pattern contains ^ prefix, check separately
   if token=='@"mrt1':continue
   self.assertIn(token,s)
  self.assertIn('^mrt1',s);self.assertIn('NSBundle.mainBundle.bundleIdentifier',s)
  self.assertIn('PlaceholdersPreserved(s,v)',s);self.assertIn('ApplyOnlineEntries(obj[@"entries"])',s)
  self.assertIn('[obj[@"revision"] isEqual:onlineConfig[@"revision"]]',s)
 def test_binary_macho_signature_bounds(self):
  d=Path("out/MirsaTranslate.dylib").read_bytes()
  magic,cpu,sub,kind,ncmds,size,flags,res=struct.unpack_from("<8I",d)
  self.assertEqual(magic,0xfeedfacf);self.assertEqual(cpu,0x100000c);self.assertEqual(kind,6)
  off=32;sig=False
  for _ in range(ncmds):
   cmd,length=struct.unpack_from("<II",d,off);self.assertGreaterEqual(length,8);self.assertLessEqual(off+length,32+size)
   if cmd==0x1d:
    a,b=struct.unpack_from("<II",d,off+8);self.assertLessEqual(a+b,len(d));sig=True
   off+=length
  self.assertEqual(off,32+size);self.assertTrue(sig)
 def test_drift_fixture_and_bidi(self):
  c=json.loads(Path("fixtures/DriftTranslations.json").read_text())
  for k,v in {"可用":"متاح","实验":"تجريبي","（在范围内）":"ضمن النطاق","需要":"يتطلب"}.items():
   self.assertEqual(c["translations"][k],v);self.assertEqual(c["substrings"][k],v)
  hits=[r for r in c["regex"] if re.search(r["pattern"],"iOS 27.0.1（构建 24A446）")]
  self.assertEqual(len(hits),1)
  m=re.search(hits[0]["pattern"],"iOS 27.0.1（构建 24A446）")
  self.assertEqual(m.group(2),"24A446")
  s=Path("Bidi.h").read_text();self.assertIn("0x2066",s);self.assertIn("intersectsIndexesInRange",s)
 def test_exact_token_patterns(self):
  root=Path("..")
  swift=(root/"ios-app/Apps/ArabicIPALocalizer.swift").read_text()
  printf=re.search(r'static let printfRegex = .*?pattern: #"(.*?)"#',swift).group(1)
  suffix=re.search(r'static let tokenRegex = .*?pattern \+ #"(.*?)"#',swift).group(1)
  header=Path("Tokens.h").read_text()
  self.assertIn(printf.replace(chr(92),chr(92)*2),header)
  self.assertIn(suffix.replace(chr(92),chr(92)*2),header)
  self.assertIn("implicitStar",header)
 def test_no_ui_wait(self):
  s=Path("Online.h").read_text()
  self.assertGreater(s.index("dispatch_semaphore_wait"),s.index("dispatch_async(onlineQueue"))
  s=Path("RuntimeTranslate.m").read_text();self.assertIn("if(remote)return IsolateLatin(remote);",s)
  self.assertIn('[s isEqualToString:result] && HasCJK(s)',s)
if __name__=="__main__":unittest.main()
