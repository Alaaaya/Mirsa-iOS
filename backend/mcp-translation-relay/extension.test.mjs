import test from 'node:test';
import assert from 'node:assert/strict';
import {randomBytes} from 'node:crypto';
import http from 'node:http';
import {pathToFileURL} from 'node:url';
import {extend,TRANSLATION} from './extension.mjs';
const basePath=process.env.MIRSA_RELAY_BASE_MODULE;
test('staged relay really produces signed delivery, replay, dedupe and ACK',{skip:!basePath},async()=>{
 const base=await import(pathToFileURL(basePath).href),Service=extend(base);
 const delivery=[];
 const service=new Service({dbPath:':memory:',token:'m'.repeat(48),hookToken:'h'.repeat(48),post:async(_url,body,headers)=>{
  const data=JSON.parse(body);assert.ok(headers['webhook-signature']);
  if(data.type==='verification')return {status:200,body:JSON.stringify({challenge:data.challenge})};
  delivery.push(data);return {status:200,body:'{}'};
 }});
 assert.ok(service.catalog().events.some(x=>x.name===TRANSLATION));
 await service.rpc('events/subscribe',{name:TRANSLATION,arguments:{},delivery:{mode:'webhook',url:'https://fixture.example.com/callback',secret:'whsec_'+randomBytes(32).toString('base64')}});
 const server=http.createServer(service.handler());await new Promise(r=>server.listen(0,'127.0.0.1',r));
 const url='http://127.0.0.1:'+server.address().port+'/internal/translation';
 const p={queue_id:'11111111-1111-4111-8111-111111111111',user_id:'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',bundle_id:'com.example.fixture',revision:'a'.repeat(64)};
 const emit=(token,payload=p)=>fetch(url,{method:'POST',headers:{authorization:'Bearer '+token,'content-type':'application/json'},body:JSON.stringify(payload)});
 try{
  assert.equal((await emit('bad')).status,401);
  assert.equal((await emit('h'.repeat(48),{...p,source:'NEVER IN EVENT'})).status,400);
  const r=await emit('h'.repeat(48));assert.equal(r.status,202);assert.equal((await r.json()).eventId,'trn_'+p.queue_id);
  await service.drain();
  assert.equal(delivery.length,1);assert.deepEqual(delivery[0].data,p);
  const replay=await emit('h'.repeat(48));assert.equal((await replay.json()).replayed,true);
  await service.drain();assert.equal(delivery.length,1);
  let events=JSON.parse((await service.rpc('tools/call',{name:'mirsa_pending_translation_events'})).content[0].text).events;
  assert.equal(events.length,1);
  await service.rpc('tools/call',{name:'mirsa_ack_translation_event',arguments:{event_id:'trn_'+p.queue_id}});
  events=JSON.parse((await service.rpc('tools/call',{name:'mirsa_pending_translation_events'})).content[0].text).events;
  assert.equal(events.length,0);
 }finally{await new Promise(r=>server.close(r));service.db.close();}
});
