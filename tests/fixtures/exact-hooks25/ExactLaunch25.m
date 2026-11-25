// Own UIKit/scene host. Only the two SHA-pinned, Mirsa-authored test dylibs run here.
#import <UIKit/UIKit.h>
#import <stdio.h>
#import <stdlib.h>
static NSString *mode;
@interface ExactScene25 : UIResponder <UIWindowSceneDelegate>
@property(strong,nonatomic) UIWindow *window;
@end
@implementation ExactScene25
- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options {
    if (![scene isKindOfClass:UIWindowScene.class]) return;
    self.window = [[UIWindow alloc] initWithWindowScene:(UIWindowScene *)scene];
    UIViewController *root = [UIViewController new];
    root.view.backgroundColor = UIColor.systemBackgroundColor;
    UILabel *label = [UILabel new]; label.text = @"اختبار مرسى"; label.textAlignment = NSTextAlignmentCenter;
    label.frame = CGRectMake(20, 100, 320, 80); [root.view addSubview:label];
    self.window.rootViewController = root; [self.window makeKeyAndVisible];
}
@end
@interface ExactDelegate25 : UIResponder <UIApplicationDelegate>
@property(strong,nonatomic) NSTimer *timer;
@property(nonatomic) NSUInteger ticks;
@end
@implementation ExactDelegate25
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
    __weak ExactDelegate25 *weakSelf = self;
    self.timer = [NSTimer scheduledTimerWithTimeInterval:0.1 repeats:YES block:^(NSTimer *timer) {
        ExactDelegate25 *self = weakSelf;
        if (++self.ticks > 250) { fprintf(stderr, "EXACT_TEST_ALERT_MISSING\n"); fflush(stderr); exit(45); }
        for (UIScene *scene in application.connectedScenes) {
            if (![scene isKindOfClass:UIWindowScene.class]) continue;
            for (UIWindow *window in ((UIWindowScene *)scene).windows) {
                UIViewController *top = window.rootViewController;
                while (top.presentedViewController) top = top.presentedViewController;
                if (![top isKindOfClass:UIAlertController.class] || !top.view.window || top.isBeingPresented) continue;
                UIAlertController *alert = (UIAlertController *)top;
                BOOL hook = [mode isEqualToString:@"HOOK"];
                NSString *title = hook ? @"مرسى شغال ✅" : @"علاء";
                if (![alert.title isEqualToString:title] || ![alert.actions.firstObject.title isEqualToString:@"تمام"] ||
                    (hook && ![alert.message isEqualToString:@"اختبار MSHookMessageEx نجح"])) continue;
                [timer invalidate];
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    UIWindow *visible = alert.view.window;
                    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithBounds:visible.bounds];
                    UIImage *shot = [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
                        [visible drawViewHierarchyInRect:visible.bounds afterScreenUpdates:YES];
                    }];
                    NSString *documents = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
                    BOOL saved = [UIImagePNGRepresentation(shot) writeToFile:[documents stringByAppendingPathComponent:@"exact-alert.png"] atomically:YES];
                    if (!saved) exit(46);
                    printf("MIRSA_EXACT_HOOK25 PASS %s %s\n", mode.UTF8String, title.UTF8String); fflush(stdout); exit(0);
                });
                return;
            }
        }
    }];
    return YES;
}
- (UISceneConfiguration *)application:(UIApplication *)application configurationForConnectingSceneSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options {
    UISceneConfiguration *config = [[UISceneConfiguration alloc] initWithName:@"Exact25" sessionRole:session.role];
    config.delegateClass = ExactScene25.class; return config;
}
@end
int main(int argc, char **argv) {
    @autoreleasepool {
        mode = argc > 1 ? [NSString stringWithUTF8String:argv[1]] : @"INVALID";
        if (!([mode isEqualToString:@"ALAA"] || [mode isEqualToString:@"HOOK"])) return 44;
        return UIApplicationMain(argc, argv, nil, NSStringFromClass(ExactDelegate25.class));
    }
}
