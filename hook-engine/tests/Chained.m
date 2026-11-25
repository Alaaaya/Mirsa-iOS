#include <substrate.h>
#include <assert.h>
#include <dlfcn.h>
#include <stdio.h>
extern int MirsaSampleAdd(int);
static int replacement(int a) { return a + 100; }
int main(void) {
    assert(MirsaSampleAdd(1) == 8);
    void *original = (void *)1;
    MSHookFunction(dlsym(RTLD_DEFAULT, "MirsaSampleAdd"), (void *)replacement, &original);
    assert(!original && MirsaHookGetLastStatus() == MIRSA_HOOK_UNSUPPORTED);
    assert(MirsaSampleAdd(1) == 8);
    puts("Mirsa chained-fixup importer skipped safely");
    return 0;
}
