/* Mirsa clean-room ABI declarations. Public references in ABI-SOURCES.md. */
#ifndef MIRSA_HOOK_H
#define MIRSA_HOOK_H
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <objc/runtime.h>
#include <mach-o/loader.h>
#define MH_API __attribute__((visibility("default")))
#ifdef __cplusplus
extern "C" {
#endif
typedef const struct MSImage *MSImageRef;
typedef struct mach_header_64 MSImageHeader;
MH_API MSImageRef MSGetImageByName(const char *file);
MH_API const MSImageHeader *MSImageAddress(MSImageRef image);
MH_API void MSCloseImage(MSImageRef image);
MH_API void *MSFindSymbol(MSImageRef image, const char *name);
MH_API void MSHookMessageEx(Class cls, SEL selector, IMP replacement, IMP *original);
MH_API void MSHookFunction(void *target, void *replacement, void **original);
/* Never modify executable pages. Unsupported memory APIs fail closed. */
MH_API void MSHookMemory(void *target, const void *data, size_t size);

enum MirsaHookStatus {
    MIRSA_HOOK_OBJC_REPLACED = 0,
    MIRSA_HOOK_IMPORTS_REBOUND = 1,
    MIRSA_HOOK_INVALID_ARGUMENT = 2,
    MIRSA_HOOK_SELECTOR_NOT_FOUND = 3,
    MIRSA_HOOK_SYMBOL_NOT_FOUND = 4,
    MIRSA_HOOK_UNSUPPORTED = 5,
    MIRSA_HOOK_VM_ERROR = 6,
    MIRSA_HOOK_NO_MEMORY = 7,
    MIRSA_HOOK_IMAGE_FOUND = 8,
    MIRSA_HOOK_SYMBOL_FOUND = 9
};
MH_API enum MirsaHookStatus MirsaHookGetLastStatus(void);
MH_API const char *MirsaHookGetLastError(void);
MH_API size_t MirsaHookGetLastReboundCount(void);
MH_API const char *MirsaHookCapabilities(void);

enum LIBHOOKER_ERR {
    LIBHOOKER_OK = 0, LIBHOOKER_ERR_SELECTOR_NOT_FOUND = 1,
    LIBHOOKER_ERR_SHORT_FUNC = 2, LIBHOOKER_ERR_BAD_INSN_AT_START = 3,
    LIBHOOKER_ERR_VM = 4, LIBHOOKER_ERR_NO_SYMBOL = 5
};
enum LHOptions { LHOptionsNone = 0, LHOptionsSetJumpReg = 1 };
struct LHFunctionHookOptions { enum LHOptions options; int jmp_reg; };
struct LHFunctionHook {
    void *function;
    void *replacement;
    void *oldptr;
    struct LHFunctionHookOptions *options;
};
struct LHMemoryPatch { void *destination; const void *data; size_t size; void *options; };
struct libhooker_image;
MH_API enum LIBHOOKER_ERR LBHookMessage(Class cls, SEL selector, void *replacement, void *old_ptr);
MH_API int LHHookFunctions(const struct LHFunctionHook *hooks, int count);
MH_API const char *LHStrError(enum LIBHOOKER_ERR error);
MH_API struct libhooker_image *LHOpenImage(const char *path);
MH_API void LHCloseImage(struct libhooker_image *image);
MH_API bool LHFindSymbols(struct libhooker_image *image, const char **names, void **symbols, size_t count);
MH_API bool LHExecMemory(void **page, void *data, size_t size);
MH_API int LHPatchMemory(const struct LHMemoryPatch *patches, int count);

enum {
    SUBSTITUTE_OK = 0, SUBSTITUTE_ERR_FUNC_TOO_SHORT = 1,
    SUBSTITUTE_ERR_FUNC_BAD_INSN_AT_START = 2, SUBSTITUTE_ERR_FUNC_CALLS_AT_START = 3,
    SUBSTITUTE_ERR_FUNC_JUMPS_TO_START = 4, SUBSTITUTE_ERR_OOM = 5,
    SUBSTITUTE_ERR_VM = 6, SUBSTITUTE_ERR_NOT_ON_MAIN_THREAD = 7,
    SUBSTITUTE_ERR_UNEXPECTED_PC_ON_OTHER_THREAD = 8, SUBSTITUTE_ERR_OUT_OF_RANGE = 9,
    SUBSTITUTE_ERR_UNKNOWN_RELOCATION_TYPE = 10, SUBSTITUTE_ERR_NO_SUCH_SELECTOR = 11,
    SUBSTITUTE_ERR_ADJUSTING_THREADS = 12
};
enum { SUBSTITUTE_NO_THREAD_SAFETY = 1 };
struct substitute_function_hook {
    void *function;
    void *replacement;
    void *old_ptr;
    int options;
};
struct substitute_function_hook_record;
struct substitute_image { intptr_t slide; void *dlhandle; const void *image_header; };
MH_API int substitute_hook_functions(const struct substitute_function_hook *hooks, size_t count,
    struct substitute_function_hook_record **record, int options);
MH_API int substitute_hook_objc_message(Class cls, SEL selector, void *replacement,
    void *old_ptr, bool *created_imp);
MH_API void substitute_free_created_imp(IMP imp);
MH_API const char *substitute_strerror(int error);
MH_API struct substitute_image *substitute_open_image(const char *path);
MH_API void substitute_close_image(struct substitute_image *image);
MH_API int substitute_find_private_syms(struct substitute_image *image,
    const char **names, void **symbols, size_t count);
#ifdef __cplusplus
}
#endif
#endif
