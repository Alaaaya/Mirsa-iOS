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
        if (types == NULL || types[0] != 'v' ||
            method_getNumberOfArguments(method) != 3) {
            NSLog(@"[MirsaUnlock] skip -[%@ %@]: not a viewDidAppear: (encoding %s)",
                  NSStringFromClass(cls), NSStringFromSelector(sel),
                  types != NULL ? types : "?");
            return;
        }
        if (class_addMethod(cls, sel, (IMP)MirsaUnlockDismissViewDidAppear, types)) {
            NSLog(@"[MirsaUnlock] added -[%@ %@] -> auto-dismiss (was inherited)",
                  NSStringFromClass(cls), NSStringFromSelector(sel));
            return;
        }
        method_setImplementation(method, (IMP)MirsaUnlockDismissViewDidAppear);
        NSLog(@"[MirsaUnlock] swizzled -[%@ %@] -> auto-dismiss",
              NSStringFromClass(cls), NSStringFromSelector(sel));
    } @catch (NSException *exception) {
        NSLog(@"[MirsaUnlock] exception swizzling dismiss -[%@ %@]: %@ %@",
              NSStringFromClass(cls), NSStringFromSelector(sel),
              exception.name, exception.reason);
    }
}

// YES when this class is defined in the host app's own bundle (main
// executable or an embedded Frameworks/ framework). System classes
// (UIKit, Foundation, NSUserDefaults, ...) live in /System/Library or
// /usr/lib and must NEVER receive a config hook: a class-less hook such
// as boolForKey: -> YES applied to NSUserDefaults forces every
// UserDefaults flag in the process to YES, which corrupts the app and
// killed ReverseAudio 1.5.9 with _xpc_api_misuse in the remote-keyboard
// handshake (crash log 2026-11-20 11:55). The built-in feature hooks
// (jailbreak / SSL / location / ads) target their classes explicitly and
// are unaffected by this guard.
static BOOL MirsaUnlockClassIsFromAppBundle(Class cls)
{
    if (cls == Nil) {
        return NO;
    }
    const char *image = class_getImageName(cls);
    if (image == NULL) {
        return NO;
    }
    // App code lives under ".../Something.app/..." (executable and
    // embedded frameworks); system images do not contain ".app/".
    return strstr(image, ".app/") != NULL;
}

// Apply ONE config hook to one class, dispatching on its "returns"
// value ("yes" | "no" | "count" | "zero" | "future" | "noop" |
// "dismiss"). Unknown values are logged and skipped.
static void MirsaUnlockApplyHookToClass(Class cls, SEL sel, NSString *returns)
{
    if (!MirsaUnlockClassIsFromAppBundle(cls)) {
        return;
    }
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
    } else if ([returns isEqualToString:@"noop"]) {
        MirsaUnlockVoidNoopMethod(cls, sel);
    } else if ([returns isEqualToString:@"dismiss"]) {
        MirsaUnlockDismissMethod(cls, sel);
    } else {
        NSLog(@"[MirsaUnlock] unknown returns %@ for -[%@ %@], skipping",
              returns, NSStringFromClass(cls), NSStringFromSelector(sel));
    }
}

// AdMob rewarded present: replace with the acceleration IMP, but only
// when the method exists, returns void, and takes exactly 4 arguments
// (self, _cmd, viewController, reward block). Anything else is skipped.
static void MirsaUnlockRewardedPresentMethod(Class cls, SEL sel)
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
        if (method_getNumberOfArguments(method) != 4) {
            NSLog(@"[MirsaUnlock] skip -[%@ %@]: rewarded present has %d args, expected 4",
                  NSStringFromClass(cls), NSStringFromSelector(sel),
                  method_getNumberOfArguments(method));
            return;
        }
        if (class_addMethod(cls, sel, (IMP)MirsaUnlockAdMobRewardedPresent, types)) {
            NSLog(@"[MirsaUnlock] ad-accelerate: -[%@ %@] -> instant reward (was inherited)",
                  NSStringFromClass(cls), NSStringFromSelector(sel));
            return;
        }
        method_setImplementation(method, (IMP)MirsaUnlockAdMobRewardedPresent);
        NSLog(@"[MirsaUnlock] ad-accelerate: -[%@ %@] -> instant reward",
              NSStringFromClass(cls), NSStringFromSelector(sel));
    } @catch (NSException *exception) {
        NSLog(@"[MirsaUnlock] exception swizzling rewarded present -[%@ %@]: %@ %@",
              NSStringFromClass(cls), NSStringFromSelector(sel),
              exception.name, exception.reason);
    }
}

// Resolve a class by name, or Nil when it is not linked into the host app.
static Class MirsaUnlockClassNamed(NSString *name)
{
    if (name == nil) {
        return Nil;
    }
    return objc_getClass([name UTF8String]);
}

// "class" empty: apply this hook to every registered class that has
// this instance method.
static void MirsaUnlockApplyHookToAllClasses(SEL sel, NSString *returns)
{
    if (sel == NULL) {
        return;
    }
    @try {
        int count = objc_getClassList(NULL, 0);
        if (count <= 0) {
            return;
        }
        Class *classes = (Class *)malloc(sizeof(Class) * (size_t)count);
        if (classes == NULL) {
            return;
        }
        @try {
            count = objc_getClassList(classes, count);
            for (int i = 0; i < count; i++) {
                Class cls = classes[i];
                if (cls == Nil) {
                    continue;
                }
                if (class_getInstanceMethod(cls, sel) == NULL) {
                    continue;
                }
                MirsaUnlockApplyHookToClass(cls, sel, returns);
            }
        } @catch (NSException *exception) {
            NSLog(@"[MirsaUnlock] exception scanning classes: %@ %@",
                  exception.name, exception.reason);
        } @finally {
            free(classes);
        }
    } @catch (NSException *exception) {
        NSLog(@"[MirsaUnlock] exception listing classes: %@ %@",
              exception.name, exception.reason);
    }
}

// Built-in RevenueCat hook (defensive: only if the class/method exists).
// RevenueCat exposes entitlement state through RCEntitlementInfo.isActive
// (a BOOL getter). We match by class NAME containing "Entitlement" rather
// than hardcoding one class, so RCEntitlementInfo and any future/renamed
// *Entitlement* class with an isActive BOOL getter are covered, and if the
// app has no RevenueCat at all this simply finds nothing and does nothing.
// NOTE: this name is the documented RevenueCat Objective-C API
// (RCEntitlementInfo.isActive); it was NOT verified against a live
// RevenueCat binary here — the runtime existence + BOOL checks above are
// what make it safe if the name ever changes.
static void MirsaUnlockApplyRevenueCatHooks(void)
{
    SEL sel = NSSelectorFromString(@"isActive");
    if (sel == NULL) {
        return;
    }
    @try {
        int count = objc_getClassList(NULL, 0);
        if (count <= 0) {
            return;
        }
        Class *classes = (Class *)malloc(sizeof(Class) * (size_t)count);
        if (classes == NULL) {
            return;
        }
        @try {
            count = objc_getClassList(classes, count);
            for (int i = 0; i < count; i++) {
                Class cls = classes[i];
                if (cls == Nil) {
                    continue;
                }
                NSString *name = NSStringFromClass(cls);
                if (name == nil ||
                    [name rangeOfString:@"Entitlement"].location == NSNotFound) {
                    continue;
                }
                if (class_getInstanceMethod(cls, sel) == NULL) {
                    continue;
                }
                MirsaUnlockSwizzleBOOLGetter(cls, sel, YES);
            }
        } @catch (NSException *exception) {
            NSLog(@"[MirsaUnlock] exception scanning RevenueCat classes: %@ %@",
                  exception.name, exception.reason);
        } @finally {
            free(classes);
        }
    } @catch (NSException *exception) {
        NSLog(@"[MirsaUnlock] exception listing classes for RevenueCat: %@ %@",
              exception.name, exception.reason);
    }
}

// MARK: - RevenueCat network interceptor (the 3BodSyPatch idea, no Substrate)
//
// RevenueCat's SDK reports entitlements from the SERVER's subscriber
// response, so forcing the local RCEntitlementInfo.isActive getter (above)
// is only half the job: if the app reads CustomerInfo.entitlements and
// the entitlement is not in the response at all, isActive is never called.
// This hook rewrites the API responses in flight instead, the way
// 3BodSyPatch does it: NSURLSession data tasks to api.revenuecat.com get
// their JSON rewritten before the SDK's completion handler runs.
// Two shapes are rewritten:
//  * product_entitlement_mapping — cached (product id -> entitlement ids),
//    so the subscriber rewrite knows which entitlements to grant. The
//    mapping is normally fetched first (SDK configure / offerings), and
//    the SDK re-fetches subscriber info on foreground, so a subscriber
//    response that arrives before any mapping is simply left alone and
//    the next fetch gets the injection.
//  * subscriber (GET /v1/subscribers/<id>, POST /v1/receipts) — for every
//    entitlement id learned from the mapping, an active entry is injected
//    (expires 2099) plus a matching active subscription entry, so the
//    SDK reports the entitlement as active and the app unlocks.
// A fake App Store receipt is also written and returned from
// appStoreReceiptURL, so the SDK always has a receipt to send (sideloaded
// apps usually have none). The receipt content is a prop — a few bytes
// shaped like an ASN.1 header — the response rewrite is what grants the
// entitlement; the server never gets to say no.
// Only active when the config lists "RevenueCat" in "sdks" (same gate as
// the isActive hook above). Responses that are not RevenueCat JSON, or
// that fail to parse, pass through untouched.
typedef void (^MirsaUnlockRCCompletion)(NSData *data, NSURLResponse *response, NSError *error);

static NSMutableDictionary *MirsaUnlockRCProductEntitlements = nil;
static NSURL *MirsaUnlockRCFakeReceiptURL = nil;

static NSURLSessionDataTask *(*MirsaUnlockDataTaskWithRequestOrig)(id, SEL, NSURLRequest *, MirsaUnlockRCCompletion) = NULL;
static NSURLSessionDataTask *(*MirsaUnlockDataTaskWithURLOrig)(id, SEL, NSURL *, MirsaUnlockRCCompletion) = NULL;
static NSURL *(*MirsaUnlockAppStoreReceiptURLOrig)(id, SEL) = NULL;

static NSData *MirsaUnlockRCRewriteResponse(NSData *data, NSURL *url)
{
    if (data == nil || data.length == 0) {
        return data;
    }
    @try {
        id json = [NSJSONSerialization JSONObjectWithData:data
                                                  options:NSJSONReadingMutableContainers
                                                    error:nil];
        if (![json isKindOfClass:[NSDictionary class]]) {
            return data;
        }
        NSMutableDictionary *root = (NSMutableDictionary *)json;
        BOOL changed = NO;
        id mapping = root[@"product_entitlement_mapping"];
        if ([mapping isKindOfClass:[NSDictionary class]]) {
            @synchronized (MirsaUnlockRCProductEntitlements) {
                for (NSString *productId in (NSDictionary *)mapping) {
                    id entIds = ((NSDictionary *)mapping)[productId];
                    if ([productId isKindOfClass:[NSString class]] &&
                        [entIds isKindOfClass:[NSArray class]]) {
                        MirsaUnlockRCProductEntitlements[productId] = entIds;
                    }
                }
            }
            NSLog(@"[MirsaUnlock] revenuecat: learned entitlement mapping for %@",
                  url.path);
        }
        id subscriber = root[@"subscriber"];
        if ([subscriber isKindOfClass:[NSMutableDictionary class]]) {
            NSMutableDictionary *sub = (NSMutableDictionary *)subscriber;
            NSMutableDictionary *entitlements = sub[@"entitlements"];
            if (![entitlements isKindOfClass:[NSMutableDictionary class]]) {
                entitlements = [NSMutableDictionary dictionary];
                sub[@"entitlements"] = entitlements;
            }
            NSMutableDictionary *subscriptions = sub[@"subscriptions"];
            if (![subscriptions isKindOfClass:[NSMutableDictionary class]]) {
                subscriptions = [NSMutableDictionary dictionary];
                sub[@"subscriptions"] = subscriptions;
            }
            NSDictionary *mappingCopy = nil;
            @synchronized (MirsaUnlockRCProductEntitlements) {
                mappingCopy = [MirsaUnlockRCProductEntitlements copy];
            }
            int injected = 0;
            for (NSString *productId in mappingCopy) {
                NSArray *entIds = mappingCopy[productId];
                if (![entIds isKindOfClass:[NSArray class]]) {
                    continue;
                }
                for (NSString *entId in entIds) {
                    if (![entId isKindOfClass:[NSString class]]) {
                        continue;
                    }
                    if (entitlements[entId] == nil) {
                        entitlements[entId] = @{
                            @"expires_date": @"2099-01-01T00:00:00Z",
                            @"product_identifier": productId,
                            @"purchase_date": @"2024-01-01T00:00:00Z"
                        };
                        injected++;
                    }
                }
                if (subscriptions[productId] == nil) {
                    subscriptions[productId] = @{
                        @"expires_date": @"2099-01-01T00:00:00Z",
                        @"purchase_date": @"2024-01-01T00:00:00Z",
                        @"original_purchase_date": @"2024-01-01T00:00:00Z",
                        @"is_sandbox": @NO,
                        @"ownership_type": @"PURCHASED",
                        @"period_type": @"normal",
                        @"store": @"app_store",
                        @"unsubscribe_detected_at": [NSNull null],
                        @"billing_issues_detected_at": [NSNull null],
                        @"grace_period_expires_date": [NSNull null],
                        @"refunded_at": [NSNull null],
                        @"auto_resume_date": [NSNull null]
                    };
                    changed = YES;
                }
            }
            if (injected > 0) {
                changed = YES;
                NSLog(@"[MirsaUnlock] revenuecat: granted %d entitlements in subscriber response",
                      injected);
            }
        }
        if (!changed) {
            return data;
        }
        NSError *error = nil;
        NSData *out = [NSJSONSerialization dataWithJSONObject:root options:0 error:&error];
        if (out == nil) {
            return data;
        }
        return out;
    } @catch (NSException *exception) {
        NSLog(@"[MirsaUnlock] revenuecat: exception rewriting response: %@ %@",
              exception.name, exception.reason);
        return data;
    }
}

static id MirsaUnlockDataTaskWithRequest(id self, SEL _cmd, NSURLRequest *request, MirsaUnlockRCCompletion completionHandler)
{
    if (MirsaUnlockDataTaskWithRequestOrig == NULL) {
        return nil;
    }
    if (completionHandler == NULL) {
        return MirsaUnlockDataTaskWithRequestOrig(self, _cmd, request, NULL);
    }
    NSURL *url = request.URL;
    if (url == nil || ![url.host isEqualToString:@"api.revenuecat.com"]) {
        return MirsaUnlockDataTaskWithRequestOrig(self, _cmd, request, completionHandler);
    }
    MirsaUnlockRCCompletion saved = (MirsaUnlockRCCompletion)[completionHandler copy];
    MirsaUnlockRCCompletion wrapped = ^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error == nil && data != nil) {
            data = MirsaUnlockRCRewriteResponse(data, url);
        }
        saved(data, response, error);
    };
    return MirsaUnlockDataTaskWithRequestOrig(self, _cmd, request, wrapped);
}

static id MirsaUnlockDataTaskWithURL(id self, SEL _cmd, NSURL *url, MirsaUnlockRCCompletion completionHandler)
{
    if (MirsaUnlockDataTaskWithURLOrig == NULL) {
        return nil;
    }
    if (completionHandler == NULL) {
        return MirsaUnlockDataTaskWithURLOrig(self, _cmd, url, NULL);
    }
    if (url == nil || ![url.host isEqualToString:@"api.revenuecat.com"]) {
        return MirsaUnlockDataTaskWithURLOrig(self, _cmd, url, completionHandler);
    }
    MirsaUnlockRCCompletion saved = (MirsaUnlockRCCompletion)[completionHandler copy];
    MirsaUnlockRCCompletion wrapped = ^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error == nil && data != nil) {
            data = MirsaUnlockRCRewriteResponse(data, url);
        }
        saved(data, response, error);
    };
    return MirsaUnlockDataTaskWithURLOrig(self, _cmd, url, wrapped);
}

static NSURL *MirsaUnlockAppStoreReceiptURL(id self, SEL _cmd)
{
    if (MirsaUnlockRCFakeReceiptURL != nil) {
        return MirsaUnlockRCFakeReceiptURL;
    }
    if (MirsaUnlockAppStoreReceiptURLOrig != NULL) {
        return MirsaUnlockAppStoreReceiptURLOrig(self, _cmd);
    }
    return nil;
}

static void MirsaUnlockApplyRevenueCatNetworkHooks(void)
{
    @try {
        if (MirsaUnlockRCProductEntitlements == nil) {
            MirsaUnlockRCProductEntitlements = [[NSMutableDictionary alloc] init];
        }
        // Fake receipt prop: a few bytes shaped like an ASN.1 header, in
        // Caches. The SDK base64s the file and sends it; the response
        // rewrite above is what grants the entitlement.
        @try {
            NSArray *caches = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
            NSString *dir = caches.firstObject;
            if (dir != nil) {
                NSString *path = [dir stringByAppendingPathComponent:@"MirsaUnlockReceipt"];
                static const unsigned char bytes[] = { 0x30, 0x82, 0x01, 0x00, 0x02, 0x01, 0x00 };
                NSData *receipt = [NSData dataWithBytes:bytes length:sizeof(bytes)];
                if ([receipt writeToFile:path atomically:YES]) {
                    MirsaUnlockRCFakeReceiptURL = [NSURL fileURLWithPath:path];
                    NSLog(@"[MirsaUnlock] revenuecat: fake receipt written");
                }
            }
        } @catch (NSException *exception) {
            NSLog(@"[MirsaUnlock] revenuecat: exception writing fake receipt: %@ %@",
                  exception.name, exception.reason);
        }
        Class session = MirsaUnlockClassNamed(@"NSURLSession");
        if (session != Nil) {
            SEL requestSel = NSSelectorFromString(@"dataTaskWithRequest:completionHandler:");
            Method requestMethod = class_getInstanceMethod(session, requestSel);
            if (requestMethod != NULL) {
                const char *types = method_getTypeEncoding(requestMethod);
                if (types != NULL && types[0] == '@' &&
                    method_getNumberOfArguments(requestMethod) == 4) {
                    IMP orig = method_getImplementation(requestMethod);
                    if (class_addMethod(session, requestSel,
                                        (IMP)MirsaUnlockDataTaskWithRequest, types)) {
                        NSLog(@"[MirsaUnlock] revenuecat: hooked -[NSURLSession dataTaskWithRequest:completionHandler:] (was inherited)");
                    } else {
                        method_setImplementation(requestMethod, (IMP)MirsaUnlockDataTaskWithRequest);
                        NSLog(@"[MirsaUnlock] revenuecat: hooked -[NSURLSession dataTaskWithRequest:completionHandler:]");
                    }
                    MirsaUnlockDataTaskWithRequestOrig =
                        (NSURLSessionDataTask *(*)(id, SEL, NSURLRequest *, MirsaUnlockRCCompletion))orig;
                }
            }
            SEL urlSel = NSSelectorFromString(@"dataTaskWithURL:completionHandler:");
            Method urlMethod = class_getInstanceMethod(session, urlSel);
            if (urlMethod != NULL) {
                const char *types = method_getTypeEncoding(urlMethod);
                if (types != NULL && types[0] == '@' &&
                    method_getNumberOfArguments(urlMethod) == 3) {
                    IMP orig = method_getImplementation(urlMethod);
                    if (class_addMethod(session, urlSel,
                                        (IMP)MirsaUnlockDataTaskWithURL, types)) {
                        NSLog(@"[MirsaUnlock] revenuecat: hooked -[NSURLSession dataTaskWithURL:completionHandler:] (was inherited)");
                    } else {
                        method_setImplementation(urlMethod, (IMP)MirsaUnlockDataTaskWithURL);
                        NSLog(@"[MirsaUnlock] revenuecat: hooked -[NSURLSession dataTaskWithURL:completionHandler:]");
                    }
                    MirsaUnlockDataTaskWithURLOrig =
                        (NSURLSessionDataTask *(*)(id, SEL, NSURL *, MirsaUnlockRCCompletion))orig;
                }
            }
        }
        Class bundle = MirsaUnlockClassNamed(@"NSBundle");
        if (bundle != Nil) {
            SEL receiptSel = NSSelectorFromString(@"appStoreReceiptURL");
            Method receiptMethod = class_getInstanceMethod(bundle, receiptSel);
            if (receiptMethod != NULL) {
                const char *types = method_getTypeEncoding(receiptMethod);
                if (types != NULL && types[0] == '@' &&
                    method_getNumberOfArguments(receiptMethod) == 2) {
                    IMP orig = method_getImplementation(receiptMethod);
                    if (class_addMethod(bundle, receiptSel,
                                        (IMP)MirsaUnlockAppStoreReceiptURL, types)) {
                        NSLog(@"[MirsaUnlock] revenuecat: hooked -[NSBundle appStoreReceiptURL] (was inherited)");
                    } else {
                        method_setImplementation(receiptMethod, (IMP)MirsaUnlockAppStoreReceiptURL);
                        NSLog(@"[MirsaUnlock] revenuecat: hooked -[NSBundle appStoreReceiptURL]");
                    }
                    MirsaUnlockAppStoreReceiptURLOrig = (NSURL *(*)(id, SEL))orig;
                }
            }
        }
    } @catch (NSException *exception) {
        NSLog(@"[MirsaUnlock] exception applying RevenueCat network hooks: %@ %@",
              exception.name, exception.reason);
    }
}

// MARK: - Ad hooks (fallback when premium is server-side)
//
// Blocking: load/show methods become no-ops and readiness getters
// return NO, so an ad can load in the background but never appears.
// Load class methods with completion handlers are deliberately NOT
// no-op'd: an app that waits on the completion would stall.
// Acceleration (best-effort): AdMob rewarded present invokes the
// reward block immediately instead of playing the video. For every
// other SDK the reward path is delegate-based and its implementing
// class / enum values are not safely identifiable from the binary,
// so acceleration is skipped there rather than guessed.

// AdMob (Google Mobile Ads SDK — documented API).
// Block: banner load, interstitial/rewarded present + canPresent.
// Accelerate: rewarded + rewarded-interstitial present fires the
// reward block instantly (see MirsaUnlockAdMobRewardedPresent).
static void MirsaUnlockApplyAdMobHooks(BOOL accelerate)
{
    Class banner = MirsaUnlockClassNamed(@"GADBannerView");
    if (banner != Nil) {
        MirsaUnlockVoidNoopMethod(banner, NSSelectorFromString(@"loadRequest:"));
    }
    Class interstitial = MirsaUnlockClassNamed(@"GADInterstitialAd");
    if (interstitial != Nil) {
        MirsaUnlockVoidNoopMethod(interstitial, NSSelectorFromString(@"presentFromRootViewController:"));
        MirsaUnlockBOOLNoMethod(interstitial, NSSelectorFromString(@"canPresentFromRootViewController:error:"));
    }
    SEL rewardedPresent = NSSelectorFromString(@"presentFromRootViewController:userDidEarnRewardHandler:");
    SEL canPresent = NSSelectorFromString(@"canPresentFromRootViewController:error:");
    for (NSString *name in @[@"GADRewardedAd", @"GADRewardedInterstitialAd"]) {
        Class cls = MirsaUnlockClassNamed(name);
        if (cls == Nil) {
            continue;
        }
        MirsaUnlockBOOLNoMethod(cls, canPresent);
        if (accelerate) {
            MirsaUnlockRewardedPresentMethod(cls, rewardedPresent);
        } else {
            MirsaUnlockVoidNoopMethod(cls, rewardedPresent);
        }
    }
}

// Unity Ads. The load/show API is class methods, so the metaclass
// variants are used. Acceleration skipped: the reward arrives via the
// UnityAdsShowDelegate callback (unityAdsShowComplete:…:withFinishState:)
// and the finish-state enum value cannot be verified from the binary
// without the SDK headers — guessing it could report "skipped" instead
// of "completed" and the reward would not be granted.
static void MirsaUnlockApplyUnityAdsHooks(void)
{
    Class unity = MirsaUnlockClassNamed(@"UnityAds");
    if (unity == Nil) {
        return;
    }
    MirsaUnlockVoidNoopClassMethod(unity, NSSelectorFromString(@"load:placementId:loadDelegate:"));
    MirsaUnlockVoidNoopClassMethod(unity, NSSelectorFromString(@"show:placementId:showDelegate:"));
    MirsaUnlockBOOLNoClassMethod(unity, NSSelectorFromString(@"isReady:"));
}

// AppLovin (legacy AL* SDK). Best-effort: `show` + `isReadyForDisplay`
// are the documented show/readiness points; if a version renames them
// the existence guards skip them silently. Acceleration skipped: the
// reward arrives via the ALAdRewardDelegate callback, whose
// implementing class is not identifiable from the binary.
static void MirsaUnlockApplyAppLovinHooks(void)
{
    for (NSString *name in @[@"ALInterstitialAd", @"ALRewardedAd"]) {
        Class cls = MirsaUnlockClassNamed(name);
        if (cls == Nil) {
            continue;
        }
        MirsaUnlockVoidNoopMethod(cls, NSSelectorFromString(@"show"));
        MirsaUnlockBOOLNoMethod(cls, NSSelectorFromString(@"isReadyForDisplay"));
    }
}

// ironSource. Best-effort: the IS* ad-unit classes expose `show` +
// `isReady`, and the IronSource facade exposes the show class methods.
// If a version's API differs, the guards skip the missing pieces.
// Acceleration skipped: rewarded completion is delegate-based.
static void MirsaUnlockApplyIronSourceHooks(void)
{
    for (NSString *name in @[@"ISInterstitial", @"ISRewardedVideo"]) {
        Class cls = MirsaUnlockClassNamed(name);
        if (cls == Nil) {
            continue;
        }
        MirsaUnlockVoidNoopMethod(cls, NSSelectorFromString(@"show"));
        MirsaUnlockBOOLNoMethod(cls, NSSelectorFromString(@"isReady"));
    }
    Class facade = MirsaUnlockClassNamed(@"IronSource");
    if (facade != Nil) {
        MirsaUnlockVoidNoopClassMethod(facade, NSSelectorFromString(@"showInterstitialWithViewController:"));
        MirsaUnlockVoidNoopClassMethod(facade, NSSelectorFromString(@"showRewardedVideoWithViewController:"));
        MirsaUnlockBOOLNoClassMethod(facade, NSSelectorFromString(@"hasInterstitial"));
        MirsaUnlockBOOLNoClassMethod(facade, NSSelectorFromString(@"hasRewardedVideo"));
    }
}

// Meta Audience Network (documented API: FBAdView loadAd,
// FBInterstitialAd / FBRewardedVideoAd showAdFromRootViewController:
// + isAdValid). Acceleration skipped: rewarded completion is
// delegate-based (FBRewardedVideoAdDelegate).
static void MirsaUnlockApplyMetaHooks(void)
{
    Class banner = MirsaUnlockClassNamed(@"FBAdView");
    if (banner != Nil) {
        MirsaUnlockVoidNoopMethod(banner, NSSelectorFromString(@"loadAd"));
    }
    for (NSString *name in @[@"FBInterstitialAd", @"FBRewardedVideoAd"]) {
        Class cls = MirsaUnlockClassNamed(name);
        if (cls == Nil) {
            continue;
        }
        MirsaUnlockVoidNoopMethod(cls, NSSelectorFromString(@"showAdFromRootViewController:"));
        MirsaUnlockBOOLNoMethod(cls, NSSelectorFromString(@"isAdValid"));
    }
}

// MARK: - AVPlayer ad acceleration (the AdSpeed idea, without Substrate)
//
// Rewarded video ads play through AVPlayer whatever SDK serves them, so
// forcing the player to a high rate finishes the ad in seconds and the
// SDK grants the reward: the video did play to the end, just fast. This
// is SDK-agnostic — unlike the per-SDK rewarded hooks above, which can
// only accelerate AdMob (the other SDKs report the reward through a
// delegate, whose implementing class cannot be identified safely).
// Caveat, same as the original tweak: it speeds up EVERY AVPlayer in
// the host app, not just ads — in apps with a normal video player, those
// videos play fast too. Only active when "ads.accelerate" is true.
// The setRate: replacement respects pause (rate 0 stays 0); the rate
// getter reports 1.0 while actually playing fast, so ad-progress logic
// that reads the rate sees ordinary playback.
static const float MirsaUnlockAdSpeedRate = 8.0f;

static void (*MirsaUnlockAVPlayerSetRateOrig)(id, SEL, float) = NULL;
static float (*MirsaUnlockAVPlayerRateOrig)(id, SEL) = NULL;

static void MirsaUnlockAVPlayerSetRate(id self, SEL _cmd, float rate)
{
    if (MirsaUnlockAVPlayerSetRateOrig == NULL) {
        return;
    }
    float forced = (rate > 0.0f) ? MirsaUnlockAdSpeedRate : 0.0f;
    MirsaUnlockAVPlayerSetRateOrig(self, _cmd, forced);
}

static float MirsaUnlockAVPlayerRate(id self, SEL _cmd)
{
    if (MirsaUnlockAVPlayerRateOrig == NULL) {
        return 1.0f;
    }
    float real = MirsaUnlockAVPlayerRateOrig(self, _cmd);
    return (real > 0.0f) ? 1.0f : 0.0f;
}

static void MirsaUnlockApplyAVPlayerAcceleration(void)
{
    Class player = MirsaUnlockClassNamed(@"AVPlayer");
    if (player == Nil) {
        return;
    }
    @try {
        SEL setRateSel = NSSelectorFromString(@"setRate:");
        Method setRate = class_getInstanceMethod(player, setRateSel);
        if (setRate != NULL) {
            const char *types = method_getTypeEncoding(setRate);
            if (types != NULL && types[0] == 'v' &&
                method_getNumberOfArguments(setRate) == 3) {
                IMP orig = method_getImplementation(setRate);
                if (class_addMethod(player, setRateSel,
                                    (IMP)MirsaUnlockAVPlayerSetRate, types)) {
                    NSLog(@"[MirsaUnlock] ad-accelerate: -[AVPlayer setRate:] -> %.0fx (was inherited)",
                          (double)MirsaUnlockAdSpeedRate);
                } else {
                    method_setImplementation(setRate, (IMP)MirsaUnlockAVPlayerSetRate);
                    NSLog(@"[MirsaUnlock] ad-accelerate: -[AVPlayer setRate:] -> %.0fx",
                          (double)MirsaUnlockAdSpeedRate);
                }
                MirsaUnlockAVPlayerSetRateOrig =
                    (void (*)(id, SEL, float))orig;
            }
        }
        SEL rateSel = NSSelectorFromString(@"rate");
        Method rate = class_getInstanceMethod(player, rateSel);
        if (rate != NULL) {
            const char *types = method_getTypeEncoding(rate);
            if (types != NULL && types[0] == 'f' &&
                method_getNumberOfArguments(rate) == 2) {
                IMP orig = method_getImplementation(rate);
                if (class_addMethod(player, rateSel,
                                    (IMP)MirsaUnlockAVPlayerRate, types)) {
                    NSLog(@"[MirsaUnlock] ad-accelerate: -[AVPlayer rate] -> reports 1.0 while fast (was inherited)");
                } else {
                    method_setImplementation(rate, (IMP)MirsaUnlockAVPlayerRate);
                    NSLog(@"[MirsaUnlock] ad-accelerate: -[AVPlayer rate] -> reports 1.0 while fast");
                }
                MirsaUnlockAVPlayerRateOrig = (float (*)(id, SEL))orig;
            }
        }
    } @catch (NSException *exception) {
        NSLog(@"[MirsaUnlock] exception accelerating AVPlayer: %@ %@",
              exception.name, exception.reason);
    }
}

// MARK: - Built-in feature hooks (jailbreak / ssl / location)
//
// These have no per-method config entry: the scanner only detects that
// the feature exists, and the config's "features" flags activate them.
// Every one is best-effort and guarded: a missing class or method is
// skipped silently, and every replacement forwards to the original
// implementation for inputs it does not recognise.

// Jailbreak / tamper-detection bypass (best-effort, ObjC level only).
//  - NSFileManager fileExistsAtPath: returns NO for known jailbreak
//    paths (/Applications/Cydia.app, /private/var/lib/apt, …), and
//    forwards to the original implementation for every other path, so
//    normal file checks keep working.
//  - UIApplication canOpenURL: returns NO for jailbreak URL schemes
//    (cydia://, sileo://, zebra://, filza://), forwards the rest.
//  - NOT covered: fork() / getenv("DYLD_INSERT_LIBRARIES") /
//    DYLD_INSERT_LIBRARIES checks and direct stat() calls — those are
//    plain C functions and cannot be interposed without fishhook or
//    substrate, which this dylib deliberately does not use. An app that
//    checks only through those C calls will still detect the jailbreak.
static IMP MirsaUnlockOrigFileExists = NULL;
static IMP MirsaUnlockOrigCanOpenURL = NULL;

static BOOL MirsaUnlockFileExistsGuard(id self, SEL _cmd, NSString *path)
{
    @try {
        if (path != nil) {
            for (NSString *bad in @[@"/Applications/Cydia.app",
                                    @"/Applications/Sileo.app",
                                    @"/private/var/lib/apt",
                                    @"/private/var/lib/cydia",
                                    @"/usr/libexec/cydia",
                                    @"/Library/MobileSubstrate"]) {
                if ([path rangeOfString:bad].location != NSNotFound) {
                    return NO;
                }
            }
        }
        if (MirsaUnlockOrigFileExists != NULL) {
            BOOL (*orig)(id, SEL, NSString *) =
                (BOOL (*)(id, SEL, NSString *))MirsaUnlockOrigFileExists;
            return orig(self, _cmd, path);
        }
    } @catch (NSException *exception) {
        NSLog(@"[MirsaUnlock] exception in fileExists guard: %@ %@",
              exception.name, exception.reason);
    }
    return NO;
}

static BOOL MirsaUnlockCanOpenURLGuard(id self, SEL _cmd, NSURL *url)
{
    @try {
        NSString *scheme = [[url scheme] lowercaseString];
        if ([scheme isEqualToString:@"cydia"] ||
            [scheme isEqualToString:@"sileo"] ||
            [scheme isEqualToString:@"zebra"] ||
            [scheme isEqualToString:@"filza"]) {
            return NO;
        }
        if (MirsaUnlockOrigCanOpenURL != NULL) {
            BOOL (*orig)(id, SEL, NSURL *) =
                (BOOL (*)(id, SEL, NSURL *))MirsaUnlockOrigCanOpenURL;
            return orig(self, _cmd, url);
        }
    } @catch (NSException *exception) {
        NSLog(@"[MirsaUnlock] exception in canOpenURL guard: %@ %@",
              exception.name, exception.reason);
    }
    return NO;
}

static void MirsaUnlockApplyJailbreakHooks(void)
{
    Class fm = MirsaUnlockClassNamed(@"NSFileManager");
    if (fm != Nil) {
        Method m = class_getInstanceMethod(fm, @selector(fileExistsAtPath:));
        if (m != NULL) {
            MirsaUnlockOrigFileExists = method_getImplementation(m);
            method_setImplementation(m, (IMP)MirsaUnlockFileExistsGuard);
            NSLog(@"[MirsaUnlock] jailbreak bypass: fileExistsAtPath: guarded");
        }
    }
    Class app = MirsaUnlockClassNamed(@"UIApplication");
    if (app != Nil) {
        Method m = class_getInstanceMethod(app, @selector(canOpenURL:));
        if (m != NULL) {
            MirsaUnlockOrigCanOpenURL = method_getImplementation(m);
            method_setImplementation(m, (IMP)MirsaUnlockCanOpenURLGuard);
            NSLog(@"[MirsaUnlock] jailbreak bypass: canOpenURL: guarded");
        }
    }
}

// SSL pinning bypass — DIAGNOSTIC / best-effort.
// Replaces URLSession:didReceiveChallenge:completionHandler: on every
// class that implements it itself, with an implementation that accepts
// any server certificate (credentialForTrust:). Classes that do not
// implement the delegate method are untouched; TrustKit / Alamofire
// pinning that runs outside this delegate method is NOT bypassed.
// Only active when the config's features.ssl is true.
static void MirsaUnlockAcceptAnyChallenge(id self, SEL _cmd,
                                          NSURLSession *session,
                                          NSURLAuthenticationChallenge *challenge,
                                          void (^completionHandler)(NSURLSessionAuthChallengeDisposition,
                                                                    NSURLCredential *))
{
    (void)self;
    (void)_cmd;
    (void)session;
    @try {
        if (completionHandler == NULL) {
            return;
        }
        if (challenge.protectionSpace.serverTrust != NULL) {
            NSURLCredential *cred =
                [NSURLCredential credentialForTrust:challenge.protectionSpace.serverTrust];
            completionHandler(NSURLSessionAuthChallengeUseCredential, cred);
            NSLog(@"[MirsaUnlock] ssl: accepted certificate for %@",
                  challenge.protectionSpace.host);
        } else {
            completionHandler(NSURLSessionAuthChallengePerformDefaultHandling, nil);
        }
    } @catch (NSException *exception) {
        NSLog(@"[MirsaUnlock] ssl: exception accepting challenge: %@ %@",
              exception.name, exception.reason);
        if (completionHandler != NULL) {
            completionHandler(NSURLSessionAuthChallengePerformDefaultHandling, nil);
        }
    }
}

static void MirsaUnlockApplySSLHooks(void)
{
    SEL sel = NSSelectorFromString(@"URLSession:didReceiveChallenge:completionHandler:");
    if (sel == NULL) {
        return;
    }
    @try {
        int count = objc_getClassList(NULL, 0);
        if (count <= 0) {
            return;
        }
        Class *classes = (Class *)malloc(sizeof(Class) * (size_t)count);
        if (classes == NULL) {
            return;
        }
        @try {
            count = objc_getClassList(classes, count);
            for (int i = 0; i < count; i++) {
                Class cls = classes[i];
                if (cls == Nil) {
                    continue;
                }
                // Only classes that implement the method THEMSELVES
                // (class_copyMethodList lists own methods): inherited
                // implementations are covered via their superclass.
                unsigned int mcount = 0;
                Method *methods = class_copyMethodList(cls, &mcount);
                if (methods == NULL) {
                    continue;
                }
                BOOL owns = NO;
                for (unsigned int j = 0; j < mcount; j++) {
                    if (method_getName(methods[j]) == sel) {
                        owns = YES;
                        break;
                    }
                }
                free(methods);
                if (!owns) {
                    continue;
                }
                if (MirsaUnlockReplaceInstanceMethod(cls, sel,
                                                     (IMP)MirsaUnlockAcceptAnyChallenge, 'v')) {
                    NSLog(@"[MirsaUnlock] ssl: challenge handler replaced on %@",
                          NSStringFromClass(cls));
                }
            }
        } @catch (NSException *exception) {
            NSLog(@"[MirsaUnlock] ssl: exception scanning classes: %@ %@",
                  exception.name, exception.reason);
        } @finally {
            free(classes);
        }
    } @catch (NSException *exception) {
        NSLog(@"[MirsaUnlock] exception listing classes for ssl: %@ %@",
              exception.name, exception.reason);
    }
}

// Location / region spoofing (best-effort, active ONLY when enabled).
//  - CLLocationManager -location returns a fixed fake CLLocation built
//    from the config coordinates (default New York).
//  - -startUpdatingLocation immediately reports that same fake location
//    to the delegate, so apps waiting on a callback get one at once.
// CoreLocation is deliberately NOT imported: the location object is
// built through the runtime (objc_getClass + messaging on id), so the
// dylib keeps its Foundation-only dependency list.
static double MirsaUnlockFakeLatitude = 40.7128;
static double MirsaUnlockFakeLongitude = -74.006;

static id MirsaUnlockFakeLocationObject(void)
{
    @try {
        Class locCls = objc_getClass("CLLocation");
        if (locCls == Nil) {
            return nil;
        }
        id loc = [locCls alloc];
        return [loc initWithLatitude:MirsaUnlockFakeLatitude
                           longitude:MirsaUnlockFakeLongitude];
    } @catch (NSException *exception) {
        NSLog(@"[MirsaUnlock] exception building fake location: %@ %@",
              exception.name, exception.reason);
        return nil;
    }
}

static id MirsaUnlockFakeLocationGetter(id self, SEL _cmd)
{
    (void)self;
    (void)_cmd;
    return MirsaUnlockFakeLocationObject();
}

static void MirsaUnlockStartUpdatingFake(id self, SEL _cmd)
{
    (void)_cmd;
    @try {
        id loc = MirsaUnlockFakeLocationObject();
        if (loc == nil) {
            return;
        }
        id delegate = [self delegate];
        SEL didUpdate = NSSelectorFromString(@"locationManager:didUpdateLocations:");
        if (delegate != nil && didUpdate != NULL &&
            [delegate respondsToSelector:didUpdate]) {
            void (*fn)(id, SEL, id, id) =
                (void (*)(id, SEL, id, id))[delegate methodForSelector:didUpdate];
            fn(delegate, didUpdate, self, @[loc]);
            NSLog(@"[MirsaUnlock] location: reported fake location to delegate");
        }
    } @catch (NSException *exception) {
        NSLog(@"[MirsaUnlock] exception faking location update: %@ %@",
              exception.name, exception.reason);
    }
}

static void MirsaUnlockApplyLocationHooks(double latitude, double longitude)
{
    MirsaUnlockFakeLatitude = latitude;
    MirsaUnlockFakeLongitude = longitude;
    Class lm = MirsaUnlockClassNamed(@"CLLocationManager");
    if (lm == Nil) {
        return;
    }
    if (MirsaUnlockReplaceInstanceMethod(lm, NSSelectorFromString(@"location"),
                                         (IMP)MirsaUnlockFakeLocationGetter, '@')) {
        NSLog(@"[MirsaUnlock] location: -location returns fake (%f, %f)",
              latitude, longitude);
    }
    if (MirsaUnlockReplaceInstanceMethod(lm, NSSelectorFromString(@"startUpdatingLocation"),
                                         (IMP)MirsaUnlockStartUpdatingFake, 'v')) {
        NSLog(@"[MirsaUnlock] location: startUpdatingLocation reports fake location");
    }
}

// MARK: - Live tracing
//
// Discovery mode: wrap candidate getters, call the original, record the
// return value. Zero-arg getters ONLY (see the header comment: forwarding
// extra arguments through a generic wrapper is not sound on arm64).
// One JSON line per call, written to Documents/MirsaUnlock-trace.jsonl
// in the host sandbox plus (best-effort) every App Group container the
// host app was signed with. Capped at 500 calls.

#define MirsaUnlockTraceMaxEntries 500
#define MirsaUnlockTraceMaxSlots 128

typedef struct {
    Class cls;
    SEL sel;
    IMP orig;
    char ret; // 'B' bool, 'q' integer, '@' object, 'v' void, 'd' floating
} MirsaUnlockTraceSlot;

static MirsaUnlockTraceSlot MirsaUnlockTraceSlots[MirsaUnlockTraceMaxSlots];
static int MirsaUnlockTraceSlotCount = 0;
static NSLock *MirsaUnlockTraceLock = nil;
static int MirsaUnlockTraceCount = 0;
static BOOL MirsaUnlockTraceCapped = NO;
static NSString *MirsaUnlockTraceSandboxPath = nil;
static NSArray<NSString *> *MirsaUnlockTraceGroupPaths = nil;

// App Group containers the HOST app was signed with, from its own
// entitlements via SecTask (same dlsym pattern as PosterBoardAccess.m /
// FairPlayDecryptor.swift). Empty when the app has no group — the
// sandbox copy below is then the only trace file, which is expected:
// Mirsa cannot read the host sandbox, the floating UI is the return path.
static NSArray<NSString *> *MirsaUnlockTraceGroupDirectories(void)
{
    NSMutableArray<NSString *> *out = [NSMutableArray array];
    @try {
        void *security = dlopen("/System/Library/Frameworks/Security.framework/Security",
                                RTLD_NOW | RTLD_LOCAL);
        typedef CFTypeRef (*CreateTaskFn)(CFAllocatorRef);
        typedef CFTypeRef (*CopyValueFn)(CFTypeRef, CFStringRef, CFErrorRef *);
        CreateTaskFn create = (CreateTaskFn)dlsym(RTLD_DEFAULT, "SecTaskCreateFromSelf");
        CopyValueFn copy = (CopyValueFn)dlsym(RTLD_DEFAULT, "SecTaskCopyValueForEntitlement");
        if (create == NULL && security != NULL) {
            create = (CreateTaskFn)dlsym(security, "SecTaskCreateFromSelf");
        }
        if (copy == NULL && security != NULL) {
            copy = (CopyValueFn)dlsym(security, "SecTaskCopyValueForEntitlement");
        }
        if (create != NULL && copy != NULL) {
            CFTypeRef task = create(kCFAllocatorDefault);
            if (task != NULL) {
                CFErrorRef error = NULL;
                CFTypeRef value = copy(task, CFSTR("com.apple.security.application-groups"), &error);
                NSArray *groups = nil;
                if (value != NULL) {
                    if (CFGetTypeID(value) == CFArrayGetTypeID()) {
                        groups = (__bridge NSArray *)value;
                    } else if (CFGetTypeID(value) == CFStringGetTypeID()) {
                        groups = @[(__bridge NSString *)value];
                    }
                }
                for (NSString *gid in groups ?: @[]) {
                    if (![gid isKindOfClass:[NSString class]] || ![gid hasPrefix:@"group."]) {
                        continue;
                    }
                    NSURL *url = [[NSFileManager defaultManager]
                        containerURLForSecurityApplicationGroupIdentifier:gid];
                    if (url != nil) {
                        BOOL isDir = NO;
                        if ([[NSFileManager defaultManager] fileExistsAtPath:url.path
                                                                  isDirectory:&isDir] && isDir) {
                            [out addObject:url.path];
                        }
                    }
                }
                if (value != NULL) {
                    CFRelease(value);
                }
                CFRelease(task);
            }
        }
        if (security != NULL) {
            dlclose(security);
        }
    } @catch (NSException *exception) {
        NSLog(@"[MirsaUnlock] trace groups lookup failed: %@ %@",
              exception.name, exception.reason);
    }
    return out;
}

// Append raw data to every trace-file location. No locking here — the
// caller (MirsaUnlockTraceLog / setup) holds MirsaUnlockTraceLock.
static void MirsaUnlockTraceAppendData(NSData *data)
{
    if (data == nil) {
        return;
    }
    @try {
        NSMutableArray<NSString *> *paths = [NSMutableArray array];
        if (MirsaUnlockTraceSandboxPath != nil) {
            [paths addObject:MirsaUnlockTraceSandboxPath];
        }
        if (MirsaUnlockTraceGroupPaths != nil) {
            [paths addObjectsFromArray:MirsaUnlockTraceGroupPaths];
        }
        for (NSString *path in paths) {
            @try {
                NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:path];
                if (handle != nil) {
                    [handle seekToEndOfFile];
                    [handle writeData:data];
                    [handle closeFile];
                } else {
                    [data writeToFile:path atomically:NO];
                }
            } @catch (NSException *exception) {
                NSLog(@"[MirsaUnlock] trace write failed %@: %@ %@",
                      path, exception.name, exception.reason);
            }
        }
    } @catch (NSException *exception) {
        NSLog(@"[MirsaUnlock] trace append failed: %@ %@",
              exception.name, exception.reason);
    }
}

// Serialize one dictionary as a JSON line. Caller holds the lock.
static void MirsaUnlockTraceAppendJSON(NSDictionary *dict)
{
    if (dict == nil) {
        return;
    }
    @try {
        NSError *error = nil;
        NSData *json = [NSJSONSerialization dataWithJSONObject:dict options:0 error:&error];
        if (json == nil) {
            return;
        }
        NSMutableData *line = [json mutableCopy];
        [line appendData:[@"\n" dataUsingEncoding:NSUTF8StringEncoding]];
        MirsaUnlockTraceAppendData(line);
    } @catch (NSException *exception) {
        NSLog(@"[MirsaUnlock] trace json failed: %@ %@",
              exception.name, exception.reason);
    }
}

// Resolve the trace-file locations and start a fresh session file with
// a {"event":"trace-start"} header line. Old traces are truncated so one
// tracing run never shows the previous run's calls.
static void MirsaUnlockTraceSetupPaths(void)
{
    @try {
        MirsaUnlockTraceLock = [[NSLock alloc] init];
        MirsaUnlockTraceCount = 0;
        MirsaUnlockTraceCapped = NO;
        MirsaUnlockTraceSlotCount = 0;
        NSArray *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,
                                                            NSUserDomainMask, YES);
        NSString *dir = docs.firstObject;
        if (dir != nil) {
            MirsaUnlockTraceSandboxPath =
                [dir stringByAppendingPathComponent:@"MirsaUnlock-trace.jsonl"];
        }
        NSMutableArray<NSString *> *groupPaths = [NSMutableArray array];
        for (NSString *group in MirsaUnlockTraceGroupDirectories()) {
            [groupPaths addObject:[group stringByAppendingPathComponent:@"MirsaUnlock-trace.jsonl"]];
        }
        MirsaUnlockTraceGroupPaths = [groupPaths copy];
        NSMutableArray<NSString *> *paths = [NSMutableArray array];
        if (MirsaUnlockTraceSandboxPath != nil) {
            [paths addObject:MirsaUnlockTraceSandboxPath];
        }
        [paths addObjectsFromArray:MirsaUnlockTraceGroupPaths];
        for (NSString *path in paths) {
            [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
        }
        NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier] ?: @"?";
        [MirsaUnlockTraceLock lock];
        @try {
            MirsaUnlockTraceAppendJSON(@{
                @"event": @"trace-start",
                @"app": bundleID,
                @"t": @([[NSDate date] timeIntervalSince1970] * 1000.0),
            });
        } @finally {
            [MirsaUnlockTraceLock unlock];
        }
        NSLog(@"[MirsaUnlock] tracing to %@ (groups: %lu)",
              MirsaUnlockTraceSandboxPath ?: @"?",
              (unsigned long)MirsaUnlockTraceGroupPaths.count);
    } @catch (NSException *exception) {
        NSLog(@"[MirsaUnlock] trace setup failed: %@ %@",
              exception.name, exception.reason);
    }
}

// One recorded call. Capped at MirsaUnlockTraceMaxEntries.
static void MirsaUnlockTraceLog(Class cls, SEL sel, NSString *returnsDesc, NSString *kind)
{
    @try {
        if (MirsaUnlockTraceLock == nil) {
            return;
        }
        [MirsaUnlockTraceLock lock];
        @try {
            if (MirsaUnlockTraceCount >= MirsaUnlockTraceMaxEntries) {
                if (!MirsaUnlockTraceCapped) {
                    MirsaUnlockTraceCapped = YES;
                    NSLog(@"[MirsaUnlock] trace capped at %d entries",
                          MirsaUnlockTraceMaxEntries);
                }
                return;
            }
            MirsaUnlockTraceCount += 1;
            MirsaUnlockTraceAppendJSON(@{
                @"t": @([[NSDate date] timeIntervalSince1970] * 1000.0),
                @"class": NSStringFromClass(cls) ?: @"?",
                @"selector": NSStringFromSelector(sel) ?: @"?",
                @"returns": returnsDesc ?: @"",
                @"kind": kind ?: @"",
            });
        } @finally {
            [MirsaUnlockTraceLock unlock];
        }
    } @catch (NSException *exception) {
        NSLog(@"[MirsaUnlock] trace log failed: %@ %@", exception.name, exception.reason);
    }
}

// Find the original IMP for a traced call. Exact-class match first,
// then isKindOfClass: a subclass that overrides the method has its own
// slot with its own original — the superclass original must never win
// for that subclass.
static IMP MirsaUnlockTraceOrigFor(id self, SEL sel)
{
    if (self == nil || sel == NULL) {
        return NULL;
    }
    @try {
        Class actual = object_getClass(self);
        for (int i = 0; i < MirsaUnlockTraceSlotCount; i++) {
            if (MirsaUnlockTraceSlots[i].sel == sel && MirsaUnlockTraceSlots[i].cls == actual) {
                return MirsaUnlockTraceSlots[i].orig;
            }
        }
        for (int i = 0; i < MirsaUnlockTraceSlotCount; i++) {
            if (MirsaUnlockTraceSlots[i].sel == sel && [self isKindOfClass:MirsaUnlockTraceSlots[i].cls]) {
                return MirsaUnlockTraceSlots[i].orig;
            }
        }
    } @catch (NSException *exception) {
        NSLog(@"[MirsaUnlock] trace orig lookup failed: %@ %@", exception.name, exception.reason);
    }
    return NULL;
}

static BOOL MirsaUnlockTraceBOOL(id self, SEL _cmd)
{
    BOOL result = NO;
    @try {
        IMP orig = MirsaUnlockTraceOrigFor(self, _cmd);
        if (orig != NULL) {
            BOOL (*fn)(id, SEL) = (BOOL (*)(id, SEL))orig;
            result = fn(self, _cmd);
        }
    } @catch (NSException *exception) {
        NSLog(@"[MirsaUnlock] trace BOOL call failed: %@ %@", exception.name, exception.reason);
    }
    MirsaUnlockTraceLog([self class], _cmd, result ? @"YES" : @"NO", @"bool");
    return result;
}

static NSInteger MirsaUnlockTraceInt(id self, SEL _cmd)
{
    NSInteger result = 0;
    @try {
        IMP orig = MirsaUnlockTraceOrigFor(self, _cmd);
        if (orig != NULL) {
            NSInteger (*fn)(id, SEL) = (NSInteger (*)(id, SEL))orig;
            result = fn(self, _cmd);
        }
    } @catch (NSException *exception) {
        NSLog(@"[MirsaUnlock] trace int call failed: %@ %@", exception.name, exception.reason);
    }
    MirsaUnlockTraceLog([self class], _cmd,
                        [NSString stringWithFormat:@"%ld", (long)result], @"int");
    return result;
}

static id MirsaUnlockTraceObject(id self, SEL _cmd)
{
    id result = nil;
    @try {
        IMP orig = MirsaUnlockTraceOrigFor(self, _cmd);
        if (orig != NULL) {
            id (*fn)(id, SEL) = (id (*)(id, SEL))orig;
            result = fn(self, _cmd);
        }
    } @catch (NSException *exception) {
        NSLog(@"[MirsaUnlock] trace object call failed: %@ %@", exception.name, exception.reason);
    }
    NSString *desc = @"nil";
    @try {
        if (result != nil) {
            if ([result isKindOfClass:[NSString class]]) {
                desc = [(NSString *)result length] > 120
                    ? [[(NSString *)result substringToIndex:120] stringByAppendingString:@"…"]
                    : (NSString *)result;
            } else if ([result isKindOfClass:[NSNumber class]]) {
                desc = [(NSNumber *)result stringValue];
            } else if ([result isKindOfClass:[NSDate class]]) {
                desc = [(NSDate *)result description];
            } else {
                desc = NSStringFromClass([result class]);
            }
        }
    } @catch (NSException *exception) {
        desc = NSStringFromClass([result class]) ?: @"?";
    }
    MirsaUnlockTraceLog([self class], _cmd, desc, @"object");
    return result;
}

static void MirsaUnlockTraceVoid(id self, SEL _cmd)
{
    @try {
        IMP orig = MirsaUnlockTraceOrigFor(self, _cmd);
        if (orig != NULL) {
            void (*fn)(id, SEL) = (void (*)(id, SEL))orig;
            fn(self, _cmd);
        }
    } @catch (NSException *exception) {
        NSLog(@"[MirsaUnlock] trace void call failed: %@ %@", exception.name, exception.reason);
    }
    MirsaUnlockTraceLog([self class], _cmd, @"", @"void");
}

static double MirsaUnlockTraceDouble(id self, SEL _cmd)
{
    double result = 0;
    @try {
        IMP orig = MirsaUnlockTraceOrigFor(self, _cmd);
        if (orig != NULL) {
            double (*fn)(id, SEL) = (double (*)(id, SEL))orig;
            result = fn(self, _cmd);
        }
    } @catch (NSException *exception) {
        NSLog(@"[MirsaUnlock] trace double call failed: %@ %@", exception.name, exception.reason);
    }
    MirsaUnlockTraceLog([self class], _cmd,
                        [NSString stringWithFormat:@"%g", result], @"number");
    return result;
}

// YES when this selector already has a tracing slot (any class): the
// constructor skips the unlock replacement for it while tracing is on.
static BOOL MirsaUnlockTraceHasSelector(SEL sel)
{
    if (sel == NULL) {
        return NO;
    }
    for (int i = 0; i < MirsaUnlockTraceSlotCount; i++) {
        if (MirsaUnlockTraceSlots[i].sel == sel) {
            return YES;
        }
    }
    return NO;
}

// Install a tracing wrapper on one class. Zero-arg getters only;
// anything else is skipped with a log line.
static void MirsaUnlockTraceInstall(Class cls, SEL sel)
{
    if (cls == Nil || sel == NULL) {
        return;
    }
    if (MirsaUnlockTraceSlotCount >= MirsaUnlockTraceMaxSlots) {
        NSLog(@"[MirsaUnlock] trace slot limit reached, skipping -[%@ %@]",
              NSStringFromClass(cls), NSStringFromSelector(sel));
        return;
    }
    @try {
        for (int i = 0; i < MirsaUnlockTraceSlotCount; i++) {
            if (MirsaUnlockTraceSlots[i].cls == cls && MirsaUnlockTraceSlots[i].sel == sel) {
                return; // already traced
            }
        }
        Method method = class_getInstanceMethod(cls, sel);
        if (method == NULL) {
            return;
        }
        if (method_getNumberOfArguments(method) != 2) {
            NSLog(@"[MirsaUnlock] trace skip -[%@ %@]: takes arguments, only zero-arg getters are traced",
                  NSStringFromClass(cls), NSStringFromSelector(sel));
            return;
        }
        const char *types = method_getTypeEncoding(method);
        if (types == NULL) {
            return;
        }
        IMP replacement = NULL;
        char ret = '?';
        switch (types[0]) {
            case 'B':
            case 'c':
                replacement = (IMP)MirsaUnlockTraceBOOL;
                ret = 'B';
                break;
            case 'q':
            case 'i':
            case 'l':
            case 's':
            case 'Q':
            case 'I':
            case 'L':
            case 'S':
                replacement = (IMP)MirsaUnlockTraceInt;
                ret = 'q';
                break;
            case '@':
                replacement = (IMP)MirsaUnlockTraceObject;
                ret = '@';
                break;
            case 'v':
                replacement = (IMP)MirsaUnlockTraceVoid;
                ret = 'v';
                break;
            case 'f':
            case 'd':
                replacement = (IMP)MirsaUnlockTraceDouble;
                ret = 'd';
                break;
            default:
                NSLog(@"[MirsaUnlock] trace skip -[%@ %@]: unsupported return type (encoding %s)",
                      NSStringFromClass(cls), NSStringFromSelector(sel), types);
                return;
        }
        IMP orig = method_getImplementation(method);
        if (orig == NULL) {
            return;
        }
        MirsaUnlockTraceSlots[MirsaUnlockTraceSlotCount].cls = cls;
        MirsaUnlockTraceSlots[MirsaUnlockTraceSlotCount].sel = sel;
        MirsaUnlockTraceSlots[MirsaUnlockTraceSlotCount].orig = orig;
        MirsaUnlockTraceSlots[MirsaUnlockTraceSlotCount].ret = ret;
        MirsaUnlockTraceSlotCount += 1;
        if (class_addMethod(cls, sel, replacement, types)) {
            NSLog(@"[MirsaUnlock] tracing -[%@ %@] (was inherited)",
                  NSStringFromClass(cls), NSStringFromSelector(sel));
            return;
        }
        method_setImplementation(method, replacement);
        NSLog(@"[MirsaUnlock] tracing -[%@ %@]",
              NSStringFromClass(cls), NSStringFromSelector(sel));
    } @catch (NSException *exception) {
        NSLog(@"[MirsaUnlock] exception installing trace -[%@ %@]: %@ %@",
              NSStringFromClass(cls), NSStringFromSelector(sel),
              exception.name, exception.reason);
    }
}

// "class" empty: trace this selector on every registered class that has
// it as an instance method.
static void MirsaUnlockTraceInstallOnAllClasses(SEL sel)
{
    if (sel == NULL) {
        return;
    }
    @try {
        int count = objc_getClassList(NULL, 0);
        if (count <= 0) {
            return;
        }
        Class *classes = (Class *)malloc(sizeof(Class) * (size_t)count);
        if (classes == NULL) {
            return;
        }
        @try {
            count = objc_getClassList(classes, count);
            for (int i = 0; i < count; i++) {
                if (MirsaUnlockTraceSlotCount >= MirsaUnlockTraceMaxSlots) {
                    break;
                }
                Class cls = classes[i];
                if (cls == Nil) {
                    continue;
                }
                if (!MirsaUnlockClassIsFromAppBundle(cls)) {
                    continue;
                }
                if (class_getInstanceMethod(cls, sel) == NULL) {
                    continue;
                }
                MirsaUnlockTraceInstall(cls, sel);
            }
        } @catch (NSException *exception) {
            NSLog(@"[MirsaUnlock] exception tracing classes: %@ %@",
                  exception.name, exception.reason);
        } @finally {
            free(classes);
        }
    } @catch (NSException *exception) {
        NSLog(@"[MirsaUnlock] exception listing classes for tracing: %@ %@",
              exception.name, exception.reason);
    }
}

// MARK: - Tracing floating UI (runtime-only UIKit)
//
// A small "● Trace" button over the host app; tapping it shows the
// recorded calls (summary + last calls) in an alert with a Copy button
// that puts the whole trace file on the shared pasteboard — that is
// how the trace gets back to Mirsa. No UIKit symbol is referenced at
// link time: every class comes from objc_getClass and every call goes
// through objc_msgSend, so this file keeps its Foundation-only linkage.

static NSString *MirsaUnlockTraceFileContents(void)
{
    @try {
        if (MirsaUnlockTraceSandboxPath == nil) {
            return @"";
        }
        NSData *data = [NSData dataWithContentsOfFile:MirsaUnlockTraceSandboxPath];
        if (data == nil || data.length == 0) {
            return @"";
        }
        if (data.length > 256 * 1024) {
            data = [data subdataWithRange:NSMakeRange(data.length - 256 * 1024, 256 * 1024)];
        }
        return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"";
    } @catch (NSException *exception) {
        NSLog(@"[MirsaUnlock] trace read failed: %@ %@", exception.name, exception.reason);
        return @"";
    }
}

// Human summary for the alert: call count + the last 5 calls as
// "HH:mm:ss -[Class selector] -> VALUE". The full JSON lines are what
// Copy puts on the pasteboard.
static NSString *MirsaUnlockTraceSummary(NSString *text)
{
    @try {
        NSArray<NSString *> *lines = [text componentsSeparatedByString:@"\n"];
        NSMutableArray<NSString *> *calls = [NSMutableArray array];
        for (NSString *line in lines) {
            if (line.length == 0) {
                continue;
            }
            NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];
            NSDictionary *entry = nil;
            if (data != nil) {
                entry = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            }
            if (![entry isKindOfClass:[NSDictionary class]] || entry[@"event"] != nil) {
                continue;
            }
            [calls addObject:line];
        }
        NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
        formatter.dateFormat = @"HH:mm:ss";
        NSMutableString *summary = [NSMutableString string];
        [summary appendFormat:@"%lu calls recorded\n", (unsigned long)calls.count];
        if (calls.count == 0) {
            [summary appendString:@"No premium-check call yet.\nOpen the paid feature, then come back here."];
            return summary;
        }
        NSArray<NSString *> *last = calls.count <= 5
            ? calls
            : [calls subarrayWithRange:NSMakeRange(calls.count - 5, 5)];
        for (NSString *line in last) {
            NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];
            NSDictionary *entry = nil;
            if (data != nil) {
                entry = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            }
            if (![entry isKindOfClass:[NSDictionary class]]) {
                continue;
            }
            double ms = [entry[@"t"] doubleValue];
            NSString *time = [formatter stringFromDate:[NSDate dateWithTimeIntervalSince1970:ms / 1000.0]];
            [summary appendFormat:@"\n%@ -[%@ %@] -> %@",
                time, entry[@"class"] ?: @"?", entry[@"selector"] ?: @"?",
                entry[@"returns"] ?: @""];
        }
        [summary appendString:@"\n\nCopy sends the full trace to Mirsa."];
        return summary;
    } @catch (NSException *exception) {
        NSLog(@"[MirsaUnlock] trace summary failed: %@ %@", exception.name, exception.reason);
        return @"Trace unavailable.";
    }
}

@interface MirsaUnlockTraceUI : NSObject
+ (instancetype)shared;
- (void)showButton;
- (void)buttonTapped:(id)sender;
@end

@implementation MirsaUnlockTraceUI

+ (instancetype)shared
{
    static MirsaUnlockTraceUI *instance = nil;
    static dispatch_once_t once = 0;
    dispatch_once(&once, ^{ instance = [[MirsaUnlockTraceUI alloc] init]; });
    return instance;
}

- (void)showButton
{
    @try {
        Class appCls = objc_getClass("UIApplication");
        if (appCls == Nil) {
            return;
        }
        id app = ((id (*)(id, SEL))objc_msgSend)(appCls, NSSelectorFromString(@"sharedApplication"));
        if (app == nil) {
            return;
        }
        id window = ((id (*)(id, SEL))objc_msgSend)(app, NSSelectorFromString(@"keyWindow"));
        if (window == nil) {
            id windows = ((id (*)(id, SEL))objc_msgSend)(app, NSSelectorFromString(@"windows"));
            if ([windows count] > 0) {
                window = [windows objectAtIndex:0];
            }
        }
        if (window == nil) {
            return;
        }
        CGRect bounds = ((CGRect (*)(id, SEL))objc_msgSend)(window, NSSelectorFromString(@"bounds"));
        Class buttonCls = objc_getClass("UIButton");
        if (buttonCls == Nil) {
            return;
        }
        id button = ((id (*)(id, SEL, NSInteger))objc_msgSend)(
            buttonCls, NSSelectorFromString(@"buttonWithType:"), (NSInteger)1);
        if (button == nil) {
            return;
        }
        CGRect frame = CGRectMake(bounds.size.width - 100, 76, 92, 36);
        ((void (*)(id, SEL, CGRect))objc_msgSend)(button, NSSelectorFromString(@"setFrame:"), frame);
        ((void (*)(id, SEL, id, NSInteger))objc_msgSend)(
            button, NSSelectorFromString(@"setTitle:forState:"), @"● Trace", (NSInteger)0);
        Class colorCls = objc_getClass("UIColor");
        if (colorCls != Nil) {
            id white = ((id (*)(id, SEL))objc_msgSend)(colorCls, NSSelectorFromString(@"whiteColor"));
            ((void (*)(id, SEL, id, NSInteger))objc_msgSend)(
                button, NSSelectorFromString(@"setTitleColor:forState:"), white, (NSInteger)0);
            id dark = ((id (*)(id, SEL, CGFloat, CGFloat, CGFloat, CGFloat))objc_msgSend)(
                colorCls, NSSelectorFromString(@"colorWithRed:green:blue:alpha:"),
                (CGFloat)0.1, (CGFloat)0.1, (CGFloat)0.1, (CGFloat)0.85);
            ((void (*)(id, SEL, id))objc_msgSend)(
                button, NSSelectorFromString(@"setBackgroundColor:"), dark);
        }
        id layer = ((id (*)(id, SEL))objc_msgSend)(button, NSSelectorFromString(@"layer"));
        if (layer != nil) {
            ((void (*)(id, SEL, id, id))objc_msgSend)(
                layer, NSSelectorFromString(@"setValue:forKey:"), @18, @"cornerRadius");
            ((void (*)(id, SEL, id, id))objc_msgSend)(
                layer, NSSelectorFromString(@"setValue:forKey:"), @YES, @"masksToBounds");
        }
        ((void (*)(id, SEL, id, SEL, uint64_t))objc_msgSend)(
            button, NSSelectorFromString(@"addTarget:action:forControlEvents:"),
            self, @selector(buttonTapped:), (uint64_t)(1ULL << 6));
        ((void (*)(id, SEL, id))objc_msgSend)(
            window, NSSelectorFromString(@"addSubview:"), button);
        NSLog(@"[MirsaUnlock] trace button shown");
    } @catch (NSException *exception) {
        NSLog(@"[MirsaUnlock] trace button failed: %@ %@", exception.name, exception.reason);
    }
}

- (void)buttonTapped:(id)sender
{
    (void)sender;
    @try {
        NSString *text = MirsaUnlockTraceFileContents();
        NSString *summary = MirsaUnlockTraceSummary(text);
        Class alertCls = objc_getClass("UIAlertController");
        Class actionCls = objc_getClass("UIAlertAction");
        if (alertCls == Nil || actionCls == Nil) {
            return;
        }
        id alert = ((id (*)(id, SEL, id, id, NSInteger))objc_msgSend)(
            alertCls, NSSelectorFromString(@"alertControllerWithTitle:message:preferredStyle:"),
            @"Mirsa Trace", summary, (NSInteger)1);
        if (alert == nil) {
            return;
        }
        void (^copyBlock)(id) = ^(id action) {
            (void)action;
            @try {
                NSString *full = MirsaUnlockTraceFileContents();
                if (full.length == 0) {
                    full = MirsaUnlockTraceSummary(@"");
                }
                Class pbCls = objc_getClass("UIPasteboard");
                if (pbCls != Nil) {
                    id board = ((id (*)(id, SEL))objc_msgSend)(
                        pbCls, NSSelectorFromString(@"generalPasteboard"));
                    if (board != nil) {
                        ((void (*)(id, SEL, id))objc_msgSend)(
                            board, NSSelectorFromString(@"setString:"), full);
                        NSLog(@"[MirsaUnlock] trace copied to pasteboard (%lu chars)",
                              (unsigned long)full.length);
                    }
                }
            } @catch (NSException *exception) {
                NSLog(@"[MirsaUnlock] trace copy failed: %@ %@",
                      exception.name, exception.reason);
            }
        };
        id copyAction = ((id (*)(id, SEL, id, NSInteger, void (^)(id)))objc_msgSend)(
            actionCls, NSSelectorFromString(@"actionWithTitle:style:handler:"),
            @"Copy trace", (NSInteger)0, copyBlock);
        id closeAction = ((id (*)(id, SEL, id, NSInteger, void (^)(id)))objc_msgSend)(
            actionCls, NSSelectorFromString(@"actionWithTitle:style:handler:"),
            @"Close", (NSInteger)1, nil);
        ((void (*)(id, SEL, id))objc_msgSend)(alert, NSSelectorFromString(@"addAction:"), copyAction);
        ((void (*)(id, SEL, id))objc_msgSend)(alert, NSSelectorFromString(@"addAction:"), closeAction);
        Class appCls = objc_getClass("UIApplication");
        id app = appCls == Nil ? nil : ((id (*)(id, SEL))objc_msgSend)(
            appCls, NSSelectorFromString(@"sharedApplication"));
        id window = app == nil ? nil : ((id (*)(id, SEL))objc_msgSend)(
            app, NSSelectorFromString(@"keyWindow"));
        if (window == nil && app != nil) {
            id windows = ((id (*)(id, SEL))objc_msgSend)(app, NSSelectorFromString(@"windows"));
            if ([windows count] > 0) {
                window = [windows objectAtIndex:0];
            }
        }
        if (window == nil) {
            return;
        }
        id vc = ((id (*)(id, SEL))objc_msgSend)(window, NSSelectorFromString(@"rootViewController"));
        while (vc != nil) {
            id presented = ((id (*)(id, SEL))objc_msgSend)(
                vc, NSSelectorFromString(@"presentedViewController"));
            if (presented == nil) {
                break;
            }
            vc = presented;
        }
        if (vc == nil) {
            return;
        }
        ((void (*)(id, SEL, id, BOOL, id))objc_msgSend)(
            vc, NSSelectorFromString(@"presentViewController:animated:completion:"),
            alert, YES, nil);
    } @catch (NSException *exception) {
        NSLog(@"[MirsaUnlock] trace alert failed: %@ %@", exception.name, exception.reason);
    }
}

@end

__attribute__((constructor)) static void MirsaUnlockLoad(void)
{
    @try {
        // Locate this dylib's own path, then read MirsaUnlock.json from the
        // same directory.
        Dl_info info = { 0 };
        if (dladdr((void *)MirsaUnlockLoad, &info) == 0 || info.dli_fname == NULL) {
            NSLog(@"[MirsaUnlock] dladdr failed, cannot locate config");
            return;
        }
        NSString *dylibPath = [NSString stringWithUTF8String:info.dli_fname];
        if (dylibPath == nil) {
            NSLog(@"[MirsaUnlock] dylib path is nil, cannot locate config");
            return;
        }
        NSString *configPath =
            [[dylibPath stringByDeletingLastPathComponent]
                stringByAppendingPathComponent:@"MirsaUnlock.json"];
        NSData *data = [NSData dataWithContentsOfFile:configPath];
        if (data == nil) {
            NSLog(@"[MirsaUnlock] no config at %@, doing nothing", configPath);
            return;
        }
        NSError *error = nil;
        id json = [NSJSONSerialization JSONObjectWithData:data
                                                  options:0
                                                    error:&error];
        if (json == nil || ![json isKindOfClass:[NSDictionary class]]) {
            NSLog(@"[MirsaUnlock] unparsable config at %@: %@, doing nothing",
                  configPath, error);
            return;
        }
        NSDictionary *config = (NSDictionary *)json;
        NSNumber *version = config[@"version"];
        if (version != nil && [version intValue] != 1 && [version intValue] != 2) {
            NSLog(@"[MirsaUnlock] warning: unsupported config version %@, "
                  @"continuing with hooks anyway", version);
        }
        // "aggressive": every built-in feature on + every detected hook kept.
        BOOL aggressive = [config[@"aggressive"] boolValue];

        // 0. Live tracing (discovery mode). Installs tracing wrappers for
        // the config's "trace_candidates" BEFORE any hook below, so the
        // hook loop can skip traced selectors (trace wins).
        BOOL tracing = [config[@"tracing"] boolValue];
        if (tracing) {
            MirsaUnlockTraceSetupPaths();
            NSArray *candidates = config[@"trace_candidates"];
            if ([candidates isKindOfClass:[NSArray class]]) {
                for (id entry in candidates) {
                    if (![entry isKindOfClass:[NSDictionary class]]) {
                        continue;
                    }
                    NSString *className = entry[@"class"];
                    NSString *selectorName = entry[@"selector"];
                    if (![selectorName isKindOfClass:[NSString class]] ||
                        selectorName.length == 0) {
                        continue;
                    }
                    SEL sel = NSSelectorFromString(selectorName);
                    if (sel == NULL) {
                        continue;
                    }
                    if ([className isKindOfClass:[NSString class]] &&
                        className.length > 0) {
                        Class cls = objc_getClass([className UTF8String]);
                        if (cls == Nil) {
                            continue;
                        }
                        MirsaUnlockTraceInstall(cls, sel);
                    } else {
                        MirsaUnlockTraceInstallOnAllClasses(sel);
                    }
                }
            }
            NSLog(@"[MirsaUnlock] tracing enabled (%d methods wrapped)",
                  MirsaUnlockTraceSlotCount);
            // Floating "● Trace" button, shortly after launch so the
            // app's window exists. Main queue only; no-op if no window.
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                @try {
                    [[MirsaUnlockTraceUI shared] showButton];
                } @catch (NSException *exception) {
                    NSLog(@"[MirsaUnlock] exception showing trace button: %@ %@",
                          exception.name, exception.reason);
                }
            });
        }

        // 1. Generic config hooks. "returns" selects the replacement
        // (missing = "yes", so v1 configs keep working).
        NSArray *hooks = config[@"hooks"];
        if ([hooks isKindOfClass:[NSArray class]]) {
            for (id entry in hooks) {
                if (![entry isKindOfClass:[NSDictionary class]]) {
                    continue;
                }
                NSString *className = entry[@"class"];
                NSString *selectorName = entry[@"selector"];
                if (![selectorName isKindOfClass:[NSString class]] ||
                    selectorName.length == 0) {
                    continue;
                }
                SEL sel = NSSelectorFromString(selectorName);
                if (sel == NULL) {
                    continue;
                }
                NSString *returns = entry[@"returns"];
                if (![returns isKindOfClass:[NSString class]] ||
                    returns.length == 0) {
                    returns = @"yes";
                }
                // Tracing wins: a replaced method would only record the
                // fake return, so traced selectors are not hooked here.
                if (tracing && MirsaUnlockTraceHasSelector(sel)) {
                    NSLog(@"[MirsaUnlock] tracing wins for %@, hook skipped",
                          selectorName);
                    continue;
                }
                if ([className isKindOfClass:[NSString class]] &&
                    className.length > 0) {
                    Class cls = objc_getClass([className UTF8String]);
                    if (cls == Nil) {
                        NSLog(@"[MirsaUnlock] class %@ not found, skipping "
                              @"selector %@", className, selectorName);
                        continue;
                    }
                    MirsaUnlockApplyHookToClass(cls, sel, returns);
                } else {
                    // Empty/missing "class" means: any class.
                    MirsaUnlockApplyHookToAllClasses(sel, returns);
                }
            }
        }

        // 2. Built-in SDK hooks.
        NSArray *sdks = config[@"sdks"];
        BOOL hasRevenueCat = NO;
        BOOL hasStoreKit = NO;
        if ([sdks isKindOfClass:[NSArray class]]) {
            for (id entry in sdks) {
                if (![entry isKindOfClass:[NSString class]]) {
                    continue;
                }
                if ([entry isEqualToString:@"RevenueCat"]) {
                    hasRevenueCat = YES;
                } else if ([entry isEqualToString:@"StoreKit"]) {
                    hasStoreKit = YES;
                }
            }
        }
        if (hasRevenueCat) {
            MirsaUnlockApplyRevenueCatHooks();
            MirsaUnlockApplyRevenueCatNetworkHooks();
        }
        if (hasStoreKit) {
            // StoreKit receipt validation has no single hook point: receipt
            // checks are app-side custom code (each app validates the
            // receipt / transaction state in its own way), so there is no
            // StoreKit method to hook here. The config hooks above are what
            // unlock StoreKit-based apps; nothing is invented here.
            NSLog(@"[MirsaUnlock] StoreKit listed: no single hook point for "
                  @"receipt validation, relying on config hooks");
        }

        // 3. Ad hooks (fallback). Only when the config asks for them:
        // "ads": {"block": true, "accelerate": true, "sdks": [...]}.
        // Acceleration without blocking still skips the ad itself (the
        // AdMob rewarded hook fires the reward and never presents), so
        // either flag activates the section.
        NSDictionary *ads = config[@"ads"];
        BOOL adsBlock = NO, adsAccelerate = NO;
        NSArray *adSDKs = nil;
        if ([ads isKindOfClass:[NSDictionary class]]) {
            adsBlock = [ads[@"block"] boolValue];
            adsAccelerate = [ads[@"accelerate"] boolValue];
            if ([ads[@"sdks"] isKindOfClass:[NSArray class]]) {
                adSDKs = ads[@"sdks"];
            }
        }
        if ((adsBlock || adsAccelerate) && [adSDKs isKindOfClass:[NSArray class]]) {
            for (id entry in adSDKs) {
                if (![entry isKindOfClass:[NSString class]]) {
                    continue;
                }
                if ([entry isEqualToString:@"admob"]) {
                    MirsaUnlockApplyAdMobHooks(adsAccelerate);
                } else if ([entry isEqualToString:@"unity"]) {
                    MirsaUnlockApplyUnityAdsHooks();
                } else if ([entry isEqualToString:@"applovin"]) {
                    MirsaUnlockApplyAppLovinHooks();
                } else if ([entry isEqualToString:@"ironsource"]) {
                    MirsaUnlockApplyIronSourceHooks();
                } else if ([entry isEqualToString:@"meta"]) {
                    MirsaUnlockApplyMetaHooks();
                } else {
                    NSLog(@"[MirsaUnlock] unknown ad SDK id %@, skipping", entry);
                }
            }
            NSLog(@"[MirsaUnlock] ad hooks applied (block=%@, accelerate=%@)",
                  adsBlock ? @"YES" : @"NO", adsAccelerate ? @"YES" : @"NO");
        }
        if (adsAccelerate) {
            // SDK-agnostic: every rewarded video ad plays through
            // AVPlayer, so forcing the player to a high rate finishes
            // the ad in seconds and the reward is granted.
            MirsaUnlockApplyAVPlayerAcceleration();
        }

        // 4. Built-in feature hooks, gated by config["features"].
        // With "aggressive" they are all on, even when undetected.
        NSDictionary *features = config[@"features"];
        BOOL jailbreakOn = aggressive;
        BOOL sslOn = aggressive;
        BOOL locationOn = aggressive;
        if ([features isKindOfClass:[NSDictionary class]]) {
            if ([features[@"jailbreak"] boolValue]) { jailbreakOn = YES; }
            if ([features[@"ssl"] boolValue]) { sslOn = YES; }
            if ([features[@"location"] boolValue]) { locationOn = YES; }
        }
        if (jailbreakOn) {
            MirsaUnlockApplyJailbreakHooks();
        }
        if (sslOn) {
            MirsaUnlockApplySSLHooks();
        }
        if (locationOn) {
            double lat = 40.7128, lon = -74.006; // New York (default)
            NSDictionary *loc = config[@"location"];
            if ([loc isKindOfClass:[NSDictionary class]]) {
                if ([loc[@"latitude"] isKindOfClass:[NSNumber class]]) {
                    lat = [loc[@"latitude"] doubleValue];
                }
                if ([loc[@"longitude"] isKindOfClass:[NSNumber class]]) {
                    lon = [loc[@"longitude"] doubleValue];
                }
            }
            MirsaUnlockApplyLocationHooks(lat, lon);
        }
        NSLog(@"[MirsaUnlock] loaded");
    } @catch (NSException *exception) {
        NSLog(@"[MirsaUnlock] exception in constructor: %@ %@",
              exception.name, exception.reason);
    }
}
