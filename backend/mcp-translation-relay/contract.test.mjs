import test from 'node:test';
import assert from 'node:assert/strict';
import {validateBatch,TRANSLATION,REVIEW,extend} from './extension.mjs';
const entry={queue_id:'11111111-1111-4111-8111-111111111111',user_id:'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',bundle_id:'com.example.fixture',revision:'a'.repeat(64),version:1,kind:'missing'};
const batch=entries=>({batch_id:'22222222-2222-4222-8222-222222222222',entries:entries??[{...entry}]});
test('live ingest validator accepts both narrowly scoped metadata kinds and bounds batches',()=>{
 assert.equal(TRANSLATION,'mirsa.translation.missing');assert.equal(REVIEW,'mirsa.translation.review');
 for(const kind of ['missing','review'])assert.deepEqual(validateBatch(batch([{...entry,kind}])),batch([{...entry,kind}]));
 assert.doesNotThrow(()=>validateBatch(batch(Array.from({length:32},(_,i)=>({...entry,queue_id:(i+1).toString(16).padStart(8,'0')+'-1111-4111-8111-111111111111'})))));
 for(const entries of [[],Array(33).fill(entry),[entry,entry],[entry,{...entry,queue_id:'33333333-3333-4333-8333-333333333333',kind:'review'}]])assert.throws(()=>validateBatch(batch(entries)));
});
test('live ingest validator rejects plaintext, scope ambiguity and invalid versions',()=>{
 for(const key of ['source','translation','candidate','ip','device_id','token']) {
  assert.throws(()=>validateBatch({...batch(),[key]:'NEVER EVENT DATA'}));
  assert.throws(()=>validateBatch(batch([{...entry,[key]:'NEVER EVENT DATA'}])));
 }
 for(const value of [null,[],{}, {...batch(),batch_id:'not-uuid'}, {...batch(),entries:'x'}])assert.throws(()=>validateBatch(value));
 for(const [key,values] of Object.entries({queue_id:['',null,'x'],user_id:['',null,'x'],bundle_id:['',null,'bare','a.'.repeat(128)],revision:['x','A'.repeat(64),'a'.repeat(63)],version:[0,-1,1.5,Number.MAX_SAFE_INTEGER+1,null,'1'],kind:['problem','voice',null]}))
  for(const value of values)assert.throws(()=>validateBatch(batch([{...entry,[key]:value}])),key);
});
test('extension delegates unrelated tools and adds only translation event schemas',async()=>{
 class Base {
  catalog(){return {events:[{name:'mirsa.voice.received'}]};}

  rpc(method,params){if(method==='tools/list')return Promise.resolve({tools:[{name:'existing_tool'}]});return Promise.resolve({delegated:true,method,params});}
 }
 const Service=extend({Service:Base}),s=new Service();
 assert.deepEqual(s.catalog().events.map(x=>x.name),['mirsa.voice.received',TRANSLATION,REVIEW]);
 assert.deepEqual((await s.rpc('tools/list')).tools.map(x=>x.name),['existing_tool','mirsa_pending_translation_events','mirsa_ack_translation_event']);
 assert.deepEqual(await s.rpc('tools/call',{name:'existing_tool'}),{delegated:true,method:'tools/call',params:{name:'existing_tool'}});
 const event=s.catalog().events.find(x=>x.name===TRANSLATION);
 assert.equal(event.payloadSchema.additionalProperties,false);
 assert.deepEqual(Object.keys(event.payloadSchema.properties.entries.items.properties).sort(),Object.keys(entry).sort());
});
