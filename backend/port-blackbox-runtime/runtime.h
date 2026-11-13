#ifndef MIRSA_BLACKBOX_RUNTIME_H
#define MIRSA_BLACKBOX_RUNTIME_H
#include <stdint.h>
#ifndef MIRSA_BB_LOCAL
#define MIRSA_BB_LOCAL __attribute__((visibility("hidden")))
#endif
#ifdef __cplusplus
extern "C" {
#endif
struct mirsa_bb_event { uint32_t magic, version, signal_number, exception, hook_index, hook_depth; };
/* Explicit opt-in only. Caller supplies private pre-created path outside handler. */
MIRSA_BB_LOCAL int mirsa_bb_start(const char *private_path, int opted_in);
MIRSA_BB_LOCAL int mirsa_bb_read_event(int fd, struct mirsa_bb_event *event);
MIRSA_BB_LOCAL void mirsa_bb_note_exception(void);
MIRSA_BB_LOCAL void mirsa_bb_stop(void);
#ifdef __cplusplus
}
#endif
#endif
