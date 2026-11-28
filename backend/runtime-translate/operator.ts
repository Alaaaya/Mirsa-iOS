// Private local operator only. No privileged HTTP route and no key in signed apps.
import {filterTranslations,safeText} from './logic.mjs';
if(Deno.env.get('RUNTIME_STAGING_ONLY')!=='true') throw Error('branch staging opt-in required');
const socket=Deno.env.get('RUNTIME_STAGING_PG_SOCKET')||'',port=Deno.env.get('RUNTIME_STAGING_PG_PORT')||'';
if(!socket.startsWith('/home/kit/')||socket.includes('..')||!/^\d{4,5}$/.test(port))throw Error('local database required');
async function query(sql:string,vars:Record<string,string>={}) {
 const args=['-XAtq','-h',socket,'-p',port,'-d','postgres','-v','ON_ERROR_STOP=1'];
 for(const [k,v] of Object.entries(vars))args.push('-v',k+'='+v);
 const p=new Deno.Command('/usr/bin/psql',{args,stdin:'piped',stdout:'piped',stderr:'null',signal:AbortSignal.timeout(5000)}).spawn();
 const w=p.stdin.getWriter();await w.write(new TextEncoder().encode(sql));await w.close();
 const r=await p.output();if(!r.success)throw Error('database operation failed or review conflict');
 return new TextDecoder().decode(r.stdout).trim();
}
const uuid=/^[a-f0-9]{8}(?:-[a-f0-9]{4}){3}-[a-f0-9]{12}$/i;
switch(Deno.args[0]) {
 case 'list': {
  // Labels/candidates are fetched privately, never added to event metadata.
  const id=Deno.args[1];if(id&&!uuid.test(id))throw Error('expected review UUID');
  const filter=id?" and r.id=:'id'::uuid":"";
  console.log(await query("select coalesce(json_agg(q),'[]'::json) from (select r.id,r.kind,r.candidate,l.user_id,l.bundle_id,l.revision,l.source,l.translation,l.version,l.provenance from public.mirsa_runtime_reviews r join public.mirsa_runtime_labels l on l.id=r.label_id where r.status='pending'"+filter+" order by r.created_at,r.id limit 64) q;",id?{id}:{}));
  break;
 }
 case 'resolve': {
  const [_,id,expected,value]=Deno.args;
  if(!uuid.test(id||'')||!/^\d{1,15}$/.test(expected||'')||!safeText(value))throw Error('expected review UUID, version and safe Arabic correction');
  const source=await query("select l.source from public.mirsa_runtime_labels l join public.mirsa_runtime_reviews r on r.label_id=l.id where r.id=:'id'::uuid and r.status='pending';",{id});
  const valid=filterTranslations([{id:'s',text:source}],{s:value});
  if(!valid.s)throw Error('unsafe output or changed placeholders');
  console.log(await query("select public.mirsa_runtime_review(:'id'::uuid,:'expected'::bigint,:'value');",{id,expected,value:valid.s}));
  break;
 }
 case 'emit': {
  const url=new URL(Deno.env.get('RUNTIME_TRANSLATION_EVENT_INGRESS')||'');
  const token=Deno.env.get('RUNTIME_TRANSLATION_EVENT_HOOK_TOKEN')||'';
  if(url.protocol!=='http:'||!['127.0.0.1','localhost'].includes(url.hostname)||url.pathname!=='/internal/translation'||url.search||url.hash||url.username||url.password||token.length<32)throw Error('reviewed local relay ingress required');
  // Snapshot stable batches under an operator lock before any network effect. Pending batches replay
  // unchanged after crashes, even if Kat changes a label while the relay is unavailable.
  const batches=JSON.parse(await query(`
begin;
do $$ begin perform pg_advisory_xact_lock(81258925); end $$;
insert into public.mirsa_runtime_batches(kind,entries)
select kind,jsonb_agg(jsonb_build_object('queue_id',id,'user_id',user_id,'bundle_id',bundle_id,'revision',revision,'version',version,'kind',kind,'source',source,'candidate',candidate) order by created_at,id)
from (
 select r.*,l.user_id,l.bundle_id,l.revision,l.source,(row_number() over(partition by r.kind order by r.created_at,r.id)-1)/32 as grp
 from public.mirsa_runtime_reviews r join public.mirsa_runtime_labels l on l.id=r.label_id
 where r.status='pending' and r.notified_at is null
 and not exists(select 1 from public.mirsa_runtime_batches b,jsonb_array_elements(b.entries) e where e->>'queue_id'=r.id::text)
 order by r.created_at,r.id limit 256
) q group by kind,grp;
select coalesce(json_agg(q),'[]'::json) from (select id as batch_id,entries from public.mirsa_runtime_batches where notified_at is null order by created_at,id limit 8) q;
commit;`));
  let emitted=0,batchCount=0;
  for(const batch of batches){
   const r=await fetch(url,{method:'POST',redirect:'error',signal:AbortSignal.timeout(4000),headers:{authorization:'Bearer '+token,'content-type':'application/json'},body:JSON.stringify(batch)});
   if(r.status!==202)throw Error('translation wake not accepted; batch kept');
   const receipt=await r.json();
   if(receipt.eventId!=='trn_'+batch.batch_id)throw Error('invalid relay receipt');
   await query("begin; update public.mirsa_runtime_reviews set notified_at=clock_timestamp() where id in(select (e->>'queue_id')::uuid from public.mirsa_runtime_batches b,jsonb_array_elements(b.entries) e where b.id=:'id'::uuid); update public.mirsa_runtime_batches set notified_at=clock_timestamp() where id=:'id'::uuid; commit;",{id:batch.batch_id});
   emitted+=batch.entries.length;batchCount++;
  }
  console.log(JSON.stringify({emitted,batches:batchCount}));break;
 }
 case 'prune': {
  await query("delete from public.mirsa_runtime_ip_audit where seen_at<clock_timestamp()-interval '24 hours'; delete from public.mirsa_runtime_batches where notified_at<clock_timestamp()-interval '30 days'; delete from public.mirsa_runtime_labels l where created_at<clock_timestamp()-interval '30 days' and not exists(select 1 from public.mirsa_runtime_caps c where c.user_id=l.user_id and c.bundle_id=l.bundle_id and c.revision=l.revision and not c.revoked and c.expires_at>clock_timestamp());");
  console.log('{"pruned":true}');break;
 }
 default:throw Error('expected list, resolve, emit or prune');
}
