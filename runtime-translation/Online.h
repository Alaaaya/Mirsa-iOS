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
 done(self.response.statusCode==200 && r.expectedContentLength<=65536?NSURLSessionResponseAllow:NSURLSessionResponseCancel);
}
- (void)URLSession:(NSURLSession *)s dataTask:(NSURLSessionDataTask *)t didReceiveData:(NSData *)d {
 (void)s;if(self.body.length+d.length>65536){self.error=[NSError errorWithDomain:@"MirsaTranslate" code:1 userInfo:nil];[t cancel];return;}[self.body appendData:d];
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
static NSMutableDictionary *onlinePositive,*onlineNegative;
static NSMutableSet *onlinePending;
static dispatch_queue_t onlineQueue;
static NSUInteger onlineIssued, onlineWaiting;
static os_unfair_lock onlineLock=OS_UNFAIR_LOCK_INIT;
static NSString *SafePrefix(NSString *s,NSUInteger n) {
 if(s.length<=n)return [s copy];
 if(n && CFStringIsSurrogateHighCharacter([s characterAtIndex:n-1]))n--;
 return [s substringToIndex:n];
}
static BOOL NetworkSafe(NSString *s) {
 if(!s.length || s.length>256 || !HasCJK(s))return NO;
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
static NSString *OnlineLookup(NSString *s) {
 os_unfair_lock_lock(&onlineLock);NSString *v=onlinePositive[s];os_unfair_lock_unlock(&onlineLock);return v;
}
static void QueueOnline(NSString *s) {
 if(!onlineConfig || !NetworkSafe(s))return;
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
   if(completed && !delegate.error && delegate.response.statusCode==200 && delegate.body.length<=65536){
    id obj=[NSJSONSerialization JSONObjectWithData:delegate.body options:0 error:NULL];
    if([obj isKindOfClass:NSDictionary.class] && [obj[@"bundleId"] isEqual:onlineConfig[@"bundleId"]] && [obj[@"revision"] isEqual:onlineConfig[@"revision"]] && [obj[@"translations"] isKindOfClass:NSDictionary.class]){
     id v=obj[@"translations"][@"s0"];
     if([v isKindOfClass:NSString.class] && [v length]>0 && [v length]<=1024 && PlaceholdersPreserved(s,v) && !HasCJK(v))translated=v;
    }
   }
   [session invalidateAndCancel];
  } @catch(__unused NSException *e) {}
  @finally {
   os_unfair_lock_lock(&onlineLock);
   if(translated && onlinePositive.count<128)onlinePositive[s]=translated;
   else {if(onlineNegative.count>=128)[onlineNegative removeAllObjects];onlineNegative[s]=@(NSDate.date.timeIntervalSince1970+60);}
   [onlinePending removeObject:s];if(onlineWaiting)onlineWaiting--;
   os_unfair_lock_unlock(&onlineLock);
  }
 }});
}
static void ConfigureOnline(NSDictionary *config) {
 onlinePositive=[NSMutableDictionary dictionary];onlineNegative=[NSMutableDictionary dictionary];onlinePending=[NSMutableSet set];
 onlineQueue=dispatch_queue_create("app.mirsa.translate.online",DISPATCH_QUEUE_SERIAL);
 id c=config[@"online"];if(![c isKindOfClass:NSDictionary.class])return;
 for(NSString *k in @[@"endpoint",@"token",@"bundleId",@"revision"])if(![c[k] isKindOfClass:NSString.class] || ![c[k] length])return;
 NSRegularExpression *tokenRE=[NSRegularExpression regularExpressionWithPattern:@"^mrt1\\.[0-9a-f]{64}$" options:0 error:NULL];
 NSRegularExpression *revisionRE=[NSRegularExpression regularExpressionWithPattern:@"^[0-9a-f]{64}$" options:0 error:NULL];
 if(![tokenRE firstMatchInString:c[@"token"] options:0 range:NSMakeRange(0,[c[@"token"] length])] || ![revisionRE firstMatchInString:c[@"revision"] options:0 range:NSMakeRange(0,[c[@"revision"] length])])return;
 NSURL *u=[NSURL URLWithString:c[@"endpoint"]];
 if(![u.scheme isEqual:@"https"] || !u.host.length || u.user || u.password || u.fragment || u.query)return;
 if(![c[@"bundleId"] isEqual:NSBundle.mainBundle.bundleIdentifier])return;
 NSTimeInterval exp=OnlineExpiry(c[@"expiresAt"]),now=NSDate.date.timeIntervalSince1970;
 if(exp<=now || exp>now+86400)return;
 onlineConfig=[c copy];
}
