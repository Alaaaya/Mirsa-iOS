#import <UIKit/UIKit.h>
#import <CoreText/CoreText.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import <mach-o/dyld.h>
#import "fishhook.h"
#import "Table.h"
#import <os/lock.h>
#import <fcntl.h>
#import <sys/stat.h>
#import <unistd.h>
#import <errno.h>

static NSDictionary *table, *pieces;
static NSArray *rules, *pieceKeys;
static NSCache *cache;
static __thread BOOL translating;
static BOOL enabled;
static __thread BOOL drawing;


// App-local diagnostic log. No network. Bounded queue/dedup and 1 MiB disk cap.
static dispatch_queue_t missingQueue;
static NSMutableSet *missingSeen;
static os_unfair_lock missingLock=OS_UNFAIR_LOCK_INIT;
static NSUInteger missingWaiting;
static BOOL HasCJK(NSString *s) {
 for(NSUInteger i=0;i<s.length;i++){
   uint32_t c=[s characterAtIndex:i];
   if(c>=0xD800 && c<=0xDBFF && i+1<s.length){
     uint32_t lo=[s characterAtIndex:i+1];
     if(lo>=0xDC00 && lo<=0xDFFF){c=0x10000+((c-0xD800)<<10)+(lo-0xDC00);i++;}
   }
   if((c>=0x3040 && c<=0x30FF)||(c>=0xAC00 && c<=0xD7AF)||
      (c>=0x1100 && c<=0x11FF)||(c>=0x3130 && c<=0x318F)||(c>=0x31F0 && c<=0x31FF)||
      (c>=0x3400 && c<=0x4DBF)||(c>=0x4E00 && c<=0x9FFF)||
      (c>=0xF900 && c<=0xFAFF)||(c>=0x20000 && c<=0x323AF))return YES;
 }
 return NO;
}
#import "Tokens.h"
#import "Activation.h"
#import "Banner.h"
#import "Online.h"
#import "Bidi.h"
static void LogMissing(NSString *source,NSString *result) {
 if(!missingQueue || !HasCJK(result))return;
 NSString *sample=SafePrefix(result,4096);
 os_unfair_lock_lock(&missingLock);
 BOOL add=missingWaiting<16 && missingSeen.count<1024 && ![missingSeen containsObject:sample];
 if(add){[missingSeen addObject:sample];missingWaiting++;}
 os_unfair_lock_unlock(&missingLock);
 if(!add)return;
 NSString *input=SafePrefix(source,4096);
 dispatch_async(missingQueue,^{
  @autoreleasepool {
   BOOL previous=translating;translating=YES;
   @try {
    NSString *dir=[NSHomeDirectory() stringByAppendingPathComponent:@"Documents"];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:NULL];
    NSString *path=[dir stringByAppendingPathComponent:@"MirsaTranslateMissing.txt"];
    NSData *json=[NSJSONSerialization dataWithJSONObject:@{@"source":input,@"remaining":sample} options:0 error:NULL];
    if(!json.length)return;
    NSMutableData *line=[json mutableCopy];[line appendBytes:"\n" length:1];
    int fd=open(path.fileSystemRepresentation,O_WRONLY|O_APPEND|O_CREAT|O_NOFOLLOW|O_CLOEXEC,0600);
    if(fd<0)return;
    struct stat st;
    if(fstat(fd,&st)==0 && S_ISREG(st.st_mode) && st.st_nlink==1 && fchmod(fd,0600)==0 && st.st_size>=0 &&
       (uint64_t)st.st_size+line.length<=1024*1024){
      const uint8_t *bytes=line.bytes;NSUInteger left=line.length;
      while(left){
        ssize_t n=write(fd,bytes,left);
        if(n<0 && errno==EINTR)continue;
        if(n<=0)break;
        bytes+=n;left-=(NSUInteger)n;
      }
    }
    close(fd);
   } @catch(__unused NSException *e) {}
   @finally {translating=previous;os_unfair_lock_lock(&missingLock);if(missingWaiting)missingWaiting--;os_unfair_lock_unlock(&missingLock);}
  }
 });
}

static NSString *Translate(NSString *s) {
 if (onlineConfig && OnlineDenied())return s;
 if (onlineConfig && OnlineExpiry(onlineConfig[@"expiresAt"])<=NSDate.date.timeIntervalSince1970)return s;
 if (!enabled || translating || ![s isKindOfClass:NSString.class] || !s.length || s.length>16384) return s;
 translating=YES;
 NSString *result=s;
 @try {
   NSString *remote=OnlineLookup(s);
   if(remote)return IsolateLatin(remote);
   NSString *known=[cache objectForKey:s];
   if (known) { result=known; }
   else {
     NSString *exact=table[s];
     if ([exact isKindOfClass:NSString.class]) result=exact;
     else {
       // Only explicitly reviewed fragments, longest first; no arbitrary machine translation.
       // Full dynamic templates must run before fragment replacement.
       for (NSDictionary *r in rules) {
         NSRegularExpression *re=r[@"compiled"];
         result=[re stringByReplacingMatchesInString:result options:0 range:NSMakeRange(0,result.length) withTemplate:r[@"replacement"]];
       }
       for (NSString *key in pieceKeys) {
         if ([result containsString:key]) result=[result stringByReplacingOccurrencesOfString:key withString:pieces[key]];
       }
     }
     if(!PlaceholdersPreserved(s,result))result=s;
     if(![result isEqualToString:s])result=IsolateLatin(result);
     [cache setObject:result forKey:s cost:s.length+result.length];

   }
 LogMissing(s,result);
   if([s isEqualToString:result] && HasCJK(s))QueueOnline(s);
 } @catch (__unused NSException *e) { result=s; }
 @finally { translating=NO; }
 return result;
}

static NSAttributedString *TranslateAttr(NSAttributedString *a) {
 if (![a isKindOfClass:NSAttributedString.class] || !a.length || translating) return a;
 @try {
  NSString *s=a.string, *t=Translate(s);
  if ([s isEqualToString:t]) return a;
  NSMutableAttributedString *out=[a mutableCopy];
  // Preserve every run when possible. If a translation crosses styled runs, inherit
  // the leading run for the new text instead of leaving out-of-bounds attributes.
  [out replaceCharactersInRange:NSMakeRange(0,out.length) withString:t];
  return out;
 } @catch (__unused NSException *e) { return a; }
}

// Add an override on this class rather than mutating an inherited superclass method.
static void HookString(Class c, SEL sel) {
 Method m=class_getInstanceMethod(c,sel); if (!m) return;
 IMP original=method_getImplementation(m);
 IMP hook=imp_implementationWithBlock(^(id obj, NSString *s) {
   ((void(*)(id,SEL,id))original)(obj,sel,Translate(s));
 });
 if (!class_addMethod(c,sel,hook,method_getTypeEncoding(m))) class_replaceMethod(c,sel,hook,method_getTypeEncoding(m));
}
static void HookAttr(Class c, SEL sel) {
 Method m=class_getInstanceMethod(c,sel); if (!m) return;
 IMP original=method_getImplementation(m);
 IMP hook=imp_implementationWithBlock(^(id obj, NSAttributedString *s) {
   ((void(*)(id,SEL,id))original)(obj,sel,TranslateAttr(s));
 });
 if (!class_addMethod(c,sel,hook,method_getTypeEncoding(m))) class_replaceMethod(c,sel,hook,method_getTypeEncoding(m));
}
static void HookButton(SEL sel, BOOL attributed) {
 Class c=UIButton.class; Method m=class_getInstanceMethod(c,sel); if(!m)return;
 IMP original=method_getImplementation(m);
 IMP hook=imp_implementationWithBlock(^(id obj,id s,UIControlState state){
  id translated=attributed ? TranslateAttr(s) : Translate(s);
  ((void(*)(id,SEL,id,UIControlState))original)(obj,sel,translated,state);
 });
 class_replaceMethod(c,sel,hook,method_getTypeEncoding(m));
}
static void HookAlert(void) {
 Class c=object_getClass(UIAlertController.class);
 SEL sel=@selector(alertControllerWithTitle:message:preferredStyle:);
 Method m=class_getClassMethod(UIAlertController.class,sel);if(!m)return;
 IMP original=method_getImplementation(m);
 class_replaceMethod(c,sel,imp_implementationWithBlock(^id(id obj,NSString *title,NSString *msg,UIAlertControllerStyle style){
  return ((id(*)(id,SEL,id,id,UIAlertControllerStyle))original)(obj,sel,Translate(title),Translate(msg),style);
 }),method_getTypeEncoding(m));
 Class ac=object_getClass(UIAlertAction.class);SEL as=@selector(actionWithTitle:style:handler:);
 Method am=class_getClassMethod(UIAlertAction.class,as); if(!am)return; IMP ai=method_getImplementation(am);
 class_replaceMethod(ac,as,imp_implementationWithBlock(^id(id obj,NSString *title,UIAlertActionStyle style,id handler){
  return ((id(*)(id,SEL,id,UIAlertActionStyle,id))ai)(obj,as,Translate(title),style,handler);
 }),method_getTypeEncoding(am));
}
static CTLineRef (*realLine)(CFAttributedStringRef);
static CTTypesetterRef (*realTypesetter)(CFAttributedStringRef);
static CTFramesetterRef (*realFramesetter)(CFAttributedStringRef);
static CTTypesetterRef (*realTypesetterOptions)(CFAttributedStringRef, CFDictionaryRef);
static CTLineRef HookLine(CFAttributedStringRef s) {
 NSAttributedString *t=TranslateAttr((__bridge NSAttributedString*)s);
 return realLine((__bridge CFAttributedStringRef)t);
}
static CTTypesetterRef HookTypesetter(CFAttributedStringRef s) {
 NSAttributedString *t=TranslateAttr((__bridge NSAttributedString*)s);
 return realTypesetter((__bridge CFAttributedStringRef)t);
}
static CTTypesetterRef HookTypesetterOptions(CFAttributedStringRef s,CFDictionaryRef options) {
 NSAttributedString *t=TranslateAttr((__bridge NSAttributedString*)s);
 return realTypesetterOptions((__bridge CFAttributedStringRef)t,options);
}
static CTFramesetterRef HookFramesetter(CFAttributedStringRef s) {
 NSAttributedString *t=TranslateAttr((__bridge NSAttributedString*)s);
 return realFramesetter((__bridge CFAttributedStringRef)t);
}
static void HookDrawing(Class c) {
 SEL sel=@selector(drawWithRect:options:attributes:context:);
 Method m=class_getInstanceMethod(c,sel);if(!m)return;IMP orig=method_getImplementation(m);
 IMP hook=imp_implementationWithBlock(^(NSString *obj,CGRect rect,NSStringDrawingOptions opts,NSDictionary *attrs,NSStringDrawingContext *ctx){
   NSString *t=drawing ? obj : Translate(obj);
   if(t==obj || [t isEqualToString:obj]){
     ((void(*)(id,SEL,CGRect,NSStringDrawingOptions,id,id))orig)(obj,sel,rect,opts,attrs,ctx);
   } else {
     drawing=YES;
     @try { [t drawWithRect:rect options:opts attributes:attrs context:ctx]; }
     @finally { drawing=NO; }
   }
 });
 if(!class_addMethod(c,sel,hook,method_getTypeEncoding(m)))class_replaceMethod(c,sel,hook,method_getTypeEncoding(m));
}
// SwiftUI often creates attributed strings without UILabel. Intercept its concrete
// Foundation class-cluster initializers as well as CoreText shaping boundaries.
static void HookAttributedInit(Class c) {
 SEL sel=@selector(initWithString:attributes:);
 Method m=class_getInstanceMethod(c,sel);if(!m)return;IMP orig=method_getImplementation(m);
 IMP hook=imp_implementationWithBlock(^id(id obj,NSString *s,NSDictionary *attrs){
  return ((id(*)(id,SEL,id,id))orig)(obj,sel,Translate(s),attrs);
 });
 if(!class_addMethod(c,sel,hook,method_getTypeEncoding(m)))class_replaceMethod(c,sel,hook,method_getTypeEncoding(m));
}
__attribute__((constructor)) static void Start(void) {
 @autoreleasepool { @try {
   NSData *data=[NSData dataWithBytes:runtime_table length:runtime_table_len];
   NSDictionary *config=[NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
   if (![config isKindOfClass:NSDictionary.class])return;
   // A local per-app JSON next to the dylib overrides its embedded defaults.
   Dl_info info;
   if(dladdr((void*)Start,&info) && info.dli_fname){
     NSString *path=[[@(info.dli_fname) stringByDeletingLastPathComponent] stringByAppendingPathComponent:@"MirsaTranslations.json"];
     NSData *override=[NSData dataWithContentsOfFile:path options:NSDataReadingMappedIfSafe error:NULL];
     if(override.length && override.length<4*1024*1024){
       id obj=[NSJSONSerialization JSONObjectWithData:override options:0 error:NULL];
       if([obj isKindOfClass:NSDictionary.class])config=obj;
     }
   }
   table=[config[@"translations"] isKindOfClass:NSDictionary.class]?config[@"translations"]:@{};
   pieces=[config[@"substrings"] isKindOfClass:NSDictionary.class]?config[@"substrings"]:@{};
   NSMutableDictionary *safe=[NSMutableDictionary dictionary];
   [pieces enumerateKeysAndObjectsUsingBlock:^(id k,id v,__unused BOOL *stop){if([k isKindOfClass:NSString.class]&&[v isKindOfClass:NSString.class]&&[k length])safe[k]=v;}];
   pieces=[safe copy];
   pieceKeys=[[pieces allKeys] sortedArrayUsingComparator:^NSComparisonResult(NSString*a,NSString*b){return a.length>b.length?NSOrderedAscending:a.length<b.length?NSOrderedDescending:NSOrderedSame;}];
   NSMutableArray *rr=[NSMutableArray array];
   if([config[@"regex"] isKindOfClass:NSArray.class])for(id r in config[@"regex"]){
     if(![r isKindOfClass:NSDictionary.class]||![r[@"pattern"] isKindOfClass:NSString.class]||![r[@"replacement"] isKindOfClass:NSString.class])continue;
     NSRegularExpression *re=[NSRegularExpression regularExpressionWithPattern:r[@"pattern"] options:0 error:NULL];
     if(re)[rr addObject:@{@"compiled":re,@"replacement":r[@"replacement"]}];
   }
   rules=[rr copy];
   cache=[NSCache new];cache.countLimit=2048;cache.totalCostLimit=1024*1024;
   missingSeen=[NSMutableSet set];
   missingQueue=dispatch_queue_create("app.mirsa.translate.missing",DISPATCH_QUEUE_SERIAL);
   ConfigureOnline(config);
   if(!onlineConfig)return;
   enabled=YES;
   HookString(UILabel.class,@selector(setText:));HookAttr(UILabel.class,@selector(setAttributedText:));
   HookString(UITextField.class,@selector(setPlaceholder:));HookAttr(UITextField.class,@selector(setAttributedPlaceholder:));
   HookString(UINavigationItem.class,@selector(setTitle:));HookString(UINavigationItem.class,@selector(setPrompt:));
   HookString(UITabBarItem.class,@selector(setTitle:));
   HookString(UIAlertController.class,@selector(setTitle:));HookString(UIAlertController.class,@selector(setMessage:));
   HookButton(@selector(setTitle:forState:),NO);HookButton(@selector(setAttributedTitle:forState:),YES);HookAlert();
   NSMutableSet *attrClasses=[NSMutableSet setWithObjects:NSAttributedString.class,NSMutableAttributedString.class,
      object_getClass([[NSAttributedString alloc] initWithString:@"sample"]),
      object_getClass([[NSMutableAttributedString alloc] initWithString:@"sample"]),nil];
   for(Class c in attrClasses)HookAttributedInit(c);
   NSMutableSet *stringClasses=[NSMutableSet setWithObjects:NSString.class,object_getClass(@"sample"),
      object_getClass([NSString stringWithFormat:@"sample %d",42]),nil];
   for(Class c in stringClasses)HookDrawing(c);
   realLine=dlsym(RTLD_DEFAULT,"CTLineCreateWithAttributedString");
   realTypesetter=dlsym(RTLD_DEFAULT,"CTTypesetterCreateWithAttributedString");
   realFramesetter=dlsym(RTLD_DEFAULT,"CTFramesetterCreateWithAttributedString");
   realTypesetterOptions=dlsym(RTLD_DEFAULT,"CTTypesetterCreateWithAttributedStringAndOptions");
   struct rebinding rb[4];size_t n=0;
   if(realLine)rb[n++]=(struct rebinding){"CTLineCreateWithAttributedString",HookLine,NULL};
   if(realTypesetter)rb[n++]=(struct rebinding){"CTTypesetterCreateWithAttributedString",HookTypesetter,NULL};
   if(realFramesetter)rb[n++]=(struct rebinding){"CTFramesetterCreateWithAttributedString",HookFramesetter,NULL};
   if(realTypesetterOptions)rb[n++]=(struct rebinding){"CTTypesetterCreateWithAttributedStringAndOptions",HookTypesetterOptions,NULL};
   if(n)rebind_symbols(rb,n);
 } @catch(__unused NSException*e){enabled=NO;} }
}
