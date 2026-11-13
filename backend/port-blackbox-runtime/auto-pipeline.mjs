// Trusted, isolated staged worker. Never call compile() in an HTTP process.
// Deployment must supply sandboxed Theos compiler and existing admin fix-push.
// Deterministic ABI policy approves only parser's narrow exact-encoding plan.
import {readFile,writeFile,mkdtemp,rm} from 'node:fs/promises';
import {join} from 'node:path';
import {randomUUID} from 'node:crypto';
import {prepareBuild,deliverReviewedBuild,sha} from './builder-integration.mjs';
import {recordConsentedPortReport} from './job-worker.mjs';
export async function buildAndDeliverAutomaticPort({store,jobID,storageRoot,buildRoot,
  resolveOriginal,compileInSandbox,existingReportRPC,existingFixPush}) {
 const job=store.db.prepare("SELECT * FROM jobs WHERE id=? AND kind='port' AND status='ready_for_build'").get(jobID);
 if(!job)throw Error('job_not_buildable');
 const plan=JSON.parse(await readFile(join(storageRoot,job.id+'.plan.json'),'utf8'));
 const proof=plan.automaticPort,source=store.source({user:job.user_id,device:job.device},
  {tweakID:job.tweak_id,bundleID:job.bundle_id,sourceSHA256:job.source_hash});
 if(!proof?.automatic||proof.originalSourceSHA256!==job.source_hash||sha(source?.code??'')!==job.source_hash||
  proof.outputSourceSHA256!==sha(plan.code)||plan.unresolved.length||!proof.abiProof.length)throw Error('proof_changed');
 // Original metadata comes from canonical owner-bound server source, not request.
 const original=await resolveOriginal({user:job.user_id,device:job.device,tweakID:job.tweak_id,sourceSHA256:job.source_hash});
 if(!original||original.sourceSHA256!==job.source_hash||original.bundleID!==job.bundle_id||
  !Number.isSafeInteger(original.version)||original.version<1)throw Error('original_metadata_missing');
 const claimed=store.db.prepare("UPDATE jobs SET status='awaiting_review' WHERE id=? AND status='ready_for_build'").run(jobID);
 if(claimed.changes!==1)throw Error('job_already_claimed');
 const dir=await mkdtemp(join(buildRoot,'mirsa-port-build-'));
 try {
  await recordConsentedPortReport({store,jobID,existingReportRPC});
  const prepared=await prepareBuild({directory:dir,name:'MirsaPort',source:plan.code,expectedSourceSHA256:sha(plan.code)});
  const result=await compileInSandbox({directory:dir,prepared,network:false,wallSeconds:120,cpuSeconds:90,memoryBytes:1073741824});
  if(result.exitCode!==0||!Buffer.isBuffer(result.dylib))throw Error('isolated_build_failed');
  const artifact={id:randomUUID(),code:plan.code,version:original.version+1,dylib:result.dylib};
  const evidenceSHA256=sha(JSON.stringify({proof,prepared,buildSHA256:sha(result.dylib)}));
  const delivery=await deliverReviewedBuild({
   job:{id:job.id,user:job.user_id,device:job.device,tweakID:job.tweak_id,bundleID:job.bundle_id,name:original.name,
    sourceSHA256:job.source_hash,originalCode:source.code,originalVersion:original.version,originalSettings:original.settings},
   artifact,review:{approved:true,jobID:job.id,originalSourceSHA256:job.source_hash,outputSourceSHA256:sha(plan.code),evidenceSHA256},
   existingFixPush});
  if(!delivery||delivery.error||delivery.ok!==true)throw Error('fix_delivery_not_confirmed');
  const receipt={id:job.id,fixID:artifact.id,status:'delivered',originalSourceSHA256:job.source_hash,
   newSourceSHA256:sha(plan.code),dylibSHA256:sha(result.dylib),version:artifact.version,
   evidenceSHA256,reviewedFixReady:true,manualEnableRequired:true};
  await writeFile(join(storageRoot,job.id+'.receipt.json'),JSON.stringify(receipt),{mode:0o600,flag:'wx'});
  store.db.prepare("UPDATE jobs SET status='delivered' WHERE id=?").run(jobID);
  return receipt;
 }catch(error){store.db.prepare("UPDATE jobs SET status='failed' WHERE id=?").run(jobID);throw error;}
 finally{await rm(dir,{recursive:true,force:true});}
}
