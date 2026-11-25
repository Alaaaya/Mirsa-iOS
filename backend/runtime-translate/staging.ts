// WEB private staging ONLY. Never deployed as a production Edge Function.
import { createHandler } from './index.ts';
import { jwtVerify } from 'npm:jose@6.2.18';

const env = (name: string) => Deno.env.get(name);
if (env('RUNTIME_STAGING_ONLY') !== 'true') throw new Error('staging opt-in required');
const socket = env('RUNTIME_STAGING_PG_SOCKET') || '';
if (!socket.startsWith('/home/kit/') || socket.includes('..')) throw new Error('local socket required');
const port = env('RUNTIME_STAGING_PG_PORT') || '';
if (!/^\d{4,5}$/.test(port)) throw new Error('port required');
const path = env('RUNTIME_STAGING_PATH') || '';
if (!/^\/runtime-translate-[a-f0-9]{24}$/.test(path)) throw new Error('unique path required');
const stagingSecret = new TextEncoder().encode(env('RUNTIME_STAGING_JWT_SECRET') || '');
if (stagingSecret.length < 64) throw new Error('independent staging secret required');
const testUser = 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee';
// Subprocess arguments and SQL variable literals, never shell interpolation.
async function sql(statement: string, vars: Record<string,string>, signal: AbortSignal) {
  const args = ['-XAt','-h',socket,'-p',port,'-d','postgres','-v','ON_ERROR_STOP=1'];
  for (const [key,value] of Object.entries(vars)) args.push('-v',key+'='+value);
  const child = new Deno.Command('/usr/bin/psql',{args,stdin:'piped',stdout:'piped',stderr:'null',signal}).spawn();
  const writer = child.stdin.getWriter();
  await writer.write(new TextEncoder().encode(statement)); await writer.close();
  const result = await child.output();
  if (!result.success) throw new Error('local database unavailable');
  return new TextDecoder().decode(result.stdout).trim();
}
const handler = createHandler(env, (url, key, deadline) => ({
  auth: {getUser: async (token: string) => {
    try {
      const {payload} = await jwtVerify(token,stagingSecret,{
        algorithms:['HS256'],issuer:'urn:mirsa:runtime-staging25',audience:'mirsa-runtime-staging25',
        requiredClaims:['sub','iat','exp','jti'],maxTokenAge:'1h'
      });
      if (payload.sub !== testUser || payload.scope !== 'runtime:bootstrap' ||
          Number(payload.exp)-Number(payload.iat) > 3600) throw new Error('scope');
      return {data:{user:{id:testUser}},error:null};
    } catch { return {data:{user:null},error:true}; }
  }},
  rpc: async (name: string, p: Record<string,unknown>) => {
    try {
      const vars = Object.fromEntries(Object.entries(p).map(([k,v])=>[k,v == null ? '' : String(v)]));
      if(name === 'mirsa_runtime_anomaly') {
        const result=await sql("select public.mirsa_runtime_anomaly(:'p_hash',:'p_ip',:'p_window'::integer,:'p_throttle'::integer,:'p_revoke'::integer);",vars,deadline);
        return {data:result,error:null};
      }
      if(['mirsa_runtime_queue','mirsa_runtime_refresh','mirsa_runtime_store'].includes(name)) {
      if(name === 'mirsa_runtime_queue') vars.p_items=JSON.stringify(p.p_items);
        if(name === 'mirsa_runtime_store') vars.p_entries=JSON.stringify(p.p_entries);
        const result=await sql(name === 'mirsa_runtime_store'
          ? "select public.mirsa_runtime_store(:'p_hash',:'p_bundle',:'p_revision',:'p_entries'::jsonb);" : name === 'mirsa_runtime_queue'
          ? "select public.mirsa_runtime_queue(:'p_hash',:'p_bundle',:'p_revision',:'p_items'::jsonb);"
          : "select public.mirsa_runtime_refresh(:'p_hash',:'p_bundle',:'p_revision');",vars,deadline);
        return {data:JSON.parse(result),error:null};
      }
      const statement = "begin; set local statement_timeout='2000ms';\n"+
        "insert into auth.users(id) select nullif(:'p_user','')::uuid where nullif(:'p_user','') is not null on conflict do nothing;\n"+
        "select public.mirsa_runtime_reserve(nullif(:'p_user','')::uuid,nullif(:'p_hash',''),:'p_bundle',:'p_revision',:'p_action',:'p_chars'::integer);\ncommit;";
      const result = await sql(statement,vars,deadline);
      return {data:result.split('\n').includes('t'),error:null};
    } catch { return {data:false,error:true}; }
  },
  from: (_name: string) => ({insert: async (p: Record<string,unknown>) => {
    try {
      await sql("insert into public.mirsa_runtime_caps(token_hash,user_id,bundle_id,revision,expires_at) values(:'token_hash',:'user_id'::uuid,:'bundle_id',:'revision',:'expires_at'::timestamptz);",
        Object.fromEntries(Object.entries(p).map(([k,v])=>[k,String(v)])),deadline);
      return {error:null};
    } catch { return {error:true}; }
  }})
}));
// Global admission bound protects auth/provider resources even before user quota.
let active = 0, minute = 0, admissions = 0;
Deno.serve({hostname:'0.0.0.0',port:Number(env('PORT'))}, async (req,info) => {
  if (new URL(req.url).pathname !== path) return new Response(null,{status:404});
  const now = Math.floor(Date.now()/60000);
  if (minute !== now) {minute=now;admissions=0;}
  if (active >= 4 || ++admissions > 60) return new Response('{"error":"rate_limited"}',{status:429,headers:{'content-type':'application/json','cache-control':'no-store'}});
  active++;
  try {return await handler(req,info.remoteAddr.hostname);} finally {active--;}
});
