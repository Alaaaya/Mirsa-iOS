#ifndef MIRSA_BLACKBOX_RUNTIME_H
#define MIRSA_BLACKBOX_RUNTIME_H
#include <stdint.h>
struct mirsa_bb_event { uint32_t magic, version, signal_number, exception, hook_index, hook_depth; };
/* Explicit opt-in only. Caller supplies private pre-created path outside handler. */
int mirsa_bb_start(const char *private_path, int opted_in);
int mirsa_bb_read_event(int fd, struct mirsa_bb_event *event);
void mirsa_bb_note_exception(void);
void mirsa_bb_stop(void);
#endif
