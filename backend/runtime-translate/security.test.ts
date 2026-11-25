import {verifyActivation} from './activation.ts';
import {sourceIP,anomalyIP} from './anomaly.ts';
const c=JSON.parse(await Deno.readTextFile(new URL('../../runtime-translation/fixtures/ActivationPublicVector.json',import.meta.url)));
const now=2000000010*1000;
function assert(v:unknown){if(!v)throw Error('assertion');}
async function rejects(fn:()=>unknown){let failed=false;try{await fn();}catch{failed=true;}assert(failed);}
const hash=''; // compute matching opaque capability digest, never a real issued credential
const digest=Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',new TextEncoder().encode(c.token))),b=>b.toString(16).padStart(2,'0')).join('');
Deno.test('asymmetric activation account bundle revision capability tamper and expiry',async()=>{
 assert(await verifyActivation(c.activation,c,digest,'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',now));
 for(const [scope,h,user,time,token] of [
  [{...c,bundleId:'com.other.app'},digest,null,now,c.activation],
  [{...c,revision:'b'.repeat(64)},digest,null,now,c.activation],
  [c,'a'.repeat(64),null,now,c.activation],
  [c,digest,'11111111-1111-4111-8111-111111111111',now,c.activation],
  [c,digest,null,2000086401*1000,c.activation],
  [c,digest,null,now,c.activation.slice(0,-8)+'aaaaaaaa'],
 ] as const)await rejects(()=>verifyActivation(String(token),scope,String(h),user,Number(time)));
});
Deno.test('untrusted forwarded header ignored and trusted immediate peer is explicit',async()=>{
 const req=new Request('https://fixture.invalid',{headers:{'x-forwarded-for':'8.8.8.8','x-real-ip':'1.1.1.1'}});
 assert(sourceIP(req,'9.9.9.9',()=>undefined)==='9.9.9.9');
 const env=(k:string)=>({RUNTIME_TRUSTED_PROXY_PEERS:'9.9.9.9',RUNTIME_TRUSTED_PROXY_IP_HEADER:'x-real-ip',RUNTIME_IP_AUDIT_ENABLED:'true',RUNTIME_IP_AUDIT_KEY:'x'.repeat(64)}[k]);
 assert(sourceIP(req,'9.9.9.9',env)==='1.1.1.1');
 assert(sourceIP(req,'7.7.7.7',env)==='7.7.7.7');
 const out=await anomalyIP(req,'9.9.9.9',env);assert(out?.length===64 && !out.includes('1.1'));
 await rejects(()=>anomalyIP(req,undefined,env));
});
