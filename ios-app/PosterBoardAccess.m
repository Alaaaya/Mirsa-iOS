// Narrow class-13 lease adapter derived from Gester's BQCore.m.
// Copyright (c) 2026 KAMUI contributors. MIT, see LICENSES/Gester-MIT.txt.
// Modified for Mirsa: only container roots/UUID containers, no rename/symlink fallback.
#import <Foundation/Foundation.h>
#import <TargetConditionals.h>
#include <dlfcn.h>
#include <stdint.h>
#include <stdlib.h>

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
int64_t mirsa_pb_access_acquire(const char *rawPath) {
#if TARGET_OS_SIMULATOR
    return -100;
#else
    NSString *path = rawPath ? [NSString stringWithUTF8String:rawPath] : nil;
    if (!allowed(path)) return -101;
    static void *library;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        library = dlopen("/usr/lib/system/libsystem_containermanager.dylib", RTLD_NOW | RTLD_LOCAL);
    });
    if (!library) return -102;
    Create create = (Create)symbol(library, "container_query_create", NULL);
    SetNumber cls = (SetNumber)symbol(library, "container_query_set_class", NULL);
    SetObject group = (SetObject)symbol(library, "container_query_set_group_identifiers", NULL);
    SetNumber flags = (SetNumber)symbol(library, "container_query_operation_set_flags", "container_query_set_flags");
    SetNumber part = (SetNumber)symbol(library, "container_query_operation_set_part", "container_query_set_part");
    SetString domain = (SetString)symbol(library, "container_query_operation_set_part_domain", "container_query_set_part_domain");
    GetOne one = (GetOne)symbol(library, "container_query_get_single_result", NULL);
    CopyToken token = (CopyToken)symbol(library, "container_copy_sandbox_token", NULL);
    FreeQuery destroy = (FreeQuery)symbol(library, "container_query_free", NULL);
    Consume consume = (Consume)dlsym(RTLD_DEFAULT, "sandbox_extension_consume");
    XString string = (XString)dlsym(RTLD_DEFAULT, "xpc_string_create");
    XRelease release = (XRelease)dlsym(RTLD_DEFAULT, "xpc_release");
    if (!create || !cls || !group || !flags || !part || !domain || !one ||
        !token || !destroy || !consume || !string || !release || !dlsym(RTLD_DEFAULT, "sandbox_extension_release")) return -103;
    void *q = create();
    if (!q) return -104;
    cls(q, 13);
    void *ident = string("systemgroup.com.apple.mobilegestaltcache");
    if (!ident) { destroy(q); return -105; }
    group(q, ident);
    release(ident);
    part(q, 3);
    NSString *dots = [@[@"..", @"..", @"..", @"..", @"..", @"..",
                        @"..", @"..", @"..", @"..", @"..", @".."] componentsJoinedByString:@"/"];
    domain(q, [dots stringByAppendingString:path].UTF8String);
    flags(q, 0x8100000000ULL);
    void *result = one(q);
    char *sandboxToken = result ? token(result) : NULL;
    int64_t handle = sandboxToken ? consume(sandboxToken) : -106;
    if (sandboxToken) free(sandboxToken);
    destroy(q);
    return handle;
#endif
}
void mirsa_pb_access_release(int64_t handle) {
    Release release = (Release)dlsym(RTLD_DEFAULT, "sandbox_extension_release");
    if (handle >= 0 && release) release(handle);
}
