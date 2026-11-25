#include <substrate.h>
#include <assert.h>
static long (*original_value)(id, SEL);
static long replacement_value(id obj, SEL sel) {
    assert(original_value);
    return original_value(obj, sel) + 1;
}
__attribute__((constructor)) static void install_tweak(void) {
    Class cls = objc_getClass("SmokeTweakTarget");
    assert(cls);
    MSHookMessageEx(cls, sel_registerName("value"), (IMP)replacement_value, (IMP *)&original_value);
    assert(MirsaHookGetLastStatus() == MIRSA_HOOK_OBJC_REPLACED);
}
__attribute__((visibility("default"))) long MirsaTweakOriginalValue(id obj) {
    return original_value(obj, sel_registerName("value"));
}
