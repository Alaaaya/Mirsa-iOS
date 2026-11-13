#ifndef MIRSA_BREADCRUMB_H
#define MIRSA_BREADCRUMB_H
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
/* IDs start at 1 and are immutable source-manifest indices, never addresses.
   These functions run in NORMAL hook context, never in a signal handler. */
uint32_t mirsa_bb_hook_enter(uint32_t hook_index);
void mirsa_bb_hook_exit(uint32_t token);
/* Signal path: no TLS lookup, pthread, allocation or locks. Captures only the
   slot containing the INTERRUPTED stack pointer. Unknown/unstable => zero.
   This is active-context evidence, never proof the hook caused a crash. */
void mirsa_bb_breadcrumb_capture(uintptr_t interrupted_sp,uint32_t *hook,uint32_t *depth);
#ifdef __cplusplus
}
#endif
#endif
