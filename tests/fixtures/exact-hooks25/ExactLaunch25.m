// Own UIKit/scene host. Only the two SHA-pinned, Mirsa-authored test dylibs run here.
#import <UIKit/UIKit.h>
#import <stdio.h>
#import <stdlib.h>
#import <mach-o/dyld.h>
#import <string.h>
static NSString *mode;
static const char *exactString26(NSString *value) {
    const char *text=value.UTF8String; return text ? text : "<nil>";
}
// Passive evidence only. Do not load a payload, synthesize lifecycle events or present UI.
static void exactImages26(const char *phase) {
    for (uint32_t index=0; index<_dyld_image_count(); ++index) {
        const char *path=_dyld_get_image_name(index);
        if (path && (strstr(path,"ExactLaunch25") || strstr(path,"MirsaLoader") || strstr(path,"Alaa.dylib") || strstr(path,"MirsaHookTest") || strstr(path,"CydiaSubstrate") || strstr(path,"MirsaBackground") || strstr(path,"MirsaTranslate")))
            fprintf(stderr,"EXACT_DIAGNOSTIC26 %s image %s\n",phase,path);
    }
    fflush(stderr);
}
static void exactState26(UIApplication *application,const char *phase) {
    fprintf(stderr,"EXACT_DIAGNOSTIC26 %s appState=%ld scenes=%lu\n",phase,(long)application.applicationState,(unsigned long)application.connectedScenes.count);
    for (UIScene *scene in application.connectedScenes) {
        fprintf(stderr,"EXACT_DIAGNOSTIC26 sceneState=%ld class=%s\n",(long)scene.activationState,exactString26(NSStringFromClass(scene.class)));
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            UIViewController *root=window.rootViewController;
            fprintf(stderr,"EXACT_DIAGNOSTIC26 window hidden=%d key=%d root=%s rootAttached=%d\n",window.hidden,window.isKeyWindow,exactString26(NSStringFromClass(root.class)),root.viewIfLoaded.window!=nil);
            for (UIViewController *top=root; top; top=top.presentedViewController)
                fprintf(stderr,"EXACT_DIAGNOSTIC26 controller=%s presented=%d attached=%d title=%s\n",exactString26(NSStringFromClass(top.class)),top.isBeingPresented,top.viewIfLoaded.window!=nil,exactString26(top.title));
        }
    }
    fflush(stderr);
}

@interface ExactScene25 : UIResponder <UIWindowSceneDelegate>
@property(strong,nonatomic) UIWindow *window;
@end
@implementation ExactScene25
- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options {
    fprintf(stderr,"EXACT_DIAGNOSTIC26 scene willConnect\n"); fflush(stderr);
    if (![scene isKindOfClass:UIWindowScene.class]) return;
    self.window = [[UIWindow alloc] initWithWindowScene:(UIWindowScene *)scene];
    UIViewController *root = [UIViewController new];
    root.view.backgroundColor = UIColor.systemBackgroundColor;
    UILabel *label = [UILabel new]; label.text = @"اختبار مرسى"; label.textAlignment = NSTextAlignmentCenter;
    label.frame = CGRectMake(20, 100, 320, 80); [root.view addSubview:label];
    self.window.rootViewController = root; [self.window makeKeyAndVisible];
    exactState26(UIApplication.sharedApplication,"connected");
}
- (void)sceneDidBecomeActive:(UIScene *)scene {
    exactState26(UIApplication.sharedApplication,"sceneDidBecomeActive");
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
        if (++self.ticks == 1) exactState26(application,"firstTimer");
        if (self.ticks > 250) { exactImages26("timeout"); exactState26(application,"timeout"); fprintf(stderr, "EXACT_TEST_ALERT_MISSING\n"); fflush(stderr); exit(45); }
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
                    exactImages26("success");
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
        exactImages26("main");
        for (NSNotificationName name in @[UIApplicationDidBecomeActiveNotification, UIApplicationWillEnterForegroundNotification, UISceneDidActivateNotification, UISceneWillEnterForegroundNotification]) {
            [[NSNotificationCenter defaultCenter] addObserverForName:name object:nil queue:nil usingBlock:^(NSNotification *notification) {
                fprintf(stderr,"EXACT_DIAGNOSTIC26 notification=%s\n",exactString26(notification.name)); fflush(stderr);
            }];
        }
        return UIApplicationMain(argc, argv, nil, NSStringFromClass(ExactDelegate25.class));
    }
}
