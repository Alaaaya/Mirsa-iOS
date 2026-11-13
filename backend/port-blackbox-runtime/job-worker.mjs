// Service worker seam. Jobs are not dispatched automatically by this staging code.
// inspectInSandbox is an approved isolated worker connector, NEVER a model/API.
// Existing fix report RPC + push RPC must be supplied from fresh live source.
import {readFile,writeFile,open,lstat} from 'node:fs/promises';
import {join} from 'node:path';
import {sha} from './builder-integration.mjs';
const UUID=/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
export async function runPortJob({store,jobID,storageRoot,inspectInSandbox}) {
 if(!UUID.test(jobID))throw Error('bad_job');
 const job=store.db.prepare("SELECT * FROM jobs WHERE id=? AND kind='port' AND status='queued'").get(jobID);
 if(!job)throw Error('job_not_queued');
 const p={user:job.user_id,device:job.device};
 const source=store.source(p,{tweakID:job.tweak_id,bundleID:job.bundle_id,sourceSHA256:job.source_hash});
 if(!source||sha(source.code)!==job.source_hash)throw Error('source_changed');
 const payload=JSON.parse(job.payload),paths={};
 for(const role of ['old','new']) {
  const input=payload[role+'IPA'],u=store.upload(p,input.uploadID);
  if(!u||u.state!=='ready'||u.role!==role||u.hash!==input.sha256||u.expires<=Date.now())throw Error('invalid_owned_upload');
  const path=join(storageRoot,u.id+'.ipa');
  const st=await lstat(path);
  if(!st.isFile()||st.isSymbolicLink()||st.size!==u.bytes)throw Error('upload_changed');
  // Bounded streaming re-hash; never loads whole archives in coordinator process.
  const fd=await open(path,'r');const {createHash}=await import('node:crypto');
  const h=createHash('sha256');let count=0;
  try {
   for await(const chunk of fd.createReadStream()){count+=chunk.length;if(count>u.bytes)throw Error('upload_changed');h.update(chunk);}
  }finally{await fd.close().catch(()=>{});}
  if(count!==u.bytes||h.digest('hex')!==u.hash)throw Error('upload_changed');
  paths[role]=path;
 }
 const plan=await inspectInSandbox({
  oldPath:paths.old,newPath:paths.new,source:source.code,bundleID:job.bundle_id,
  constraints:{network:false,executeBinaries:false,cpuSeconds:30,memoryBytes:1610612736,outputBytes:8388608}
 });
 const automatic=plan?.automaticPort;
 const autoValid=plan?.status==='ready_for_build'&&automatic?.automatic===true&&
   automatic.originalSourceSHA256===job.source_hash&&automatic.outputSourceSHA256===sha(plan.code)&&
   automatic.oldIPA===payload.oldIPA.sha256&&automatic.newIPA===payload.newIPA.sha256&&
   Array.isArray(automatic.abiProof)&&automatic.abiProof.length>0&&plan.unresolved?.length===0;
 if(!plan||plan.sourceSHA256!==job.source_hash||(!autoValid&&plan.code!==source.code)||
    plan.oldIPA!==payload.oldIPA.sha256||plan.newIPA!==payload.newIPA.sha256||
    (!autoValid&&plan.status!=='unresolved')||!Array.isArray(plan.unresolved)||!Array.isArray(plan.candidates))
  throw Error('invalid_worker_plan');
 const output=JSON.stringify(plan);
 if(Buffer.byteLength(output)>8388608)throw Error('plan_too_large');
 await writeFile(join(storageRoot,job.id+'.plan.json'),output,{mode:0o600,flag:'wx'});
 store.db.prepare("UPDATE jobs SET status=? WHERE id=? AND status='queued'").run(autoValid?'ready_for_build':'unresolved',jobID);
 return {id:jobID,status:autoValid?'ready_for_build':'unresolved',requiresReview:!autoValid,automaticRepair:autoValid};
}
export async function forwardConsentedCrash({store,jobID,existingReportRPC}) {
 const job=store.db.prepare("SELECT * FROM jobs WHERE id=? AND kind='crash-review' AND status='queued'").get(jobID);
 if(!job)throw Error('job_not_queued');
 const payload=JSON.parse(job.payload);
 const e=store.enrollment({user:job.user_id,device:job.device},payload.installationID);
 if(!e||e.revoked||e.expires<=Date.now()||e.source_hash!==job.source_hash)throw Error('consent_expired');
 const s=store.source({user:job.user_id,device:job.device},{tweakID:job.tweak_id,bundleID:job.bundle_id,sourceSHA256:job.source_hash});
 if(!s||sha(s.code)!==job.source_hash)throw Error('source_changed');
 const row={id:job.id,user_id:job.user_id,device:job.device,tweak_id:job.tweak_id,
   bundle_id:job.bundle_id,name:'Mirsa tweak',kind:'crash',
   // No attribution claims. Fixed text is valid existing sanitized crash diagnostics.
   diagnostics:payload.exception?'Exception Type: Uncaught Objective-C exception; culprit unknown':
    'Exception Type: Fatal signal '+payload.signal+'; culprit unknown',
   source_sha256:job.source_hash,consent:true};
 if(payload.activeHook)row.diagnostics+='; active at crash (not cause): '+payload.activeHook.kind+'['+payload.activeHook.className+' '+payload.activeHook.selector+']; source '+job.source_hash;
 const result=await existingReportRPC(row,sha(JSON.stringify(row)));
 if(result!=='ok')throw Error('existing_report_rejected');
 store.db.prepare("UPDATE jobs SET status='awaiting_review' WHERE id=?").run(jobID);
 return {status:'awaiting_review',requiresReview:true,culprit:null,automaticRepair:false};
}

export async function recordConsentedPortReport({store,jobID,existingReportRPC}) {
 const job=store.db.prepare("SELECT * FROM jobs WHERE id=? AND kind='port'").get(jobID);
 if(!job)throw Error('missing_port_job');
 const payload=JSON.parse(job.payload);
 if(payload.consent!==true)throw Error('explicit_consent_required');
 const source=store.source({user:job.user_id,device:job.device},{tweakID:job.tweak_id,bundleID:job.bundle_id,sourceSHA256:job.source_hash});
 if(!source||sha(source.code)!==job.source_hash)throw Error('source_changed');
 const row={id:job.id,user_id:job.user_id,device:job.device,tweak_id:job.tweak_id,
  bundle_id:job.bundle_id,name:'Mirsa tweak',kind:'build',
  diagnostics:'warning: User requested a version port; mapping and ABI require review.',
  source_sha256:job.source_hash,consent:true};
 if(await existingReportRPC(row,sha(JSON.stringify(row)))!=='ok')throw Error('existing_report_rejected');
 return {ok:true,requiresReview:true,automaticRepair:false};
}
