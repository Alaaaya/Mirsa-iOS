import {prepareBuild,sha} from './builder-integration.mjs';
const source='%hook NSObject\n- (NSString *)description { return %orig; }\n%end\n';
const result=await prepareBuild({directory:'build-ci',name:'MirsaReporter',source,expectedSourceSHA256:sha(source),
 enrollment:{consent:true,installationID:'11111111-1111-4111-8111-111111111111',reportToken:'1'.repeat(64),
 bundleID:'com.mirsa.offline.fixture',appVersion:'1.0',sourceSHA256:sha(source),expiresAt:'2099-01-01T00:00:00Z'},
 reportEndpoint:'https://invalid.example/blackbox-report',approvedReportOrigin:'https://invalid.example'});
console.log(JSON.stringify(result));
