import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtempSync,mkdirSync,writeFileSync,readFileSync,rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join,dirname} from 'node:path';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';
const here=dirname(fileURLToPath(import.meta.url));
test('scoped routing is health-first, idempotent, restored after restart, rollback leaves old state untouched',()=>{
 const root=mkdtempSync(join(tmpdir(),'mirsa-routing-')),bin=join(root,'bin'),state=join(root,'fixture.json');
 mkdirSync(bin);mkdirSync(join(root,'translation25'));
 const database=join(root,'state.sqlite');writeFileSync(database,'unchanged old four subscriptions plus new watches');
 const initial={running:false,healthy:true,rules:[],calls:[]};
 writeFileSync(state,JSON.stringify(initial));
 const fake=`#!${process.execPath}
import {readFileSync,writeFileSync} from 'node:fs';
import {basename} from 'node:path';
const name=basename(process.argv[1]),args=process.argv.slice(2),p=process.env.ROUTE_FIXTURE,s=JSON.parse(readFileSync(p));
s.calls.push([name,...args]);let status=0;
if(name==='tmux'){
 if(args[0]==='has-session')status=s.running?0:1;
 if(args[0]==='new-session')s.running=true;
 if(args[0]==='kill-session')s.running=false;
}else if(name==='curl')status=s.running&&s.healthy?0:7;
else if(name==='iptables'){
 const op=args[2],chain=args[3];
 if(op==='-C')status=s.rules.includes(chain)?0:1;
 if(op==='-A')s.rules.push(chain);
 if(op==='-D')s.rules=s.rules.filter(c=>c!==chain);
}
writeFileSync(p,JSON.stringify(s));process.exit(status);
`;
 for(const cmd of ['tmux','curl','iptables'])writeFileSync(join(bin,cmd),fake,{mode:0o755});
 writeFileSync(join(bin,'sudo'),'#!/bin/sh\n[ "$1" != "-n" ] || shift\nexec "$@"\n',{mode:0o755});
 const env={...process.env,PATH:bin+':'+process.env.PATH,MIRSA_RELAY_ROOT:root,ROUTE_FIXTURE:state};
 const run=name=>spawnSync('/bin/sh',[join(here,name)],{env,encoding:'utf8'});
 const get=()=>JSON.parse(readFileSync(state));
 try{
  let result=run('activate.sh');assert.equal(result.status,0,result.stderr);
  let s=get();assert.deepEqual(s.rules,['PREROUTING','OUTPUT']);
  assert.equal(s.calls.filter(c=>c[0]==='tmux'&&c[1]==='new-session').length,1);
  assert.ok(s.calls.findIndex(c=>c[0]==='curl')<s.calls.findIndex(c=>c[0]==='iptables'));
  assert.ok(s.calls.find(c=>c[0]==='curl').includes('--retry-connrefused'));
  result=run('activate.sh');assert.equal(result.status,0,result.stderr);
  s=get();assert.deepEqual(s.rules,['PREROUTING','OUTPUT']);
  assert.equal(s.calls.filter(c=>c[0]==='tmux'&&c[1]==='new-session').length,1);
  // Simulate host restart with processes/routing gone. This is exactly the enabled init path.
  s.running=false;s.rules=[];writeFileSync(state,JSON.stringify(s));
  assert.equal(run('activate.sh').status,0);s=get();
  assert.deepEqual(s.rules,['PREROUTING','OUTPUT']);assert.equal(s.running,true);
  assert.equal(run('rollback-scoped.sh').status,0);s=get();
  assert.deepEqual(s.rules,[]);assert.equal(s.running,false);
  assert.equal(readFileSync(database,'utf8'),'unchanged old four subscriptions plus new watches');
  s.healthy=false;writeFileSync(state,JSON.stringify(s));
  assert.notEqual(run('activate.sh').status,0);assert.deepEqual(get().rules,[]);
  assert.ok(get().calls.filter(c=>c[0]==='tmux').every(c=>c.includes('mirsa-translation-relay25')));
 }finally{rmSync(root,{recursive:true,force:true});}
});
