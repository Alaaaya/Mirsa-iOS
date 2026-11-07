import test from 'node:test';
import assert from 'node:assert/strict';
import { cleanupStorage } from './cleanup.ts';
const H=3600000, now=Date.parse('2026-11-07T20:00:00Z');
const file=(name,h)=>({id:name,name,created_at:new Date(now-h*H).toISOString()});
function fake(jobs=[],out=[],options={}) {
 const calls=[],removed=[],dirs={'forge/jobs':jobs,'forge/out':out};
 const store={
  async list(dir,opts) {calls.push([dir,opts]);if(options.listError===dir)return {error:{message:'bad'}};return {data:dirs[dir].slice(opts.offset,opts.offset+opts.limit)};},
  async remove(names){removed.push(names);return options.removeError?{error:{message:'bad'}}:{data:names};}
 };
 return {db:{storage:{from:()=>store}},calls,removed};
}
test('exact boundaries and fresh preservation',async()=>{
 const f=fake([file('old',1),file('fresh',.99)],[file('day',24),file('fresh',23.99)]);
 assert.deepEqual(await cleanupStorage(f.db,'bucket','forge',now),['forge/jobs/old','forge/out/day']);
});
test('all 2501 entries paginated before mutation and deletion batched',async()=>{
 const f=fake(Array.from({length:2501},(_,i)=>file('job'+String(i).padStart(5,'0'),2)));
 assert.equal((await cleanupStorage(f.db,'bucket','forge',now)).length,2501);
 assert.deepEqual(f.calls.filter(c=>c[0]==='forge/jobs').map(c=>c[1].offset),[0,1000,2000]);
 assert.ok(f.calls.every(c=>c[1].sortBy.column==='name'));
 assert.ok(f.removed.every(x=>x.length<=100));
});
test('full final page requests empty next page',async()=>{
 const f=fake(Array.from({length:1000},(_,i)=>file('job'+i,2)));
 await cleanupStorage(f.db,'bucket','forge',now);
 assert.deepEqual(f.calls.filter(c=>c[0]==='forge/jobs').map(c=>c[1].offset),[0,1000]);
});
test('list errors fail rather than silently succeeding or deleting partial scan',async()=>{
 const f=fake([file('old',2)],[],{listError:'forge/out'});
 await assert.rejects(cleanupStorage(f.db,'bucket','forge',now),/storage_list/);
 assert.equal(f.removed.length,0);
});
test('remove errors propagate',async()=>{
 const f=fake([file('old',2)],[],{removeError:true});
 await assert.rejects(cleanupStorage(f.db,'bucket','forge',now),/storage_remove/);
});
test('folders skipped and bad file timestamp fails closed',async()=>{
 const f=fake([{name:'folder',id:null,created_at:null}]);
 assert.deepEqual(await cleanupStorage(f.db,'bucket','forge',now),[]);
 const g=fake([{id:'bad',name:'bad',created_at:null}]);
 await assert.rejects(cleanupStorage(g.db,'bucket','forge',now),/storage_timestamp/);
 assert.equal(g.removed.length,0);
});
test('fresh files cause no remove call',async()=>{
 const f=fake([file('fresh',0)],[file('fresh',0)]);
 assert.deepEqual(await cleanupStorage(f.db,'bucket','forge',now),[]);
 assert.equal(f.removed.length,0);
});
