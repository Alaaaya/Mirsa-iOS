// Mirsa-owned native host, never runs a supplied user IPA or package.
#import <UIKit/UIKit.h>
#import <dlfcn.h>
#import <stdio.h>
#import <string.h>
@interface MirsaOwnedLaunchTarget25 : NSObject
- (const char *)marker;
@end
@implementation MirsaOwnedLaunchTarget25
- (const char *)marker { return "original25"; }
@end
int main(int argc, char **argv) {
    @autoreleasepool {
        int (*marker)(void) = dlsym(RTLD_DEFAULT, "MirsaInjectionMarker25");
        if (!marker || marker() != 25) return 41;
        BOOL hook = argc > 1 && !strcmp(argv[1], "hook");
        const char *actual = [[MirsaOwnedLaunchTarget25 new] marker];
        if (strcmp(actual, hook ? "mirsa-hook-marker25" : "original25")) return 42;
        UILabel *label = [UILabel new];
        label.text = @"مرسى شغال ✅";
        if (![label.text isEqualToString:@"مرسى شغال ✅"]) return 43;
        printf("MIRSA_GENERIC_PRODUCTION_LAUNCH25 PASS %s\n", hook ? "hook" : "plain");
        return 0;
    }
}
