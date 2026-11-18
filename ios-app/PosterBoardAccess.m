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
#include <mach-o/loader.h>
#include <libkern/OSByteOrder.h>

// Synchronous, per-worker live checkpoints. Never wait for the UI queue.
typedef void (*PBProgress)(const char *, void *);
static _Thread_local PBProgress pbProgress;
static _Thread_local void *pbProgressContext;
void mirsa_pb_progress_set(PBProgress callback, void *context) {
    pbProgress = callback; pbProgressContext = context;
}
void mirsa_pb_progress(const char *message) {
    if (pbProgress) pbProgress(message, pbProgressContext);
}
static void checkpoint(NSString *message) { mirsa_pb_progress(message.UTF8String); }

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

// A stale swap can only point at an allowlisted root/UUID, metadata, or
// PosterBoard wallpaper-specific descendants. Never recover arbitrary links.
static BOOL allowedGrantTarget(NSString *path) {
    if (allowed(path)) return YES;
    NSArray *parts = path.pathComponents;
    if (parts.count < 8) return NO;
    NSString *container = [NSString pathWithComponents:[parts subarrayWithRange:NSMakeRange(0, 7)]];
    if (!allowed(container) || ![[NSUUID alloc] initWithUUIDString:container.lastPathComponent]) return NO;
    NSString *suffix = [path substringFromIndex:container.length + 1];
    NSArray *exact = @[@".com.apple.mobile_container_manager.metadata.plist",
        @"com.apple.mobile_container_manager.metadata.plist", @"Library", @"Library/Application Support",
        @"Library/Preferences", @"Library/Preferences/com.apple.PosterBoard.unprotectedUserDefaults.plist"];
    NSString *store = @"Library/Application Support/PRBPosterExtensionDataStore";
    return [path isEqualToString:path.stringByStandardizingPath] &&
        ([exact containsObject:suffix] || [suffix isEqualToString:store] ||
         [suffix hasPrefix:[store stringByAppendingString:@"/"]]);
}

@interface MirsaPBSession : NSObject
@property(nonatomic) int64_t nativeHandle;
@property(nonatomic, copy) NSString *target;
@property(nonatomic, copy) NSString *effectivePath;
@property(nonatomic, copy) NSString *groupRoot;
@property(nonatomic, copy) NSString *backup;
@property(nonatomic) BOOL hadCaches;
@property(nonatomic) BOOL canonicalGrant;
@property(nonatomic, strong) NSMutableArray<NSNumber *> *extraHandles;
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

// Read only our on-disk executable. This fallback reports signature requests,
// not provisioning grants; FileManager must still accept the actual own group.
static NSDictionary *embeddedEntitlements(NSMutableString *log) {
    NSData *data = [NSData dataWithContentsOfURL:NSBundle.mainBundle.executableURL
                                       options:NSDataReadingMappedIfSafe error:nil];
    if (data.length < sizeof(struct mach_header_64)) return @{};
    const uint8_t *bytes = data.bytes;
    struct mach_header_64 header;
    memcpy(&header, bytes, sizeof(header));
    if (header.magic != MH_MAGIC_64 || header.sizeofcmds > data.length - sizeof(header)) return @{};
    NSUInteger end = sizeof(header) + header.sizeofcmds, offset = sizeof(header);
    for (uint32_t i = 0; i < header.ncmds && offset <= end && end - offset >= sizeof(struct load_command); i++) {
        struct load_command command;
        memcpy(&command, bytes + offset, sizeof(command));
        if (command.cmdsize < sizeof(command) || command.cmdsize > end - offset) return @{};
        if (command.cmd == LC_CODE_SIGNATURE && command.cmdsize >= sizeof(struct linkedit_data_command)) {
            struct linkedit_data_command signature;
            memcpy(&signature, bytes + offset, sizeof(signature));
            if (signature.dataoff > data.length || signature.datasize > data.length - signature.dataoff ||
                signature.datasize < 12) return @{};
            const uint8_t *blob = bytes + signature.dataoff;
            uint32_t magic, length, count;
            memcpy(&magic, blob, 4); memcpy(&length, blob + 4, 4); memcpy(&count, blob + 8, 4);
            magic = OSSwapBigToHostInt32(magic); length = OSSwapBigToHostInt32(length); count = OSSwapBigToHostInt32(count);
            if (magic != 0xfade0cc0 || length > signature.datasize || length < 12 || count > (length - 12) / 8) return @{};
            for (uint32_t j = 0; j < count; j++) {
                uint32_t at;
                memcpy(&at, blob + 16 + j * 8, 4); at = OSSwapBigToHostInt32(at);
                if (at > length || length - at < 8) continue;
                uint32_t tag, size;
                memcpy(&tag, blob + at, 4); memcpy(&size, blob + at + 4, 4);
                tag = OSSwapBigToHostInt32(tag); size = OSSwapBigToHostInt32(size);
                if (tag != 0xfade7171 || size < 8 || size > length - at) continue;
                NSData *xml = [NSData dataWithBytes:blob + at + 8 length:size - 8];
                id plist = [NSPropertyListSerialization propertyListWithData:xml options:0 format:NULL error:nil];
                if ([plist isKindOfClass:NSDictionary.class]) {
                    [log appendString:@"Embedded LC_CODE_SIGNATURE entitlement dictionary found (not a grant).\n"];
                    return plist;
                }
            }
        }
        offset += command.cmdsize;
    }
    [log appendString:@"Embedded entitlement dictionary absent.\n"];
    return @{};
}

static NSArray<NSString *> *signedGroups(NSMutableString *log) {
    typedef CFTypeRef (*CreateTask)(CFAllocatorRef);
    typedef CFTypeRef (*CopyEntitlement)(CFTypeRef, CFStringRef, CFErrorRef *);
    void *security = dlopen("/System/Library/Frameworks/Security.framework/Security", RTLD_NOW | RTLD_LOCAL);
    CreateTask create = (CreateTask)dlsym(RTLD_DEFAULT, "SecTaskCreateFromSelf");
    CopyEntitlement copy = (CopyEntitlement)dlsym(RTLD_DEFAULT, "SecTaskCopyValueForEntitlement");
    if (!create && security) create = (CreateTask)dlsym(security, "SecTaskCreateFromSelf");
    if (!copy && security) copy = (CopyEntitlement)dlsym(security, "SecTaskCopyValueForEntitlement");
    CFTypeRef task = create ? create(kCFAllocatorDefault) : NULL;
    [log appendFormat:@"Entitlement acquisition: Security dlopen=%@ createSymbol=%@ copySymbol=%@ task=%@\n",
        security ? @"YES" : @"NO", create ? @"YES" : @"NO", copy ? @"YES" : @"NO", task ? @"YES" : @"NO"];
    CFErrorRef groupError = NULL, debugError = NULL;
    CFTypeRef value = task && copy ? copy(task, CFSTR("com.apple.security.application-groups"), &groupError) : NULL;
    CFTypeRef debug = task && copy ? copy(task, CFSTR("get-task-allow"), &debugError) : NULL;
    id process = value ? (__bridge id)value : nil;
    [log appendFormat:@"Runtime application-groups status=%@ type=%@ value=%@ error=%@\n",
        !task || !copy ? @"QUERY_UNAVAILABLE" : (value ? @"VALUE_RETURNED" : (groupError ? @"QUERY_ERROR" : @"NO_VALUE")),
        process ? NSStringFromClass([process class]) : @"<none>", process ?: @"<none>",
        groupError ? (__bridge id)groupError : @"<none>"];
    [log appendFormat:@"Runtime get-task-allow value=%@ error=%@ (not required)\n",
        debug ? (__bridge id)debug : @"<unavailable or absent>", debugError ? (__bridge id)debugError : @"<none>"];
    NSDictionary *embedded = embeddedEntitlements(log);
    id fallback = embedded[@"com.apple.security.application-groups"];
    [log appendFormat:@"Embedded application-groups status=%@ type=%@ value=%@\n",
        fallback ? @"PRESENT" : @"KEY_ABSENT", fallback ? NSStringFromClass([fallback class]) : @"<none>",
        fallback ?: @"<none>"];
    NSString *bundle = NSBundle.mainBundle.bundleIdentifier ?: @"";
    NSString *preferred = [@"group." stringByAppendingString:bundle];
    [log appendFormat:@"Runtime bundle=%@ preferred group=%@ embedded application-identifier=%@\n",
        bundle, preferred, embedded[@"application-identifier"] ?: @"<absent>"];
    // A signer can change the bundle ID and/or provision a differently named own
    // group. Do not discard a declared usable group merely for a naming mismatch.
    // No guessed, foreign/system group is ever tried: only this executable's
    // declared group.* values, still requiring the OS group-container lookup.
    NSMutableOrderedSet *declared = [NSMutableOrderedSet orderedSet];
    for (id source in @[process ?: NSNull.null, fallback ?: NSNull.null]) {
        if ([source isKindOfClass:NSArray.class]) [declared addObjectsFromArray:source];
        else if ([source isKindOfClass:NSString.class]) [declared addObject:source];
    }
    if ([declared containsObject:preferred]) {
        [declared removeObject:preferred]; [declared insertObject:preferred atIndex:0];
    }
    NSMutableArray *groups = [NSMutableArray array];
    for (id item in declared) {
        if (![item isKindOfClass:NSString.class] || ![item hasPrefix:@"group."] ||
            [item containsString:@"/"] || [item containsString:@".."]) {
            [log appendFormat:@"Group candidate rejected: invalid declared own-group identifier %@\n", item]; continue;
        }
        [log appendFormat:@"Declared group %@ naming=%@ runtimeListed=%@ embeddedListed=%@\n", item,
            [item isEqualToString:preferred] ? @"PREFERRED" : @"DIFFERENT_FROM_BUNDLE_DERIVED_NAME",
            [process isKindOfClass:NSArray.class] && [process containsObject:item] ? @"YES" : @"NO",
            [fallback isKindOfClass:NSArray.class] && [fallback containsObject:item] ? @"YES" : @"NO"];
        errno = 0;
        NSURL *url = [NSFileManager.defaultManager containerURLForSecurityApplicationGroupIdentifier:item];
        int snapshot = errno;
        [log appendFormat:@"containerURL group=%@ result=%@ errnoSnapshot=%d (%s); this API has no NSError output, errno is not an authoritative denial reason.\n",
            item, url.path ?: @"NIL", snapshot, strerror(snapshot)];
        if (url) {
            struct stat st;
            errno = 0; int rc = lstat(url.fileSystemRepresentation, &st); int statError = errno;
            [log appendFormat:@"Group path lstat rc=%d errno=%d directory=%@ symlink=%@\n",
                rc, statError, rc == 0 && S_ISDIR(st.st_mode) ? @"YES" : @"NO",
                rc == 0 && S_ISLNK(st.st_mode) ? @"YES" : @"NO"];
            [groups addObject:item];
        }
    }
    if (declared.count == 0)
        [log appendString:@"No group candidates in queried/runtime or parsed embedded entitlements. This is NOT proof the signer stripped them if either source is unavailable.\n"];
    else if (groups.count == 0)
        [log appendString:@"Declared groups exist but none returned an OS group container. This is distinct from a missing entitlement; exact provisioning cause is unknown.\n"];
    if (groupError) CFRelease(groupError);
    if (debugError) CFRelease(debugError);
    if (value) CFRelease(value);
    if (debug) CFRelease(debug);
    if (task) CFRelease(task);
    if (security) dlclose(security);
    [log appendFormat:@"signed usable app groups: %lu (OS container lookup required)\n", (unsigned long)groups.count];
    return groups;
}

static int64_t queryFlags(uint64_t queryClass, NSString *identifier, BOOL isGroup,
                     NSString *partDomain, uint64_t requestedFlags, NSString *label, NSMutableString *log) {
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
    if (!create || !cls || !ids || !flags || !part || (partDomain.length && !domain) || !one ||
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
    flags(q, requestedFlags);
    checkpoint([NSString stringWithFormat:@"QUERY BEFORE container_query_get_single_result strategy=%@", label]);
    void *result = one(q);
    checkpoint([NSString stringWithFormat:@"QUERY AFTER result strategy=%@ found=%@", label, result ? @"YES" : @"NO"]);
    checkpoint(@"QUERY BEFORE copy sandbox token");
    char *sandboxToken = result ? token(result) : NULL;
    checkpoint(@"QUERY AFTER copy sandbox token");
    // -106 is Mirsa's missing-result/token sentinel, NOT an OS errno.
    checkpoint(@"QUERY BEFORE consume sandbox token");
    int64_t handle = sandboxToken ? consume(sandboxToken) : -106;
    checkpoint([NSString stringWithFormat:@"QUERY AFTER consume=%lld", (long long)handle]);
    [log appendFormat:@"strategy %@: result=%@ token=%@ consume=%lld\n", label,
        result ? @"YES" : @"NO", sandboxToken ? @"YES" : @"NO", (long long)handle];
    if (sandboxToken) free(sandboxToken);
    destroy(q);
    return handle;
}

static int64_t query(uint64_t cls, NSString *identifier, BOOL group, NSString *domain,
                     NSString *label, NSMutableString *log) {
    return queryFlags(cls, identifier, group, domain, 0x8100000000ULL, label, log);
}

// Independent implementation from the documented behavior of worse_query.
// Only our own signed group is used. Preserve the original cache and restore
// it BEFORE using the canonical destination. Never retain an alias lease.
static int64_t canonicalGrant(NSString *target, NSArray<NSString *> *groups, NSMutableString *log) {
    NSFileManager *fm = NSFileManager.defaultManager;
    if (!allowedGrantTarget(target)) return -101;
    int64_t last = -106;
    for (NSString *group in groups) {
        NSString *root = [fm containerURLForSecurityApplicationGroupIdentifier:group].path;
        if (!root.length || ![normalized(root.stringByResolvingSymlinksInPath) isEqualToString:normalized(root)]) continue;
        NSMutableSet *busy = busyGroups();
        @synchronized(busy) {
            if ([busy containsObject:root]) continue;
            [busy addObject:root];
        }
        NSString *library = [root stringByAppendingPathComponent:@"Library"];
        NSString *cache = [library stringByAppendingPathComponent:@"Caches"];
        NSString *backup = [library stringByAppendingPathComponent:@"Caches.mirsa-pb-backup"];
        BOOL had = NO;
        struct stat original, installed;
        checkpoint(@"CACHE BEFORE create/validate own-group Library");
        BOOL ready = [fm createDirectoryAtPath:library withIntermediateDirectories:YES attributes:nil error:nil] &&
            [normalized(library.stringByResolvingSymlinksInPath) isEqualToString:normalized(library)];
        checkpoint(@"CACHE AFTER create/validate Library; BEFORE recovery check");
        if (ready && existsNoFollow(backup, &original)) {
            NSString *old = [fm destinationOfSymbolicLinkAtPath:cache error:nil];
            struct stat cacheState;
            BOOL missing = !existsNoFollow(cache, &cacheState) && errno == ENOENT;
            ready = S_ISDIR(original.st_mode) && !S_ISLNK(original.st_mode) &&
                ((old && allowedGrantTarget(old)) || missing) &&
                restoreCaches(cache, backup, YES, old, log);
        }
        if (ready) {
            checkpoint(@"CACHE BEFORE preserve original Caches");
            had = existsNoFollow(cache, &original);
            ready = had ? S_ISDIR(original.st_mode) && [fm moveItemAtPath:cache toPath:backup error:nil] : errno == ENOENT;
        }
        checkpoint(@"CACHE AFTER preserve original Caches");
        if (ready) {
            BOOL installedLink = NO;
            @try {
                checkpoint(@"CACHE BEFORE install own-group Caches alias");
                if (symlink(target.fileSystemRepresentation, cache.fileSystemRepresentation) != 0) {
                    [log appendFormat:@"placard-style cache symlink error errno=%d\n", errno];
                } else {
                    installedLink = YES;
                    if (!existsNoFollow(cache, &installed) || !S_ISLNK(installed.st_mode)) {
                        last = -108;
                    } else {
                        checkpoint(@"CACHE alias installed; QUERY starting (synchronous OS call, not forcibly cancellable)");
                        last = queryFlags(7, group, YES, @"", 0x8000000000ULL, @"placard-style", log);
                        if (last < 0 && NSProcessInfo.processInfo.operatingSystemVersion.majorVersion == 26)
                            last = queryFlags(7, group, YES, @"", 0x800000000ULL, @"placard-style-ios26", log);
                    }
                }
            } @finally {
                // Run on success and every normal error/exception exit. A stuck
                // kernel/IPC call or process kill cannot execute finally.
                checkpoint(@"CACHE BEFORE restore original own-group Caches");
                BOOL restored = installedLink ? restoreCaches(cache, backup, had, target, log) :
                    (!had || [fm moveItemAtPath:backup toPath:cache error:nil]);
                checkpoint(restored ? @"CACHE AFTER restore OK" : @"CACHE AFTER restore FAILED; backup retained, stop");
                if (!restored) { releaseNative(last); last = -108; }
                @synchronized(busy) { [busy removeObject:root]; }
            }
            if (last >= 0)
                [log appendFormat:@"placard-style canonical grant %@; own Caches restored immediately.\n", target];
        }
        @synchronized(busy) { [busy removeObject:root]; }
        if (last >= 0 || last == -108) return last;
    }
    return last;
}

static MirsaPBSession *session(NSString *target, int64_t handle) {
    MirsaPBSession *s = [MirsaPBSession new];
    s.nativeHandle = handle;
    s.target = target;
    s.effectivePath = target;
    s.extraHandles = [NSMutableArray array];
    return s;
}
static MirsaPBSession *acquire(NSString *target, int64_t *errorCode, NSMutableString *log) {
#if TARGET_OS_SIMULATOR
    *errorCode = -100;
    return nil;
#else
    if (!allowed(target)) { *errorCode = -101; return nil; }
    checkpoint(@"ACCESS BEFORE signed-group lookup");
    NSArray *groups = signedGroups(log);
    checkpoint(@"ACCESS AFTER signed-group lookup; BEFORE placard-style grant");
    int64_t canonical = canonicalGrant(target, groups, log);
    checkpoint([NSString stringWithFormat:@"ACCESS AFTER placard-style grant result=%lld", (long long)canonical]);
    if (canonical >= 0) {
        MirsaPBSession *lease = session(target, canonical);
        lease.canonicalGrant = YES;
        [log appendFormat:@"placard-style resolved target = %@; root readable=%@ (metadata gets a separate token)\n",
            target.stringByResolvingSymlinksInPath, canOpen(target) ? @"YES" : @"NO"];
        return lease;
    }
    if (canonical == -108) { *errorCode = canonical; return nil; }
    if (groups.count == 0) [log appendString:@"placard-style unavailable: no usable own signed app group. See entitlement-source and per-group OS lookup diagnostics; cause not established.\n"];
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
// Identification-only endpoint. Call only for an xattr match or a
// PosterBoard-specific path hint. Never exposes file contents/other identities.
extern char *mirsa_pb_container_identifier(const char *path);
char *mirsa_pb_target_identity_json(const char *raw) {
    @autoreleasepool {
        NSString *root = raw ? [NSString stringWithUTF8String:raw] : nil;
        NSMutableDictionary *report = [NSMutableDictionary dictionary];
        NSMutableArray *errors = [NSMutableArray array];
        report[@"errors"] = errors;
        if (!allowed(root) || ![[NSUUID alloc] initWithUUIDString:root.lastPathComponent]) {
            report[@"invalid"] = @YES;
        } else {
            char *attribute = mirsa_pb_container_identifier(root.UTF8String);
            BOOL wrongAttribute = attribute && strcmp(attribute, "com.apple.PosterBoard");
            if (attribute) free(attribute);
            if (wrongAttribute) {
                report[@"matched"] = @NO;
                report[@"contradiction"] = @YES;
                [errors addObject:@"Target hint has another container identity xattr (redacted); no metadata grants attempted"];
                NSData *data = [NSJSONSerialization dataWithJSONObject:report options:0 error:nil];
                return strdup([[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding].UTF8String ?: "{}");
            }
            NSMutableString *accessLog = [NSMutableString string];
            NSArray *groups = signedGroups(accessLog);
            NSString *identifier = nil;
            BOOL contradiction = NO, restoreFailure = NO;
            for (NSString *name in @[@".com.apple.mobile_container_manager.metadata.plist",
                                     @"com.apple.mobile_container_manager.metadata.plist"]) {
                NSString *path = [root stringByAppendingPathComponent:name];
                checkpoint([NSString stringWithFormat:@"IDENTITY BEFORE exact metadata token %@", name]);
                int64_t h = canonicalGrant(path, groups, accessLog);
                if (h < 0) {
                    [errors addObject:[NSString stringWithFormat:@"%@ token=%lld", name, (long long)h]];
                    if (h == -108) { restoreFailure = YES; break; }
                    continue;
                }
                @try {
                    struct stat st;
                    int rc = lstat(path.fileSystemRepresentation, &st), saved = errno;
                    if (rc || !S_ISREG(st.st_mode) || st.st_size <= 0 || st.st_size > 1024*1024) {
                        [errors addObject:[NSString stringWithFormat:@"%@ lstat=%d errno=%d regular=%@ size=%lld",
                            name, rc, rc ? saved : 0, !rc && S_ISREG(st.st_mode) ? @"YES" : @"NO",
                            rc ? -1LL : (long long)st.st_size]];
                        continue;
                    }
                    NSString *resolved = normalized(path.stringByResolvingSymlinksInPath);
                    if (![resolved isEqualToString:path]) {
                        [errors addObject:[name stringByAppendingString:@" redirected path rejected"]];
                        contradiction = YES; break;
                    }
                    NSError *error = nil;
                    NSData *bytes = [NSData dataWithContentsOfFile:path options:NSDataReadingUncached error:&error];
                    id plist = bytes ? [NSPropertyListSerialization propertyListWithData:bytes
                        options:NSPropertyListImmutable format:nil error:&error] : nil;
                    id value = [plist isKindOfClass:NSDictionary.class] ? plist[@"MCMMetadataIdentifier"] : nil;
                    if (![value isKindOfClass:NSString.class] || ![value length]) {
                        [errors addObject:[NSString stringWithFormat:@"%@ metadata read/parse %@ code=%ld; MCMMetadataIdentifier missing=%@",
                            name, error.domain ?: @"no NSError", (long)error.code, value ? @"NO" : @"YES"]];
                        continue;
                    }
                    if ([value isEqualToString:@"com.apple.PosterBoard"]) identifier = value;
                    else { contradiction = YES; [errors addObject:[name stringByAppendingString:@" identifies OTHER container (identity redacted)"]]; }
                    checkpoint(@"IDENTITY AFTER metadata read; only equality result retained");
                } @finally { releaseNative(h); }
            }
            report[@"matched"] = @([identifier isEqualToString:@"com.apple.PosterBoard"] && !contradiction);
            report[@"contradiction"] = @(contradiction);
            report[@"restoreFailure"] = @(restoreFailure);
            report[@"method"] = @"exact metadata files only; no candidate root token";
        }
        NSData *data = [NSJSONSerialization dataWithJSONObject:report options:0 error:nil];
        return strdup([[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding].UTF8String ?: "{}");
    }
}
// Only metadata and wallpaper-specific paths of this lease's exact container.
// No arbitrary filesystem primitive is exposed to Swift.
int32_t mirsa_pb_access_grant_relative(void *raw, const char *relative, char **outLog) {
    MirsaPBSession *s = (__bridge MirsaPBSession *)raw;
    NSMutableString *log = [NSMutableString string];
    NSString *part = relative ? [NSString stringWithUTF8String:relative] : nil;
    BOOL safe = part.length && ![part hasPrefix:@"/"] && [part isEqualToString:part.stringByStandardizingPath] &&
        ![[part componentsSeparatedByString:@"/"] containsObject:@".."];
    NSArray *specific = @[@".com.apple.mobile_container_manager.metadata.plist",
        @"com.apple.mobile_container_manager.metadata.plist", @"Library", @"Library/Application Support",
        @"Library/Preferences", @"Library/Preferences/com.apple.PosterBoard.unprotectedUserDefaults.plist"];
    NSString *store = @"Library/Application Support/PRBPosterExtensionDataStore";
    safe = safe && ([specific containsObject:part] || [part isEqualToString:store] ||
        [part hasPrefix:[store stringByAppendingString:@"/"]]);
    int32_t result = 0;
    if (s && s.canonicalGrant && safe && ![s.target.lastPathComponent isEqualToString:@"Application"] &&
        [[NSUUID alloc] initWithUUIDString:s.target.lastPathComponent]) {
        NSString *target = [s.target stringByAppendingPathComponent:part];
        int64_t h = canonicalGrant(target, signedGroups(log), log);
        if (h >= 0) { [s.extraHandles addObject:@(h)]; result = 1; }
    } else if (s && !s.canonicalGrant && safe) result = 1; // legacy recursive alias lease
    if (outLog) *outLog = strdup(log.UTF8String);
    return result;
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
    for (NSNumber *h in s.extraHandles) releaseNative(h.longLongValue);
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

int32_t mirsa_pb_has_own_group(char **outLog) {
    @autoreleasepool {
        NSMutableString *log = [NSMutableString string];
        int32_t count = (int32_t)signedGroups(log).count;
        if (outLog) *outLog = strdup(log.UTF8String);
        return count;
    }
}
