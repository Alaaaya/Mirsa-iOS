// Apple SDK end-to-end staged fixture. No production credentials/RPCs.
// Its fix-push test connector is an in-memory inbox, NOT a deployed transport.
import assert from 'node:assert/strict';
import {mkdtemp,readFile,writeFile,rm,mkdir} from 'node:fs/promises';
import {join} from 'node:path';
import {tmpdir} from 'node:os';
import {randomUUID} from 'node:crypto';
import {execFileSync} from 'node:child_process';
import {StagedStore} from './staged-store.mjs';
import {createStagedAdapter} from './adapter.mjs';
import {runPortJob} from './job-worker.mjs';
import {buildAndDeliverAutomaticPort} from './auto-pipeline.mjs';
import {sha} from './builder-integration.mjs';
const root=await mkdtemp(join(tmpdir(),'mirsa-ci-port-'));
const store=new StagedStore(),p={user:randomUUID(),device:randomUUID(),fixDeviceAuthenticated:true};
const source='%hook OldController\n- (void)tap { %orig; }\n%end\n';
const identity={tweakID:randomUUID(),bundleID:'com.example.test',sourceSHA256:sha(source)};
const adapter=createStagedAdapter({store,storageRoot:root,portEnabled:true});
const request=b=>adapter(new Request('https://fixture.invalid/forge',{method:'POST',body:JSON.stringify(b)}),p);
const output=process.env.MIRSA_EVIDENCE_DIR??'pipeline-evidence';await mkdir(output,{recursive:true});
try{
 store.registerOwnedSource({user:p.user,device:p.device,...identity,code:source});
 const refs={};
 for(const role of ['old','new']){
  const data=await readFile('fixtures/'+role+'.ipa'),id=randomUUID(),hash=sha(data);
  let r=await request({action:'port-upload-create',id,role,bytes:data.length,sha256:hash});assert.equal(r.status,200);
  const upload=await r.json();
  r=await adapter(new Request('https://fixture.invalid/forge'+upload.uploadURL,{method:'POST',
   headers:{'content-type':'application/octet-stream','content-length':String(data.length)},body:data}),p);
  assert.equal(r.status,200);refs[role+'IPA']={uploadID:id,sha256:hash};
 }
 const id=randomUUID();
 assert.equal((await request({action:'port-request',id,...identity,consent:true,name:'Fixture',code:source,...refs})).status,202);
 // This fixture plan was produced by actual bounded Linux bubblewrap parser.
 // Apple runner has no bubblewrap. Test DOES NOT substitute this connector in production.
 const fixture=JSON.parse(await readFile('fixtures/plan.json','utf8'));
 const parsed=await runPortJob({store,jobID:id,storageRoot:root,inspectInSandbox:async input=>{
  assert.equal(input.source,source);assert.equal(sha(await readFile(input.oldPath)),fixture.oldIPA);
  assert.equal(sha(await readFile(input.newPath)),fixture.newIPA);return fixture;
 }});
 assert.equal(parsed.status,'ready_for_build');
 let reported=false,delivered=false,binary;
 const result=await buildAndDeliverAutomaticPort({store,jobID:id,storageRoot:root,buildRoot:root,
  resolveOriginal:async target=>{
   assert.equal(target.user,p.user);assert.equal(target.device,p.device);
   return {sourceSHA256:identity.sourceSHA256,bundleID:identity.bundleID,version:1,name:'Fixture',settings:[]};
  },
  existingReportRPC:async row=>{assert.equal(row.user_id,p.user);assert.equal(row.device,p.device);assert.equal(row.source_sha256,sha(source));assert.equal(row.consent,true);reported=true;return 'ok';},
  compileInSandbox:async ({directory,network})=>{
   assert.equal(network,false); // CI trusted fixture only, compiler runner is ephemeral hosted VM.
   const sdk=execFileSync('xcrun',['--sdk','iphoneos','--show-sdk-path'],{encoding:'utf8'}).trim();
   const generated=execFileSync('perl',[process.env.MIRSA_CI_LOGOS,'-c','generator=internal',join(directory,'Tweak.xm')]);
   await writeFile(join(directory,'Tweak.mm'),generated);
   execFileSync('xcrun',['--sdk','iphoneos','clang++','-arch','arm64','-isysroot',sdk,
    '-miphoneos-version-min=14.0','-dynamiclib','-fobjc-arc','-include','Foundation/Foundation.h',
    '-framework','Foundation',join(directory,'Tweak.mm'),'-o',join(directory,'Fix.dylib')]);
   binary=await readFile(join(directory,'Fix.dylib'));return {exitCode:0,dylib:binary};
  },
  existingFixPush:async b=>{
   assert(reported);assert.equal(b.action,'fix-push');assert.equal(b.targetUser,p.user);assert.equal(b.targetDevice,p.device);
   assert.equal(b.tweakID,identity.tweakID);assert.equal(b.bundleID,identity.bundleID);assert.equal(b.version,2);
   assert.equal(b.code,source.replace('%hook OldController','%hook NewController'));
   assert.equal(b.sourceSHA256,sha(b.code));assert.equal(b.dylibSHA256,sha(Buffer.from(b.dylib,'base64')));
   delivered=true;return {ok:true,id:b.id};
  }});
 assert(delivered);assert.equal(result.status,'delivered');assert.equal(result.manualEnableRequired,true);
 const status=await (await request({action:'port-status',id})).json();
 assert.equal(status.reviewedFixReady,true);assert.equal(status.originalSourceSHA256,sha(source));
 assert.equal(status.newSourceSHA256,result.newSourceSHA256);assert.equal(status.autoEnable,false);
 await assert.rejects(buildAndDeliverAutomaticPort({store,jobID:id}),/job_not_buildable/);
 await writeFile(join(output,'Fix.dylib'),binary);
 await writeFile(join(output,'result.json'),JSON.stringify({testOnly:true,productionCalls:0,deliveryConnector:'in-memory-existing-fix-push-shaped',...result,statusResponse:status},null,2));
 console.log('Apple SDK generated real automatic port dylib; owner-bound staged fix-inbox transport assertions PASS');
}finally{store.close();await rm(root,{recursive:true,force:true});}
