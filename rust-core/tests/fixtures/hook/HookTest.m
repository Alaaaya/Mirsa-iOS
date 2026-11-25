// Clean-room ABI smoke test. No Substrate implementation is bundled.
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

extern void MSHookMessageEx(Class target, SEL selector, IMP replacement, IMP *original);
static void (*originalViewDidAppear)(UIViewController *, SEL, BOOL);
static BOOL pending;
static BOOL shown;

static void hookViewDidAppear(UIViewController *controller, SEL selector, BOOL animated) {
    if (originalViewDidAppear) originalViewDidAppear(controller, selector, animated);
    // Only the hooked method schedules the alert. No constructor/notification fallback.
    dispatch_async(dispatch_get_main_queue(), ^{
        if (shown || pending || !controller.viewIfLoaded.window ||
            [controller isKindOfClass:[UIAlertController class]]) return;
        pending = YES;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            pending = NO;
            if (shown || !controller.viewIfLoaded.window ||
                UIApplication.sharedApplication.applicationState != UIApplicationStateActive) return;
            UIViewController *presenter = controller;
            while (presenter.presentedViewController && !presenter.presentedViewController.isBeingDismissed)
                presenter = presenter.presentedViewController;
            if ([presenter isKindOfClass:[UIAlertController class]] || presenter.isBeingDismissed) return;
            shown = YES;
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"مرسى شغال ✅"
                message:@"اختبار MSHookMessageEx نجح" preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"تمام" style:UIAlertActionStyleDefault handler:nil]];
            [presenter presentViewController:alert animated:YES completion:nil];
        });
    });
}

__attribute__((constructor)) static void initializeHookTest(void) {
    @autoreleasepool {
        MSHookMessageEx(objc_getClass("UIViewController"), @selector(viewDidAppear:),
                        (IMP)hookViewDidAppear, (IMP *)&originalViewDidAppear);
    }
}
