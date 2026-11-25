import test from 'node:test';
import assert from 'node:assert/strict';
import {validate,safeText,scopeAllowed,filterTranslations,providerConfig,readBounded,newToken,digest} from './logic.mjs';
const base = {action:'missing',bundleId:'com.example.app',revision:'a'.repeat(64),consent:true,items:[{id:'s0',text:'设置 %@'}]};
const rejects = (patch,code) => assert.throws(()=>validate({...base,...patch}),new RegExp(code));
test('valid scoped CJK and extracted dictionary',()=>{
 assert.equal(validate(base).chars,5);
 assert.equal(validate({...base,action:'dictionary',items:[{id:'s1',text:'Settings'}]}).chars,8);
 assert.equal(validate({action:'issue',bundleId:base.bundleId,revision:base.revision,consent:true}).chars,0);
});
test('consent, unknown fields, invalid actions and request identity',()=>{
 rejects({consent:false},'consent'); rejects({userId:'other'},'bad_fields');
 rejects({action:'foo'},'bad_action'); rejects({bundleId:'x'},'bad_bundle');
 rejects({revision:'../../secret'},'bad_revision'); rejects({revision:'A'.repeat(64)},'bad_revision');
 rejects({items:[]},'bad_items'); rejects({items:[{id:'x',text:'Hello'}]},'not_cjk');
 rejects({items:[{id:'__proto__!',text:'设置'}]},'bad_item');
 rejects({items:[{id:'x',text:'设置'},{id:'x',text:'设置'}]},'bad_item');
});
test('bounded sizes and items prevent bulk exfil',()=>{
 rejects({items:Array.from({length:17},(_,i)=>({id:'x'+i,text:'设置'}))},'bad_items');
 rejects({items:[{id:'x',text:'设'.repeat(257)}]},'unsafe_text');
 rejects({items:Array.from({length:16},(_,i)=>({id:'x'+i,text:'设'.repeat(256)}))},'too_large');
});
test('private data and secrets rejected wholesale, never echoed to model',()=>{
 for(const text of ['设置 a@b.de','设置 https://example.com','设置 www.foo.io','设置 123456789','设置 +49 (179) 2298195','设置 password: foo','设置 密码：foo','设置 sk-abcdefghijklmnopqrstuvwxyz','设置 eyJabcdefghijklmnopqrstuvwxyz','设置 /Users/alaa/private','设置 file:///foo','设置 \u0000','设置 \u202eabc','设置 '+ 'a'.repeat(45)]) {
   assert.equal(safeText(text),false,text); rejects({items:[{id:'s0',text}]},'unsafe_text');
 }
});
test('capability scope checks reject cross app/revision expiry revocation and invalid date',()=>{
 const cap = {revoked:false,bundle_id:base.bundleId,revision:base.revision,expires_at:new Date(2000).toISOString()};
 assert.equal(scopeAllowed(cap,base,1000),true);
 for(const change of [{bundle_id:'com.evil.app'},{revision:'b'.repeat(64)},{revoked:true},{expires_at:new Date(1000).toISOString()},{expires_at:'invalid'}])
  assert.equal(scopeAllowed({...cap,...change},base,1000),false);
 assert.equal(scopeAllowed(null,base),false);
});
test('translations preserve printf order/multiset and return only requested safe Arabic',()=>{
 assert.deepEqual({...filterTranslations(base.items,{s0:'الإعدادات %@',evil:'x'})},{s0:'الإعدادات %@'});
 for (const out of ['الإعدادات','设置 %@','Settings %@','الإعدادات %@ https://x.com']) assert.equal(Object.keys(filterTranslations(base.items,{s0:out})).length,0);
 assert.equal(Object.keys(filterTranslations([{id:'x',text:'设置 %d %@'}],{x:'إعداد %@ %d'})).length,0);
 assert.equal(Object.keys(filterTranslations([{id:'x',text:'设置 {name}'}],{x:'إعداد {name}'})).length,1);
});
test('configuration fail closed with no weak or implicit model, no unapproved host',()=>{
 const cfg = {RUNTIME_LLM_MODEL:'gemini-2.5-flash',RUNTIME_LLM_API_KEY:'test',RUNTIME_LLM_BASE_URL:'https://generativelanguage.googleapis.com/v1beta/openai',RUNTIME_STRONG_MODELS:'gemini-2.5-flash',RUNTIME_PROVIDER_ORIGINS:'https://generativelanguage.googleapis.com'};
 const load = o => providerConfig(k=>({...cfg,...o})[k]);
 assert.equal(load({}).model,'gemini-2.5-flash');
 for(const model of ['openai/gpt-oss-120b','qwen/qwen3.8-27b','gemini-2.5-pro','flash','model-lite','x-mini','x-nano','small','weak','']) assert.throws(()=>load({RUNTIME_LLM_MODEL:model,RUNTIME_STRONG_MODELS:model}),/not_configured/);
 for(const url of ['http://provider.example','https://evil.example','https://user:pass@provider.example','https://provider.example?q=x']) assert.throws(()=>load({RUNTIME_LLM_BASE_URL:url}),/not_configured/);
 assert.throws(()=>load({RUNTIME_LLM_MODEL:'not-approved'}),/not_configured/);
 assert.throws(()=>load({RUNTIME_LLM_API_KEY:''}),/not_configured/);
});
test('stream reader caps actual bytes even without Content-Length',async()=>{
 assert.equal(await readBounded(new Response('hello').body,5),'hello');
 await assert.rejects(readBounded(new Response('你好').body,5),/too_large/);
 const controller = new AbortController(); controller.abort();
 await assert.rejects(readBounded(new Response('a').body,5,controller.signal),/timeout/);
});
test('opaque token entropy format and only digests persist',async()=>{
 const a = newToken(),b = newToken(); assert.match(a,/^mrt1\.[0-9a-f]{64}$/); assert.notEqual(a,b);
 assert.match(await digest(a),/^[0-9a-f]{64}$/); assert.notEqual(await digest(a),await digest(b));
});
