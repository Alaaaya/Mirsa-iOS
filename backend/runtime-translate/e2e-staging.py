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
def run(cmd,**kw):return subprocess.run(cmd,text=True,check=True,capture_output=True,**kw).stdout.strip()
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
  assert len(events)==1 and set(events[0]['data'])=={'queue_id','user_id','bundle_id','revision'}
  row=json.loads(run(op+['list'],env=openv))[0]
  assert events[0]['data']['queue_id']==row['id']
  result=json.loads(run(op+['resolve',row['id'],'الإعدادات %d'],env=openv));assert result['resolved']
  refreshed={**scope,'action':'refresh'}
  status,reply=post(refreshed,token,activation)
  assert status==200 and reply['entries']==[{'source':'设置 %d','translation':'الإعدادات %d'}],(status,reply)
  # New capability/launch for same authenticated account+app+revision sees the persisted review.
  status,new=post(issue,bootstrap);assert status==200
  new=new['online'];status,reply=post(refreshed,new['token'],new['activation'])
  assert status==200 and len(reply['entries'])==1
  # Sign-time generated dictionary is persisted server-side too.
  h=hashlib.sha256(token.encode()).hexdigest()
  sql("select public.mirsa_runtime_store('"+h+"','"+bundle+"','"+revision+"','[{\"source\":\"Cancel\",\"translation\":\"إلغاء\"}]'::jsonb);")
  status,reply=post(refreshed,token,activation);assert status==200 and len(reply['entries'])==2
  sql("update public.mirsa_runtime_caps set revoked=true where token_hash='"+h+"';")
  assert post(refreshed,token,activation)[0]==403
  assert post(missing,token,activation)[0]==403
  assert post({**scope,'action':'dictionary','items':[{'id':'s','text':'Cancel'}]},bootstrap,activation)[0]!=200
  rpc('mirsa_ack_translation_event',{'event_id':events[0]['eventId']})
  assert not json.loads(rpc('mirsa_pending_translation_events')['content'][0]['text'])['events']
  print(json.dumps({'proof':'isolated real HTTP PG account issuer queue relay operator OTA revocation','passed':True,'liveKatWake':False,'provider':'intentionally unconfigured, queue survived 503','newLaunchRefresh':True,'noLiveServicesChanged':True}))
 finally:
  for c in children:
   c.terminate()
   try:c.wait(timeout=5)
   except subprocess.TimeoutExpired:c.kill();c.wait()
  subprocess.run([pg+'/pg_ctl','-D',str(t/'db'),'-m','immediate','stop'],capture_output=True)
