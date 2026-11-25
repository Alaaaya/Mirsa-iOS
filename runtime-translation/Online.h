// Missing-only, fail-open translation. Never blocks the rendering thread.
@interface MirsaNoRedirect : NSObject <NSURLSessionDataDelegate>
@property(nonatomic,strong) NSMutableData *body;
@property(nonatomic,strong) NSHTTPURLResponse *response;
@property(nonatomic,strong) NSError *error;
@property(nonatomic) dispatch_semaphore_t finished;
@end
@implementation MirsaNoRedirect
- (instancetype)init {if((self=[super init])){_body=[NSMutableData data];_finished=dispatch_semaphore_create(0);}return self;}
- (void)URLSession:(NSURLSession *)s task:(NSURLSessionTask *)t willPerformHTTPRedirection:(NSHTTPURLResponse *)r newRequest:(NSURLRequest *)q completionHandler:(void (^)(NSURLRequest *))done {
 (void)s;(void)t;(void)r;(void)q;done(nil);
}
- (void)URLSession:(NSURLSession *)s dataTask:(NSURLSessionDataTask *)t didReceiveResponse:(NSURLResponse *)r completionHandler:(void (^)(NSURLSessionResponseDisposition))done {
 (void)s;(void)t;
 self.response=[r isKindOfClass:NSHTTPURLResponse.class]?(id)r:nil;
 done(self.response.statusCode==200 && r.expectedContentLength<=1048576?NSURLSessionResponseAllow:NSURLSessionResponseCancel);
}
- (void)URLSession:(NSURLSession *)s dataTask:(NSURLSessionDataTask *)t didReceiveData:(NSData *)d {
 (void)s;if(self.body.length+d.length>1048576){self.error=[NSError errorWithDomain:@"MirsaTranslate" code:1 userInfo:nil];[t cancel];return;}[self.body appendData:d];
}
- (void)URLSession:(NSURLSession *)s task:(NSURLSessionTask *)t didCompleteWithError:(NSError *)e {
 (void)s;(void)t;if(e)self.error=e;dispatch_semaphore_signal(self.finished);
}
@end
static NSTimeInterval OnlineExpiry(id value) {
 if(![value isKindOfClass:NSString.class])return 0;
 NSISO8601DateFormatter *f=[NSISO8601DateFormatter new];
 NSDate *d=[f dateFromString:value];
 if(!d){f.formatOptions=NSISO8601DateFormatWithInternetDateTime|NSISO8601DateFormatWithFractionalSeconds;d=[f dateFromString:value];}
 return d.timeIntervalSince1970;
}
static NSDictionary *onlineConfig;
static NSMutableDictionary *onlinePositive,*onlineNegative,*onlineMeta;
static NSMutableSet *onlinePending;
static dispatch_queue_t onlineQueue;
static BOOL onlineDenied;
static NSUInteger onlineIssued, onlineWaiting;
static NSMutableSet *onlineUncovered;
static os_unfair_lock onlineLock=OS_UNFAIR_LOCK_INIT;
#import "OnlineMerge.h"
static NSString *SafePrefix(NSString *s,NSUInteger n) {
 if(s.length<=n)return [s copy];
 if(n && CFStringIsSurrogateHighCharacter([s characterAtIndex:n-1]))n--;
 return [s substringToIndex:n];
}
static BOOL DictionarySourceSafe(NSString *s) {
 if(!s.length || s.length>256)return NO;
 // Deliberately conservative. Private/user-entered material is never opted in.
 static NSRegularExpression *bad;static dispatch_once_t once;
 dispatch_once(&once,^{bad=[NSRegularExpression regularExpressionWithPattern:@"(?i)(https?[:/]|www\\.|@|[/\\\\]|[0-9０-９]{4,}|token|secret|password|passwd|bearer|api.?key|authorization|cookie|private|密码|密钥|验证码|账户|账号|地址|姓名|电话|邮件|订单|余额|消息|聊天|身份证|信用卡)" options:0 error:NULL];});
 NSString *screened=[PrintfRegex() stringByReplacingMatchesInString:s options:0 range:NSMakeRange(0,s.length) withTemplate:@""];
 if([bad firstMatchInString:screened options:0 range:NSMakeRange(0,screened.length)])return NO;
 NSRegularExpression *domain=[NSRegularExpression regularExpressionWithPattern:@"[A-Za-z0-9-]+\\.[A-Za-z]{2,}" options:0 error:NULL];
 if([domain firstMatchInString:screened options:0 range:NSMakeRange(0,screened.length)])return NO;
 if([screened rangeOfCharacterFromSet:NSCharacterSet.controlCharacterSet].location!=NSNotFound)return NO;
 return YES;
}
static BOOL NetworkSafe(NSString *s){return HasCJK(s) && DictionarySourceSafe(s);}
static BOOL OnlineDenied(void) {
 os_unfair_lock_lock(&onlineLock);BOOL denied=onlineDenied;os_unfair_lock_unlock(&onlineLock);return denied;
}
static void DenyOnline(void) {
 os_unfair_lock_lock(&onlineLock);onlineDenied=YES;[onlinePositive removeAllObjects];[onlineUncovered removeAllObjects];os_unfair_lock_unlock(&onlineLock);
 [NSUserDefaults.standardUserDefaults setBool:YES forKey:[@"MirsaTranslationRevoked25." stringByAppendingString:ActivationHash(onlineConfig[@"token"])]];
 BannerUpdate(NO);
}
static NSString *OnlineLookup(NSString *s) {
 os_unfair_lock_lock(&onlineLock);NSString *v=onlinePositive[s];os_unfair_lock_unlock(&onlineLock);return v;
}
static NSString *DictionaryCacheKey(void) {
 return [NSString stringWithFormat:@"MirsaTranslationDictionary25.%@.%@",onlineConfig[@"bundleId"],onlineConfig[@"revision"]];
}
static void SaveOnlineCache(void) {
 os_unfair_lock_lock(&onlineLock);
 NSMutableDictionary *snapshot=[NSMutableDictionary dictionaryWithCapacity:onlinePositive.count];
 for(NSString *k in onlinePositive){NSDictionary *m=onlineMeta[k];snapshot[k]=@{@"t":onlinePositive[k],@"v":m[@"v"]?:@0,@"p":m[@"p"]?:@"gemini"};}
 os_unfair_lock_unlock(&onlineLock);
 NSData *d=[NSJSONSerialization dataWithJSONObject:@{@"format":@2,@"entries":snapshot} options:0 error:NULL];
 if(d.length && d.length<=1048576)[NSUserDefaults.standardUserDefaults setObject:d forKey:DictionaryCacheKey()];
}
static void RefreshBannerCoverage(void) {
 os_unfair_lock_lock(&onlineLock);BOOL pending=onlineUncovered.count>0;os_unfair_lock_unlock(&onlineLock);
 BannerUpdate(pending);
}
static BOOL ValidOnlineValue(NSString *s,id v) {
 return DictionarySourceSafe(s) && [v isKindOfClass:NSString.class] && [v length]>0 && [v length]<=1024 &&
  PlaceholdersPreserved(s,v) && !HasCJK(v) && [v rangeOfCharacterFromSet:[NSCharacterSet characterSetWithRange:NSMakeRange(0x0600,0x100)]].location!=NSNotFound;
}
static void ApplyOnlineEntries(NSArray *entries) {
 if(![entries isKindOfClass:NSArray.class] || entries.count>1564)return;
 for(id item in entries){
  if(![item isKindOfClass:NSDictionary.class])continue;
  id source=item[@"source"],value=item[@"translation"];
  if(![source isKindOfClass:NSString.class] || !ValidOnlineValue(source,value) || !ProvenanceValid(item[@"provenance"]) || !VersionValid(item[@"version"]))continue;
  os_unfair_lock_lock(&onlineLock);
  MergeOnlineLocked(source,value,[item[@"version"] integerValue],item[@"provenance"]);
  os_unfair_lock_unlock(&onlineLock);
 }
 SaveOnlineCache();RefreshBannerCoverage();
}
static void RefreshOnlineDictionary(void) {
 dispatch_async(onlineQueue,^{@autoreleasepool{
  @try {
   if(!ValidActivation(onlineConfig,NSBundle.mainBundle.bundleIdentifier,NSDate.date.timeIntervalSince1970))return;
   NSMutableURLRequest *req=[NSMutableURLRequest requestWithURL:[NSURL URLWithString:onlineConfig[@"endpoint"]] cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:5];
   req.HTTPMethod=@"POST";[req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
   [req setValue:[@"Bearer " stringByAppendingString:onlineConfig[@"token"]] forHTTPHeaderField:@"Authorization"];
   [req setValue:onlineConfig[@"activation"] forHTTPHeaderField:@"X-Mirsa-Activation"];
   req.HTTPBody=[NSJSONSerialization dataWithJSONObject:@{@"action":@"refresh",@"consent":@YES,@"bundleId":onlineConfig[@"bundleId"],@"revision":onlineConfig[@"revision"]} options:0 error:NULL];
   NSURLSessionConfiguration *cfg=NSURLSessionConfiguration.ephemeralSessionConfiguration;
   cfg.timeoutIntervalForRequest=5;cfg.timeoutIntervalForResource=5;cfg.HTTPShouldSetCookies=NO;cfg.HTTPCookieStorage=nil;cfg.URLCache=nil;cfg.URLCredentialStorage=nil;
   MirsaNoRedirect *delegate=[MirsaNoRedirect new];NSOperationQueue *callbacks=[NSOperationQueue new];callbacks.maxConcurrentOperationCount=1;
   NSURLSession *session=[NSURLSession sessionWithConfiguration:cfg delegate:delegate delegateQueue:callbacks];
   NSURLSessionDataTask *task=[session dataTaskWithRequest:req];[task resume];
   BOOL completed=dispatch_semaphore_wait(delegate.finished,dispatch_time(DISPATCH_TIME_NOW,6*NSEC_PER_SEC))==0;
   if(!completed)[task cancel];
   if(completed && delegate.response.statusCode==403)DenyOnline();
   if(completed && !delegate.error && delegate.response.statusCode==200){
    id obj=[NSJSONSerialization JSONObjectWithData:delegate.body options:0 error:NULL];
    if([obj isKindOfClass:NSDictionary.class] && [obj[@"bundleId"] isEqual:onlineConfig[@"bundleId"]] && [obj[@"revision"] isEqual:onlineConfig[@"revision"]])ApplyOnlineEntries(obj[@"entries"]);
   }
   [session invalidateAndCancel];
  } @catch(__unused NSException *e){}
 }});
}
static void QueueOnline(NSString *s) {
 if(!onlineConfig || OnlineDenied() || !NetworkSafe(s))return;
 os_unfair_lock_lock(&onlineLock);
 if(!onlinePositive[s] && onlineUncovered.count<128)[onlineUncovered addObject:s];
 os_unfair_lock_unlock(&onlineLock);
 dispatch_after(dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC),onlineQueue,^{RefreshBannerCoverage();});
 os_unfair_lock_lock(&onlineLock);
 NSTimeInterval now=NSDate.date.timeIntervalSince1970;
 BOOL skip=onlinePositive[s] || [onlinePending containsObject:s] || [onlineNegative[s] doubleValue]>now || onlineWaiting>=16 || onlineIssued>=128;
 if(!skip){onlineWaiting++;onlineIssued++;[onlinePending addObject:s];}
 os_unfair_lock_unlock(&onlineLock);if(skip)return;
 dispatch_async(onlineQueue,^{@autoreleasepool{
  __block NSString *translated=nil;
  @try {
   if(OnlineExpiry(onlineConfig[@"expiresAt"])<=NSDate.date.timeIntervalSince1970)return;
   NSURL *url=[NSURL URLWithString:onlineConfig[@"endpoint"]];
   NSMutableURLRequest *req=[NSMutableURLRequest requestWithURL:url cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:5];
   req.HTTPMethod=@"POST";
   [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
   [req setValue:[@"Bearer " stringByAppendingString:onlineConfig[@"token"]] forHTTPHeaderField:@"Authorization"];
   [req setValue:onlineConfig[@"activation"] forHTTPHeaderField:@"X-Mirsa-Activation"];
   req.HTTPBody=[NSJSONSerialization dataWithJSONObject:@{@"action":@"missing",@"consent":@YES,@"items":@[@{@"id":@"s0",@"text":s}],@"bundleId":onlineConfig[@"bundleId"],@"revision":onlineConfig[@"revision"]} options:0 error:NULL];
   NSURLSessionConfiguration *cfg=NSURLSessionConfiguration.ephemeralSessionConfiguration;
   cfg.timeoutIntervalForRequest=5;cfg.timeoutIntervalForResource=5;cfg.HTTPShouldSetCookies=NO;cfg.HTTPCookieStorage=nil;cfg.URLCache=nil;cfg.URLCredentialStorage=nil;
   MirsaNoRedirect *delegate=[MirsaNoRedirect new];
   NSOperationQueue *callbacks=[NSOperationQueue new];callbacks.maxConcurrentOperationCount=1;
   NSURLSession *session=[NSURLSession sessionWithConfiguration:cfg delegate:delegate delegateQueue:callbacks];
   NSURLSessionDataTask *task=[session dataTaskWithRequest:req];
   [task resume];
   // A bounded background worker wait, never a rendering/UI wait.
   BOOL completed=dispatch_semaphore_wait(delegate.finished,dispatch_time(DISPATCH_TIME_NOW,6*NSEC_PER_SEC))==0;
   if(!completed)[task cancel];
   if(completed && delegate.response.statusCode==403)DenyOnline();
   if(completed && !delegate.error && delegate.response.statusCode==200 && delegate.body.length<=65536){
    id obj=[NSJSONSerialization JSONObjectWithData:delegate.body options:0 error:NULL];
    if([obj isKindOfClass:NSDictionary.class] && [obj[@"bundleId"] isEqual:onlineConfig[@"bundleId"]] && [obj[@"revision"] isEqual:onlineConfig[@"revision"]] && [obj[@"translations"] isKindOfClass:NSDictionary.class]){
     id v=obj[@"translations"][@"s0"];
     if([v isKindOfClass:NSString.class] && [v length]>0 && [v length]<=1024 && PlaceholdersPreserved(s,v) && !HasCJK(v))translated=v;
     // Canonical entries win over the bare map (the server returns protected latest values).
     if([obj[@"entries"] isKindOfClass:NSArray.class])ApplyOnlineEntries(obj[@"entries"]);
    }
   }
   [session invalidateAndCancel];
  } @catch(__unused NSException *e) {}
  @finally {
   os_unfair_lock_lock(&onlineLock);
   if(translated && (onlinePositive[s] || onlinePositive.count<2048)){
    // Bare translation without entry is unversioned Gemini: only fills a gap, never overrides.
    if(!onlineMeta[s])MergeOnlineLocked(s,translated,0,@"gemini");
    [onlineUncovered removeObject:s];
   } else {if(onlineNegative.count>=128)[onlineNegative removeAllObjects];onlineNegative[s]=@(NSDate.date.timeIntervalSince1970+60);}
   [onlinePending removeObject:s];if(onlineWaiting)onlineWaiting--;
   os_unfair_lock_unlock(&onlineLock);
   if(translated)SaveOnlineCache();RefreshBannerCoverage();
  }
 }});
}
static void LoadOnlineCache(void) {
 id stored=[NSUserDefaults.standardUserDefaults objectForKey:DictionaryCacheKey()];
 if(![stored isKindOfClass:NSData.class] || [stored length]>1048576)return;
 id map=[NSJSONSerialization JSONObjectWithData:stored options:0 error:NULL];
 if(![map isKindOfClass:NSDictionary.class])return;
 if([map[@"format"] isEqual:@2] && [map[@"entries"] isKindOfClass:NSDictionary.class]){
  NSDictionary *e=map[@"entries"];if(e.count>2048)return;
  for(id source in e){
   id it=e[source];
   if(![source isKindOfClass:NSString.class] || ![it isKindOfClass:NSDictionary.class] || !ValidOnlineValue(source,it[@"t"]) || !ProvenanceValid(it[@"p"]) || !VersionValid(it[@"v"]))continue;
   os_unfair_lock_lock(&onlineLock);MergeOnlineLocked(source,it[@"t"],[it[@"v"] integerValue],it[@"p"]);os_unfair_lock_unlock(&onlineLock);
  }
 } else if([map count]<=2048){
  // Legacy v1 cache: unversioned Gemini, any later entry supersedes it.
  for(id source in map)if([source isKindOfClass:NSString.class] && ValidOnlineValue(source,map[source])){
   os_unfair_lock_lock(&onlineLock);MergeOnlineLocked(source,map[source],0,@"gemini");os_unfair_lock_unlock(&onlineLock);}
 }
}
static void ConfigureOnline(NSDictionary *config) {
 onlinePositive=[NSMutableDictionary dictionary];onlineNegative=[NSMutableDictionary dictionary];onlineMeta=[NSMutableDictionary dictionary];onlinePending=[NSMutableSet set];onlineUncovered=[NSMutableSet set];
 onlineQueue=dispatch_queue_create("app.mirsa.translate.online",DISPATCH_QUEUE_SERIAL);
 id c=config[@"online"];if(![c isKindOfClass:NSDictionary.class])return;
 for(NSString *k in @[@"endpoint",@"token",@"bundleId",@"revision",@"activation",@"installationId"])if(![c[k] isKindOfClass:NSString.class] || ![c[k] length])return;
 NSRegularExpression *tokenRE=[NSRegularExpression regularExpressionWithPattern:@"^mrt1\\.[0-9a-f]{64}$" options:0 error:NULL];
 NSRegularExpression *revisionRE=[NSRegularExpression regularExpressionWithPattern:@"^[0-9a-f]{64}$" options:0 error:NULL];
 if(![tokenRE firstMatchInString:c[@"token"] options:0 range:NSMakeRange(0,[c[@"token"] length])] || ![revisionRE firstMatchInString:c[@"revision"] options:0 range:NSMakeRange(0,[c[@"revision"] length])])return;
 NSURL *u=[NSURL URLWithString:c[@"endpoint"]];
 if(![u.scheme isEqual:@"https"] || !u.host.length || u.user || u.password || u.fragment || u.query)return;
 if(![c[@"bundleId"] isEqual:NSBundle.mainBundle.bundleIdentifier])return;
 NSTimeInterval exp=OnlineExpiry(c[@"expiresAt"]),now=NSDate.date.timeIntervalSince1970;
 if(exp<=now || exp>now+86400)return;
 if(!ValidActivation(c,NSBundle.mainBundle.bundleIdentifier,now))return;
 if([NSUserDefaults.standardUserDefaults boolForKey:[@"MirsaTranslationRevoked25." stringByAppendingString:ActivationHash(c[@"token"])]])return;
 onlineConfig=[c copy];
 LoadOnlineCache();
 RefreshOnlineDictionary();
}
