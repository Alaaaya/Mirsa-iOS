/* Mirsa-owned inert fixture. Never executes user package code. */
int MirsaInjectionMarker25(void) { return 25; }
#ifdef MIRSA_HOOK_DEPENDENCY
extern void MSHookFunction(void *, void *, void **);
void (*MirsaHookDependency25)(void *, void *, void **) = MSHookFunction;
#endif
