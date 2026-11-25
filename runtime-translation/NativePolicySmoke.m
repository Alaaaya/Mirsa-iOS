// Compile/link on iOS simulator and execute via simulator-smoke.sh.
#import "RuntimeTranslate.m"
#import <assert.h>
#import <objc/runtime.h>
static NSInteger fixtureCode,fixtureCalls,fixtureItems;
@interface MirsaFallbackProtocol : NSURLProtocol
@end
@implementation MirsaFallbackProtocol
+ (BOOL)canInitWithRequest:(NSURLRequest *)request { return [request.URL.host isEqual:@"staging.fixture.invalid"]; }
+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request { return request; }
- (void)startLoading {
 NSData *body=self.request.HTTPBody;
 if(!body && self.request.HTTPBodyStream){
  NSInputStream *stream=self.request.HTTPBodyStream;[stream open];NSMutableData *data=[NSMutableData data];uint8_t b[1024];NSInteger n;
  while((n=[stream read:b maxLength:sizeof(b)])>0)[data appendBytes:b length:(NSUInteger)n];
  [stream close];body=data;
 }
 NSDictionary *request=[NSJSONSerialization JSONObjectWithData:body options:0 error:NULL];
 NSArray *items=request[@"items"];assert(items.count==3);
 @synchronized(MirsaFallbackProtocol.class){fixtureCalls++;fixtureItems=items.count;}
 NSMutableArray *entries=[NSMutableArray array];
 for(NSDictionary *item in items)[entries addObject:@{@"source":item[@"text"],@"labelId":NSUUID.UUID.UUIDString,@"reviewId":NSUUID.UUID.UUIDString,@"kind":@"missing",@"version":@1}];
 NSDictionary *reply=@{@"bundleId":request[@"bundleId"],@"revision":request[@"revision"],@"translations":@{},@"entries":@[],
  @"deferred":[NSString stringWithFormat:@"provider_%ld",(long)fixtureCode],@"queue":@{@"persisted":@YES,@"entries":entries}};
 NSHTTPURLResponse *response=[[NSHTTPURLResponse alloc]initWithURL:self.request.URL statusCode:200 HTTPVersion:@"HTTP/1.1" headerFields:@{@"Content-Type":@"application/json"}];
 [self.client URLProtocol:self didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageNotAllowed];
 [self.client URLProtocol:self didLoadData:[NSJSONSerialization dataWithJSONObject:reply options:0 error:NULL]];
 [self.client URLProtocolDidFinishLoading:self];
}
- (void)stopLoading {}
@end
@interface NSURLSessionConfiguration (MirsaFallbackFixture)
+ (NSURLSessionConfiguration *)mirsaFixtureConfiguration;
@end
@implementation NSURLSessionConfiguration (MirsaFallbackFixture)
+ (NSURLSessionConfiguration *)mirsaFixtureConfiguration {
 NSURLSessionConfiguration *config=[self mirsaFixtureConfiguration]; // original after swap
 config.protocolClasses=@[MirsaFallbackProtocol.class];return config;
}
@end
int main(int argc,char **argv) {@autoreleasepool {
 assert(NetworkSafe(@"设置"));
 assert(NetworkSafe(@"设置 %@") && NetworkSafe(@"설정 %lld") && NetworkSafe(@"せってい %.*f"));
 assert(HasCJK(@"せってい") && HasCJK(@"설정") && HasCJK(@"ㄱ"));
 assert(PlaceholdersPreserved(@"设置 %lld %.*f %%",@"الإعدادات %lld %.*f %%"));
 assert(!PlaceholdersPreserved(@"设置 %lld %.*f",@"الإعدادات %.*f %lld"));
 assert(!PlaceholdersPreserved(@"设置 %lld",@"الإعدادات %ld"));
 assert(!PlaceholdersPreserved(@"设置 %.*f",@"الإعدادات %.2f"));
 assert(!PlaceholdersPreserved(@"设置 %%",@"الإعدادات %"));
 assert(PlaceholdersPreserved(@"设置 %1$*2$.*3$f %4$lld",@"الإعدادات %4$lld %1$*2$.*3$f"));
 assert(!PlaceholdersPreserved(@"设置 %1$*2$.*3$f",@"الإعدادات %1$*3$.*2$f"));
 assert(!PlaceholdersPreserved(@"设置 %1$*.*3$f %4$lld",@"الإعدادات %4$lld %1$*.*3$f"));
 assert(!PlaceholdersPreserved(@"<b data='%lld'>设置 %.*f</b>",@"<b data='%.*f'>إعدادات %lld</b>"));
 assert([IsolateLatin(@"قيمة %lld و%.*f و%1$*2$.*3$f %%") isEqual:@"قيمة %lld و%.*f و%1$*2$.*3$f %%"]);

 for(NSString *s in @[@"用户邮件 test@example.com",@"设置 https://example.com",@"设置 /private/test",@"密码 abc",@"订单 123456",@"设置 api_key=abc",@"设置 example.org"]){assert(!NetworkSafe(s));}
 assert([Placeholders(@"النسخة %1$@ %@ %02d {build}") isEqual:Placeholders(@"版本 %1$@ %@ %02d {build}")]);
 assert(![Placeholders(@"版本 %@") isEqual:Placeholders(@"النسخة %d")]);
 NSMutableString *s=[NSMutableString string];
 for(int i=0;i<4095;i++)[s appendString:@"中"];
 [s appendString:@"𠀀"];
 NSString *cut=SafePrefix(s,4096);
 assert(cut.length==4095 && [cut dataUsingEncoding:NSUTF8StringEncoding]);
 assert(HasCJK(@"𠀀") && !HasCJK(@"مرحبا"));
 // Verify permission repair of an existing app-local diagnostic file.
 NSString *dir=[NSHomeDirectory() stringByAppendingPathComponent:@"Documents"];
 [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:NULL];
 NSString *path=[dir stringByAppendingPathComponent:@"MirsaTranslateMissing.txt"];
 [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
 int fd=open(path.fileSystemRepresentation,O_WRONLY|O_CREAT,0644);assert(fd>=0);close(fd);chmod(path.fileSystemRepresentation,0644);
 LogMissing(s,s);dispatch_sync(missingQueue,^{});
 struct stat st;assert(lstat(path.fileSystemRepresentation,&st)==0 && (st.st_mode&0777)==0600);
 NSData *lines=[NSData dataWithContentsOfFile:path];assert(lines.length>0);
 // Symlinks must not be followed or modify the target.
 [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
 NSString *target=[dir stringByAppendingPathComponent:@"MirsaTranslateSmokeTarget"];
 [@"sentinel" writeToFile:target atomically:YES encoding:NSUTF8StringEncoding error:NULL];
 assert(symlink(target.fileSystemRepresentation,path.fileSystemRepresentation)==0);
 LogMissing(@"另一项",@"另一项");dispatch_sync(missingQueue,^{});
 assert([[NSString stringWithContentsOfFile:target encoding:NSUTF8StringEncoding error:NULL] isEqual:@"sentinel"]);
 [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
 [[NSFileManager defaultManager] removeItemAtPath:target error:NULL];
 // Signed public vector has no corresponding server capability, so it grants nothing online.
 assert(argc==2);
 NSDictionary *c=[NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:@(argv[1])] options:0 error:NULL];
 assert(ValidActivation(c,@"com.example.activationfixture",2000000010));
 assert(!ValidActivation(c,@"com.other.app",2000000010));
 assert(!ValidActivation(c,@"com.example.activationfixture",2000086401));
 for(NSString *key in @[@"activation",@"revision",@"installationId",@"token"]){
  NSMutableDictionary *bad=[c mutableCopy];bad[key]=@"tampered";
  assert(!ValidActivation(bad,@"com.example.activationfixture",2000000010));
 }
 NSString *suite=[@"mirsa.queue.smoke." stringByAppendingString:NSUUID.UUID.UUIDString];
 NSUserDefaults *prefs=[[NSUserDefaults alloc] initWithSuiteName:suite];
 assert(BannerShouldShow(prefs,@"com.first.app",YES));
 assert(!BannerShouldShow(prefs,@"com.first.app",NO));
 BannerPresentInWindow(nil,prefs,@"com.first.app",YES);
 assert(BannerShouldShow(prefs,@"com.first.app",YES)); // never marked on unavailable window
 [prefs setBool:YES forKey:BannerPreferenceKey(@"com.first.app")];
 NSUserDefaults *restarted=[[NSUserDefaults alloc] initWithSuiteName:suite];
 assert(!BannerShouldShow(restarted,@"com.first.app",YES));
 assert(BannerShouldShow(restarted,@"com.second.app",YES));
 assert(!pendingBanner);BannerRemove();
 // Actual visible attachment marks only this app and never creates an interactive overlay.
 bannerShownThisProcess=NO;
 UIWindow *window=[[UIWindow alloc] initWithFrame:CGRectMake(0,0,390,844)];
 window.rootViewController=[UIViewController new];window.hidden=NO;
 BannerPresentInWindow(window,prefs,@"com.visible.app",YES);
 assert(pendingBanner && !pendingBanner.userInteractionEnabled && !BannerShouldShow(prefs,@"com.visible.app",YES));
 UILabel *first=pendingBanner;BannerPresentInWindow(window,prefs,@"com.visible.app",YES);assert(pendingBanner==first);
 NSDate *end=[NSDate dateWithTimeIntervalSinceNow:5.2];
 while(end.timeIntervalSinceNow>0)[NSRunLoop.currentRunLoop runMode:NSDefaultRunLoopMode beforeDate:end];
 assert(!pendingBanner); // real auto-dismiss timer fired, no blocking alert
 bannerShownThisProcess=NO; // simulated process restart, persistent marker still prevents redisplay
 BannerPresentInWindow(window,prefs,@"com.visible.app",YES);assert(!pendingBanner);
 assert(BannerShouldShow(prefs,@"com.different.app",YES));
 window.hidden=YES;
 [prefs removePersistentDomainForName:suite];
 onlineConfig=c;onlinePositive=[NSMutableDictionary dictionary];onlineMeta=[NSMutableDictionary dictionary];onlineUncovered=[NSMutableSet setWithObject:@"设置"];
 ApplyOnlineEntries(@[@{@"source":@"设置",@"translation":@"الإعدادات",@"provenance":@"kat",@"version":@2}]);
 assert([OnlineLookup(@"设置") isEqual:@"الإعدادات"] && !onlineUncovered.count);
 assert([onlineMeta[@"设置"][@"p"] isEqual:@"kat"] && [onlineMeta[@"设置"][@"v"] integerValue]==2);
 ApplyOnlineEntries(@[@{@"source":@"设置",@"translation":@"خطأ",@"provenance":@"gemini",@"version":@99}]);
 assert([OnlineLookup(@"设置") isEqual:@"الإعدادات"]); // late Gemini cannot replace Kat
 ApplyOnlineEntries(@[@{@"source":@"说明",@"translation":@"شرح"}]);
 assert(!OnlineLookup(@"说明")); // unversioned candidates remain rejected
 onlinePositive=[NSMutableDictionary dictionary];onlineMeta=[NSMutableDictionary dictionary];LoadOnlineCache();
 assert([OnlineLookup(@"设置") isEqual:@"الإعدادات"]); // exact next-launch load path
 NSString *oldKey=DictionaryCacheKey();
 NSMutableDictionary *other=[c mutableCopy];other[@"revision"]=[@"b" stringByPaddingToLength:64 withString:@"b" startingAtIndex:0];
 onlineConfig=other;onlinePositive=[NSMutableDictionary dictionary];onlineMeta=[NSMutableDictionary dictionary];LoadOnlineCache();assert(!OnlineLookup(@"设置"));
 onlineConfig=c;
 ApplyOnlineEntries(@[@{@"source":@"设置 %d",@"translation":@"الإعدادات %@",@"provenance":@"kat",@"version":@2}]);
 assert(!OnlineLookup(@"设置 %d")); // placeholders never changed
 [NSUserDefaults.standardUserDefaults removeObjectForKey:oldKey];
 // Exercise REAL runtime queue batching and original-rendering path on both fallback kinds.
 Method original=class_getClassMethod(NSURLSessionConfiguration.class,@selector(ephemeralSessionConfiguration));
 Method mocked=class_getClassMethod(NSURLSessionConfiguration.class,@selector(mirsaFixtureConfiguration));
 method_exchangeImplementations(original,mocked);
 for(NSNumber *code in @[@429,@503]){
  NSMutableDictionary *fixture=[c mutableCopy];fixture[@"endpoint"]=@"https://staging.fixture.invalid/runtime";
  fixture[@"expiresAt"]=@"2033-05-19T03:33:20Z";onlineConfig=fixture;
  onlinePositive=[NSMutableDictionary dictionary];onlineMeta=[NSMutableDictionary dictionary];onlinePending=[NSMutableSet set];
  onlineNegative=[NSMutableDictionary dictionary];onlineUncovered=[NSMutableSet set];onlineIssued=0;onlineWaiting=0;onlineFlushScheduled=NO;
  onlineQueue=dispatch_queue_create("mirsa.runtime.fixture.batch",DISPATCH_QUEUE_SERIAL);
  fixtureCode=code.integerValue;fixtureCalls=0;fixtureItems=0;
  NSArray *sources=@[@"重试按钮",@"帮助按钮",@"更多按钮"];
  NSTimeInterval started=NSDate.date.timeIntervalSince1970;
  for(NSString *source in sources){assert([Translate(source) isEqual:source]);QueueOnline(source);}
  assert(NSDate.date.timeIntervalSince1970-started<0.2); // rendering did not wait for HTTP
  NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:5];
  BOOL waiting=YES;
  while(waiting && deadline.timeIntervalSinceNow>0){
   [NSRunLoop.currentRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
   os_unfair_lock_lock(&onlineLock);waiting=onlineWaiting>0;os_unfair_lock_unlock(&onlineLock);
  }
  assert(!waiting);
  @synchronized(MirsaFallbackProtocol.class){assert(fixtureCalls==1 && fixtureItems==3);}
  for(NSString *source in sources){assert(!OnlineLookup(source));assert([Translate(source) isEqual:source]);}
  assert(!onlinePositive.count && onlineNegative.count==3);
 }
 method_exchangeImplementations(original,mocked);
 NSLog(@"Native batched 429/503 fallback original UI and no-crash smoke passed");
 NSLog(@"Native policy, activation, queue cache and banner persistence smoke passed");return 0;
}}
