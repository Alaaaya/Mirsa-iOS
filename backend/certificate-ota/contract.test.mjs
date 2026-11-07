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

import {lifetime,linkPage} from "./contract.mjs";
test("only explicit short and 48h lifetimes allowed",()=>{
 assert.equal(lifetime(null),900); assert.equal(lifetime("900"),900); assert.equal(lifetime("172800"),48*60*60);
 for(const bad of ["0","-1","172801","Infinity","900.0",172800,""]) assert.throws(()=>lifetime(bad));
});
test("share page escapes metadata and has no external scripts or trackers",()=>{
 const p=linkPage({...good,title:'<script>alert("bad")</script>'},"https://example.test/manifest?token=a&x=b","2026-01-03T00:00:00Z");
 assert.ok(p.includes("&lt;script&gt;")); assert.ok(!p.includes("<script"));
 assert.ok(p.includes('dir="ltr"')); assert.ok(p.includes('charset="utf-8"'));
 assert.ok(p.includes("itms-services://")); assert.ok(p.includes("2026-01-03T00:00:00.000Z"));
 assert.throws(()=>linkPage(good,"http://example.test","2026-01-01"));
 assert.throws(()=>linkPage(good,"https://example.test","bad"));
});
