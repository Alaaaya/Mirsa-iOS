extern int MirsaSampleAdd(int a);
__attribute__((visibility("default"))) int MirsaFutureCall(int a) { return MirsaSampleAdd(a); }
