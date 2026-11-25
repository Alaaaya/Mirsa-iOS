// Branch-only extension. Does NOT modify/restart the live relay.
// Deployment needs explicit approval, catalog rescan and a real Kat subscription.
import {randomBytes,createHash} from 'node:crypto';
import {pathToFileURL} from 'node:url';
export const TRANSLATION='mirsa.translation.missing';
const uuid=/^[a-f0-9]{8}(?:-[a-f0-9]{4}){3}-[a-f0-9]{12}$/i;
export function extend({Service,equal,callbackURL,validSecret}) {
 return class TranslationService extends Service {
  catalog(){const c=super.catalog();c.events.push({name:TRANSLATION,description:'Safe app labels await private operator translation. IDs only, not UI text.',delivery:['webhook'],inputSchema:{type:'object',properties:{},additionalProperties:false},payloadSchema:{type:'object',properties:Object.fromEntries(['queue_id','user_id','bundle_id','revision'].map(k=>[k,{type:'string'}])),required:['queue_id','user_id','bundle_id','revision'],additionalProperties:false}});return c;}
  async rpc(method,p={}){
   if(method==='tools/list'){const r=await super.rpc(method,p);r.tools.push(
    {name:'mirsa_pending_translation_events',description:'Private translation queue event replay, no label text.',inputSchema:{type:'object',properties:{},additionalProperties:false}},
    {name:'mirsa_ack_translation_event',description:'Transport ACK only, not translated or resolved.',inputSchema:{type:'object',properties:{event_id:{type:'string'}},required:['event_id'],additionalProperties:false}});return r;}
   if(method==='tools/call'&&p.name==='mirsa_pending_translation_events'){
    const events=this.db.prepare("select body from events where acknowledged=0 and json_extract(body,'$.name')=? order by created limit 100").all(TRANSLATION).map(x=>JSON.parse(x.body));
    return {content:[{type:'text',text:JSON.stringify({events})}]};
   }
   if(method==='tools/call'&&p.name==='mirsa_ack_translation_event'){
    if(!/^trn_[a-f0-9-]{36}$/i.test(p.arguments?.event_id))throw Error('invalid_event_id');
    this.db.prepare("update events set acknowledged=1 where id=? and json_extract(body,'$.name')=?").run(p.arguments.event_id,TRANSLATION);
    return {content:[{type:'text',text:'{"transport_acknowledged":true,"translated":false}'}]};
   }
   if(['events/subscribe','events/unsubscribe'].includes(method)&&p.name===TRANSLATION){
    if(!p.arguments || Object.keys(p.arguments).length || p.delivery?.mode!=='webhook')throw Error('invalid_arguments');
    callbackURL(p.delivery.url);
    const id='sub_'+createHash('sha256').update('owner\n'+p.delivery.url+'\n'+TRANSLATION+'\n{}').digest('hex');
    if(method==='events/unsubscribe'){
     this.db.prepare('delete from subs where id=?').run(id);
     this.db.prepare("update jobs set status='unsubscribed' where sub_id=? and status='pending'").run(id);return {};
    }
    if(!validSecret(p.delivery.secret) || (p.ttlMs!==undefined&&(!Number.isSafeInteger(p.ttlMs)||p.ttlMs<1)))throw Error('invalid_subscription');
    const expires=this.clock()+Math.min(p.ttlMs??86400000,86400000),challenge=randomBytes(32).toString('base64url');
    const r=await this.signed({url:p.delivery.url,secret:p.delivery.secret},{type:'verification',challenge,eventId:'verify_'+randomBytes(16).toString('hex')});
    if(r.status<200||r.status>=300||!equal(JSON.parse(r.body).challenge,challenge))throw Error('callback_verification_failed');
    const old=this.db.prepare('select * from subs where id=?').get(id);
    this.db.prepare('insert or replace into subs(id,args,url,secret,old_secret,rotate_until,expires,event_name) values(?,?,?,?,?,?,?,?)')
     .run(id,'{}',p.delivery.url,p.delivery.secret,old&&old.secret!==p.delivery.secret?old.secret:null,old&&old.secret!==p.delivery.secret?this.clock()+300000:0,expires,TRANSLATION);
    return {id,refreshBefore:new Date(expires).toISOString(),cursor:null,truncated:false};
   }
   return super.rpc(method,p);
  }
  ingestTranslation(p){
   if(!p||Object.keys(p).sort().join(',')!=='bundle_id,queue_id,revision,user_id' || !uuid.test(p.queue_id)||!uuid.test(p.user_id)||
    !/^[A-Za-z0-9][A-Za-z0-9.-]{2,254}$/.test(p.bundle_id)||!p.bundle_id.includes('.')||!/^[a-f0-9]{64}$/.test(p.revision))throw Error('invalid_event_data');
   // Parent persist gives durable transactional outbox and same-ID dedupe.
   return this.persist(p,TRANSLATION,'trn_'+p.queue_id);
  }
  handler(){
   const base=super.handler();
   return async(req,res)=>{
    if(req.url?.split('?')[0]!=='/internal/translation')return base(req,res);
    const json=(s,b)=>{res.writeHead(s,{'content-type':'application/json','cache-control':'no-store'});res.end(JSON.stringify(b));};
    if(!equal(req.headers.authorization,'Bearer '+this.hookToken))return json(401,{error:'unauthorized'});
    if(req.method!=='POST'||req.headers.origin)return json(403,{error:'not_allowed'});
    if(!String(req.headers['content-type']).startsWith('application/json'))return json(415,{error:'json_required'});
    let size=0,parts=[];
    try{for await(const chunk of req){size+=chunk.length;if(size>2048)return json(413,{error:'too_large'});parts.push(chunk);}
     const result=this.ingestTranslation(JSON.parse(Buffer.concat(parts).toString('utf8')));
     json(202,result);void this.drain().catch(()=>{});
    }catch{return json(400,{error:'invalid_event'});}
   };
  }
 };
}
if(process.argv[1]&&import.meta.url===pathToFileURL(process.argv[1]).href){
 const http=await import('node:http'),basePath=process.env.MIRSA_RELAY_BASE_MODULE;
 if(!basePath?.startsWith('/home/kit/'))throw Error('explicit existing relay module required');
 const Base=await import(pathToFileURL(basePath).href),Service=extend(Base);
 const s=new Service({dbPath:process.env.DB_PATH,token:process.env.MCP_TOKEN,hookToken:process.env.HOOK_TOKEN});
 const timer=setInterval(()=>void s.drain().catch(()=>{}),500);timer.unref();
 const server=http.createServer(s.handler());server.requestTimeout=15000;server.headersTimeout=10000;
 server.listen(Number(process.env.PORT),'127.0.0.1',()=>console.error('translation relay ready'));
}
