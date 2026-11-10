import test from "node:test";
import assert from "node:assert/strict";
import vm from "node:vm";
import fs from "node:fs";
const source=fs.readFileSync(new URL("./static/install.js",import.meta.url),"utf8");
function run(hash) {
 const nodes={status:{},install:{hidden:true,removeAttribute(k){delete this[k];}}};
 vm.runInNewContext(source,{location:{hash},URLSearchParams,Date,
  document:{getElementById:id=>nodes[id]},setInterval:()=>{}});
 return nodes;
}
test("valid page constructs only the fixed Mirsa manifest",()=>{
 const n=run("#token="+"a".repeat(64)+"&expires="+encodeURIComponent(new Date(Date.now()+60000).toISOString()));
 assert.equal(n.install.hidden,false);
 const u=new URL(n.install.href);
 const m=new URL(u.searchParams.get("url"));
 assert.equal(u.protocol,"itms-services:");
 assert.equal(m.hostname,"hirebeofomiyumwysppj.supabase.co");
 assert.equal(m.searchParams.get("token"),"a".repeat(64));
});
test("expired and malformed page cannot offer installation",()=>{
 for(const h of ["#token=bad","#token="+"a".repeat(64)+"&expires=bad","#token="+"a".repeat(64)+"&expires=2020-01-01"]) {
  const n=run(h);assert.equal(n.install.hidden,true);assert.equal(n.install.href,undefined);
 }
});
test("fragment cannot override manifest host",()=>{
 const n=run("#token="+"b".repeat(64)+"&url=https://evil.test&expires="+encodeURIComponent(new Date(Date.now()+60000).toISOString()));
 assert.ok(!n.install.href.includes("evil.test"));
});
