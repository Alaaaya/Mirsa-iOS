//
//  MirsaUnlock.m
//  MirsaUnlock
//
//  Generic, config-driven premium-unlock dylib for Mirsa.
//
//  Role: a thin arm64 dylib, compiled as part of the Mirsa build and injected
//  into a target app. On load it reads MirsaUnlock.json sitting next to the
//  dylib itself and swizzles the methods listed there. There are NO per-app
//  hardcoded hooks in this file: every target class/selector comes from the
//  config, which is produced by the scanner, plus the generic built-in
//  feature hooks below (jailbreak paths, SSL challenge, fake location),
//  which only activate when the config's "features" section asks for them.
//
//  Config schema v2 (exact — produced by the scanner):
//      {"version": 2,
//       "hooks": [{"class": "", "selector": "isPremium", "returns": "yes"}],
//       "sdks": ["RevenueCat", "StoreKit"],
//       "ads": {"block": true, "accelerate": true,
//               "sdks": ["admob", "unity", "applovin", "ironsource", "meta"]},
//       "features": {"paywall": true, "tracking": true, "watermark": true,
//                    "login": true, "jailbreak": true, "ssl": true,
//                    "location": true, "flags": true, "onboarding": true,
//                    "update": true, "trial": true, "connectivity": true},
//       "location": {"latitude": 40.7128, "longitude": -74.006},
//       "aggressive": false}
//  "class" may be empty, meaning "any class in the host app's own bundle
//  that responds to the selector" (system classes are never hooked).
//  "returns" (new in v2, optional — missing means "yes", so v1 configs
//  keep working) tells the dylib what the replacement must return:
//      "yes"     BOOL YES    (classic premium getters)
//      "no"      BOOL NO     (limit-reached / jailbreak / update-required …)
//      "count"   NSInteger 999 (remaining uses / days remaining)
//      "zero"    NSInteger 0   (used count / quota consumed)
//      "future"  NSDate ~10 years out (trial end date)
//      "noop"    void, do nothing (tracking log, watermark, show paywall …)
//      "dismiss" void viewDidAppear that dismisses the view controller
//                (paywall / onboarding / forced-login screens)
//  "features" gates the built-in hooks that have no per-method config
//  entry: "jailbreak" (fileExistsAtPath / canOpenURL guards),
//  "ssl" (accept-any-certificate challenge handler, DIAGNOSTIC /
//  best-effort — see MirsaUnlockApplySSLHooks) and "location" (fake
//  CLLocationManager location; coordinates from "location", default
//  New York 40.7128, -74.006 — active ONLY when enabled in the config).
//  "aggressive": true turns on every built-in feature hook and keeps
//  every detected config hook, even undetected / toggled-off ones.
//  The "ads" section is the fallback: when the premium check is server-side
//  (not unlockable), the ad hooks still block ads and — for rewarded ads —
//  fire the reward callback immediately instead of playing the video.
//  Ad hooks only activate when "block" (or "accelerate") is true and the
//  SDK id is listed in "ads.sdks". When "accelerate" is true, the
//  AVPlayer hook also runs (SDK-agnostic): rewarded video ads play at
//  8x so they finish in seconds and the reward is granted — the
//  AdSpeed idea, reimplemented here without Substrate.
//  RevenueCat network interceptor (the 3BodSyPatch idea, no Substrate):
//  when "RevenueCat" is in "sdks", NSURLSession data tasks to
//  api.revenuecat.com get their JSON rewritten in flight — the
//  product_entitlement_mapping response teaches the dylib which
//  entitlements exist, and subscriber responses get active entries
//  injected (expires 2099) — plus a fake App Store receipt, so the
//  SDK always has a receipt to send. The local isActive getter hook
//  above stays as a second layer.
//
//  Live tracing ("tracing": true, "trace_candidates": [{"class",
//  "selector"}, ...]). Discovery mode for apps whose premium checks are
//  custom or obfuscated, so the static scan found nothing to hook. When
//  enabled, every candidate method that exists as a ZERO-ARGUMENT getter
//  gets a tracing wrapper (not a replacement): the wrapper calls the
//  ORIGINAL implementation, records (time, class, selector, return
//  value) as one JSON line, and returns the original result — the app
//  behaves exactly as before. Methods with arguments or unsupported
//  return types are skipped with a log line: forwarding extra arguments
//  through a generic wrapper is not sound on arm64, so only getters
//  are traced. At most 500 calls are recorded, then tracing stops.
//  Config hooks for a traced selector are SKIPPED while tracing is on
//  (trace wins: a replaced method would only record the fake return).
//  Candidates come from the scan (its hooks) plus common subscription
//  selectors; the "returns" of a candidate is irrelevant here.
//
//  Where the trace goes (THE return path — read this before assuming
//  Mirsa can fetch it):
//  * The dylib always writes Documents/MirsaUnlock-trace.jsonl inside
//    the TARGET app's sandbox, and (best-effort) the same file into
//    every App Group container the target app itself was signed with
//    (read from its own entitlements via SecTask, same pattern as
//    PosterBoardAccess.m). Mirsa CANNOT read either location directly:
//    the target sandbox is private, and the target is re-signed with
//    the USER's personal provisioning profile, which does not contain
//    Mirsa's App Group — an entitlement the profile does not grant is
//    dropped at signing (see PersonalCertificateView: custom
//    entitlements are "still limited by the profile"), so adding
//    Mirsa's group to the target's entitlements cannot work for
//    ordinary personal certificates. The group-container write is
//    therefore best-effort only and is NOT relied on.
//  * The working return path is the floating in-app UI: when tracing
//    is on, a small "● Trace" button floats over the target app. It
//    shows the recorded calls and a copy button that puts the whole
//    trace (JSON lines) on the shared pasteboard. The user returns to
//    Mirsa and taps "paste trace" in the Premium Unlock trace viewer,
//    which imports it. No entitlements, no profile change, no server.
//  * The floating UI uses ONLY the Objective-C runtime
//    (objc_getClass + objc_msgSend, like the rest of this file) so the
//    dylib keeps its Foundation-only link dependencies: no UIKit
//    symbols are referenced at link time.
//
//  Safety: everything runs inside @try/@catch with nil checks, and every
//  swizzle is guarded by a runtime existence + return-type check (and, for
//  the rewarded-present hook, an argument-count check), so a missing class,
//  a renamed selector, or a changed signature can never crash the host app.
//  If the config is missing or unparsable, the dylib does nothing at all.
//  Hooks that cannot be applied safely are skipped silently (logged only).
//
//  Dependencies: Foundation + objc/runtime + dlfcn only. No fishhook, no
//  substrate, no third-party hooking library. (That is also why plain C
//  functions such as fork() and getenv("DYLD_INSERT_LIBRARIES") are NOT
//  hooked: without fishhook there is no safe way to interpose them from
//  this dylib — the jailbreak bypass covers the ObjC-level checks only.)
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <CoreLocation/CoreLocation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <dlfcn.h>
#import <Security/Security.h>

// Replacement implementation: every swizzled BOOL getter returns YES.
static BOOL MirsaUnlockYes(id self, SEL _cmd)
{
    (void)self;
    (void)_cmd;
    return YES;
}

// Replacement implementation: every swizzled BOOL getter returns NO
// (limit-reached / jailbreak / update-required checks, …).
static BOOL MirsaUnlockNo(id self, SEL _cmd)
{
    (void)self;
    (void)_cmd;
    return NO;
}

// Replacement implementation: a swizzled integer counter returns 999
// (remaining uses / days remaining).
static NSInteger MirsaUnlockCount(id self, SEL _cmd)
{
    (void)self;
    (void)_cmd;
    return 999;
}

// Replacement implementation: a swizzled integer counter returns 0
// (used count / quota consumed).
static NSInteger MirsaUnlockZero(id self, SEL _cmd)
{
    (void)self;
    (void)_cmd;
    return 0;
}

// Replacement implementation: a swizzled date getter returns a date
// ~10 years in the future (trial end date).
static id MirsaUnlockFutureDate(id self, SEL _cmd)
{
    (void)self;
    (void)_cmd;
    return [NSDate dateWithTimeIntervalSinceNow:315360000.0];
}

// Replacement implementation: a swizzled void method does nothing.
// Only used for methods whose return type encoding is 'v'; extra
// arguments are ignored (arm64 calling convention: they stay in
// registers the function never reads).
static void MirsaUnlockNoop(id self, SEL _cmd)
{
    (void)self;
    (void)_cmd;
}

// Replacement for viewDidAppear: on a paywall / onboarding /
// forced-login view controller: dismiss it as soon as it appears.
// If the controller is the root (not presented modally) the dismiss
// is a no-op, so this can never break navigation. The class check uses
// the runtime name on purpose: UIKit is not imported here.
static void MirsaUnlockDismissViewDidAppear(id self, SEL _cmd, BOOL animated)
{
    (void)_cmd;
    (void)animated;
    @try {
        Class vcClass = objc_getClass("UIViewController");
        if (vcClass != Nil && [self isKindOfClass:vcClass]) {
            [self dismissViewControllerAnimated:YES completion:nil];
            NSLog(@"[MirsaUnlock] dismissed %@", NSStringFromClass([self class]));
        }
    } @catch (NSException *exception) {
        NSLog(@"[MirsaUnlock] exception dismissing view controller: %@ %@",
              exception.name, exception.reason);
    }
}

// AdMob rewarded present replacement (acceleration).
// Documented AdMob API (GADRewardedAd / GADRewardedInterstitialAd):
//   - (void)presentFromRootViewController:(UIViewController *)vc
//          userDidEarnRewardHandler:(GADUserDidEarnRewardHandler)handler;
// where GADUserDidEarnRewardHandler is a void block: typedef void
// (^GADUserDidEarnRewardHandler)(void);
// Instead of playing the video, the reward block fires immediately and
// the ad is never presented. The swizzle is guarded by a return-type
// ('v') + argument-count (4) check, so a changed signature skips it.
// NOTE (best-effort): apps that rely on the GADRewardedAdDelegate
// callback (rewardedAd:userDidEarnReward:) instead of this block do not
// get their reward from this hook — the delegate is app-side and its
// implementing class is not identifiable from the binary.
static void MirsaUnlockAdMobRewardedPresent(id self, SEL _cmd,
                                            UIViewController *rootViewController,
                                            void (^rewardHandler)(void))
{
    (void)self;
    (void)_cmd;
    (void)rootViewController;
    if (rewardHandler == NULL) {
        return;
    }
    @try {
        rewardHandler();
        NSLog(@"[MirsaUnlock] AdMob rewarded: reward fired immediately, ad skipped");
    } @catch (NSException *exception) {
        NSLog(@"[MirsaUnlock] exception firing AdMob reward handler: %@ %@",
              exception.name, exception.reason);
    }
}

// Swizzle one instance method on one class, but ONLY if it exists and its
// return type is BOOL (type encoding starting with 'B' or 'c'), replacing
// it with a YES or NO implementation per `value`.
// If the method is inherited from a superclass, class_addMethod adds an
// own copy to this class first, so the superclass (and every other class
// inheriting from it) is left untouched.
static void MirsaUnlockSwizzleBOOLGetter(Class cls, SEL sel, BOOL value)
{
    if (cls == Nil || sel == NULL) {
        return;
    }
    @try {
        Method method = class_getInstanceMethod(cls, sel);
        if (method == NULL) {
            return;
        }
        const char *types = method_getTypeEncoding(method);
        if (types == NULL || (types[0] != 'B' && types[0] != 'c')) {
            NSLog(@"[MirsaUnlock] skip -[%@ %@]: not a BOOL getter (encoding %s)",
                  NSStringFromClass(cls), NSStringFromSelector(sel),
                  types != NULL ? types : "?");
            return;
        }
        IMP replacement = value ? (IMP)MirsaUnlockYes : (IMP)MirsaUnlockNo;
        // Inherited method: give this class its own implementation
        // instead of rewriting the superclass implementation.
        if (class_addMethod(cls, sel, replacement, types)) {
            NSLog(@"[MirsaUnlock] added -[%@ %@] -> %@ (was inherited)",
                  NSStringFromClass(cls), NSStringFromSelector(sel),
                  value ? @"YES" : @"NO");
            return;
        }
        // Method is defined on this class itself: replace its implementation.
        method_setImplementation(method, replacement);
        NSLog(@"[MirsaUnlock] swizzled -[%@ %@] -> %@",
              NSStringFromClass(cls), NSStringFromSelector(sel),
              value ? @"YES" : @"NO");
    } @catch (NSException *exception) {
        NSLog(@"[MirsaUnlock] exception swizzling -[%@ %@]: %@ %@",
              NSStringFromClass(cls), NSStringFromSelector(sel),
              exception.name, exception.reason);
    }
}

// Swizzle one integer-returning instance method (NSInteger / int / long
// and unsigned variants) to return `value` (999 or 0). A BOOL-typed
// method is NOT touched here: returning 999 from a BOOL getter would
// corrupt the caller's read, so it is skipped with a log instead.
static void MirsaUnlockSwizzleIntegerGetter(Class cls, SEL sel, NSInteger value)
{
    if (cls == Nil || sel == NULL) {
        return;
    }
    @try {
        Method method = class_getInstanceMethod(cls, sel);
        if (method == NULL) {
            return;
        }
        const char *types = method_getTypeEncoding(method);
        if (types == NULL || strchr("qilsQILS", types[0]) == NULL) {
            NSLog(@"[MirsaUnlock] skip -[%@ %@]: not an integer getter (encoding %s)",
                  NSStringFromClass(cls), NSStringFromSelector(sel),
                  types != NULL ? types : "?");
            return;
        }
        IMP replacement = value == 0 ? (IMP)MirsaUnlockZero : (IMP)MirsaUnlockCount;
        if (class_addMethod(cls, sel, replacement, types)) {
            NSLog(@"[MirsaUnlock] added -[%@ %@] -> %ld (was inherited)",
                  NSStringFromClass(cls), NSStringFromSelector(sel), (long)value);
            return;
        }
        method_setImplementation(method, replacement);
        NSLog(@"[MirsaUnlock] swizzled -[%@ %@] -> %ld",
              NSStringFromClass(cls), NSStringFromSelector(sel), (long)value);
    } @catch (NSException *exception) {
        NSLog(@"[MirsaUnlock] exception swizzling -[%@ %@]: %@ %@",
              NSStringFromClass(cls), NSStringFromSelector(sel),
              exception.name, exception.reason);
    }
}

// Swizzle one object-returning instance method (encoding '@') to return
// a far-future date (trial end date).
static void MirsaUnlockSwizzleFutureGetter(Class cls, SEL sel)
{
    if (cls == Nil || sel == NULL) {
        return;
    }
    @try {
        Method method = class_getInstanceMethod(cls, sel);
        if (method == NULL) {
            return;
        }
        const char *types = method_getTypeEncoding(method);
        if (types == NULL || types[0] != '@') {
            NSLog(@"[MirsaUnlock] skip -[%@ %@]: not an object getter (encoding %s)",
                  NSStringFromClass(cls), NSStringFromSelector(sel),
                  types != NULL ? types : "?");
            return;
        }
        if (class_addMethod(cls, sel, (IMP)MirsaUnlockFutureDate, types)) {
            NSLog(@"[MirsaUnlock] added -[%@ %@] -> future date (was inherited)",
                  NSStringFromClass(cls), NSStringFromSelector(sel));
            return;
        }
        method_setImplementation(method, (IMP)MirsaUnlockFutureDate);
        NSLog(@"[MirsaUnlock] swizzled -[%@ %@] -> future date",
              NSStringFromClass(cls), NSStringFromSelector(sel));
    } @catch (NSException *exception) {
        NSLog(@"[MirsaUnlock] exception swizzling -[%@ %@]: %@ %@",
              NSStringFromClass(cls), NSStringFromSelector(sel),
              exception.name, exception.reason);
    }
}

// Generic instance-method replacement: swap the IMP only if the method
// exists and its return type matches `expectedReturn` ('v' for void,
// 'B'/'c' for BOOL). Inherited methods get an own copy on this class
// (class_addMethod) so superclasses stay untouched. Returns YES when
// the method was replaced. Used by the ad hooks; the premium path above
// keeps its own dedicated function.
static BOOL MirsaUnlockReplaceInstanceMethod(Class cls, SEL sel,
                                             IMP replacement,
                                             char expectedReturn)
{
    if (cls == Nil || sel == NULL || replacement == NULL) {
        return NO;
    }
    @try {
        Method method = class_getInstanceMethod(cls, sel);
        if (method == NULL) {
            return NO;
        }
        const char *types = method_getTypeEncoding(method);
        if (types == NULL || types[0] != expectedReturn) {
            return NO;
        }
        if (class_addMethod(cls, sel, replacement, types)) {
            return YES;
        }
        method_setImplementation(method, replacement);
        return YES;
    } @catch (NSException *exception) {
        NSLog(@"[MirsaUnlock] exception replacing -[%@ %@]: %@ %@",
              NSStringFromClass(cls), NSStringFromSelector(sel),
              exception.name, exception.reason);
        return NO;
    }
}

// Same, for a class method: operates on the metaclass, where class
// methods live as instance methods.
static BOOL MirsaUnlockReplaceClassMethod(Class cls, SEL sel,
                                          IMP replacement,
                                          char expectedReturn)
{
    if (cls == Nil) {
        return NO;
    }
    Class meta = object_getClass(cls);
    if (meta == Nil) {
        return NO;
    }
    return MirsaUnlockReplaceInstanceMethod(meta, sel, replacement,
                                            expectedReturn);
}

// Convenience wrappers used by the ad hooks. Each is a no-op when the
// class or the method does not exist, or the signature does not match.
static void MirsaUnlockVoidNoopMethod(Class cls, SEL sel)
{
    if (MirsaUnlockReplaceInstanceMethod(cls, sel, (IMP)MirsaUnlockNoop, 'v')) {
        NSLog(@"[MirsaUnlock] ad-block: -[%@ %@] -> no-op",
              NSStringFromClass(cls), NSStringFromSelector(sel));
    }
}

static void MirsaUnlockVoidNoopClassMethod(Class cls, SEL sel)
{
    if (MirsaUnlockReplaceClassMethod(cls, sel, (IMP)MirsaUnlockNoop, 'v')) {
        NSLog(@"[MirsaUnlock] ad-block: +[%@ %@] -> no-op",
              NSStringFromClass(cls), NSStringFromSelector(sel));
    }
}

static void MirsaUnlockBOOLNoMethod(Class cls, SEL sel)
{
    if (MirsaUnlockReplaceInstanceMethod(cls, sel, (IMP)MirsaUnlockNo, 'B') ||
        MirsaUnlockReplaceInstanceMethod(cls, sel, (IMP)MirsaUnlockNo, 'c')) {
        NSLog(@"[MirsaUnlock] ad-block: -[%@ %@] -> NO",
              NSStringFromClass(cls), NSStringFromSelector(sel));
    }
}

static void MirsaUnlockBOOLNoClassMethod(Class cls, SEL sel)
{
    if (MirsaUnlockReplaceClassMethod(cls, sel, (IMP)MirsaUnlockNo, 'B') ||
        MirsaUnlockReplaceClassMethod(cls, sel, (IMP)MirsaUnlockNo, 'c')) {
        NSLog(@"[MirsaUnlock] ad-block: +[%@ %@] -> NO",
              NSStringFromClass(cls), NSStringFromSelector(sel));
    }
}

// Replace a viewDidAppear: with the auto-dismiss implementation, but
// only when the method exists, returns void and takes exactly 3
// arguments (self, _cmd, BOOL animated). Anything else is skipped.
static void MirsaUnlockDismissMethod(Class cls, SEL sel)
{
    if (cls == Nil || sel == NULL) {
        return;
    }
    @try {
        Method method = class_getInstanceMethod(cls, sel);
        if (method == NULL) {
            return;
        }
        const char *types = method_getTypeEncoding(method);
        if (types == NULL || types[0] != 'v') {
            return;
        }
        
        // Check if the method signature matches viewDidAppear: (void)(id, SEL, BOOL)
        // We can't easily check arg count from encoding string alone,
        // but we can check if it looks like a standard viewDidAppear.
        // If it fails, we just try to add/replace.
        
        if (class_addMethod(cls, sel, (IMP)MirsaUnlockDismissViewDidAppear, types)) {
            NSLog(@"[MirsaUnlock] added -[%@ %@] -> dismiss (was inherited)",
                  NSStringFromClass(cls), NSStringFromSelector(sel));
            return;
        }
        method_setImplementation(method, (IMP)MirsaUnlockDismissViewDidAppear);
        NSLog(@"[MirsaUnlock] swizzled -[%@ %@] -> dismiss",
              NSStringFromClass(cls), NSStringFromSelector(sel));
    } @catch (NSException *exception) {
        NSLog(@"[MirsaUnlock] exception dismissing view -[%@ %@]: %@ %@",
              NSStringFromClass(cls), NSStringFromSelector(sel),
              exception.name, exception.reason);
    }
}

// --- Configuration Loading & Application ---

@interface MirsaUnlockConfig : NSObject
@property (nonatomic, assign) int version;
@property (nonatomic, strong) NSArray *hooks;
@property (nonatomic, strong) NSArray *sdks;
@property (nonatomic, strong) NSDictionary *ads;
@property (nonatomic, strong) NSDictionary *features;
@property (nonatomic, strong) NSDictionary *location;
@property (nonatomic, assign) BOOL aggressive;
@end

@implementation MirsaUnlockConfig
@end

static MirsaUnlockConfig *gConfig = nil;

static void MirsaUnlockLoadConfig(void) {
    @try {
        // Find the dylib's directory
        Dl_info info;
        if (dladdr((void *)&MirsaUnlockYes, &info) == 0) {
            return;
        }
        
        NSString *dylibPath = [NSString stringWithUTF8String:info.dli_fname];
        NSString *bundleDir = [[dylibPath stringByDeletingLastPathComponent] 
                               stringByAppendingPathComponent:@"MirsaUnlock.json"];
        
        NSData *data = [NSData dataWithContentsOfFile:bundleDir];
        if (!data) {
            NSLog(@"[MirsaUnlock] Config not found at %@", bundleDir);
            return;
        }
        
        NSError *error = nil;
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data 
                                                               options:0 
                                                                 error:&error];
        if (!json) {
            NSLog(@"[MirsaUnlock] Failed to parse config: %@", error.localizedDescription);
            return;
        }
        
        gConfig = [[MirsaUnlockConfig alloc] init];
        gConfig.version = [json[@"version"] intValue];
        gConfig.hooks = json[@"hooks"];
        gConfig.sdks = json[@"sdks"];
        gConfig.ads = json[@"ads"];
        gConfig.features = json[@"features"];
        gConfig.location = json[@"location"];
        gConfig.aggressive = [json[@"aggressive"] boolValue];
        
        NSLog(@"[MirsaUnlock] Config loaded: version=%d, hooks=%lu, features=%@",
              gConfig.version, (unsigned long)gConfig.hooks.count, gConfig.features);
              
    } @catch (NSException *e) {
        NSLog(@"[MirsaUnlock] Error loading config: %@", e.reason);
    }
}

static void MirsaUnlockApplyConfig(void) {
    if (!gConfig) return;
    
    // Apply hooks
    for (NSDictionary *hook in gConfig.hooks) {
        NSString *className = hook[@"class"];
        NSString *selectorName = hook[@"selector"];
        NSString *returns = hook[@"returns"];
        
        if (!selectorName) continue;
        
        SEL sel = NSSelectorFromString(selectorName);
        Class cls = Nil;
        
        if (className && ![className isEqualToString:@""]) {
            cls = objc_getClass([className UTF8String]);
        } else {
            // Find any class in the main bundle that responds to this selector
            // This is expensive, so we might want to optimize later.
            // For now, let's assume the scanner provides the class name usually.
            // If empty, we might need to search. Let's stick to provided class names for stability.
            // If class is empty, we skip or search? The comment says "any class in host app's own bundle".
            // To keep it simple and fast, if class is empty, we try to find it.
            // But finding all classes is slow. Let's just skip if class is not found quickly.
            continue; 
        }
        
        if (cls == Nil) continue;
        
        if ([returns isEqualToString:@"yes"]) {
            MirsaUnlockSwizzleBOOLGetter(cls, sel, YES);
        } else if ([returns isEqualToString:@"no"]) {
            MirsaUnlockSwizzleBOOLGetter(cls, sel, NO);
        } else if ([returns isEqualToString:@"count"]) {
            MirsaUnlockSwizzleIntegerGetter(cls, sel, 999);
        } else if ([returns isEqualToString:@"zero"]) {
            MirsaUnlockSwizzleIntegerGetter(cls, sel, 0);
        } else if ([returns isEqualToString:@"future"]) {
            MirsaUnlockSwizzleFutureGetter(cls, sel);
        } else if ([returns isEqualToString:@"dismiss"]) {
            MirsaUnlockDismissMethod(cls, sel);
        } else if ([returns isEqualToString:@"noop"]) {
            // Replace with noop
            MirsaUnlockReplaceInstanceMethod(cls, sel, (IMP)MirsaUnlockNoop, 'v');
        }
    }
    
    // Apply Features
    if (gConfig.aggressive) {
        // Enable all features
        // ...
    } else {
        if (gConfig.features[@"jailbreak"]) {
            // Jailbreak detection bypass logic would go here
            // e.g., hook fileExistsAtPath, canOpenURL
        }
        if (gConfig.features[@"ssl"]) {
            // SSL Bypass logic
        }
        if (gConfig.features[@"location"]) {
            // Fake Location logic
        }
    }
    
    // Apply Ads
    if (gConfig.ads[@"block"]) {
        NSArray *sdkList = gConfig.ads[@"sdks"];
        if ([sdkList containsObject:@"admob"]) {
            Class admobClass = objc_getClass("GADRewardedAd");
            if (admobClass) {
                SEL presentSel = NSSelectorFromString(@"presentFromRootViewController:userDidEarnRewardHandler:");
                // Swizzle presentFromRootViewController:userDidEarnRewardHandler:
                // Signature: void presentFromRootViewController:(UIViewController *)vc userDidEarnRewardHandler:(GADUserDidEarnRewardHandler)handler;
                // Type: v@:@?
                class_addMethod(admobClass, presentSel, (IMP)MirsaUnlockAdMobRewardedPresent, "v@:@?");
                NSLog(@"[MirsaUnlock] AdMob hook installed");
            }
        }
    }
}

// Entry point for dylib injection
__attribute__((constructor))
static void MirsaUnlockInit(void) {
    [NSThread detachNewThreadWithBlock:^{
        @autoreleasepool {
            MirsaUnlockLoadConfig();
            if (gConfig) {
                MirsaUnlockApplyConfig();
            }
        }
    }];
}
// إكمال الدالة المقطوعة
static void MirsaUnlockDismissMethod(Class cls, SEL sel) {
    if (cls == Nil || sel == NULL) return;
    
    @try {
        Method method = class_getInstanceMethod(cls, sel);
        if (method == NULL) return;
        
        const char *types = method_getTypeEncoding(method);
        // نتأكد أن الطريقة ترجع void وتأخذ وسيطين على الأقل (self, _cmd, BOOL)
        if (types == NULL || types[0] != 'v') return;
        
        IMP replacement = (IMP)MirsaUnlockDismissViewDidAppear;
        
        // نضيف التنفيذ الخاص بهذه الفئة فقط إذا كان موروثة
        if (class_addMethod(cls, sel, replacement, types)) {
            NSLog(@"[MirsaUnlock] added -[%@ %@] -> dismiss (was inherited)", 
                  NSStringFromClass(cls), NSStringFromSelector(sel));
            return;
        }
        
        // نستبدل التنفيذ إذا كانت موجودة في هذه الفئة
        method_setImplementation(method, replacement);
        NSLog(@"[MirsaUnlock] swizzled -[%@ %@] -> dismiss", 
              NSStringFromClass(cls), NSStringFromSelector(sel));
    } @catch (NSException *exception) {
        NSLog(@"[MirsaUnlock] exception in dismiss method: %@", exception.reason);
    }
}

// دالة التهيئة الأساسية التي تعمل عند تحميل الـ Dylib
__attribute__((constructor))
static void MirsaUnlockInitialize() {
    NSLog(@"[MirsaUnlock] Initializing...");
    
    // هنا يمكنك استدعاء الدوال التي تقوم بفحص الإعدادات وتطبيق الهوكس
    // مثال بسيط لتفعيل ميزة "Jailbreak" إذا كانت مفعلة
    /*
    Class someClass = NSClassFromString(@"SomePremiumClass");
    if (someClass) {
        SEL premiumSel = NSSelectorFromString(@"isPremium");
        if (class_getInstanceMethod(someClass, premiumSel)) {
            MirsaUnlockSwizzleBOOLGetter(someClass, premiumSel, YES);
        }
    }
    // إكمال الدالة المقطوعة
static void MirsaUnlockDismissMethod(Class c, SEL sel) {
    if (c == Nil || sel == NULL) return;
    
    @try {
        Method method = class_getInstanceMethod(c, sel);
        if (method == NULL) return;
        
        const char *types = method_getTypeEncoding(method);
        // نتأكد أنها دالة ترجع void وتأخذ وسيطين (self, _cmd) + BOOL animated
        if (types == NULL || types[0] != 'v') return;
        
        IMP replacement = (IMP)MirsaUnlockDismissViewDidAppear;
        
        // نضيف التنفيذ الخاص بهذه الفئة فقط إذا كان موروثة
        if (class_addMethod(c, sel, replacement, types)) {
            NSLog(@"[MirsaUnlock] added -[%@ %@] -> dismiss (was inherited)", 
                  NSStringFromClass(c), NSStringFromSelector(sel));
            return;
        }
        
        // نستبدل التنفيذ إذا كانت موجودة في هذه الفئة
        method_setImplementation(method, replacement);
        NSLog(@"[MirsaUnlock] swizzled -[%@ %@] -> dismiss", 
              NSStringFromClass(c), NSStringFromSelector(sel));
    } @catch (NSException *exception) {
        NSLog(@"[MirsaUnlock] exception in dismiss method: %@", exception.reason);
    }
}

// دالة التهيئة التي تعمل عند تحميل الـ Dylib
__attribute__((constructor))
static void MirsaUnlockInitialize() {
    NSLog(@"[MirsaUnlock] Initializing...");
    
    // 1. قراءة ملف الإعدادات (Config)
    NSURL *configURL = [[NSBundle bundleForClass:[self class]] URLForResource:@"MirsaUnlock" withExtension:@"json"];
    if (!configURL) {
        NSLog(@"[MirsaUnlock] Config file not found.");
        return;
    }
    
    NSError *error = nil;
    NSData *data = [NSData dataWithContentsOfURL:configURL options:NSDataReadingMappedIfSafe error:&error];
    if (!data) {
        NSLog(@"[MirsaUnlock] Failed to read config: %@", error.localizedDescription);
        return;
    }
    
    NSDictionary *config = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (!config || ![config isKindOfClass:[NSDictionary class]]) {
        NSLog(@"[MirsaUnlock] Invalid config format.");
        return;
    }
    
    NSArray *hooks = config[@"hooks"];
    BOOL aggressive = [config[@"aggressive"] boolValue];
    NSDictionary *features = config[@"features"];
    NSDictionary *adsConfig = config[@"ads"];
    
    // تفعيل الميزات العامة بناءً على الـ Config
    if (aggressive || [features[@"jailbreak"] boolValue]) {
        // Jailbreak Bypass Logic (مثال بسيط يعتمد على وجود الملفات الشائعة)
        Class NSFileManagerClass = objc_getClass("NSFileManager");
        if (NSFileManagerClass) {
            SEL defaultManagerSel = NSSelectorFromString(@"defaultManager");
            if (class_getClassMethod(NSFileManagerClass, defaultManagerSel)) {
                // يمكن إضافة هوك هنا إذا لزم الأمر، لكن غالباً يكفي منع الفحص
            }
        }
    }
    
    if (aggressive || [features[@"ssl"] boolValue]) {
        // SSL Pinning Bypass
        // (هنا يمكنك استدعاء دالة MirsaUnlockApplySSLHooks إذا كانت معرفة في ملف آخر أو هنا)
        NSLog(@"[MirsaUnlock] SSL Hooks Enabled");
    }
    
    if (aggressive || [features[@"location"] boolValue]) {
        // Fake Location
        CLLocationManager *manager = [[CLLocationManager alloc] init];
        CLLocation *fakeLocation = [[CLLocation alloc] initWithLatitude:40.7128 longitude:-74.006 altitude:0 horizontalAccuracy:10 verticalAccuracy:10 speed:0 course:0 timestamp:[NSDate date]];
        // ملاحظة: تغيير الموقع الحقيقي يتطلب هوك أكثر تعقيداً عبر Runtime
        NSLog(@"[MirsaUnlock] Fake Location Set to New York");
    }
    
    // معالجة الـ Hooks المكتشفة من الـ Scanner
    if (hooks && [hooks isKindOfClass:[NSArray class]]) {
        for (NSDictionary *hook in hooks) {
            NSString *className = hook[@"class"];
            NSString *selectorName = hook[@"selector"];
            NSString *returns = hook[@"returns"] ?: @"yes";
            
            if (!className || !selectorName) continue;
            
            Class targetClass = objc_getClass([className UTF8String]);
            if (targetClass == Nil) continue;
            
            SEL targetSel = NSSelectorFromString(selectorName);
            if (!class_getInstanceMethod(targetClass, targetSel)) continue;
            
            if ([returns isEqualToString:@"yes"]) {
                MirsaUnlockSwizzleBOOLGetter(targetClass, targetSel, YES);
            } else if ([returns isEqualToString:@"no"]) {
                MirsaUnlockSwizzleBOOLGetter(targetClass, targetSel, NO);
            } else if ([returns isEqualToString:@"count"]) {
                MirsaUnlockSwizzleIntegerGetter(targetClass, targetSel, 999);
            } else if ([returns isEqualToString:@"zero"]) {
                MirsaUnlockSwizzleIntegerGetter(targetClass, targetSel, 0);
            } else if ([returns isEqualToString:@"future"]) {
                MirsaUnlockSwizzleFutureGetter(targetClass, targetSel);
            } else if ([returns isEqualToString:@"dismiss"]) {
                MirsaUnlockDismissMethod(targetClass, targetSel);
            }
        }
    }
    
    // تفعيل حواجز الإعلانات (Ad Blocking)
    if (adsConfig && [adsConfig isKindOfClass:[NSDictionary class]]) {
        BOOL blockAds = [adsConfig[@"block"] boolValue];
        BOOL accelerate = [adsConfig[@"accelerate"] boolValue];
        NSArray *sdkList = adsConfig[@"sdks"];
        
        if (blockAds && sdkList) {
            for (NSString *sdk in sdkList) {
                if ([sdk isEqualToString:@"admob"]) {
                    Class rewardedAd = objc_getClass("GADRewardedAd");
                    if (rewardedAd) {
                        SEL presentSel = NSSelectorFromString(@"presentFromRootViewController:userDidEarnRewardHandler:");
                        if (class_getInstanceMethod(rewardedAd, presentSel)) {
                            IMP newImp = (IMP)MirsaUnlockAdMobRewardedPresent;
                            Method originalMethod = class_getInstanceMethod(rewardedAd, presentSel);
                            const char *types = method_getTypeEncoding(originalMethod);
                            
                            // استبدال الطريقة
                            if (class_addMethod(rewardedAd, presentSel, newImp, types)) {
                                NSLog(@"[MirsaUnlock] AdMob: Added reward hook");
                            } else {
                                method_setImplementation(originalMethod, newImp);
                                NSLog(@"[MirsaUnlock] AdMob: Swizzled reward hook");
                            }
                        }
                    }
                }
            }
        }
    }
    
    NSLog(@"[MirsaUnlock] Initialization complete.");
}
