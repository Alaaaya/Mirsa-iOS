#import <Foundation/Foundation.h>
#include <substrate.h>
#include <assert.h>
#include <dlfcn.h>
#include <mach-o/dyld.h>
#include <stdio.h>
#include <string.h>
extern int MirsaSampleAdd(int);
extern int MirsaSampleLH(int);
extern int MirsaSampleSubstitute(int);
static int (*old_add)(int);
static int (*old_add2)(int);
static int (*old_lh)(int);
static int (*old_sub)(int);
static int add_hook(int a) { return old_add(a) + 100; }
static int add_hook2(int a) { return old_add2(a) + 200; }
static int lh_hook(int a) { return old_lh(a) + 300; }
static int sub_hook(int a) { return old_sub(a) + 400; }
__attribute__((noinline)) static int local_only(int a) { return a + 1; }
@interface Base : NSObject
- (NSInteger)value;
+ (NSInteger)classValue;
@end
@implementation Base
- (NSInteger)value { return 11; }
+ (NSInteger)classValue { return 21; }
@end
@interface Child : Base @end
@implementation Child @end
@interface Sibling : Base @end
@implementation Sibling @end
@interface LHChild : Base @end
@implementation LHChild @end
@interface SubChild : Base @end
@implementation SubChild @end
static NSInteger (*old_value)(id, SEL);
static NSInteger (*old_value2)(id, SEL);
static NSInteger (*old_class)(id, SEL);
static NSInteger (*old_lhvalue)(id, SEL);
static NSInteger (*old_subvalue)(id, SEL);
static NSInteger value_hook(id obj, SEL sel) { assert(old_value); return old_value(obj, sel) + 10; }
static NSInteger value_hook2(id obj, SEL sel) { assert(old_value2); return old_value2(obj, sel) + 20; }
static NSInteger class_hook(id obj, SEL sel) { assert(old_class); return old_class(obj, sel) + 30; }
static NSInteger lhvalue_hook(id obj, SEL sel) { return old_lhvalue(obj, sel) + 40; }
static NSInteger subvalue_hook(id obj, SEL sel) { return old_subvalue(obj, sel) + 50; }
@interface SmokeTweakTarget : NSObject
- (NSInteger)value;
@end
@implementation SmokeTweakTarget
- (NSInteger)value { return 71; }
@end
int main(int argc, char **argv) {
    @autoreleasepool {
        assert(argc == 3);
        assert(sizeof(struct LHFunctionHook) == 32);
        assert(offsetof(struct LHFunctionHook, oldptr) == 16);
        assert(offsetof(struct LHFunctionHook, options) == 24);
        assert(sizeof(struct substitute_function_hook) == 32);
        assert(offsetof(struct substitute_function_hook, options) == 24);
        Base *base = [Base new]; Child *child = [Child new]; Sibling *sibling = [Sibling new];
        assert(child.value == 11 && base.value == 11 && sibling.value == 11);
        MSHookMessageEx([Child class], @selector(value), (IMP)value_hook, (IMP *)&old_value);
        assert(MirsaHookGetLastStatus() == MIRSA_HOOK_OBJC_REPLACED);
        assert(child.value == 21 && base.value == 11 && sibling.value == 11);
        assert(old_value(child, @selector(value)) == 11);
        MSHookMessageEx([Child class], @selector(value), (IMP)value_hook2, (IMP *)&old_value2);
        assert(child.value == 41 && base.value == 11 && sibling.value == 11);
        assert(old_value2 == value_hook);
        MSHookMessageEx(object_getClass([Child class]), @selector(classValue), (IMP)class_hook, (IMP *)&old_class);
        assert([Child classValue] == 51 && [Base classValue] == 21 && [Sibling classValue] == 21);
        IMP missing = (IMP)value_hook;
        MSHookMessageEx([Child class], sel_registerName("mirsaMissingMethod25"), (IMP)value_hook, &missing);
        assert(missing == NULL && MirsaHookGetLastStatus() == MIRSA_HOOK_SELECTOR_NOT_FOUND);
        assert(LBHookMessage([LHChild class], @selector(value), (void *)lhvalue_hook, &old_lhvalue) == LIBHOOKER_OK);
        assert([LHChild new].value == 51);
        bool created = true;
        assert(substitute_hook_objc_message([SubChild class], @selector(value),
            (void *)subvalue_hook, &old_subvalue, &created) == SUBSTITUTE_OK);
        assert(!created && [SubChild new].value == 61 && base.value == 11);

        assert(MirsaSampleAdd(1) == 8);
        assert(MirsaSampleLH(1) == 18);
        assert(MirsaSampleSubstitute(1) == 28);
        void *target = dlsym(RTLD_DEFAULT, "MirsaSampleAdd");
        Dl_info provider;
        assert(target && dladdr(target, &provider));
        MSImageRef image = MSGetImageByName(provider.dli_fname);
        assert(image && (const void *)image == provider.dli_fbase);
        assert((const void *)MSImageAddress(image) == provider.dli_fbase);
        assert(MSFindSymbol(image, "_MirsaSampleAdd") == target);
        assert(MSFindSymbol(image, "MirsaSampleAdd") == target);
        assert(MSFindSymbol(NULL, "_MirsaSampleAdd") == target);
        assert(MSFindSymbol(image, "_MSHookFunction") == NULL);
        assert(MSFindSymbol((MSImageRef)(uintptr_t)1, "_MirsaSampleAdd") == NULL);
        assert(MSGetImageByName("/mirsa/not/a/loaded/library.dylib") == NULL);
        assert(MSFindSymbol(image, "_mirsaNotExported25") == NULL);
        const char *names[] = {"_MirsaSampleAdd", "_mirsaNotExported25"};
        void *symbols[2] = {(void *)1, (void *)1};
        struct libhooker_image *lh_image = LHOpenImage(provider.dli_fname);
        assert(lh_image && !LHFindSymbols(lh_image, names, symbols, 2));
        assert(symbols[0] == target && symbols[1] == NULL);
        LHCloseImage(lh_image);
        struct substitute_image *sub_image = substitute_open_image(provider.dli_fname);
        assert(sub_image && sub_image->image_header == provider.dli_fbase && sub_image->dlhandle);
        assert(substitute_find_private_syms(sub_image, names, symbols, 2) == SUBSTITUTE_OK);
        assert(symbols[0] == target && !symbols[1]);
        substitute_close_image(sub_image);

        MSHookFunction(target, (void *)add_hook, (void **)&old_add);
        assert(MirsaHookGetLastStatus() == MIRSA_HOOK_IMPORTS_REBOUND);
        assert(MirsaHookGetLastReboundCount() > 0 && old_add);
        assert(MirsaSampleAdd(1) == 108 && old_add(1) == 8);
        /* Saved address and direct calls are deliberately not patched. */
        assert(((int (*)(int))target)(1) == 8);
        MSHookFunction(target, (void *)add_hook2, (void **)&old_add2);
        assert(MirsaHookGetLastStatus() == MIRSA_HOOK_IMPORTS_REBOUND);
        assert(MirsaSampleAdd(1) == 308 && old_add2(1) == 108);

        struct LHFunctionHook lh = {dlsym(RTLD_DEFAULT, "MirsaSampleLH"), (void *)lh_hook, &old_lh, NULL};
        assert(LHHookFunctions(&lh, 1) == LIBHOOKER_OK);
        assert(MirsaHookGetLastStatus() == MIRSA_HOOK_IMPORTS_REBOUND);
        assert(MirsaSampleLH(1) == 318 && old_lh(1) == 18);
        struct substitute_function_hook sub = {
            dlsym(RTLD_DEFAULT, "MirsaSampleSubstitute"), (void *)sub_hook, &old_sub, 0};
        assert(substitute_hook_functions(&sub, 1, NULL, 0) == SUBSTITUTE_OK);
        assert(MirsaSampleSubstitute(1) == 428 && old_sub(1) == 28);

        void *unsupported_old = (void *)1;
        void *unused = dlsym(RTLD_DEFAULT, "MirsaSampleUnused");
        assert(unused);
        MSHookFunction(unused, (void *)add_hook, &unsupported_old);
        assert(!unsupported_old && MirsaHookGetLastReboundCount() == 0);
        assert(MirsaHookGetLastStatus() == MIRSA_HOOK_UNSUPPORTED);
        MSHookFunction((void *)local_only, (void *)add_hook, &unsupported_old);
        assert(!unsupported_old && MirsaHookGetLastStatus() == MIRSA_HOOK_UNSUPPORTED);
        assert(local_only(5) == 6);
        struct LHFunctionHookOptions opts = {LHOptionsSetJumpReg, 16};
        lh.options = &opts;
        assert(LHHookFunctions(&lh, 1) != LIBHOOKER_OK);
        assert(LHHookFunctions(NULL, -1) != LIBHOOKER_OK);
        assert(substitute_hook_functions(&sub, 1, NULL, 128) != SUBSTITUTE_OK);
        void *page = (void *)1;
        assert(!LHExecMemory(&page, NULL, 0) && !page);
        assert(LHPatchMemory(NULL, 0) != LIBHOOKER_OK);
        MSHookMemory((void *)target, NULL, 4);
        assert(MirsaHookGetLastStatus() == MIRSA_HOOK_UNSUPPORTED);
        /* No retained stack output addresses and no hidden future-image hooks. */
        void *future = dlopen(argv[1], RTLD_NOW | RTLD_LOCAL);
        assert(future);
        int (*future_call)(int) = (int (*)(int))dlsym(future, "MirsaFutureCall");
        assert(future_call && future_call(1) == 8);
        dlclose(future);
        SmokeTweakTarget *tweak_target = [SmokeTweakTarget new];
        assert(tweak_target.value == 71);
        void *tweak = dlopen(argv[2], RTLD_NOW | RTLD_LOCAL);
        assert(tweak && tweak_target.value == 72);
        long (*tweak_original)(id) = (long (*)(id))dlsym(tweak, "MirsaTweakOriginalValue");
        assert(tweak_original && tweak_original(tweak_target) == 71);
        /* Do not unload an installed tweak: live method IMPs point into it. */
        puts("Mirsa hook smoke passed: inherited/sibling, chaining, metaclass, ABI, scoped images, imported C, failures, future images");
    }
    return 0;
}
