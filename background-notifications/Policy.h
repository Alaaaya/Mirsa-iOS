#ifndef MIRSA_BACKGROUND_POLICY_H
#define MIRSA_BACKGROUND_POLICY_H
#include <stdbool.h>
#include <stdint.h>
typedef struct { bool enabled, consent, notifications, audioSelected, locationSelected, audioStopped; int64_t lastBadge; double lastEvent; unsigned emitted; } MBPolicy;
static inline bool MBMayAudio(const MBPolicy *p) { return p->enabled && p->consent && p->audioSelected && !p->audioStopped; }
static inline bool MBMayLocation(const MBPolicy *p, bool available, bool always) { return p->enabled && p->consent && p->locationSelected && available && always; }
static inline bool MBMayNotify(MBPolicy *p, bool background, int64_t badge, double now) {
    int64_t previous = p->lastBadge; p->lastBadge = badge;
    if (!p->enabled || !p->consent || !p->notifications || !background || badge <= 0 || badge <= previous || p->emitted >= 32) return false;
    if (p->lastEvent > 0 && now - p->lastEvent < 10) return false;
    p->lastEvent = now; p->emitted++; return true;
}
#endif
