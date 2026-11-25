#include "MirsaHook.h"
#include "fishhook.h"
#include <dlfcn.h>
#include <mach/mach.h>
#include <mach-o/dyld.h>
#include <pthread.h>
#include <stdlib.h>
#include <string.h>

_Static_assert(sizeof(void *) == 8, "64-bit ABI only");
_Static_assert(sizeof(struct LHFunctionHook) == 32, "libhooker four-pointer ABI");
_Static_assert(offsetof(struct LHFunctionHook, options) == 24, "libhooker options offset");
_Static_assert(sizeof(struct LHFunctionHookOptions) == 8, "libhooker options ABI");
_Static_assert(sizeof(struct substitute_function_hook) == 32, "substitute padded ABI");
_Static_assert(offsetof(struct substitute_function_hook, options) == 24, "substitute options offset");
_Static_assert(sizeof(struct substitute_image) == 24, "substitute image ABI");

static _Thread_local enum MirsaHookStatus last_status = MIRSA_HOOK_UNSUPPORTED;
static _Thread_local size_t rebound_count;
static _Thread_local size_t vm_failures;
static _Thread_local void *expected_target;
static _Thread_local void *expected_previous;
static pthread_mutex_t hook_lock = PTHREAD_MUTEX_INITIALIZER;

static void status(enum MirsaHookStatus value) { last_status = value; rebound_count = 0; }
enum MirsaHookStatus MirsaHookGetLastStatus(void) { return last_status; }
size_t MirsaHookGetLastReboundCount(void) { return rebound_count; }
const char *MirsaHookCapabilities(void) {
    return "Mirsa clean-room shim v1; Objective-C runtime replacement; current-image "
           "legacy Mach-O imported-symbol rebinding only; no inline hooks; no future-image "
           "callback; no chained fixups; no arm64e/PAC imports; exported symbols only";
}
const char *MirsaHookGetLastError(void) {
    switch (last_status) {
        case MIRSA_HOOK_OBJC_REPLACED: return "Objective-C implementation replaced";
        case MIRSA_HOOK_IMPORTS_REBOUND: return "Imported pointers rebound only; direct calls unchanged";
        case MIRSA_HOOK_INVALID_ARGUMENT: return "Invalid argument";
        case MIRSA_HOOK_SELECTOR_NOT_FOUND: return "Selector not found";
        case MIRSA_HOOK_SYMBOL_NOT_FOUND: return "Exported symbol or loaded image not found";
        case MIRSA_HOOK_UNSUPPORTED: return "Unsupported: no eligible import, inline hook, chained fixup, or option";
        case MIRSA_HOOK_VM_ERROR: return "Memory protection operation failed; inspect rebound count for partial application";
        case MIRSA_HOOK_NO_MEMORY: return "Allocation failed; inspect rebound count for partial application";
        case MIRSA_HOOK_IMAGE_FOUND: return "Loaded image found";
        case MIRSA_HOOK_SYMBOL_FOUND: return "Exported symbol found";
    }
    return "Unknown status";
}
static int image_index(MSImageRef image) {
    for (uint32_t i = 0; i < _dyld_image_count(); ++i)
        if ((MSImageRef)_dyld_get_image_header(i) == image) return (int)i;
    return -1;
}
MSImageRef MSGetImageByName(const char *file) {
    status(MIRSA_HOOK_INVALID_ARGUMENT);
    if (!file || !*file) return NULL;
    for (uint32_t i = 0; i < _dyld_image_count(); ++i) {
        const char *name = _dyld_get_image_name(i);
        if (name && strcmp(name, file) == 0) {
            status(MIRSA_HOOK_IMAGE_FOUND);
            return (MSImageRef)_dyld_get_image_header(i);
        }
    }
    status(MIRSA_HOOK_SYMBOL_NOT_FOUND);
    return NULL;
}
const MSImageHeader *MSImageAddress(MSImageRef image) {
    if (!image || image_index(image) < 0) {
        status(MIRSA_HOOK_INVALID_ARGUMENT); return NULL;
    }
    status(MIRSA_HOOK_IMAGE_FOUND);
    return (const MSImageHeader *)image;
}
void MSCloseImage(MSImageRef image) { (void)image; /* borrowed loaded header */ }

void *MSFindSymbol(MSImageRef image, const char *name) {
    status(MIRSA_HOOK_INVALID_ARGUMENT);
    if (!name || !*name) return NULL;
    void *handle = RTLD_DEFAULT;
    if (image) {
        int index = image_index(image);
        if (index < 0) return NULL;
        handle = dlopen(_dyld_get_image_name((uint32_t)index), RTLD_LAZY | RTLD_NOLOAD);
        if (!handle) { status(MIRSA_HOOK_SYMBOL_NOT_FOUND); return NULL; }
    }
    /* Substrate accepts raw Mach-O names, not dlsym names. */
    const char *lookup = name[0] == '_' ? name + 1 : name;
    void *result = dlsym(handle, lookup);
    if (image && result) {
        Dl_info info;
        if (!dladdr(result, &info) || (MSImageRef)info.dli_fbase != image) result = NULL;
    }
    if (image) dlclose(handle);
    status(result ? MIRSA_HOOK_SYMBOL_FOUND : MIRSA_HOOK_SYMBOL_NOT_FOUND);
    return result;
}

void MSHookMessageEx(Class cls, SEL selector, IMP replacement, IMP *original) {
    if (original) *original = NULL;
    status(MIRSA_HOOK_INVALID_ARGUMENT);
    if (!cls || !selector || !replacement) return;
    pthread_mutex_lock(&hook_lock);
    Method method = class_getInstanceMethod(cls, selector);
    if (!method) {
        status(MIRSA_HOOK_SELECTOR_NOT_FOUND);
        pthread_mutex_unlock(&hook_lock);
        return;
    }
    IMP previous = method_getImplementation(method);
    const char *types = method_getTypeEncoding(method);
    /* Publish the saved implementation before exposing the replacement. Add on
       the actual class first so an inherited method never mutates its parent. */
    if (original) *original = previous;
    if (!class_addMethod(cls, selector, replacement, types)) {
        IMP replaced = class_replaceMethod(cls, selector, replacement, types);
        if (original && replaced) *original = replaced;
    }
    status(MIRSA_HOOK_OBJC_REPLACED);
    pthread_mutex_unlock(&hook_lock);
}

/* Called only by our BSD fishhook adapter. No instruction pages are modified.
   Slots must already resolve to this symbol (or our preceding replacement).
   Lazy unresolved pointers are intentionally skipped, never treated as proof. */
__attribute__((visibility("hidden")))
void mirsa_fishhook_store(void **slot, void *replacement, void **old_slot) {
    void *old = __atomic_load_n(slot, __ATOMIC_ACQUIRE);
    if (old != expected_target && old != expected_previous) return;
    if (old == replacement) return;
    vm_address_t region = (vm_address_t)slot;
    vm_size_t region_size = 0;
    vm_region_basic_info_data_64_t info;
    mach_msg_type_number_t count = VM_REGION_BASIC_INFO_COUNT_64;
    mach_port_t object = MACH_PORT_NULL;
    kern_return_t result = vm_region_64(mach_task_self(), &region, &region_size,
        VM_REGION_BASIC_INFO_64, (vm_region_info_t)&info, &count, &object);
    if (object != MACH_PORT_NULL) mach_port_deallocate(mach_task_self(), object);
    if (result != KERN_SUCCESS || (info.protection & VM_PROT_EXECUTE) ||
        !(info.protection & VM_PROT_READ) || (uintptr_t)slot < region ||
        (uintptr_t)slot - region > region_size ||
        region_size - ((uintptr_t)slot - region) < sizeof(void *)) {
        ++vm_failures; return;
    }
    const bool writable = (info.protection & VM_PROT_WRITE) != 0;
    vm_address_t page = (vm_address_t)slot & ~((vm_address_t)vm_page_size - 1);
    if (!writable && vm_protect(mach_task_self(), page, vm_page_size, false,
        info.protection | VM_PROT_WRITE | VM_PROT_COPY) != KERN_SUCCESS) {
        ++vm_failures; return;
    }
    /* The original is owned by the caller, not retained by fishhook. */
    if (old_slot && !*old_slot) *old_slot = old;
    __atomic_store_n(slot, replacement, __ATOMIC_RELEASE);
    ++rebound_count;
    if (!writable && vm_protect(mach_task_self(), page, vm_page_size, false,
        info.protection) != KERN_SUCCESS) ++vm_failures;
}

struct prior_hook { void *target; void *replacement; struct prior_hook *next; };
static struct prior_hook *prior_hooks;

static bool eligible_image(const struct mach_header *header) {
    if (!header || header->magic != MH_MAGIC_64) return false;
    if ((header->cpusubtype & ~CPU_SUBTYPE_MASK) == CPU_SUBTYPE_ARM64E) return false;
    const unsigned char *start = (const unsigned char *)header + sizeof(struct mach_header_64);
    const unsigned char *end = start + header->sizeofcmds;
    const unsigned char *p = start;
    /* Apple's loader validated these commands; still bound every access. */
    for (uint32_t i = 0; i < header->ncmds; ++i) {
        if ((size_t)(end - p) < sizeof(struct load_command)) return false;
        const struct load_command *lc = (const struct load_command *)p;
        if (lc->cmdsize < sizeof(*lc) || lc->cmdsize > (size_t)(end - p)) return false;
        if (lc->cmd == LC_DYLD_CHAINED_FIXUPS) return false;
        p += lc->cmdsize;
    }
    return true;
}
void MSHookFunction(void *target, void *replacement, void **original) {
    if (original) *original = NULL;
    status(MIRSA_HOOK_INVALID_ARGUMENT);
    if (!target || !replacement || target == replacement) return;
    Dl_info symbol;
    if (!dladdr(target, &symbol) || symbol.dli_saddr != target || !symbol.dli_sname) {
        status(MIRSA_HOOK_UNSUPPORTED); return;
    }
    void *exported = dlsym(RTLD_DEFAULT, symbol.dli_sname);
    if (exported != target) { status(MIRSA_HOOK_UNSUPPORTED); return; }
    struct prior_hook *record = calloc(1, sizeof(*record));
    if (!record) { status(MIRSA_HOOK_NO_MEMORY); return; }
    pthread_mutex_lock(&hook_lock);
    void *previous = target;
    for (struct prior_hook *p = prior_hooks; p; p = p->next)
        if (p->target == target) { previous = p->replacement; break; }
    expected_target = target;
    expected_previous = previous;
    rebound_count = 0; vm_failures = 0;
    /* Do not save pointer-to-caller storage or install dyld callbacks. */
    if (original) *original = previous;
    struct rebinding bind = {symbol.dli_sname, replacement, NULL};
    bool allocation_failed = false;
    for (uint32_t i = 0; i < _dyld_image_count(); ++i) {
        const struct mach_header *header = _dyld_get_image_header(i);
        if (eligible_image(header) && rebind_symbols_image((void *)header,
            _dyld_get_image_vmaddr_slide(i), &bind, 1) != 0) {
            allocation_failed = true;
            break;
        }
    }
    if (rebound_count) {
        record->target = target; record->replacement = replacement;
        record->next = prior_hooks; prior_hooks = record;
    } else {
        free(record);
        if (original) *original = NULL;
    }
    expected_target = NULL; expected_previous = NULL;
    last_status = allocation_failed ? MIRSA_HOOK_NO_MEMORY :
        vm_failures ? MIRSA_HOOK_VM_ERROR :
        rebound_count ? MIRSA_HOOK_IMPORTS_REBOUND : MIRSA_HOOK_UNSUPPORTED;
    pthread_mutex_unlock(&hook_lock);
}
void MSHookMemory(void *target, const void *data, size_t size) {
    (void)target; (void)data; (void)size; status(MIRSA_HOOK_UNSUPPORTED);
}
static int lh_error(void) {
    switch (last_status) {
        case MIRSA_HOOK_OBJC_REPLACED:
        case MIRSA_HOOK_IMPORTS_REBOUND: return LIBHOOKER_OK;
        case MIRSA_HOOK_SELECTOR_NOT_FOUND: return LIBHOOKER_ERR_SELECTOR_NOT_FOUND;
        case MIRSA_HOOK_VM_ERROR:
        case MIRSA_HOOK_NO_MEMORY: return LIBHOOKER_ERR_VM;
        case MIRSA_HOOK_UNSUPPORTED: return LIBHOOKER_ERR_BAD_INSN_AT_START;
        default: return LIBHOOKER_ERR_NO_SYMBOL;
    }
}
enum LIBHOOKER_ERR LBHookMessage(Class cls, SEL sel, void *replacement, void *old_ptr) {
    MSHookMessageEx(cls, sel, (IMP)replacement, (IMP *)old_ptr);
    return (enum LIBHOOKER_ERR)lh_error();
}
int LHHookFunctions(const struct LHFunctionHook *hooks, int count) {
    status(MIRSA_HOOK_INVALID_ARGUMENT);
    if (count < 0 || (count && !hooks)) return LIBHOOKER_ERR_NO_SYMBOL;
    for (int i = 0; i < count; ++i) {
        if (hooks[i].oldptr) *(void **)hooks[i].oldptr = NULL;
        if (!hooks[i].function || !hooks[i].replacement) return LIBHOOKER_ERR_NO_SYMBOL;
        if (hooks[i].options && hooks[i].options->options != LHOptionsNone) {
            status(MIRSA_HOOK_UNSUPPORTED); return LIBHOOKER_ERR_BAD_INSN_AT_START;
        }
    }
    for (int i = 0; i < count; ++i) {
        MSHookFunction(hooks[i].function, hooks[i].replacement, (void **)hooks[i].oldptr);
        int error = lh_error();
        if (error) return error; /* Earlier hooks may already have applied. */
    }
    return LIBHOOKER_OK; /* Current 1.6 public docs: error code, not count. */
}
const char *LHStrError(enum LIBHOOKER_ERR error) {
    switch (error) {
        case LIBHOOKER_OK: return "No error (import rebinding only for C functions)";
        case LIBHOOKER_ERR_SELECTOR_NOT_FOUND: return "Selector not found";
        case LIBHOOKER_ERR_SHORT_FUNC: return "Function too short";
        case LIBHOOKER_ERR_BAD_INSN_AT_START: return "Unsupported function or inline-hook option";
        case LIBHOOKER_ERR_VM: return "Memory protection or allocation error";
        case LIBHOOKER_ERR_NO_SYMBOL: return "Invalid argument or missing exported symbol";
    }
    return "Unknown Error";
}
struct libhooker_image { MSImageRef header; };
struct libhooker_image *LHOpenImage(const char *path) {
    MSImageRef header = MSGetImageByName(path);
    if (!header) return NULL;
    struct libhooker_image *result = malloc(sizeof(*result));
    if (!result) { status(MIRSA_HOOK_NO_MEMORY); return NULL; }
    result->header = header; return result;
}
void LHCloseImage(struct libhooker_image *image) { free(image); }
bool LHFindSymbols(struct libhooker_image *image, const char **names, void **symbols, size_t count) {
    if (!image || (count && (!names || !symbols))) {
        status(MIRSA_HOOK_INVALID_ARGUMENT); return false;
    }
    bool found = true;
    for (size_t i = 0; i < count; ++i) {
        symbols[i] = MSFindSymbol(image->header, names[i]);
        if (!symbols[i]) found = false;
    }
    if (!found) status(MIRSA_HOOK_SYMBOL_NOT_FOUND);
    return found;
}
bool LHExecMemory(void **page, void *data, size_t size) {
    if (page) *page = NULL;
    (void)data; (void)size; status(MIRSA_HOOK_UNSUPPORTED); return false;
}
int LHPatchMemory(const struct LHMemoryPatch *patches, int count) {
    (void)patches; (void)count; status(MIRSA_HOOK_UNSUPPORTED); return LIBHOOKER_ERR_VM;
}
static int substitute_error(void) {
    switch (last_status) {
        case MIRSA_HOOK_OBJC_REPLACED:
        case MIRSA_HOOK_IMPORTS_REBOUND: return SUBSTITUTE_OK;
        case MIRSA_HOOK_NO_MEMORY: return SUBSTITUTE_ERR_OOM;
        case MIRSA_HOOK_SELECTOR_NOT_FOUND: return SUBSTITUTE_ERR_NO_SUCH_SELECTOR;
        case MIRSA_HOOK_UNSUPPORTED: return SUBSTITUTE_ERR_FUNC_BAD_INSN_AT_START;
        default: return SUBSTITUTE_ERR_VM;
    }
}
int substitute_hook_functions(const struct substitute_function_hook *hooks, size_t count,
    struct substitute_function_hook_record **record, int options) {
    if (record) *record = NULL;
    status(MIRSA_HOOK_INVALID_ARGUMENT);
    if ((count && !hooks) || count > 4096) return SUBSTITUTE_ERR_VM;
    if (record || (options & ~SUBSTITUTE_NO_THREAD_SAFETY)) {
        status(MIRSA_HOOK_UNSUPPORTED); return SUBSTITUTE_ERR_FUNC_BAD_INSN_AT_START;
    }
    for (size_t i = 0; i < count; ++i) {
        if (hooks[i].old_ptr) *(void **)hooks[i].old_ptr = NULL;
        if (!hooks[i].function || !hooks[i].replacement || hooks[i].options) {
            status(MIRSA_HOOK_UNSUPPORTED); return SUBSTITUTE_ERR_FUNC_BAD_INSN_AT_START;
        }
    }
    for (size_t i = 0; i < count; ++i) {
        MSHookFunction(hooks[i].function, hooks[i].replacement, (void **)hooks[i].old_ptr);
        int error = substitute_error();
        if (error) return error;
    }
    return SUBSTITUTE_OK;
}
int substitute_hook_objc_message(Class cls, SEL sel, void *replacement,
    void *old_ptr, bool *created_imp) {
    if (created_imp) *created_imp = false;
    MSHookMessageEx(cls, sel, (IMP)replacement, (IMP *)old_ptr);
    return substitute_error();
}
void substitute_free_created_imp(IMP imp) { (void)imp; /* Never manufacture IMPs. */ }
const char *substitute_strerror(int error) {
    switch (error) {
        case SUBSTITUTE_OK: return "No error (import rebinding only for C functions)";
        case SUBSTITUTE_ERR_NO_SUCH_SELECTOR: return "No such selector";
        case SUBSTITUTE_ERR_FUNC_BAD_INSN_AT_START: return "Unsupported function or option";
        case SUBSTITUTE_ERR_OOM: return "Out of memory";
        case SUBSTITUTE_ERR_VM: return "Memory protection or argument error";
        default: return "Unsupported substitute error code";
    }
}
struct substitute_image *substitute_open_image(const char *path) {
    MSImageRef header = MSGetImageByName(path);
    if (!header) return NULL;
    int index = image_index(header);
    if (index < 0) return NULL;
    void *handle = dlopen(path, RTLD_LAZY | RTLD_NOLOAD);
    if (!handle) { status(MIRSA_HOOK_SYMBOL_NOT_FOUND); return NULL; }
    struct substitute_image *result = calloc(1, sizeof(*result));
    if (!result) { dlclose(handle); status(MIRSA_HOOK_NO_MEMORY); return NULL; }
    result->slide = _dyld_get_image_vmaddr_slide((uint32_t)index);
    result->dlhandle = handle; result->image_header = (const void *)header;
    return result;
}
void substitute_close_image(struct substitute_image *image) {
    if (image) { if (image->dlhandle) dlclose(image->dlhandle); free(image); }
}
int substitute_find_private_syms(struct substitute_image *image,
    const char **names, void **symbols, size_t count) {
    if (!image || (count && (!names || !symbols))) {
        status(MIRSA_HOOK_INVALID_ARGUMENT); return SUBSTITUTE_ERR_VM;
    }
    bool found = true;
    for (size_t i = 0; i < count; ++i) {
        symbols[i] = MSFindSymbol((MSImageRef)image->image_header, names[i]);
        if (!symbols[i]) found = false;
    }
    if (!found) status(MIRSA_HOOK_SYMBOL_NOT_FOUND);
    /* The documented substitute API returns OK even when individual symbols
       are absent; NULL outputs and Mirsa status expose that limitation. */
    return SUBSTITUTE_OK;
}
