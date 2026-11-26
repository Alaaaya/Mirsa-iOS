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
// Configuration is signature-verified by ConfigureOnline. Keep the signed
// deadline authoritative for cached rendering too, not just outgoing requests.
static NSTimeInterval OnlineSignedExpiry(NSDictionary *config) {
 id jwt=config[@"activation"];
 if(![jwt isKindOfClass:NSString.class] || [jwt length]>4096)return 0;
 NSArray *parts=[jwt componentsSeparatedByString:@"."];
 if(parts.count!=3)return 0;
 NSData *payload=ActivationDecode(parts[1]);if(!payload)return 0;
 id claims=[NSJSONSerialization JSONObjectWithData:payload options:0 error:NULL];
 if(![claims isKindOfClass:NSDictionary.class] || ![claims[@"exp"] isKindOfClass:NSNumber.class])return 0;
 return [claims[@"exp"] doubleValue];
}
static NSDictionary *onlineConfig;
static NSMutableDictionary *onlinePositive,*onlineNegative,*onlineMeta;
static NSMutableSet *onlinePending;
static dispatch_queue_t onlineQueue;
static BOOL onlineDenied;
static NSUInteger onlineIssued, onlineWaiting;
static NSMutableSet *onlineUncovered;
static NSMutableDictionary *onlineAttempts;
static NSTimeInterval onlineBudgetStart,onlineAttemptStart;
// Injectable clock for deterministic policy tests. Production always uses wall time.
static NSTimeInterval (*onlineClock)(void);
static NSTimeInterval OnlineNow(void){return onlineClock?onlineClock():NSDate.date.timeIntervalSince1970;}
static NSTimeInterval OnlineBackoff(NSUInteger attempt){return attempt<=1?60:(attempt==2?300:900);}
static void ReapplyTranslations(void);
static void RefreshOnlineDictionary(void);
static void OnlineForeground(void);
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
// Reserved explicit-local revoke API, intentionally not inferred from HTTP errors.
static void __attribute__((unused)) DenyOnline(void) {
 os_unfair_lock_lock(&onlineLock);onlineDenied=YES;[onlinePositive removeAllObjects];[onlineUncovered removeAllObjects];os_unfair_lock_unlock(&onlineLock);
 [NSUserDefaults.standardUserDefaults setBool:YES forKey:[@"MirsaTranslationExplicitRevoked26." stringByAppendingString:ActivationHash(onlineConfig[@"token"])]];
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
 BOOL changed=NO;
 for(id item in entries){
  if(![item isKindOfClass:NSDictionary.class])continue;
  id source=item[@"source"],value=item[@"translation"];
  if(![source isKindOfClass:NSString.class] || !ValidOnlineValue(source,value) || !ProvenanceValid(item[@"provenance"]) || !VersionValid(item[@"version"]))continue;
  os_unfair_lock_lock(&onlineLock);
  changed=MergeOnlineLocked(source,value,[item[@"version"] integerValue],item[@"provenance"]) || changed;
  os_unfair_lock_unlock(&onlineLock);
 }
 if(changed){SaveOnlineCache();dispatch_async(dispatch_get_main_queue(),^{ReapplyTranslations();});}
 RefreshBannerCoverage();
}
// Queue-only state. A foreground event starts at most one refresh per minute.
// One timer owns the finite receipt/failure follow-up chain, never a timer per label.
static BOOL onlineRefreshScheduled;
static NSUInteger onlineRefreshAttempt;
static NSTimeInterval onlineLastRefresh;
// Simulator-only signed public-vector context. No override is compiled into an IPA.
#if defined(MIRSA_RUNTIME_TESTING)
static NSString *onlineTestActivationBundle;
#endif
static NSString *OnlineActivationBundle(void) {
#if defined(MIRSA_RUNTIME_TESTING)
 if(onlineTestActivationBundle)return onlineTestActivationBundle;
#endif
 return NSBundle.mainBundle.bundleIdentifier;
}
static BOOL OnlineUsable(void) {
 return onlineConfig && !OnlineDenied() && OnlineExpiry(onlineConfig[@"expiresAt"])>OnlineNow() &&
  ValidActivation(onlineConfig,OnlineActivationBundle(),OnlineNow());
}
static NSDictionary *OnlinePost(NSString *action,NSArray *items) {
 if(!OnlineUsable())return nil;
 NSMutableDictionary *payload=[@{@"action":action,@"consent":@YES,@"bundleId":onlineConfig[@"bundleId"],@"revision":onlineConfig[@"revision"]} mutableCopy];
 if(items)payload[@"items"]=items;
 NSMutableURLRequest *req=[NSMutableURLRequest requestWithURL:[NSURL URLWithString:onlineConfig[@"endpoint"]] cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:5];
 req.HTTPMethod=@"POST";[req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
 [req setValue:@"MirsaRuntimeTranslation/1.0" forHTTPHeaderField:@"User-Agent"];
 [req setValue:[@"Bearer " stringByAppendingString:onlineConfig[@"token"]] forHTTPHeaderField:@"Authorization"];
 [req setValue:onlineConfig[@"activation"] forHTTPHeaderField:@"X-Mirsa-Activation"];
 req.HTTPBody=[NSJSONSerialization dataWithJSONObject:payload options:0 error:NULL];
 NSURLSessionConfiguration *cfg=NSURLSessionConfiguration.ephemeralSessionConfiguration;
 cfg.timeoutIntervalForRequest=5;cfg.timeoutIntervalForResource=5;cfg.HTTPShouldSetCookies=NO;cfg.HTTPCookieStorage=nil;cfg.URLCache=nil;cfg.URLCredentialStorage=nil;
 MirsaNoRedirect *delegate=[MirsaNoRedirect new];NSOperationQueue *callbacks=[NSOperationQueue new];callbacks.maxConcurrentOperationCount=1;
 NSURLSession *session=[NSURLSession sessionWithConfiguration:cfg delegate:delegate delegateQueue:callbacks];
 @try {
  NSURLSessionDataTask *task=[session dataTaskWithRequest:req];[task resume];
  BOOL completed=dispatch_semaphore_wait(delegate.finished,dispatch_time(DISPATCH_TIME_NOW,6*NSEC_PER_SEC))==0;
  if(!completed)[task cancel];
  // HTTP 403 alone is NOT authenticated explicit revocation. Never poison future launches.
  // Local DenyOnline() remains the explicit persistent revocation path.
  if(!completed || delegate.error || delegate.response.statusCode!=200 || !OnlineUsable())return nil;
  if(items && delegate.body.length>65536)return nil;
  id obj=[NSJSONSerialization JSONObjectWithData:delegate.body options:0 error:NULL];
  if([obj isKindOfClass:NSDictionary.class] && [obj[@"bundleId"] isEqual:onlineConfig[@"bundleId"]] && [obj[@"revision"] isEqual:onlineConfig[@"revision"]])return obj;
 } @finally {[session invalidateAndCancel];}
 return nil;
}
static void ScheduleOnlineRefresh(void) {
 if(onlineRefreshScheduled || onlineRefreshAttempt>=3 || !OnlineUsable())return;
 onlineRefreshScheduled=YES;
 NSTimeInterval delay=OnlineBackoff(++onlineRefreshAttempt);
 dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(delay*NSEC_PER_SEC)),onlineQueue,^{
  onlineRefreshScheduled=NO;
  if(!OnlineUsable())return;
  RefreshOnlineDictionary();
 });
}
static void RefreshOnlineDictionary(void) { @autoreleasepool {
 @try {
  if(!OnlineUsable())return;
  if(onlineLastRefresh && OnlineNow()>=onlineLastRefresh && OnlineNow()-onlineLastRefresh<60){ScheduleOnlineRefresh();return;}
  onlineLastRefresh=OnlineNow();
  NSDictionary *obj=OnlinePost(@"refresh",nil);
  if(obj)ApplyOnlineEntries(obj[@"entries"]);
  // Finite follow-ups also recover a failed foreground refresh without render activity.
  ScheduleOnlineRefresh();
 } @catch(__unused NSException *e){ScheduleOnlineRefresh();}
}}
// All scheduling transitions below hold onlineLock; HTTP is serialized on onlineQueue.
static BOOL onlineFlushScheduled,onlineFlushRunning;
static NSUInteger onlineFlushGeneration;
static NSTimeInterval onlineFlushDeadline;
static void FlushOnline(void);
// Caller holds onlineLock. Earlier work replaces the logical timer; superseded
// dispatch_after blocks retain their generation and become inert on onlineQueue.
// A running flush schedules its own earliest remaining deadline in @finally.
static void ScheduleOnlineFlushLocked(NSTimeInterval delay) {
 if(onlineFlushRunning)return;
 delay=MAX(0.15,delay);
 NSTimeInterval deadline=OnlineNow()+delay;
 if(onlineFlushScheduled && onlineFlushDeadline<=deadline)return;
 onlineFlushScheduled=YES;onlineFlushDeadline=deadline;
 NSUInteger generation=++onlineFlushGeneration;
 dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(delay*NSEC_PER_SEC)),onlineQueue,^{
  os_unfair_lock_lock(&onlineLock);
  if(!onlineFlushScheduled || generation!=onlineFlushGeneration){os_unfair_lock_unlock(&onlineLock);return;}
  onlineFlushScheduled=NO;onlineFlushDeadline=0;onlineFlushRunning=YES;
  os_unfair_lock_unlock(&onlineLock);
  FlushOnline();
 });
}
static void ResetOnlineBudgetLocked(NSTimeInterval now) {
 if(!onlineBudgetStart || now-onlineBudgetStart>=60 || now<onlineBudgetStart){onlineBudgetStart=now;onlineIssued=0;}
 if(!onlineAttempts)onlineAttempts=[NSMutableDictionary dictionary];
 if(!onlineAttemptStart || now-onlineAttemptStart>=900 || now<onlineAttemptStart){
  onlineAttemptStart=now;
  // Preserve attempts on active retries. Clearing these at 15min would make the
  // 15min final backoff retry forever instead of terminating at four requests.
  for(NSString *source in [onlineAttempts allKeys])if(![onlinePending containsObject:source])[onlineAttempts removeObjectForKey:source];
 }
 for(NSString *source in [onlineNegative allKeys])if([onlineNegative[source] doubleValue]<=now)[onlineNegative removeObjectForKey:source];
 if(onlineNegative.count>2048){
  for(NSString *source in [onlineNegative allKeys]){
   if(![onlinePending containsObject:source])[onlineNegative removeObjectForKey:source];
   if(onlineNegative.count<=2048)break;
  }
 }
}
static void FlushOnline(void) { @autoreleasepool {
 NSMutableArray *batch=[NSMutableArray array];NSUInteger chars=0;
 NSTimeInterval now=OnlineNow();
 os_unfair_lock_lock(&onlineLock);ResetOnlineBudgetLocked(now);
 for(NSString *source in [[onlinePending allObjects] sortedArrayUsingSelector:@selector(compare:)]){
  if(onlinePositive[source])continue;
  if([onlineNegative[source] doubleValue]>now)continue;
  if(batch.count>=16 || onlineIssued>=128 || chars+source.length>2048)break;
  [batch addObject:source];chars+=source.length;onlineIssued++;
  onlineAttempts[source]=@([onlineAttempts[source] unsignedIntegerValue]+1);
 }
 os_unfair_lock_unlock(&onlineLock);
 BOOL accepted=NO;
 @try {
  if(!batch.count || !OnlineUsable())return;
  NSMutableArray *items=[NSMutableArray array];
  for(NSUInteger i=0;i<batch.count;i++)[items addObject:@{@"id":[NSString stringWithFormat:@"s%lu",(unsigned long)i],@"text":batch[i]}];
  NSDictionary *obj=OnlinePost(@"missing",items);
  if(obj){
   ApplyOnlineEntries(obj[@"entries"]);
   NSDictionary *receipt=[obj[@"queue"] isKindOfClass:NSDictionary.class]?obj[@"queue"]:nil;
   NSArray *entries=[receipt[@"entries"] isKindOfClass:NSArray.class]?receipt[@"entries"]:nil;
   NSMutableSet *received=[NSMutableSet set];
   if([receipt[@"persisted"] isEqual:@YES])for(id entry in entries){
    if(![entry isKindOfClass:NSDictionary.class])continue;
    if([entry[@"source"] isKindOfClass:NSString.class] && [entry[@"labelId"] isKindOfClass:NSString.class] && [entry[@"labelId"] length] &&
       [entry[@"reviewId"] isKindOfClass:NSString.class] && [entry[@"reviewId"] length])[received addObject:entry[@"source"]];
   }
   accepted=[[NSSet setWithArray:batch] isSubsetOfSet:received];
   if(accepted){if(!onlineRefreshScheduled && onlineRefreshAttempt>=3)onlineRefreshAttempt=0;ScheduleOnlineRefresh();}
  }
 } @catch(__unused NSException *e) {}
 @finally {
  now=OnlineNow();
  os_unfair_lock_lock(&onlineLock);
  for(NSString *source in batch){
   NSUInteger attempt=[onlineAttempts[source] unsignedIntegerValue];
   if(!onlinePositive[source])onlineNegative[source]=@(now+(accepted?900:OnlineBackoff(attempt)));
   if(accepted || onlinePositive[source] || attempt>=4){[onlinePending removeObject:source];}
  }
  // Remove labels resolved by refresh while waiting for their next bounded attempt.
  for(NSString *source in [onlinePending allObjects])if(onlinePositive[source])[onlinePending removeObject:source];
  onlineWaiting=onlinePending.count;
  BOOL more=onlineWaiting>0 && !onlineDenied && OnlineExpiry(onlineConfig[@"expiresAt"])>now;
  NSTimeInterval delay=900;
  if(more){
   for(NSString *source in onlinePending)delay=MIN(delay,MAX(0.15,[onlineNegative[source] doubleValue]-now));
   if(onlineIssued>=128)delay=MAX(delay,MAX(0.15,onlineBudgetStart+60-now));
  }
  onlineFlushRunning=NO;
  if(more){ScheduleOnlineFlushLocked(delay);}
  else {
   // Invalidate any outstanding generation, including a timer installed before
   // a direct test flush. No obsolete callback can consume a later timer.
   onlineFlushScheduled=NO;onlineFlushDeadline=0;onlineFlushGeneration++;
  }
  os_unfair_lock_unlock(&onlineLock);
  RefreshBannerCoverage();
 }
}}
static void QueueOnline(NSString *s) {
 if(!onlineConfig || OnlineDenied() || (OnlineExpiry(onlineConfig[@"expiresAt"])<=OnlineNow() || OnlineSignedExpiry(onlineConfig)<=OnlineNow()) || !NetworkSafe(s))return;
 NSTimeInterval now=OnlineNow();
 os_unfair_lock_lock(&onlineLock);ResetOnlineBudgetLocked(now);
 if(!onlinePositive[s] && onlineUncovered.count<128)[onlineUncovered addObject:s];
 BOOL skip=onlinePositive[s] || [onlinePending containsObject:s] || [onlineNegative[s] doubleValue]>now || onlinePending.count>=128 ||
  [onlineAttempts[s] unsignedIntegerValue]>=4 || (!onlineAttempts[s] && onlineAttempts.count>=2048);
 if(!skip){
  [onlinePending addObject:s];onlineWaiting=onlinePending.count;
  ScheduleOnlineFlushLocked(0.15);
 }
 os_unfair_lock_unlock(&onlineLock);
}
static void OnlineForeground(void) {
 if(!onlineConfig || !onlineQueue)return;
 dispatch_async(onlineQueue,^{
  if(!OnlineUsable())return;
  if(onlineLastRefresh && OnlineNow()-onlineLastRefresh<60)return;
  if(!onlineRefreshScheduled)onlineRefreshAttempt=0;
  RefreshOnlineDictionary();
 });
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
 NSTimeInterval exp=OnlineExpiry(c[@"expiresAt"]),now=OnlineNow();
 if(exp<=now || exp>now+86400)return;
 if(!ValidActivation(c,NSBundle.mainBundle.bundleIdentifier,now))return;
 // Revoked25 was also written on transient generic403, so it cannot prove revocation.
 // Only the separate explicit-local marker is authoritative going forward.
 if([NSUserDefaults.standardUserDefaults boolForKey:[@"MirsaTranslationExplicitRevoked26." stringByAppendingString:ActivationHash(c[@"token"])]])return;
 onlineConfig=[c copy];
 LoadOnlineCache();
 OnlineForeground();
}
