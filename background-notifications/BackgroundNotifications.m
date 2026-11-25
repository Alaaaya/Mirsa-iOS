#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreLocation/CoreLocation.h>
#import <UserNotifications/UserNotifications.h>
#import <objc/runtime.h>
#import "Policy.h"

// Clean-room, app-local public API implementation. No network or text inspection.
@interface MBController : NSObject <CLLocationManagerDelegate>
@property(nonatomic) AVAudioPlayer *player;
@property(nonatomic) CLLocationManager *location;
@property(nonatomic) NSDictionary *configuration;
@property(nonatomic) MBPolicy policy;
@property(nonatomic) BOOL prompted;
@property(nonatomic) BOOL locationAttempted;
@property(nonatomic) BOOL ownsAudioSession;
@property(nonatomic) NSString *previousCategory;
@property(nonatomic) NSString *previousMode;
@property(nonatomic) AVAudioSessionCategoryOptions previousOptions;
+ (instancetype)shared;
- (void)activated;
- (void)badge:(NSInteger)badge;
- (void)stop;
@end

@implementation MBController
+ (instancetype)shared { static MBController *c; static dispatch_once_t once; dispatch_once(&once, ^{ c = [MBController new]; }); return c; }
- (instancetype)init {
    self = [super init]; if (!self) return nil;
    NSURL *url = [NSBundle.mainBundle URLForResource:@"MirsaBackgroundNotifications" withExtension:@"plist"];
    if (!url) return self;
    NSDictionary *config = [NSDictionary dictionaryWithContentsOfURL:url];
    NSArray *methods = [config[@"methods"] isKindOfClass:NSArray.class] ? config[@"methods"] : @[];
    _configuration = config;
    _policy.enabled = [config[@"schema"] isEqual:@1] && [config[@"enabled"] isEqual:@YES];
    _policy.audioSelected = [methods containsObject:@"audio"];
    _policy.locationSelected = [methods containsObject:@"significantLocation"];
    _policy.lastBadge = UIApplication.sharedApplication.applicationIconBadgeNumber;
    if (_policy.enabled) {
        NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
        [center addObserver:self selector:@selector(activated) name:UIApplicationDidBecomeActiveNotification object:nil];
        [center addObserver:self selector:@selector(interrupted:) name:AVAudioSessionInterruptionNotification object:nil];
        [center addObserver:self selector:@selector(audioReset:) name:AVAudioSessionMediaServicesWereResetNotification object:nil];
        [center addObserver:self selector:@selector(routeChanged:) name:AVAudioSessionRouteChangeNotification object:nil];
    }
    return self;
}
- (UIViewController *)presenter {
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (scene.activationState != UISceneActivationStateForegroundActive || ![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) if (window.isKeyWindow) {
            UIViewController *controller = window.rootViewController;
            while (controller.presentedViewController) controller = controller.presentedViewController;
            if (![controller isKindOfClass:UIAlertController.class]) return controller;
        }
    }
    return nil;
}
- (NSString *)consentKey {
    return [NSString stringWithFormat:@"MirsaBackgroundConsent1.%d.%d", _policy.audioSelected, _policy.locationSelected];
}
- (void)activated {
    if (!_policy.enabled) return;
    if ([NSUserDefaults.standardUserDefaults boolForKey:[self consentKey]]) {
        _policy.consent = YES;
        [self refreshNotificationPermission];
        [self startConsentedMethods];
        return;
    }
    if (_prompted) return;
    UIViewController *presenter = [self presenter]; if (!presenter) return;
    _prompted = YES;
    NSMutableString *message = [NSMutableString stringWithString:@"بتاكل بطارية، وبتوقف إذا سكّرت التطبيق من المهام.\nمو ضمان لبقاء التطبيق شغّال أو لوصول كل الرسائل."];
    if (_policy.audioSelected) [message appendString:@"\nاخترت تشغيل صوت صامت بالخلفية. ما بيستخدم الميكروفون."];
    if (_policy.locationSelected) [message appendString:@"\nاخترت تنبيهات تغيّر الموقع الكبير لإعطاء التطبيق فرص تشغيل. رح يطلب iOS إذن الموقع. ما بنخزّن ولا بنبعت الإحداثيات."];
    [message appendString:@"\nالإشعارات عامة بدون محتوى الرسائل، بس للأحداث اللي التطبيق بيشوفها وهو شغّال. فيك توقف الميزة بإعادة التوقيع وهي طافية."];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"إشعارات بالخلفية" message:message preferredStyle:UIAlertControllerStyleAlert];
    alert.view.semanticContentAttribute = UISemanticContentAttributeForceLeftToRight;
    [alert addAction:[UIAlertAction actionWithTitle:@"مو هلأ" style:UIAlertActionStyleCancel handler:^(__unused UIAlertAction *a) {}]];
    [alert addAction:[UIAlertAction actionWithTitle:@"موافق على الطرق المختارة" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) {
        self->_policy.consent = YES;
        [NSUserDefaults.standardUserDefaults setBool:YES forKey:[self consentKey]];
        [self requestNotifications];
    }]];
    [presenter presentViewController:alert animated:YES completion:nil];
}
- (void)requestNotifications {
    if (!_policy.enabled || !_policy.consent) return;
    UNUserNotificationCenter *center = UNUserNotificationCenter.currentNotificationCenter;
    [center getNotificationSettingsWithCompletionHandler:^(UNNotificationSettings *settings) {
        if (settings.authorizationStatus == UNAuthorizationStatusNotDetermined) {
            [center requestAuthorizationWithOptions:UNAuthorizationOptionAlert completionHandler:^(BOOL granted, __unused NSError *error) {
                dispatch_async(dispatch_get_main_queue(), ^{ self->_policy.notifications = granted; [self startConsentedMethods]; });
            }];
        } else {
            [self refreshNotificationPermission];
            dispatch_async(dispatch_get_main_queue(), ^{ [self startConsentedMethods]; });
        }
    }];
}
- (void)refreshNotificationPermission {
    [UNUserNotificationCenter.currentNotificationCenter getNotificationSettingsWithCompletionHandler:^(UNNotificationSettings *settings) {
        BOOL allowed = settings.authorizationStatus == UNAuthorizationStatusAuthorized || settings.authorizationStatus == UNAuthorizationStatusProvisional;
        dispatch_async(dispatch_get_main_queue(), ^{ self->_policy.notifications = self->_policy.enabled && self->_policy.consent && allowed; });
    }];
}
- (NSData *)silence {
    // One second mono PCM WAV, generated in memory, no file or microphone.
    uint32_t samples = 8000, size = samples * 2, riff = size + 36, fmt = 16, rate = 8000, bytes = 16000;
    uint16_t pcm = 1, channels = 1, align = 2, bits = 16;
    NSMutableData *data = [NSMutableData data];
    [data appendBytes:"RIFF" length:4]; [data appendBytes:&riff length:4]; [data appendBytes:"WAVEfmt " length:8];
    [data appendBytes:&fmt length:4]; [data appendBytes:&pcm length:2]; [data appendBytes:&channels length:2];
    [data appendBytes:&rate length:4]; [data appendBytes:&bytes length:4]; [data appendBytes:&align length:2];
    [data appendBytes:&bits length:2]; [data appendBytes:"data" length:4]; [data appendBytes:&size length:4];
    [data increaseLengthBy:size]; return data;
}
- (void)startConsentedMethods {
    if (MBMayAudio(&_policy) && !_player) {
        AVAudioSession *session = AVAudioSession.sharedInstance;
        // Do not replace an app's recording/voice session or active native playback.
        if ([session.category isEqualToString:AVAudioSessionCategoryRecord] ||
            [session.category isEqualToString:AVAudioSessionCategoryPlayAndRecord] ||
            [session.category isEqualToString:AVAudioSessionCategoryMultiRoute]) { _policy.audioStopped = YES; }
        else {
            _previousCategory = session.category; _previousMode = session.mode; _previousOptions = session.categoryOptions;
            NSError *error = nil;
            BOOL categoryOK = [session setCategory:AVAudioSessionCategoryPlayback mode:AVAudioSessionModeDefault options:AVAudioSessionCategoryOptionMixWithOthers error:&error];
            if (categoryOK) _ownsAudioSession = YES;
            if (categoryOK && [session setActive:YES error:&error]) {
                _player = [[AVAudioPlayer alloc] initWithData:[self silence] error:&error];
                _player.numberOfLoops = -1;
                if (![_player play]) { _policy.audioStopped = YES; [self stopAudio]; }
            } else { _policy.audioStopped = YES; [self stopAudio]; }
        }
    }
    if (_policy.locationSelected && !_locationAttempted) {
        _locationAttempted = YES;
        if (![CLLocationManager significantLocationChangeMonitoringAvailable] || ![CLLocationManager locationServicesEnabled]) return;
        _location = [CLLocationManager new]; _location.delegate = self;
        CLAuthorizationStatus status = _location.authorizationStatus;
        if (status == kCLAuthorizationStatusNotDetermined) {
            // Explicit method selection and runtime disclosure precede the OS prompt.
            [_location requestAlwaysAuthorization];
        } else [self locationManagerDidChangeAuthorization:_location];
    }
}
- (void)locationManagerDidChangeAuthorization:(CLLocationManager *)manager {
    if (MBMayLocation(&_policy, [CLLocationManager significantLocationChangeMonitoringAvailable], manager.authorizationStatus == kCLAuthorizationStatusAuthorizedAlways)) {
        [manager startMonitoringSignificantLocationChanges];
    } else {
        [manager stopMonitoringSignificantLocationChanges];
        // When-In-Use is not silently upgraded. User may change it in iOS Settings.
    }
}
- (void)locationManager:(CLLocationManager *)manager didUpdateLocations:(NSArray<CLLocation *> *)locations {
    // Deliberately do not read, persist, log, transmit or notify coordinates.
    (void)manager; (void)locations;
}
- (void)locationManager:(CLLocationManager *)manager didFailWithError:(NSError *)error {
    (void)error; [manager stopMonitoringSignificantLocationChanges]; // No restart loop.
}
- (void)stopAudio {
    [_player stop]; _player = nil;
    if (_ownsAudioSession) {
        AVAudioSession *session = AVAudioSession.sharedInstance;
        // Avoid overwriting a host app's newer audio-session configuration.
        if ([session.category isEqualToString:AVAudioSessionCategoryPlayback] && session.categoryOptions == AVAudioSessionCategoryOptionMixWithOthers) {
            [session setActive:NO withOptions:AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation error:nil];
            [session setCategory:_previousCategory mode:_previousMode options:_previousOptions error:nil];
        }
        _ownsAudioSession = NO;
    }
}
- (void)interrupted:(NSNotification *)note {
    if (!NSThread.isMainThread) { dispatch_async(dispatch_get_main_queue(), ^{ [self interrupted:note]; }); return; }
    if ([note.userInfo[AVAudioSessionInterruptionTypeKey] unsignedIntegerValue] == AVAudioSessionInterruptionTypeBegan) {
        _policy.audioStopped = YES; [self stopAudio]; // Never resume behind the user's back.
    }
}
- (void)audioReset:(NSNotification *)note { if (!NSThread.isMainThread) { dispatch_async(dispatch_get_main_queue(), ^{ [self audioReset:note]; }); return; } (void)note; _policy.audioStopped = YES; [self stopAudio]; }
- (void)routeChanged:(NSNotification *)note {
    if (!NSThread.isMainThread) { dispatch_async(dispatch_get_main_queue(), ^{ [self routeChanged:note]; }); return; }
    if ([note.userInfo[AVAudioSessionRouteChangeReasonKey] unsignedIntegerValue] == AVAudioSessionRouteChangeReasonOldDeviceUnavailable) {
        _policy.audioStopped = YES; [self stopAudio];
    }
}
- (void)badge:(NSInteger)badge {
    NSAssert(NSThread.isMainThread, @"main thread required");
    BOOL background = UIApplication.sharedApplication.applicationState == UIApplicationStateBackground;
    if (!MBMayNotify(&_policy, background, badge, NSProcessInfo.processInfo.systemUptime)) return;
    __block UIBackgroundTaskIdentifier task = UIBackgroundTaskInvalid;
    task = [UIApplication.sharedApplication beginBackgroundTaskWithName:@"Mirsa local notification" expirationHandler:^{
        if (task != UIBackgroundTaskInvalid) {
            [UIApplication.sharedApplication endBackgroundTask:task]; task = UIBackgroundTaskInvalid;
        }
    }];
    UNMutableNotificationContent *content = [UNMutableNotificationContent new];
    content.title = @"إشعارات بالخلفية";
    content.body = @"في نشاط جديد بالتطبيق"; // Never capture native notification text or account data.
    UNNotificationRequest *request = [UNNotificationRequest requestWithIdentifier:@"MirsaBackgroundActivity" content:content trigger:nil];
    [UNUserNotificationCenter.currentNotificationCenter addNotificationRequest:request withCompletionHandler:^(__unused NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{ if (task != UIBackgroundTaskInvalid) { [UIApplication.sharedApplication endBackgroundTask:task]; task = UIBackgroundTaskInvalid; } });
    }];
}
- (void)stop { _policy.enabled = NO; [self stopAudio]; [_location stopMonitoringSignificantLocationChanges]; }
@end

__attribute__((visibility("default"))) void MirsaBackgroundStop(void) {
    dispatch_async(dispatch_get_main_queue(), ^{ [[MBController shared] stop]; });
}
__attribute__((constructor)) static void MBInstall(void) {
    @autoreleasepool {
        if ([NSBundle.mainBundle.bundlePath.pathExtension isEqualToString:@"appex"]) return;
        dispatch_async(dispatch_get_main_queue(), ^{
            MBController *controller = [MBController shared];
            if (!controller.policy.enabled) return;
            Method method = class_getInstanceMethod(UIApplication.class, @selector(setApplicationIconBadgeNumber:));
            if (method) {
                IMP original = method_getImplementation(method);
                IMP hook = imp_implementationWithBlock(^(UIApplication *app, NSInteger badge) {
                    ((void (*)(id, SEL, NSInteger))original)(app, @selector(setApplicationIconBadgeNumber:), badge);
                    dispatch_async(dispatch_get_main_queue(), ^{ [[MBController shared] badge:badge]; });
                });
                method_setImplementation(method, hook);
            }
            if ([UNUserNotificationCenter instancesRespondToSelector:NSSelectorFromString(@"setBadgeCount:withCompletionHandler:")]) {
                SEL badgeSelector = @selector(setBadgeCount:withCompletionHandler:);
                Method badgeMethod = class_getInstanceMethod(UNUserNotificationCenter.class, badgeSelector);
                if (badgeMethod) {
                    IMP originalBadge = method_getImplementation(badgeMethod);
                    IMP badgeHook = imp_implementationWithBlock(^(UNUserNotificationCenter *center, NSInteger badge, void (^completion)(NSError *)) {
                        ((void (*)(id, SEL, NSInteger, void (^)(NSError *)))originalBadge)(center, badgeSelector, badge, ^(NSError *error) {
                            if (!error) dispatch_async(dispatch_get_main_queue(), ^{ [[MBController shared] badge:badge]; });
                            if (completion) completion(error);
                        });
                    });
                    method_setImplementation(badgeMethod, badgeHook);
                }
            }
            if (UIApplication.sharedApplication.applicationState == UIApplicationStateActive) [controller activated];
        });
    }
}
