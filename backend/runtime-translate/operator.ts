// Service-only local operator. No HTTP admin endpoint and no privileged key in signed apps.
import {filterTranslations,safeText} from './logic.mjs';
const env=(k:string)=>Deno.env.get(k);
if(env('RUNTIME_STAGING_ONLY')!=='true') throw Error('branch staging opt-in required');
const socket=env('RUNTIME_STAGING_PG_SOCKET')||'',port=env('RUNTIME_STAGING_PG_PORT')||'';
if(!socket.startsWith('/home/kit/') || socket.includes('..') || !/^\d{4,5}$/.test(port))throw Error('local database required');
async function query(sql:string,vars:Record<string,string>={}) {
 const args=['-XAtq','-h',socket,'-p',port,'-d','postgres','-v','ON_ERROR_STOP=1'];
 for(const [k,v] of Object.entries(vars))args.push('-v',k+'='+v);
 const p=new Deno.Command('/usr/bin/psql',{args,stdin:'piped',stdout:'piped',stderr:'null',signal:AbortSignal.timeout(5000)}).spawn();
 const w=p.stdin.getWriter();await w.write(new TextEncoder().encode(sql));await w.close();
 const r=await p.output();if(!r.success)throw Error('database operation failed');
 return new TextDecoder().decode(r.stdout).trim();
}
const uuid=/^[a-f0-9]{8}(?:-[a-f0-9]{4}){3}-[a-f0-9]{12}$/i;
switch(Deno.args[0]) {
 case 'list': {
  // Explicit private operator output, never emitted into event metadata or application logs.
  const rows=await query("select coalesce(json_agg(q),'[]'::json) from (select id,user_id,bundle_id,revision,source from public.mirsa_runtime_labels where translation is null order by created_at limit 64) q;");
  console.log(rows);break;
 }
 case 'resolve': {
  const id=Deno.args[1],value=Deno.args[2];
  if(!uuid.test(id||'') || !safeText(value) || value.length>256)throw Error('invalid review');
  const raw=await query("select source from public.mirsa_runtime_labels where id=:'id'::uuid and translation is null;",{id});
  const valid=filterTranslations([{id:'s',text:raw}],{s:value});
  if(!valid.s)throw Error('unsafe output or changed placeholders');
  const receipt=await query("update public.mirsa_runtime_labels set translation=:'value',resolved_at=clock_timestamp() where id=:'id'::uuid and source=:'source' and translation is null returning json_build_object('id',id,'resolved',true);",{id,value:valid.s,source:raw});
  if(!receipt)throw Error('review raced or already resolved');
  console.log(receipt);break;
 }
 case 'emit': {
  const raw=env('RUNTIME_TRANSLATION_EVENT_INGRESS')||'',token=env('RUNTIME_TRANSLATION_EVENT_HOOK_TOKEN')||'';
  const url=new URL(raw);
  if(url.protocol!=='http:' || !['127.0.0.1','localhost'].includes(url.hostname) || url.pathname!=='/internal/translation' || url.search || url.hash || url.username || url.password || token.length<32)throw Error('reviewed local relay ingress required');
  const rows=JSON.parse(await query("select coalesce(json_agg(q),'[]'::json) from (select id as queue_id,user_id,bundle_id,revision from public.mirsa_runtime_labels where translation is null and notified_at is null order by created_at limit 32) q;"));
  let emitted=0;
  for(const row of rows){
   const r=await fetch(url,{method:'POST',redirect:'error',signal:AbortSignal.timeout(4000),headers:{authorization:'Bearer '+token,'content-type':'application/json'},body:JSON.stringify(row)});
   if(r.status!==202)throw Error('translation wake not accepted; queue kept');
   const receipt=await r.json();
   if(receipt.eventId!=='trn_'+row.queue_id)throw Error('invalid relay receipt');
   await query("update public.mirsa_runtime_labels set notified_at=clock_timestamp() where id=:'id'::uuid;",{id:row.queue_id});emitted++;
  }
  console.log(JSON.stringify({emitted}));break;
 }
 case 'prune': {
  await query("delete from public.mirsa_runtime_ip_audit where seen_at<clock_timestamp()-interval '24 hours'; delete from public.mirsa_runtime_labels where created_at<clock_timestamp()-interval '30 days';");
  console.log('{"pruned":true}');break;
 }
 default:throw Error('expected list, resolve, emit or prune');
}
