// CI-only actual activated constructor coverage. Not linked into shipped binaries.
#import <UIKit/UIKit.h>
#import <CoreText/CoreText.h>
#import <objc/runtime.h>
#import <assert.h>
#import "RuntimeTranslate.m"
static NSUInteger fixtureRefreshes;
@interface ActivatedProtocol26 : NSURLProtocol
@end
@implementation ActivatedProtocol26
+ (BOOL)canInitWithRequest:(NSURLRequest *)r { return [r.URL.host isEqual:@"activated.fixture.invalid"]; }
+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)r { return r; }
- (void)startLoading {
 @try {
  NSDictionary *config=[NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:[NSBundle.mainBundle pathForResource:@"MirsaTranslations" ofType:@"json"]] options:0 error:NULL];
  NSDictionary *map=[NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:[NSBundle.mainBundle pathForResource:@"DriftExact128Translations26" ofType:@"json"]] options:0 error:NULL];
  NSMutableArray *entries=[NSMutableArray array];
  for(NSString *source in map)[entries addObject:@{@"source":source,@"translation":map[source],@"provenance":@"gemini",@"version":@1}];
  NSDictionary *reply=@{@"bundleId":config[@"online"][@"bundleId"],@"revision":config[@"online"][@"revision"],@"entries":entries};
  NSData *body=[NSJSONSerialization dataWithJSONObject:reply options:0 error:NULL];
  NSHTTPURLResponse *response=[[NSHTTPURLResponse alloc]initWithURL:self.request.URL statusCode:200 HTTPVersion:@"HTTP/1.1" headerFields:@{@"Content-Type":@"application/json"}];
  [self.client URLProtocol:self didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageNotAllowed];
  [self.client URLProtocol:self didLoadData:body];[self.client URLProtocolDidFinishLoading:self];
  @synchronized(ActivatedProtocol26.class){fixtureRefreshes++;}
 } @catch(NSException *e){NSLog(@"fixture response failed %@",e);abort();}
}
- (void)stopLoading {}
@end
@interface NSURLSessionConfiguration (ActivatedFixture26)
+ (NSURLSessionConfiguration *)activatedFixtureConfiguration26;
@end
@implementation NSURLSessionConfiguration (ActivatedFixture26)
+ (void)load {
 Method a=class_getClassMethod(self,@selector(ephemeralSessionConfiguration));
 Method b=class_getClassMethod(self,@selector(activatedFixtureConfiguration26));
 method_exchangeImplementations(a,b);
}
+ (NSURLSessionConfiguration *)activatedFixtureConfiguration26 {
 NSURLSessionConfiguration *config=[self activatedFixtureConfiguration26];config.protocolClasses=@[ActivatedProtocol26.class];return config;
}
@end
static void RunActivatedChecks26(void) {
 fprintf(stderr,"ACTIVE26 checks start enabled=%d online=%d\n",enabled,onlineConfig!=nil);fflush(stderr);
 assert(enabled && onlineConfig && table.count==0);
 assert(ValidActivation(onlineConfig,NSBundle.mainBundle.bundleIdentifier,NSDate.date.timeIntervalSince1970));
 NSDictionary *map=[NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:[NSBundle.mainBundle pathForResource:@"DriftExact128Translations26" ofType:@"json"]] options:0 error:NULL];assert(map.count==128);
 // Immediate UIKit/Foundation/CoreText activity overlaps the asynchronous first refresh.
 for(int pass=0;pass<2;pass++){
  for(NSString *source in map){
   UILabel *label=[UILabel new];label.text=source;
   NSAttributedString *attr=[[NSAttributedString alloc]initWithString:source attributes:@{NSForegroundColorAttributeName:UIColor.redColor}];
   label.attributedText=attr;
   NSMutableAttributedString *mutable=[[NSMutableAttributedString alloc]initWithString:source attributes:nil];assert(mutable.length>0);
   CTLineRef line=CTLineCreateWithAttributedString((__bridge CFAttributedStringRef)attr);assert(line);CFRelease(line);
   CTTypesetterRef typesetter=CTTypesetterCreateWithAttributedString((__bridge CFAttributedStringRef)attr);assert(typesetter);CFRelease(typesetter);
   CTFramesetterRef framesetter=CTFramesetterCreateWithAttributedString((__bridge CFAttributedStringRef)attr);assert(framesetter);CFRelease(framesetter);
   UIButton *button=[UIButton new];[button setTitle:source forState:UIControlStateNormal];
   UINavigationItem *nav=[UINavigationItem new];nav.title=source;
  }
  dispatch_sync(onlineQueue,^{});
 }
 assert(fixtureRefreshes==1);
 NSUInteger accepted=0;
 for(NSString *source in map){
  if(!ValidOnlineValue(source,map[source]))continue;accepted++;
  UILabel *label=[UILabel new];label.text=source;assert([label.text isEqual:IsolateLatin(map[source])]);
 }
 assert(accepted>100);
 // Repeat interleaved render/refresh-cache access, including nil inputs and unknown text.
 dispatch_apply(8,dispatch_get_global_queue(QOS_CLASS_DEFAULT,0),^(size_t idx){
  (void)idx;for(int i=0;i<100;i++){
   @autoreleasepool {NSAttributedString *attr=[[NSAttributedString alloc]initWithString:@"无关文本" attributes:nil];assert(attr.length>0);assert(Translate(nil)==nil);}
  }
 });
 fprintf(stderr,"ACTIVE26 PASS exact online-empty constructor, %lu refresh entries, %lu accepted\n",(unsigned long)map.count,(unsigned long)accepted);fflush(stderr);
 [@"PASS" writeToFile:[NSHomeDirectory() stringByAppendingPathComponent:@"Documents/Activated26.result"] atomically:YES encoding:NSUTF8StringEncoding error:NULL];
 exit(0);
}
@interface ActivatedDelegate26 : UIResponder <UIApplicationDelegate>
@property(nonatomic,strong) UIWindow *window;
@end
@implementation ActivatedDelegate26
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
 (void)application;(void)options;
 self.window=[[UIWindow alloc]initWithFrame:UIScreen.mainScreen.bounds];self.window.rootViewController=[UIViewController new];[self.window makeKeyAndVisible];
 dispatch_async(dispatch_get_main_queue(),^{RunActivatedChecks26();});return YES;
}
@end
int main(int argc,char **argv){@autoreleasepool{
 fprintf(stderr,"ACTIVE26 main reached\n");fflush(stderr);
 return UIApplicationMain(argc,argv,nil,NSStringFromClass(ActivatedDelegate26.class));
}}
