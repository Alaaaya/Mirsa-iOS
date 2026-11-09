import test from "node:test";
import assert from "node:assert/strict";
import {validateMetadata,manifest,isExpired,MAX_IPA_BYTES} from "./contract.mjs";
const good={bundleID:"com.alaa.mirsa",version:"1.3.2",title:"Mirsa",bytes:12000};
test("valid metadata keeps original ID",()=>assert.deepEqual(validateMetadata(good),good));
test("reject secrets and arbitrary fields",()=>{for(const k of ["p12","password","privateKey","profile","url"])assert.throws(()=>validateMetadata({...good,[k]:"secret"}));});
test("bounded uploads",()=>{for(const bytes of [0,-1,MAX_IPA_BYTES+1,Infinity,4.5])assert.throws(()=>validateMetadata({...good,bytes}));});
test("bundle identifier injection rejected",()=>assert.throws(()=>validateMetadata({...good,bundleID:'x.y</string>'})));
test("manifest escapes XML",()=>{const m=manifest({...good,title:'A < B & "C"'},'https://example.test/ipa?x=1&y=2');assert.ok(m.includes("A &lt; B &amp; &quot;C&quot;"));assert.ok(m.includes("x=1&amp;y=2"));});
test("HTTPS only without credentials",()=>{for(const u of ["http://x.test/a","https://user:pass@x.test/a","file:///tmp/x","https://x.test/a#secret"])assert.throws(()=>manifest(good,u));});
test("expiry fails closed including exact deadline",()=>{assert.equal(isExpired("bad"),true);assert.equal(isExpired("2026-01-01T00:00:00Z",Date.parse("2026-01-01T00:00:00Z")),true);assert.equal(isExpired("2026-01-01T00:00:01Z",Date.parse("2026-01-01T00:00:00Z")),false);});

import {lifetime,shareLink,SHARE_PAGE} from "./contract.mjs";
test("only explicit short and 48h lifetimes allowed",()=>{
 assert.equal(lifetime(null),900); assert.equal(lifetime("900"),900); assert.equal(lifetime("172800"),48*60*60);
 for(const bad of ["0","-1","172801","Infinity","900.0",172800,""]) assert.throws(()=>lifetime(bad));
});
test("share URLs pin free static origin and keep bearer token in fragment",()=>{
 const token="a".repeat(64);
 const value=new URL(shareLink(SHARE_PAGE,token,"2026-01-03T00:00:00Z"));
 assert.equal(value.search,""); assert.ok(value.hash.includes("token="+token));
 for(const page of [undefined,"http://example.test","https://evil.test/install.html",SHARE_PAGE+"?x=1"]) assert.throws(()=>shareLink(page,token,"2026-01-01"));
 assert.throws(()=>shareLink(SHARE_PAGE,"bad","2026-01-01"));
 assert.throws(()=>shareLink(SHARE_PAGE,token,"bad"));
});

import {localManifest} from "./contract.mjs";
test("local manifest points only at loopback with bounded port/token",()=>{
 const t="b".repeat(32);
 const m=localManifest(good,51234,t);
 assert.ok(m.includes("http://127.0.0.1:51234/"+t+"/Mirsa.ipa"));
 for(const p of [80,1023,65536,"x",1.5]) assert.throws(()=>localManifest(good,p,t));
 for(const bad of ["","short","../x","G".repeat(32)]) assert.throws(()=>localManifest(good,51234,bad));
 assert.throws(()=>localManifest({...good,bundleID:"x</string>"},51234,t));
});

import {localManifestFromQuery} from "./contract.mjs";
const localToken="a".repeat(32);
const localQuery=()=>new URLSearchParams({action:"local-manifest",port:"51234",token:localToken,...good,bytes:String(2*1024**3)});
test("local supports bounded 2 GiB without widening legacy upload or manifest limits",()=>{
 for(const bytes of [MAX_IPA_BYTES+1,2*1024**3]) {
  assert.ok(localManifest({...good,bytes},51234,localToken).includes(localToken));
  assert.throws(()=>validateMetadata({...good,bytes}));
  assert.throws(()=>manifest({...good,bytes},"https://example.test/a"));
 }
 for(const bytes of [3,2*1024**3+1,Infinity,NaN,4.5,"4",undefined]) assert.throws(()=>localManifest({...good,bytes},51234,localToken));
});
test("local rejects coercions, credentials, arbitrary hosts and token/path injection",()=>{
 for(const p of [null,undefined,true,[],[51234],{}," 51234","51234 ","051234","5e4","0xc800","51234.0","51234@evil.test"]) assert.throws(()=>localManifest(good,p,localToken));
 for(const token of [null,undefined,[],[localToken],{},"a".repeat(31),"a".repeat(65),localToken+"/x",localToken+"?x",localToken+"#x","é".repeat(32),"Ａ".repeat(32),"user:pass@host"]) assert.throws(()=>localManifest(good,51234,token));
 for(const port of [1024,"1024",65535,"65535"]) assert.ok(localManifest(good,port,localToken).includes("http://127.0.0.1:"+port+"/"));
});
test("local XML escapes multilingual text and rejects non XML Unicode",()=>{
 assert.ok(localManifest({...good,title:'مرسى 😀 <tag> & "quote"'},51234,localToken).includes('مرسى 😀 &lt;tag&gt; &amp; &quot;quote&quot;'));
 for(const title of ["a\u0000b","a\ud800b","a\udfff","a\ufffe","a\uffff"]) assert.throws(()=>localManifest({...good,title},51234,localToken));
});
test("local query is strict, bounded and duplicate-free",()=>{
 assert.ok(localManifestFromQuery(localQuery()).includes(localToken));
 for(const field of ["action","port","token","bundleID","version","title","bytes"]) {
  const missing=localQuery(); missing.delete(field); assert.throws(()=>localManifestFromQuery(missing));
  const duplicate=localQuery(); duplicate.append(field,duplicate.get(field)); assert.throws(()=>localManifestFromQuery(duplicate));
 }
 for(const key of ["url","host","password","p12","privateKey","profile"]) {const q=localQuery();q.set(key,"secret");assert.throws(()=>localManifestFromQuery(q));}
 for(const bytes of ["4e2","4.0","+4","04"," 4","2147483649","Infinity",""]) {const q=localQuery();q.set("bytes",bytes);assert.throws(()=>localManifestFromQuery(q));}
});
