#ifndef MIRSA_BREADCRUMB_H
#define MIRSA_BREADCRUMB_H
#include <stdint.h>
#ifndef MIRSA_BB_LOCAL
#define MIRSA_BB_LOCAL __attribute__((visibility("hidden")))
#endif
#ifdef __cplusplus
extern "C" {
#endif
/* IDs start at 1 and are immutable source-manifest indices, never addresses.
   These functions run in NORMAL hook context, never in a signal handler. */
MIRSA_BB_LOCAL uint32_t mirsa_bb_hook_enter(uint32_t hook_index);
MIRSA_BB_LOCAL void mirsa_bb_hook_exit(uint32_t token);
/* Signal path: no TLS lookup, pthread, allocation or locks. Captures only the
   slot containing the INTERRUPTED stack pointer. Unknown/unstable => zero.
   This is active-context evidence, never proof the hook caused a crash. */
MIRSA_BB_LOCAL void mirsa_bb_breadcrumb_capture(uintptr_t interrupted_sp,uint32_t *hook,uint32_t *depth);
#ifdef __cplusplus
}
#endif
#endif
