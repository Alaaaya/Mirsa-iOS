import {createHandler} from './index.ts';
const vector=JSON.parse(await Deno.readTextFile(new URL('../../runtime-translation/fixtures/ActivationPublicVector.json',import.meta.url)));
function assert(v:unknown,m='capacity assertion'){if(!v)throw Error(m);}
Deno.test('full 10k Kat dictionary refresh and bounded count/byte overflow',async()=>{
 const oldNow=Date.now;Date.now=()=>2000000010*1000;
 try{
  const entries=Array.from({length:10000},(_,i)=>({source:'Menu item '+i.toString(16).padStart(4,'0').replace(/[0-9a-f]/g,c=>'abcdefghijklmnop'[parseInt(c,16)]),translation:'خيار من قائمة التطبيق لعرض تفاصيل العنصر المحدد',version:2,provenance:'kat'}));
  let rows=entries;
  const handler=createHandler(k=>({RUNTIME_STAGING_ONLY:'true',RUNTIME_STAGING_KAT_ONLY:'true',RUNTIME_PUBLIC_ENDPOINT:'https://fixture.invalid/runtime',SUPABASE_URL:'https://fixture.invalid',SUPABASE_SERVICE_ROLE_KEY:'fixture'} as Record<string,string>)[k],()=>({rpc:async(name:string)=>name==='mirsa_runtime_reserve'?{data:true}:{data:rows}}));
  const req=()=>new Request('https://fixture.invalid/runtime',{method:'POST',headers:{'content-type':'application/json',authorization:'Bearer '+vector.token,'x-mirsa-activation':vector.activation},body:JSON.stringify({action:'refresh',bundleId:vector.bundleId,revision:vector.revision,consent:true})});
  let response=await handler(req());const raw=await response.text();
  assert(response.status===200,raw);assert(new TextEncoder().encode(raw).length>1048576);assert(JSON.parse(raw).entries.length===10000);assert(JSON.stringify(JSON.parse(raw).entries)===JSON.stringify(entries));
  rows=Array.from({length:20001},()=>entries[0]);response=await handler(req());assert(response.status===503);assert((await response.json()).error==='too_large');
  rows=entries.map(x=>({...x,translation:'ش'.repeat(1024)}));response=await handler(req());assert(response.status===503);assert((await response.json()).error==='too_large');
 }finally{Date.now=oldNow;}
});
