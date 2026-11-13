// Trusted server/builder integration only. Never called by request body fields.
// prepareBuild preserves original Logos source byte-for-byte in Tweak.xm.
// It adds reporter as SEPARATE trusted compiler units, only after enrollment.
import {readFile,writeFile,copyFile,chmod,mkdir} from 'node:fs/promises';
import {join,dirname} from 'node:path';
import {fileURLToPath} from 'node:url';
import {createHash} from 'node:crypto';
import {instrumentHooks} from './instrumentation.mjs';
const ROOT=dirname(fileURLToPath(import.meta.url));
const UUID=/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
const HASH=/^[0-9a-f]{64}$/;
export const sha=value=>createHash('sha256').update(value).digest('hex');
export async function prepareBuild({directory,name,source,expectedSourceSHA256,enrollment=null,reportEndpoint=null,approvedReportOrigin=null}) {
 if(!/^[A-Za-z][A-Za-z0-9]{0,39}$/.test(name)||!HASH.test(expectedSourceSHA256)||
    typeof source!=='string'||Buffer.byteLength(source)>196608||sha(source)!==expectedSourceSHA256)
  throw Error('source_identity_mismatch');
 // directory must be trusted server mkdtemp(), not a caller path.
 await mkdir(directory,{recursive:true,mode:0o700});
 await writeFile(join(directory,'Tweak.xm'),source,{mode:0o600,flag:'wx'});
 let files='Tweak.xm';const runtimeHashes={};let instrumentation=null;
 if(enrollment) {
  if(enrollment.consent!==true||enrollment.revoked||!Number.isFinite(Date.parse(enrollment.expiresAt))||Date.parse(enrollment.expiresAt)<=Date.now()||
     enrollment.sourceSHA256!==expectedSourceSHA256||!UUID.test(enrollment.installationID)||
     !HASH.test(enrollment.reportToken)||!approvedReportOrigin||
     !/^[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+$/.test(enrollment.bundleID??'')||
     !/^[A-Za-z0-9._+-]{1,32}$/.test(enrollment.appVersion??''))throw Error('enrollment_required');
  const endpoint=new URL(reportEndpoint);
  if(endpoint.protocol!=='https:'||endpoint.origin!==approvedReportOrigin||
     endpoint.username||endpoint.password||endpoint.hash||endpoint.search||!endpoint.pathname.endsWith('/blackbox-report')||
     !/^[a-zA-Z0-9/_.-]+$/.test(endpoint.pathname))throw Error('unapproved_report_endpoint');
  instrumentation=instrumentHooks(source,expectedSourceSHA256);
  if(enrollment.manifestSHA256 && enrollment.manifestSHA256!==instrumentation.manifestSHA256)throw Error('manifest_changed');
  await writeFile(join(directory,'Instrumented.xm'),instrumentation.code,{mode:0o600,flag:'wx'});
  await writeFile(join(directory,'HookManifest.json'),JSON.stringify(instrumentation.manifest),{mode:0o600,flag:'wx'});
  const config=[
   '#define MIRSA_BB_OPT_IN 1',
   '#define MIRSA_BB_MANIFEST_SHA '+JSON.stringify(instrumentation.manifestSHA256),
   '#define MIRSA_BB_INSTALLATION '+JSON.stringify(enrollment.installationID),
   '#define MIRSA_BB_REPORT_TOKEN '+JSON.stringify(enrollment.reportToken),
   '#define MIRSA_BB_ENDPOINT '+JSON.stringify(endpoint.href),
   '#define MIRSA_BB_BUNDLE '+JSON.stringify(enrollment.bundleID),
   '#define MIRSA_BB_APP_VERSION '+JSON.stringify(enrollment.appVersion),
   ''
  ].join('\n');
  for(const file of ['runtime.c','runtime.h','breadcrumb.c','breadcrumb.h','BlackboxUploader.m']) {
   await copyFile(join(ROOT,file),join(directory,file));
   runtimeHashes[file]=sha(await readFile(join(directory,file)));
  }
  await writeFile(join(directory,'BlackboxConfig.h'),config,{mode:0o600,flag:'wx'});
  files='Instrumented.xm runtime.c breadcrumb.c BlackboxUploader.m';
 }
 const makefile=[
  'TARGET := iphone:clang:latest:14.0',
  'ARCHS = arm64 arm64e',
  'include $(THEOS)/makefiles/common.mk',
  'TWEAK_NAME = '+name,
  name+'_FILES = '+files,
  name+'_CFLAGS = -fobjc-arc -Wall -Wextra',
  name+'_FRAMEWORKS = Foundation',
  'include $(THEOS_MAKE_PATH)/tweak.mk',''
 ].join('\n');
 await writeFile(join(directory,'Makefile'),makefile,{mode:0o600,flag:'wx'});
 return {sourceSHA256:sha(await readFile(join(directory,'Tweak.xm'))),
   reporterIncluded:Boolean(enrollment),manifest:instrumentation?.manifest??null,manifestSHA256:instrumentation?.manifestSHA256??null,runtimeSHA256:runtimeHashes,files:files.split(' '),requiresDeviceValidation:true};
}
export async function deliverReviewedBuild({job,artifact,review,existingFixPush}) {
 // Existing fix-push retains admin auth, target-report consent, version uniqueness,
 // source/dylib validation and owner/device-bound inbox. No new transport bypass.
 if(!review||review.approved!==true||review.jobID!==job.id||
    review.originalSourceSHA256!==job.sourceSHA256||
    sha(job.originalCode)!==job.sourceSHA256||
    review.outputSourceSHA256!==sha(artifact.code)||
    !HASH.test(review.evidenceSHA256??'')||
    !Number.isSafeInteger(artifact.version)||artifact.version<=job.originalVersion||
    !Buffer.isBuffer(artifact.dylib)||artifact.dylib.length<32||artifact.dylib.length>4194304)
   throw Error('reviewed_build_required');
 if(!/^[0-9a-f-]{36}$/.test(artifact.id??''))throw Error('bad_artifact_id');
 const magic=artifact.dylib.subarray(0,4).toString('hex');
 if(!['cafebabe','bebafeca','cffaedfe','feedfacf','cafebabf'].includes(magic))throw Error('not_macho');
 return existingFixPush({
  action:'fix-push',id:artifact.id,targetUser:job.user,targetDevice:job.device,
  tweakID:job.tweakID,bundleID:job.bundleID,name:job.name,version:artifact.version,
  code:artifact.code,settings:job.originalSettings,
  sourceSHA256:sha(artifact.code),dylibSHA256:sha(artifact.dylib),
  dylib:artifact.dylib.toString('base64')
 });
}
