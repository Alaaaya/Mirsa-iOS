// Scoped PosterBoard access adapter derived from Gester's BQCore.m.
// Copyright (c) 2026 KAMUI contributors. MIT, see LICENSES/Gester-MIT.txt.
// Modified for Mirsa: allowlisted data roots/UUID children only; no Library-parent rename.
// Signed-own-group Caches swaps and own-Caches probes are temporary and restored.
#import <Foundation/Foundation.h>
#import <TargetConditionals.h>
#include <dlfcn.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <dirent.h>
#include <unistd.h>
#include <sys/stat.h>
#include <errno.h>

typedef void *(*Create)(void);
typedef void (*SetNumber)(void *, uint64_t);
typedef void (*SetObject)(void *, void *);
typedef void (*SetString)(void *, const char *);
typedef void *(*GetOne)(void *);
typedef char *(*CopyToken)(void *);
typedef void (*FreeQuery)(void *);
typedef int64_t (*Consume)(const char *);
typedef int64_t (*Release)(int64_t);
typedef void *(*XString)(const char *);
typedef void (*XRelease)(void *);

static void *symbol(void *h, const char *name, const char *fallback) {
    void *p = dlsym(h, name);
    return p ?: (fallback ? dlsym(h, fallback) : NULL);
}
static BOOL allowed(NSString *path) {
    if (!path || ![path isEqualToString:path.stringByStandardizingPath]) return NO;
    for (NSString *root in @[@"/var/mobile/Containers/Data/Application",
                             @"/var/mobile/Containers/Data/InternalDaemon",
                             @"/var/mobile/Containers/Data/PluginKitPlugin"]) {
        if ([path isEqualToString:root]) return YES;
        if ([path.stringByDeletingLastPathComponent isEqualToString:root] &&
            [[NSUUID alloc] initWithUUIDString:path.lastPathComponent]) return YES;
    }
    return NO;
}

@interface MirsaPBSession : NSObject
@property(nonatomic) int64_t nativeHandle;
@property(nonatomic, copy) NSString *target;
@property(nonatomic, copy) NSString *effectivePath;
@property(nonatomic, copy) NSString *groupRoot;
@property(nonatomic, copy) NSString *backup;
@property(nonatomic) BOOL hadCaches;
@end
@implementation MirsaPBSession
@end

static NSMutableSet<NSString *> *busyGroups(void) {
    static NSMutableSet *groups;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ groups = [NSMutableSet set]; });
    return groups;
}
static BOOL existsNoFollow(NSString *path, struct stat *st) {
    return lstat(path.fileSystemRepresentation, st) == 0;
}
static BOOL canOpen(NSString *path) {
    DIR *dir = opendir(path.fileSystemRepresentation);
    if (!dir) return NO;
    closedir(dir);
    return YES;
}
static void releaseNative(int64_t handle) {
    Release release = (Release)dlsym(RTLD_DEFAULT, "sandbox_extension_release");
    if (handle >= 0 && release) release(handle);
}
static NSString *normalized(NSString *path) {
    return [path hasPrefix:@"/private/var/"] ? [path substringFromIndex:8] : path;
}

// Never recursively remove Caches or discard an old backup. A crash-recovery
// conflict preserves both paths and fails closed rather than deleting user data.
static BOOL restoreCaches(NSString *caches, NSString *backup, BOOL hadCaches,
                          NSString *target, NSMutableString *log) {
    NSFileManager *fm = NSFileManager.defaultManager;
    struct stat st;
    if (existsNoFollow(caches, &st)) {
        NSString *destination = S_ISLNK(st.st_mode) ? [fm destinationOfSymbolicLinkAtPath:caches error:nil] : nil;
        if (![destination isEqualToString:target]) {
            [log appendString:@"class7 restore blocked: Caches changed; backup retained.\n"];
            return NO;
        }
        if (unlink(caches.fileSystemRepresentation) != 0) {
            [log appendFormat:@"class7 unlink failed errno=%d; backup retained.\n", errno];
            return NO;
        }
    }
    if (hadCaches && ![fm moveItemAtPath:backup toPath:caches error:nil]) {
        [log appendString:@"class7 restore failed; original Caches backup retained.\n"];
        return NO;
    }
    return YES;
}

static NSArray<NSString *> *signedGroups(NSMutableString *log) {
    typedef CFTypeRef (*CreateTask)(CFAllocatorRef);
    typedef CFTypeRef (*CopyEntitlement)(CFTypeRef, CFStringRef, CFErrorRef *);
    void *security = dlopen("/System/Library/Frameworks/Security.framework/Security", RTLD_NOW | RTLD_LOCAL);
    CreateTask create = (CreateTask)dlsym(RTLD_DEFAULT, "SecTaskCreateFromSelf");
    CopyEntitlement copy = (CopyEntitlement)dlsym(RTLD_DEFAULT, "SecTaskCopyValueForEntitlement");
    if (!create && security) create = (CreateTask)dlsym(security, "SecTaskCreateFromSelf");
    if (!copy && security) copy = (CopyEntitlement)dlsym(security, "SecTaskCopyValueForEntitlement");
    NSMutableArray *groups = [NSMutableArray array];
    CFTypeRef task = create ? create(kCFAllocatorDefault) : NULL;
    CFTypeRef value = task && copy ? copy(task, CFSTR("com.apple.security.application-groups"), NULL) : NULL;
    CFTypeRef debug = task && copy ? copy(task, CFSTR("get-task-allow"), NULL) : NULL;
    BOOL debugAllowed = debug && CFGetTypeID(debug) == CFBooleanGetTypeID() && CFBooleanGetValue((CFBooleanRef)debug);
    [log appendFormat:@"actual signed get-task-allow: %@ (no entitlement is assumed or added)\n", debugAllowed ? @"YES" : @"NO"];
    if (debug) CFRelease(debug);
    if (value && CFGetTypeID(value) == CFArrayGetTypeID()) {
        for (id group in (__bridge NSArray *)value) {
            if ([group isKindOfClass:NSString.class] && [group length] > 0 &&
                [NSFileManager.defaultManager containerURLForSecurityApplicationGroupIdentifier:group]) {
                [groups addObject:group];
            }
        }
    } else if (value && CFGetTypeID(value) == CFStringGetTypeID()) {
        NSString *group = (__bridge NSString *)value;
        if (group.length && [NSFileManager.defaultManager containerURLForSecurityApplicationGroupIdentifier:group]) [groups addObject:group];
    }
    if (value) CFRelease(value);
    if (task) CFRelease(task);
    if (security) dlclose(security);
    [log appendFormat:@"signed usable app groups: %lu (no assumed group entitlement)\n", (unsigned long)groups.count];
    return groups;
}

static int64_t query(uint64_t queryClass, NSString *identifier, BOOL isGroup,
                     NSString *partDomain, NSString *label, NSMutableString *log) {
    static void *library;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        library = dlopen("/usr/lib/system/libsystem_containermanager.dylib", RTLD_NOW | RTLD_LOCAL);
    });
    if (!library) { [log appendFormat:@"strategy %@: containermanager unavailable (-102)\n", label]; return -102; }
    Create create = (Create)symbol(library, "container_query_create", NULL);
    SetNumber cls = (SetNumber)symbol(library, "container_query_set_class", NULL);
    SetObject ids = (SetObject)symbol(library, isGroup ? "container_query_set_group_identifiers" : "container_query_set_identifiers", NULL);
    SetNumber flags = (SetNumber)symbol(library, "container_query_operation_set_flags", "container_query_set_flags");
    SetNumber part = (SetNumber)symbol(library, "container_query_operation_set_part", "container_query_set_part");
    SetString domain = (SetString)symbol(library, "container_query_operation_set_part_domain", "container_query_set_part_domain");
    GetOne one = (GetOne)symbol(library, "container_query_get_single_result", NULL);
    CopyToken token = (CopyToken)symbol(library, "container_copy_sandbox_token", NULL);
    FreeQuery destroy = (FreeQuery)symbol(library, "container_query_free", NULL);
    Consume consume = (Consume)dlsym(RTLD_DEFAULT, "sandbox_extension_consume");
    XString string = (XString)dlsym(RTLD_DEFAULT, "xpc_string_create");
    XRelease release = (XRelease)dlsym(RTLD_DEFAULT, "xpc_release");
    if (!create || !cls || !ids || !flags || !part || !domain || !one ||
        !token || !destroy || !consume || !string || !release || !dlsym(RTLD_DEFAULT, "sandbox_extension_release")) { [log appendFormat:@"strategy %@: required symbol missing (-103)\n", label]; return -103; }
    void *q = create();
    if (!q) { [log appendFormat:@"strategy %@: query allocation failed (-104)\n", label]; return -104; }
    cls(q, queryClass);
    void *ident = string(identifier.UTF8String);
    if (!ident) { destroy(q); [log appendFormat:@"strategy %@: identifier allocation failed (-105)\n", label]; return -105; }
    ids(q, ident);
    release(ident);
    part(q, 3);
    // Match Gester: empty domain means no setter call.
    if (partDomain.length) domain(q, partDomain.UTF8String);
    flags(q, 0x8100000000ULL);
    void *result = one(q);
    char *sandboxToken = result ? token(result) : NULL;
    // -106 is Mirsa's missing-result/token sentinel, NOT an OS errno.
    int64_t handle = sandboxToken ? consume(sandboxToken) : -106;
    [log appendFormat:@"strategy %@: result=%@ token=%@ consume=%lld\n", label,
        result ? @"YES" : @"NO", sandboxToken ? @"YES" : @"NO", (long long)handle];
    if (sandboxToken) free(sandboxToken);
    destroy(q);
    return handle;
}

static MirsaPBSession *session(NSString *target, int64_t handle) {
    MirsaPBSession *s = [MirsaPBSession new];
    s.nativeHandle = handle;
    s.target = target;
    s.effectivePath = target;
    return s;
}
static MirsaPBSession *acquire(NSString *target, int64_t *errorCode, NSMutableString *log) {
#if TARGET_OS_SIMULATOR
    *errorCode = -100;
    return nil;
#else
    if (!allowed(target)) { *errorCode = -101; return nil; }
    NSString *dots = [@[@"..", @"..", @"..", @"..", @"..", @"..",
                        @"..", @"..", @"..", @"..", @"..", @".."] componentsJoinedByString:@"/"];
    NSString *traversal = [dots stringByAppendingString:target];
    int64_t h = query(13, @"systemgroup.com.apple.mobilegestaltcache", YES, traversal, @"class13-traversal", log);
    if (h >= 0) {
        if (canOpen(target)) return session(target, h);
        [log appendString:@"class13 token did not open the actual target.\n"];
        releaseNative(h);
    }
    NSFileManager *fm = NSFileManager.defaultManager;
    for (NSString *group in signedGroups(log)) {
        NSString *root = [fm containerURLForSecurityApplicationGroupIdentifier:group].path;
        if (!root.length || ![normalized(root.stringByResolvingSymlinksInPath) isEqualToString:normalized(root)]) continue;
        NSMutableSet *busy = busyGroups();
        @synchronized(busy) {
            if ([busy containsObject:root]) continue;
            [busy addObject:root];
        }
        NSString *lib = [root stringByAppendingPathComponent:@"Library"];
        NSString *caches = [lib stringByAppendingPathComponent:@"Caches"];
        NSString *backup = [lib stringByAppendingPathComponent:@"Caches.mirsa-pb-backup"];
        BOOL ownsSwap = NO, hadCaches = NO;
        struct stat st;
        if (![fm createDirectoryAtPath:lib withIntermediateDirectories:YES attributes:nil error:nil] ||
            ![normalized(lib.stringByResolvingSymlinksInPath) isEqualToString:normalized(lib)]) goto groupDone;
        // Recover only Mirsa's exact previous symlink and fixed backup. If the
        // app died mid-operation, never delete a replacement real directory.
        if (existsNoFollow(backup, &st)) {
            if (!S_ISDIR(st.st_mode) || S_ISLNK(st.st_mode)) {
                [log appendString:@"class7 recovery rejected redirected backup; nothing removed.\n"];
                goto groupDone;
            }
            NSString *oldTarget = [fm destinationOfSymbolicLinkAtPath:caches error:nil];
            if (oldTarget && !allowed(oldTarget)) goto groupDone;
            if (!restoreCaches(caches, backup, YES, oldTarget, log)) goto groupDone;
        }
        hadCaches = existsNoFollow(caches, &st);
        if (hadCaches && (!S_ISDIR(st.st_mode) || ![fm moveItemAtPath:caches toPath:backup error:nil])) goto groupDone;
        if (symlink(target.fileSystemRepresentation, caches.fileSystemRepresentation) != 0) {
            if (hadCaches) [fm moveItemAtPath:backup toPath:caches error:nil];
            [log appendFormat:@"class7 symlink denied errno=%d\n", errno];
            goto groupDone;
        }
        ownsSwap = YES;
        h = query(7, group, YES, @"", @"class7-symlink", log);
        if (h >= 0 && canOpen(caches) &&
            [normalized(caches.stringByResolvingSymlinksInPath) isEqualToString:target]) {
            MirsaPBSession *s = session(target, h);
            s.effectivePath = caches;
            s.groupRoot = root; s.backup = backup; s.hadCaches = hadCaches;
            return s; // Alias and original Caches backup live until release.
        }
        releaseNative(h);
    groupDone:
        if (ownsSwap && !restoreCaches(caches, backup, hadCaches, target, log)) {
            *errorCode = -108;
            @synchronized(busy) { [busy removeObject:root]; }
            return nil;
        }
        @synchronized(busy) { [busy removeObject:root]; }
    }
    // The class-2 probes create unique tiny trees only inside this app's Caches.
    // They never rename Library, Caches, Documents, or any existing directory.
    NSString *bid = NSBundle.mainBundle.bundleIdentifier;
    NSString *caches = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Caches"];
    if (bid.length && [fm createDirectoryAtPath:caches withIntermediateDirectories:YES attributes:nil error:nil] &&
        [normalized(caches.stringByResolvingSymlinksInPath) isEqualToString:normalized(caches)]) {
        for (NSNumber *staged in @[@YES, @NO]) {
            NSString *tag = [@".mirsa-pb-" stringByAppendingString:NSUUID.UUID.UUIDString];
            NSString *stage = [caches stringByAppendingPathComponent:[tag stringByAppendingString:@"-stage"]];
            NSString *link = [caches stringByAppendingPathComponent:tag];
            NSString *lib = [stage stringByAppendingPathComponent:@"Library"];
            NSString *stageCaches = [lib stringByAppendingPathComponent:@"Caches"];
            BOOL madeStage = NO, madeLink = NO, madeStageLink = NO;
            struct stat existing;
            if (existsNoFollow(stage, &existing) || existsNoFollow(link, &existing)) continue;
            if (staged.boolValue) {
                madeStage = [fm createDirectoryAtPath:lib withIntermediateDirectories:YES attributes:nil error:nil];
                if (madeStage) madeStageLink = symlink(target.fileSystemRepresentation, stageCaches.fileSystemRepresentation) == 0;
                if (madeStageLink) madeLink = symlink(stage.fileSystemRepresentation, link.fileSystemRepresentation) == 0;
            } else { madeLink = symlink(target.fileSystemRepresentation, link.fileSystemRepresentation) == 0; }
            BOOL success = NO;
            if (madeLink) {
                NSArray *domains = staged.boolValue ? @[[@"Library/Caches/" stringByAppendingString:tag], [@"Caches/" stringByAppendingString:tag], tag] :
                    @[tag, [@"Caches/" stringByAppendingString:tag], [@"Library/Caches/" stringByAppendingString:tag]];
                for (NSString *domain in domains) {
                    h = query(2, bid, NO, domain, staged.boolValue ? @"class2-stage" : @"class2-subpath", log);
                    if (h >= 0 && canOpen(target)) { success = YES; break; }
                    releaseNative(h);
                }
            } else { [log appendFormat:@"class2 temporary symlink denied errno=%d\n", errno]; }
            if (madeLink) unlink(link.fileSystemRepresentation);
            if (madeStageLink) unlink(stageCaches.fileSystemRepresentation);
            if (madeStage) { rmdir(lib.fileSystemRepresentation); rmdir(stage.fileSystemRepresentation); }
            if (success) return session(target, h);
        }
    }
    h = query(12, @"com.apple.geod", NO, traversal, @"class12-geod-traversal", log);
    if (h >= 0 && canOpen(target)) return session(target, h);
    releaseNative(h);
    [log appendString:@"All scoped access strategies failed. Library-parent rename is disabled.\nAirlift fallback not attempted: no independent final-target read/hash access; transport staging is not destination verification.\n"];
    *errorCode = h < 0 ? h : -107;
    return nil;
#endif
}

void *mirsa_pb_access_acquire(const char *rawPath, int64_t *errorCode, char **outLog) {
    @autoreleasepool {
        NSMutableString *log = [NSMutableString string];
        *errorCode = 0;
        MirsaPBSession *s = acquire(rawPath ? [NSString stringWithUTF8String:rawPath] : nil, errorCode, log);
        if (outLog) *outLog = strdup(log.UTF8String);
        return s ? (__bridge_retained void *)s : NULL;
    }
}
char *mirsa_pb_access_copy_path(void *raw) {
    MirsaPBSession *s = (__bridge MirsaPBSession *)raw;
    return s ? strdup(s.effectivePath.UTF8String) : NULL;
}
void mirsa_pb_access_free_string(char *value) { free(value); }
// Returning cleanup diagnostics lets callers retain proof of restore failure.
char *mirsa_pb_access_release(void *raw) {
    if (!raw) return NULL;
    MirsaPBSession *s = CFBridgingRelease(raw);
    NSMutableString *log = [NSMutableString string];
    releaseNative(s.nativeHandle);
    if (s.groupRoot) {
        restoreCaches(s.effectivePath, s.backup, s.hadCaches, s.target, log);
        NSMutableSet *busy = busyGroups();
        @synchronized(busy) { [busy removeObject:s.groupRoot]; }
    }
    return strdup(log.UTF8String);
}

#if DEBUG && TARGET_OS_SIMULATOR
// Host-only fixtures exercise safe cleanup, not device access or segmentation.
int32_t mirsa_pb_test_allowed(const char *path) {
    return allowed([NSString stringWithUTF8String:path]) ? 1 : 0;
}
int32_t mirsa_pb_test_restore(const char *caches, const char *backup, int32_t hadCaches, const char *target) {
    return restoreCaches([NSString stringWithUTF8String:caches], [NSString stringWithUTF8String:backup],
                         hadCaches != 0, [NSString stringWithUTF8String:target], [NSMutableString string]) ? 1 : 0;
}
#endif
