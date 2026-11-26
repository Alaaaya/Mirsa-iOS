// Deterministic authenticated foreground refresh through the real NSURLSession path.
// Only a signed public vector and an in-process fixture are used.
#define MIRSA_RUNTIME_TESTING 1
#import "RuntimeTranslate.m"
#import <assert.h>
#import <objc/runtime.h>

static NSTimeInterval foregroundTime=2000000010;
static NSDictionary *foregroundFixture;
static NSUInteger foregroundCalls;
static NSTimeInterval ForegroundNow(void){return foregroundTime;}
static void ForegroundSpin(NSTimeInterval seconds){
 NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:seconds];
 while(deadline.timeIntervalSinceNow>0)
  [NSRunLoop.currentRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
}
static NSUInteger ForegroundCalls(void){
 @synchronized(NSURLProtocol.class){return foregroundCalls;}
}
@interface MirsaForegroundProtocol : NSURLProtocol
@end
@implementation MirsaForegroundProtocol
+ (BOOL)canInitWithRequest:(NSURLRequest *)request {
 return [request.URL.host isEqual:@"foreground.fixture.invalid"];
}
+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request{return request;}
- (void)startLoading {
 assert([self.request.URL.absoluteString isEqual:@"https://foreground.fixture.invalid/runtime"]);
 assert([self.request.HTTPMethod isEqual:@"POST"]);
 assert([[self.request valueForHTTPHeaderField:@"Authorization"] isEqual:[@"Bearer " stringByAppendingString:foregroundFixture[@"token"]]]);
 assert([[self.request valueForHTTPHeaderField:@"X-Mirsa-Activation"] isEqual:foregroundFixture[@"activation"]]);
 NSData *body=self.request.HTTPBody;
 if(!body && self.request.HTTPBodyStream){
  NSInputStream *stream=self.request.HTTPBodyStream;[stream open];
  NSMutableData *data=[NSMutableData data];uint8_t bytes[1024];NSInteger n;
  while((n=[stream read:bytes maxLength:sizeof(bytes)])>0)[data appendBytes:bytes length:(NSUInteger)n];
  assert(n==0);[stream close];body=data;
 }
 assert(body.length);
 NSDictionary *request=[NSJSONSerialization JSONObjectWithData:body options:0 error:NULL];
 assert([request isKindOfClass:NSDictionary.class]);
 // Exact allowlist also excludes raw strings, item batches, history and credentials.
 assert(request.count==4 && [request[@"action"] isEqual:@"refresh"]);
 assert([request[@"consent"] isEqual:@YES]);
 assert([request[@"bundleId"] isEqual:foregroundFixture[@"bundleId"]]);
 assert([request[@"revision"] isEqual:foregroundFixture[@"revision"]]);
 assert(!request[@"items"]);
 NSUInteger call;
 @synchronized(NSURLProtocol.class){call=++foregroundCalls;}
 assert(call<=2);
 NSDictionary *entry=@{@"source":@"前台设置",@"translation":call==1?@"الإعدادات القديمة":@"الإعدادات الجديدة",
  @"provenance":@"kat",@"version":@(call)};
 NSDictionary *reply=@{@"bundleId":request[@"bundleId"],@"revision":request[@"revision"],@"entries":@[entry]};
 NSHTTPURLResponse *response=[[NSHTTPURLResponse alloc] initWithURL:self.request.URL statusCode:200 HTTPVersion:@"HTTP/1.1" headerFields:@{@"Content-Type":@"application/json"}];
 [self.client URLProtocol:self didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageNotAllowed];
 [self.client URLProtocol:self didLoadData:[NSJSONSerialization dataWithJSONObject:reply options:0 error:NULL]];
 [self.client URLProtocolDidFinishLoading:self];
}
- (void)stopLoading {}
@end
@interface NSURLSessionConfiguration (MirsaForegroundFixture)
+ (NSURLSessionConfiguration *)mirsaForegroundConfiguration;
@end
@implementation NSURLSessionConfiguration (MirsaForegroundFixture)
+ (NSURLSessionConfiguration *)mirsaForegroundConfiguration {
 NSURLSessionConfiguration *config=[self mirsaForegroundConfiguration];
 config.protocolClasses=@[MirsaForegroundProtocol.class];return config;
}
@end
static void ForegroundWaitForLabel(UILabel *label,NSString *expected){
 NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:5];
 while(![label.text isEqual:expected] && deadline.timeIntervalSinceNow>0)ForegroundSpin(0.01);
 assert([label.text isEqual:expected]);
 // Drain the serialized worker without blocking main-queue UI application.
 dispatch_sync(onlineQueue,^{});
}
int main(int argc,char **argv){@autoreleasepool{
 assert(argc==2);
 foregroundFixture=[NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:@(argv[1])] options:0 error:NULL];
 assert(ValidActivation(foregroundFixture,@"com.example.activationfixture",foregroundTime));
 assert(!enabled); // The production constructor has no dictionary in this executable.
 enabled=YES;table=@{};pieces=@{};rules=@[];cache=[NSCache new];
 onlineConfig=nil;
 onlinePositive=[NSMutableDictionary dictionary];onlineMeta=[NSMutableDictionary dictionary];
 onlineNegative=[NSMutableDictionary dictionary];onlinePending=[NSMutableSet set];onlineUncovered=[NSMutableSet set];
 onlineAttempts=[NSMutableDictionary dictionary];onlineIssued=0;onlineWaiting=0;onlineBudgetStart=0;onlineAttemptStart=0;
 onlineDenied=NO;onlineFlushScheduled=NO;onlineFlushRunning=NO;onlineFlushGeneration++;onlineFlushDeadline=0;
 onlineRefreshScheduled=NO;onlineRefreshAttempt=0;onlineLastRefresh=0;
 onlineClock=ForegroundNow;onlineTestActivationBundle=@"com.example.activationfixture";
 onlineQueue=dispatch_queue_create("mirsa.foreground.fixture",DISPATCH_QUEUE_SERIAL);
 Method original=class_getClassMethod(NSURLSessionConfiguration.class,@selector(ephemeralSessionConfiguration));
 Method fixture=class_getClassMethod(NSURLSessionConfiguration.class,@selector(mirsaForegroundConfiguration));
 method_exchangeImplementations(original,fixture);
 HookString(UILabel.class,@selector(setText:));
 UILabel *label=[UILabel new];label.text=@"前台设置";
 assert([label.text isEqual:@"前台设置"] && !ForegroundCalls());
 // Render first, then enable the signed capability without queuing missing text.
 NSMutableDictionary *config=[foregroundFixture mutableCopy];
 config[@"endpoint"]=@"https://foreground.fixture.invalid/runtime";onlineConfig=config;
 assert(OnlineUsable());
 OnlineForeground();
 ForegroundWaitForLabel(label,@"الإعدادات القديمة");assert(ForegroundCalls()==1);
 for(NSUInteger i=0;i<8;i++)OnlineForeground();
 dispatch_sync(onlineQueue,^{});ForegroundSpin(0.1);assert(ForegroundCalls()==1);
 foregroundTime+=60;OnlineForeground();
 ForegroundWaitForLabel(label,@"الإعدادات الجديدة");assert(ForegroundCalls()==2);
 // Neither assertion above calls the label setter after its first render.
 config=[onlineConfig mutableCopy];config[@"expiresAt"]=@"2099-01-01T00:00:00Z";onlineConfig=config;
 foregroundTime=2000086401;assert(!OnlineUsable());
 OnlineForeground();dispatch_sync(onlineQueue,^{});ForegroundSpin(0.1);
 assert(ForegroundCalls()==2 && [Translate(@"前台设置") isEqual:@"前台设置"]);
 // Restore time but corrupt activation: no refresh or direct transport bypass.
 foregroundTime=2000000130;
 config=[onlineConfig mutableCopy];config[@"activation"]=@"tampered";onlineConfig=config;
 assert(!OnlineUsable());OnlineForeground();dispatch_sync(onlineQueue,^{});ForegroundSpin(0.1);
 assert(!OnlinePost(@"refresh",nil) && ForegroundCalls()==2);
 method_exchangeImplementations(original,fixture);
 [NSUserDefaults.standardUserDefaults removeObjectForKey:DictionaryCacheKey()];
 NSLog(@"Authenticated foreground refresh, debounce, retained UILabel reapply, signed expiry and invalid activation passed");
 return 0;
}}
