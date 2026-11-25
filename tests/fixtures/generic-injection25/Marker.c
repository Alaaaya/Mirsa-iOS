/* Mirsa-owned inert payload. Executed only with the Mirsa-owned native CI host. */
static int initialized;
int MirsaInjectionMarker25(void) { return initialized; }
#ifdef MIRSA_HOOK_DEPENDENCY
extern void MSHookFunction(void *, void *, void **);
extern void MSHookMessageEx(void *, void *, void *, void **);
extern void *objc_getClass(const char *);
extern void *sel_registerName(const char *);
void (*MirsaHookDependency25)(void *, void *, void **) = MSHookFunction;
static const char *replacement(void *self, void *selector) {
    (void)self; (void)selector;
    return "mirsa-hook-marker25";
}
#endif
__attribute__((constructor)) static void initialize(void) {
    initialized = 25;
#ifdef MIRSA_HOOK_DEPENDENCY
    void *target = objc_getClass("MirsaOwnedLaunchTarget25");
    if (target) MSHookMessageEx(target, sel_registerName("marker"), (void *)replacement, (void **)0);
#endif
}
