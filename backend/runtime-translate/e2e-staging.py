#!/usr/bin/env python3
"""Disposable real HTTP/PostgreSQL/service-operator/relay proof. Never changes existing staging."""
import os,sys,tempfile,subprocess,json,secrets,socket,time,base64,hmac,hashlib,urllib.request,urllib.error,selectors
from pathlib import Path
root=Path(__file__).resolve().parents[2]
private=os.environ.get('RUNTIME_ACTIVATION_PRIVATE_KEY_FILE')
base=os.environ.get('MIRSA_RELAY_BASE_MODULE')
if not private or not base:raise SystemExit('Explicit staging signing key and existing relay module required')
pg='/usr/lib/postgresql/16/bin'
def port():
 s=socket.socket();s.bind(('127.0.0.1',0));p=s.getsockname()[1];s.close();return str(p)
def run(cmd,**kw):
 p=subprocess.run(cmd,text=True,capture_output=True,**kw)
 if p.returncode:
  raise RuntimeError(p.stderr)
 return p.stdout.strip()
def waitline(p,needle):
 sel=selectors.DefaultSelector();sel.register(p.stderr,selectors.EVENT_READ)
 deadline=time.monotonic()+20
 while time.monotonic()<deadline:
  if not sel.select(deadline-time.monotonic()):break
  line=p.stderr.readline()
  if needle in line:return
  if not line:break
 raise RuntimeError('fixture failed readiness, no service started')
def jwt(secret,sub):
 b=lambda x:base64.urlsafe_b64encode(json.dumps(x,separators=(',',':')).encode()).decode().rstrip('=')
 now=int(time.time());s=b({'alg':'HS256','typ':'JWT'})+'.'+b({'iss':'urn:mirsa:runtime-staging25','aud':'mirsa-runtime-staging25','scope':'runtime:bootstrap','sub':sub,'iat':now,'exp':now+3600,'jti':secrets.token_hex(16)})
 return s+'.'+base64.urlsafe_b64encode(hmac.new(secret.encode(),s.encode(),hashlib.sha256).digest()).decode().rstrip('=')
os.umask(0o077)
with tempfile.TemporaryDirectory(prefix='queue25-proof-',dir='/home/kit') as tmp:
 t=Path(tmp);pgport=port();httpport=port();relayport=port();children=[]
 run([pg+'/initdb','-D',str(t/'db'),'-A','trust'])
 run([pg+'/pg_ctl','-D',str(t/'db'),'-o',f"-k {t} -p {pgport} -c listen_addresses=''",'-l',str(t/'pg.log'),'start'])
 def sql(text):
  return run(['/usr/bin/psql','-XAt','-h',str(t),'-p',pgport,'-d','postgres','-v','ON_ERROR_STOP=1'],input=text)
 try:
  sql("create role anon; create role authenticated; create role service_role; create schema auth; create table auth.users(id uuid primary key);")
  sql((root/'backend/runtime-translate/schema.sql').read_text())
  secret=secrets.token_hex(48);hook=secrets.token_hex(32);mcp=secrets.token_hex(32);path='/runtime-translate-'+secrets.token_hex(12)
  env={**os.environ,'RUNTIME_STAGING_ONLY':'true','RUNTIME_STAGING_PG_SOCKET':str(t),'RUNTIME_STAGING_PG_PORT':pgport,
   'SUPABASE_URL':'http://127.0.0.1/unused-independent-adapter','SUPABASE_SERVICE_ROLE_KEY':'isolated-adapter-no-production-secret','RUNTIME_STAGING_JWT_SECRET':secret,'RUNTIME_STAGING_PATH':path,'RUNTIME_PUBLIC_ENDPOINT':'https://fixture.invalid'+path,
   'RUNTIME_ACTIVATION_PRIVATE_PEM':Path(private).read_text(),'PORT':httpport}
  p=subprocess.Popen(['npx','--yes','deno','run','--allow-env','--allow-net','--allow-read','--allow-run=/usr/bin/psql',str(root/'backend/runtime-translate/staging.ts')],env=env,stdout=subprocess.DEVNULL,stderr=subprocess.PIPE,text=True)
  children.append(p);waitline(p,'Listening on')
  relayenv={**os.environ,'MIRSA_RELAY_BASE_MODULE':base,'MCP_TOKEN':mcp,'HOOK_TOKEN':hook,'DB_PATH':str(t/'relay.sqlite'),'PORT':relayport}
  relay=subprocess.Popen(['node',str(root/'backend/mcp-translation-relay/extension.mjs')],env=relayenv,stdout=subprocess.DEVNULL,stderr=subprocess.PIPE,text=True)
  children.append(relay);waitline(relay,'translation relay ready')
  endpoint='http://127.0.0.1:'+httpport+path;revision='a'*64;bundle='com.example.queueproof'
  scope={'consent':True,'bundleId':bundle,'revision':revision}
  def post(body,token,activation=None):
   headers={'Authorization':'Bearer '+token,'Content-Type':'application/json'}
   if activation:headers['X-Mirsa-Activation']=activation
   req=urllib.request.Request(endpoint,data=json.dumps(body).encode(),headers=headers,method='POST')
   try:r=urllib.request.urlopen(req,timeout=15)
   except urllib.error.HTTPError as e:r=e
   return r.status,json.loads(r.read())
  bootstrap=jwt(secret,'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee')
  issue={**scope,'action':'issue','installationId':'11111111-1111-4111-8111-111111111111'}
  assert post(issue,jwt(secret,'11111111-1111-4111-8111-111111111111'))[0]==401
  status,issued=post(issue,bootstrap);assert status==200,(status,issued)
  online=issued['online'];token=online['token'];activation=online['activation']
  payload=json.loads(base64.urlsafe_b64decode(activation.split('.')[1]+'=='))
  assert payload['sub']=='eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee' and payload['bundleId']==bundle
  missing={**scope,'action':'missing','items':[{'id':'s0','text':'设置 %d'}]}
  assert post(missing,token)[0]==403
  assert post(missing,bootstrap,activation)[0]==401
  assert post({**missing,'bundleId':'com.other.app'},token,activation)[0]==403
  assert post(missing,token,activation[:-12]+'aaaaaaaaaaaa')[0]==403
  # Provider intentionally unconfigured. Queue must persist before the unchanged fail-open 503.
  assert post(missing,token,activation)[0]==503
  assert post(missing,token,activation)[0]==503
  assert sql('select count(*) from public.mirsa_runtime_labels;')=='1'
  op=['npx','--yes','deno','run','--allow-env','--allow-read','--allow-net=127.0.0.1','--allow-run=/usr/bin/psql',str(root/'backend/runtime-translate/operator.ts')]
  openv={**env,'RUNTIME_TRANSLATION_EVENT_INGRESS':'http://127.0.0.1:'+relayport+'/internal/translation','RUNTIME_TRANSLATION_EVENT_HOOK_TOKEN':hook}
  assert json.loads(run(op+['emit'],env=openv))['emitted']==1
  def rpc(name,args={}):
   req=urllib.request.Request('http://127.0.0.1:'+relayport+'/mcp',data=json.dumps({'jsonrpc':'2.0','id':1,'method':'tools/call','params':{'name':name,'arguments':args}}).encode(),headers={'Authorization':'Bearer '+mcp,'Content-Type':'application/json'})
   with urllib.request.urlopen(req,timeout=5) as r:return json.loads(r.read())['result']
  events=json.loads(rpc('mirsa_pending_translation_events')['content'][0]['text'])['events']
  assert len(events)==1 and set(events[0]['data'])=={'batch_id','entries'}
  assert set(events[0]['data']['entries'][0])=={'queue_id','user_id','bundle_id','revision','version','kind'}
  assert json.loads(run(op+['emit'],env=openv))['emitted']==0
  row=json.loads(run(op+['list'],env=openv))[0]
  assert events[0]['data']['entries'][0]['queue_id']==row['id']
  result=json.loads(run(op+['resolve',row['id'],str(row['version']),'الإعدادات %d'],env=openv));assert result['resolved']
  refreshed={**scope,'action':'refresh'}
  status,reply=post(refreshed,token,activation)
  assert status==200 and reply['entries']==[{'source':'设置 %d','translation':'الإعدادات %d','version':2,'provenance':'kat'}],(status,reply)
  # New capability/launch for same authenticated account+app+revision sees the persisted review.
  status,new=post(issue,bootstrap);assert status==200
  new=new['online'];status,reply=post(refreshed,new['token'],new['activation'])
  assert status==200 and len(reply['entries'])==1
  # Exercise the exact HTTP handler + real PG against a deterministic provider transport fixture.
  # This is NOT a claim of a real Gemini request; provider model/origin enforcement is still real.
  answers=t/'provider.json'
  outputs={'Cancel':'إلغاء','设置 %d':'خيارات %d',**{'Label '+str(i):'العنصر '+str(i) for i in range(33)}}
  answers.write_text(json.dumps(outputs))
  providerport=port()
  providerenv={**env,'PORT':providerport,'RUNTIME_E2E_PROVIDER_OUTPUTS':str(answers),
   'RUNTIME_LLM_MODEL':'gemini-2.5-flash','RUNTIME_LLM_API_KEY':'isolated-fixture-not-a-key',
   'RUNTIME_LLM_BASE_URL':'https://generativelanguage.googleapis.com/v1beta/openai',
   'RUNTIME_STRONG_MODELS':'gemini-2.5-flash','RUNTIME_PROVIDER_ORIGINS':'https://generativelanguage.googleapis.com'}
  pp=subprocess.Popen(['npx','--yes','deno','run','--allow-env','--allow-net','--allow-read','--allow-run=/usr/bin/psql',
   '--preload',str(root/'backend/runtime-translate/fixture-provider.ts'),str(root/'backend/runtime-translate/staging.ts')],
   env=providerenv,stdout=subprocess.DEVNULL,stderr=subprocess.PIPE,text=True)
  children.append(pp);waitline(pp,'Listening on')
  endpoint='http://127.0.0.1:'+providerport+path
  status,reply=post({**scope,'action':'dictionary','items':[{'id':'s','text':'Cancel'}]},bootstrap,activation)
  assert status==200 and reply['translations']=={'s':'إلغاء'} and reply['entries'][0]['provenance']=='gemini',(status,reply)
  # Runtime fallback must enqueue every Gemini candidate, but never replace a Kat correction.
  status,reply=post(missing,token,activation)
  assert status==200 and reply['translations']=={'s0':'الإعدادات %d'} and reply['entries'][0]['provenance']=='kat',(status,reply)
  rows=json.loads(run(op+['list'],env=openv))
  fallback=next(r for r in rows if r['candidate']=='خيارات %d')
  dictionary=next(r for r in rows if r['candidate']=='إلغاء')
  assert fallback['kind']=='review' and fallback['provenance']=='kat'
  assert dictionary['kind']=='review' and dictionary['provenance']=='gemini'
  assert json.loads(run(op+['resolve',dictionary['id'],str(dictionary['version']),'إلغاء العملية'],env=openv))['resolved']
  stale=subprocess.run(op+['resolve',dictionary['id'],str(dictionary['version']),'نص قديم'],env=openv,capture_output=True)
  assert stale.returncode!=0
  # Same Gemini candidate remains immutable and deduped after the correction.
  status,reply=post({**scope,'action':'dictionary','items':[{'id':'s','text':'Cancel'}]},bootstrap,activation)
  assert status==200 and reply['translations']=={'s':'إلغاء العملية'} and reply['entries'][0]['provenance']=='kat'
  status,reply=post(refreshed,new['token'],new['activation'])
  assert status==200 and len(reply['entries'])==2 and any(x['translation']=='إلغاء العملية' for x in reply['entries'])
  # Move the isolated DB into a new quota minute without sleeping or changing limits.
  sql("update public.mirsa_runtime_usage set minute=minute-interval '1 minute';")
  # 33 dictionary inputs produce both missing/review work; every event is <=32 homogeneous entries.
  status,reply=post({**scope,'action':'dictionary','items':[{'id':'l'+str(i),'text':'Label '+str(i)} for i in range(33)]},bootstrap,activation)
  assert status==200 and len(reply['entries'])==33,(status,reply)
  result=json.loads(run(op+['emit'],env=openv))
  assert result['emitted']==67 and result['batches']==(33+31)//32+(34+31)//32,result
  events=json.loads(rpc('mirsa_pending_translation_events')['content'][0]['text'])['events']
  assert len(events)==5
  for event in events:
   entries=event['data']['entries'];assert 1<=len(entries)<=32
   assert len({e['kind'] for e in entries})==1
   assert all(set(e)=={'queue_id','user_id','bundle_id','revision','version','kind'} for e in entries)
  assert json.loads(run(op+['emit'],env=openv))['emitted']==0
  # Simulate a crash after relay acceptance, before the DB marks notification.
  sql("update public.mirsa_runtime_batches set notified_at=null;")
  assert json.loads(run(op+['emit'],env=openv))['batches']==len(events)
  assert len(json.loads(rpc('mirsa_pending_translation_events')['content'][0]['text'])['events'])==len(events)
  h=hashlib.sha256(token.encode()).hexdigest()
  sql("update public.mirsa_runtime_caps set revoked=true where token_hash='"+h+"';")
  assert post(refreshed,token,activation)[0]==403
  assert post(missing,token,activation)[0]==403
  assert post({**scope,'action':'dictionary','items':[{'id':'s','text':'Cancel'}]},bootstrap,activation)[0]!=200
  for event in events:rpc('mirsa_ack_translation_event',{'event_id':event['eventId']})
  assert not json.loads(rpc('mirsa_pending_translation_events')['content'][0]['text'])['events']
  print(json.dumps({'proof':'isolated real HTTP PG account issuer queue relay operator OTA revocation','passed':True,'liveKatWake':False,'provider':'unconfigured failure durability + test-only deterministic transport (NOT live Gemini)','newLaunchRefresh':True,'allOutputReview':True,'katCASAndPriority':True,'batchBound32':True,'crashReplayDeduped':True,'noLiveServicesChanged':True}))
 finally:
  for c in children:
   c.terminate()
   try:c.wait(timeout=5)
   except subprocess.TimeoutExpired:c.kill();c.wait()
  subprocess.run([pg+'/pg_ctl','-D',str(t/'db'),'-m','immediate','stop'],capture_output=True)
