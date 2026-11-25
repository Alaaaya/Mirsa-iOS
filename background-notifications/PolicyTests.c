#include "Policy.h"
#include <assert.h>
#include <stdio.h>
int main(void) {
    MBPolicy p = {0};
    assert(!MBMayAudio(&p)); assert(!MBMayLocation(&p, true, true));
    assert(!MBMayNotify(&p, true, 1, 20));
    p.enabled = true; p.audioSelected = true; p.locationSelected = true;
    assert(!MBMayAudio(&p)); assert(!MBMayLocation(&p, true, true));
    assert(!MBMayNotify(&p, true, 2, 30));
    p.consent = true;
    assert(MBMayAudio(&p)); assert(MBMayLocation(&p, true, true));
    assert(!MBMayLocation(&p, false, true)); assert(!MBMayLocation(&p, true, false));
    p.audioStopped = true; assert(!MBMayAudio(&p)); /* Interruption is terminal for launch. */
    p.audioSelected = false; p.audioStopped = false; assert(!MBMayAudio(&p));
    assert(!MBMayNotify(&p, true, 3, 40)); /* Permission denied. */
    p.notifications = true;
    assert(!MBMayNotify(&p, false, 4, 50)); /* Foreground baseline only. */
    assert(!MBMayNotify(&p, true, 4, 60)); /* Same badge not new event. */
    assert(MBMayNotify(&p, true, 5, 70));
    assert(!MBMayNotify(&p, true, 6, 72)); /* Native setter + completion dedupe. */
    assert(!MBMayNotify(&p, true, 6, 90));
    assert(!MBMayNotify(&p, true, 0, 100));
    assert(MBMayNotify(&p, true, 1, 110));
    p.emitted = 32; assert(!MBMayNotify(&p, true, 2, 130));
    p.enabled = false; assert(!MBMayAudio(&p)); assert(!MBMayLocation(&p, true, true));
    puts("background policy permission, opt-in, interruption, dedupe and cap tests passed");
}
