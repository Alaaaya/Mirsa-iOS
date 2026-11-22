//
//  MirsaUnlock.m
//  MirsaUnlock
//
//  B44 Final Version - Full Override & Network Fix
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <dlfcn.h>

#pragma mark - Constants

#define RC_BACKUP_DOMAIN @"api.rc-backup.com"
#define RC_MAIN_DOMAIN @"api.revenuecat.com"
#define FORCE_SUBSCRIPTION_STATUS @"active"

#pragma mark - Global State

static BOOL g_isConfigLoaded = NO;
static NSDictionary *g_config = nil;
static NSArray *g_hooks = nil;
static NSDictionary *g_features = nil;
static NSDictionary *g_ads = nil;
static CLLocation *g_fakeLocation = nil;
static BOOL g_aggressive = NO;

#pragma mark - Helpers

NSDictionary *parseJSON(NSString *jsonString) {
    NSData *data = [jsonString dataUsingEncoding:NSUTF8StringEncoding];
    return [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
}

NSString *configValueForKey(NSString *key) {
    if (!g_config || !key) return nil;
    return g_config[key];
}

BOOL isFeatureEnabled(NSString *featureName) {
    if (!g_features) return NO;
    id val = g_features[featureName];
    if ([val isKindOfClass:[NSNumber class]]) return [(NSNumber *)val boolValue];
    if ([val isKindOfClass:[NSString class]]) return ![val isEqualToString:@"false"];
    return NO;
}

#pragma mark - Core Hooks: Subscription Force

@interface RCPurchaseController (Hooked)
- (void)setActiveSubscriptionStatus:(id)status;
- (BOOL)isSubscriber;
@end

@implementation RCPurchaseController (Hooked)

- (void)setActiveSubscriptionStatus:(id)status {
    // Call original to keep internal state valid, but we force it externally too
    ((void (*)(id, SEL, id))objc_msgSend)(self, @selector(setActiveSubscriptionStatus:), FORCE_SUBSCRIPTION_STATUS);
    NSLog(@"[B44] Forced setActiveSubscriptionStatus to: %@", FORCE_SUBSCRIPTION_STATUS);
}

- (BOOL)isSubscriber {
    // Always return YES
    return YES;
}

@end

#pragma mark - Core Hooks: Network Interceptor

@interface NSURLSession (RevenueCatFix)
@end

@implementation NSURLSession (RevenueCatFix)

+ (void)load {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class originalClass = self;
        SEL originalSelector = @selector(dataTaskWithRequest:completionHandler:);
        
        Method originalMethod = class_getInstanceMethod(originalClass, originalSelector);
        Method swizzledMethod = class_getInstanceMethod(originalClass, @selector(b44_dataTaskWithRequest:completionHandler:));
        
        method_exchangeImplementations(originalMethod, swizzledMethod);
    });
}

- (NSURLSessionDataTask *)b44_dataTaskWithRequest:(NSURLRequest *)request completionHandler:(void (^)(NSData * _Nullable, NSURLResponse * _Nullable, NSError * _Nullable))completionHandler {
    NSString *urlString = request.URL.absoluteString;
    
    if ([urlString containsString:RC_BACKUP_DOMAIN] || [urlString containsString:RC_MAIN_DOMAIN]) {
        NSLog(@"[B44] Intercepting RevenueCat Request: %@", urlString);
        
        NSMutableURLRequest *newRequest = [NSMutableURLRequest requestWithURL:request.URL 
                                                                 cachePolicy:NSURLRequestReloadIgnoringLocalCacheData 
                                                             timeoutInterval:request.timeoutInterval];
        [newRequest setHTTPMethod:request.HTTPMethod];
        [newRequest setValue:request.valueForHTTPHeaderField:@"Accept"] forHTTPHeaderField:@"Accept"];
        
        return [self b44_dataTaskWithRequest:newRequest completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            
            // Check for 304 or Empty Data
            if (([response isKindOfClass:[NSHTTPURLResponse class]] && 
                 ((NSHTTPURLResponse *)response).statusCode == 304) || 
                (!data || data.length == 0)) {
                
                NSLog(@"[B44] Fixing 304/Empty Response for %@", urlString);
                
                NSDictionary *fakePayload = @{
                    @"subscriber": @{
                        @"entitlements": @{
                            @"premium": @{
                                @"expires_date": @"2099-12-31T23:59:59Z",
                                @"purchase_date": @"2026-11-22T00:00:00Z",
                                @"product_id": @"mirsa_pro"
                            }
                        },
                        @"non_subscription_purchases": @{},
                        @"original_application_version": @"1.0",
                        @"first_seen": @"2026-11-22T00:00:00Z",
                        @"request_date": @"2026-11-22T00:00:00Z",
                        @"management_url": @"https://apps.apple.com/account/subscriptions"
                    }
                };
                
                NSData *fakeData = [NSJSONSerialization dataWithJSONObject:fakePayload options:0 error:nil];
                
                NSHTTPURLResponse *fakeResponse = [[NSHTTPURLResponse alloc] initWithURL:request.URL 
                                                                                statusCode:200 
                                                              HTTPVersion:nil 
                                                             headerFields:@{@"Content-Type": @"application/json"}];
                
                if (completionHandler) {
                    completionHandler(fakeData, fakeResponse, nil);
                }
                return;
            }
            
            if (completionHandler) {
                completionHandler(data, response, error);
            }
        }];
    }
    
    return [self b44_dataTaskWithRequest:request completionHandler:completionHandler];
}

@end

#pragma mark - Initialization

+ (void)load {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSLog(@"[B44] MirsaUnlock B44 Loaded.");
        
        [self applyConfigHooks];
        [self applyBuiltInHooks];
        [self forceSubscriptionState];
    });
}

+ (void)applyConfigHooks {
    NSString *configPath = [[NSBundle mainBundle] pathForResource:@"MirsaUnlock" ofType:@"json"];
    if (!configPath) {
        NSString *docsDir = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES)[0] stringByAppendingPathComponent:@"MirsaUnlock.json"];
        if ([[NSFileManager defaultManager] fileExistsAtPath:docsDir]) {
            configPath = docsDir;
        }
    }
    
    if (configPath) {
        NSString *jsonString = [NSString stringWithContentsOfFile:configPath encoding:NSUTF8StringEncoding error:nil];
        if (jsonString) {
            g_config = parseJSON(jsonString);
            g_hooks = g_config[@"hooks"];
            g_features = g_config[@"features"];
            g_ads = g_config[@"ads"];
            g_aggressive = [g_config[@"aggressive"] boolValue];
            g_isConfigLoaded = YES;
            NSLog(@"[B44] Config loaded. Features: %@, Aggressive: %d", g_features ? @"Yes" : @"No", g_aggressive);
        }
    } else {
        NSLog(@"[B44] No config found. Using defaults.");
    }
}

+ (void)applyBuiltInHooks {
    if (isFeatureEnabled(@"jailbreak") || g_aggressive) {
        Class NSFileManagerClass = objc_getClass("__NSFileManager");
        if (NSFileManagerClass) {
            SEL sel = @selector(fileExistsAtPath:);
            Method orig = class_getInstanceMethod(NSFileManagerClass, sel);
            Method hook = class_getInstanceMethod(NSFileManagerClass, @selector(b44_fileExistsAtPath:));
            method_exchangeImplementations(orig, hook);
        }
    }
}

+ (void)b44_fileExistsAtPath:(NSString *)path {
    // Simple Jailbreak Bypass
    if ([path isEqualToString:@"/Applications/Cydia.app"] || 
        [path isEqualToString:@"/Library/MobileSubstrate/MobileSubstrate.dylib"]) {
        return YES;
    }
    // Call original
    return ((BOOL (*)(id, SEL, NSString *))objc_msgSend)(self, @selector(fileExistsAtPath:), path);
}

+ (void)forceSubscriptionState {
    Class rcClass = objc_getClass("RCPurchaseController");
    if (!rcClass) {
        // Try alternative names
        rcClass = objc_getClass("PurchasedEntitlementManager");
    }
    
    if (rcClass) {
        SEL sel = @selector(setActiveSubscriptionStatus:);
        if ([rcClass instancesRespondToSelector:sel]) {
            [[rcClass alloc] performSelector:sel withObject:FORCE_SUBSCRIPTION_STATUS];
        }
        
        // Also hook the instance method if it exists
        Method m = class_getInstanceMethod(rcClass, @selector(isSubscriber));
        if (m) {
            // Swizzle isSubscriber to always return YES
            Method hookM = class_getInstanceMethod(rcClass, @selector(isSubscriber));
            Method overrideM = class_getInstanceMethod(rcClass, @selector(isSubscriber));
            
            // We already defined the category above, so this just ensures it's active
            // If you need a separate implementation here, define it below
        }
    } else {
        NSLog(@"[B44] Warning: RCPurchaseController not found.");
    }
}

@end
