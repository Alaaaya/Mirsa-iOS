#define _GNU_SOURCE 1
#define _DARWIN_C_SOURCE 1
#define _POSIX_C_SOURCE 200809L
#include "runtime.h"
#include "breadcrumb.h"
#include <stdatomic.h>
#if defined(__APPLE__)
#include <sys/ucontext.h>
#else
#include <ucontext.h>
#endif
#if defined(__APPLE__) && defined(__aarch64__)
#include <mach/arm/thread_status.h>
#endif
#include <signal.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <errno.h>
#include <string.h>

static int event_fd = -1;
static volatile sig_atomic_t active = 0;
static atomic_uint writing = 0;
_Static_assert(ATOMIC_INT_LOCK_FREE==2,"event claim must be lockfree");
static const int fatal_signals[] = {SIGABRT,SIGBUS,SIGFPE,SIGILL,SIGSEGV,SIGTRAP};
#define COUNT (sizeof(fatal_signals)/sizeof(fatal_signals[0]))
static unsigned char installed[COUNT];
static struct sigaction prior[COUNT];

static void persist(int sig, int exception, uintptr_t sp) {
    /* Fixed primitive values only. No pointers, hook guesses, addresses, ObjC,
       malloc, locks, time, backtrace, logging or network here. */
    struct mirsa_bb_event e = {0x4d424231U,2U,(uint32_t)sig,(uint32_t)exception,0,0};
    mirsa_bb_breadcrumb_capture(sp,&e.hook_index,&e.hook_depth);
    unsigned expected=0;
    if (event_fd >= 0 && atomic_compare_exchange_strong_explicit(&writing,&expected,1,memory_order_seq_cst,memory_order_seq_cst)) {
        (void)write(event_fd, &e, sizeof e);
    }
}
static void handler(int sig, siginfo_t *info, void *context) {
    (void)info;uintptr_t sp=0;
    ucontext_t *uc=context;
#if defined(__APPLE__) && defined(__aarch64__)
    if(uc)sp=(uintptr_t)arm_thread_state64_get_sp(uc->uc_mcontext->__ss);
#elif defined(__APPLE__) && defined(__x86_64__)
    if(uc)sp=(uintptr_t)uc->uc_mcontext->__ss.__rsp;
#elif defined(__linux__) && defined(__x86_64__)
    if(uc)sp=(uintptr_t)uc->uc_mcontext.gregs[REG_RSP];
#elif defined(__linux__) && defined(__aarch64__)
    if(uc)sp=(uintptr_t)uc->uc_mcontext.sp;
#else
    (void)uc;
#endif
    int saved_errno = errno;
    if (active) persist(sig,0,sp);
    /* Only SIG_DFL handlers are replaced. Existing crash guards/custom signal
       handlers and SIG_IGN remain untouched, avoiding unsafe manual chaining.
       Restore original disposition, re-raise, return so kernel delivers fatal
       signal after this handler's mask is released. Never swallow termination. */
    for (unsigned i=0;i<COUNT;i++) {
        if (fatal_signals[i]==sig && installed[i]) {
            (void)sigaction(sig,&prior[i],0);
            break;
        }
    }
    (void)kill(getpid(),sig);
    errno = saved_errno;
}
int mirsa_bb_read_event(int fd, struct mirsa_bb_event *e) {
    struct stat st;
    if (fstat(fd,&st)!=0 || !S_ISREG(st.st_mode) ||
        st.st_size != (off_t)sizeof(*e)) return 0;
    ssize_t n=pread(fd,e,sizeof(*e),0);
    if (n!=(ssize_t)sizeof(*e) || e->magic!=0x4d424231U ||
        e->version!=2 || e->exception>1 || e->hook_depth>32 ||
        ((e->hook_index==0)!=(e->hook_depth==0))) return 0;
    if (e->exception==1) return e->signal_number==0;
    for (unsigned i=0;i<COUNT;i++)
        if (e->signal_number==(uint32_t)fatal_signals[i]) return 1;
    return 0;
}
int mirsa_bb_start(const char *path,int opted_in) {
    if (!opted_in || active || !path) return 0;
    int fd=open(path,O_WRONLY|O_CREAT|O_NOFOLLOW|O_CLOEXEC,0600);
    if (fd<0) return 0;
    struct stat st;
    if (fstat(fd,&st)!=0 || !S_ISREG(st.st_mode) || st.st_uid!=getuid() ||
        st.st_nlink!=1 || fchmod(fd,0600)!=0 || ftruncate(fd,0)!=0) {close(fd);return 0;}
    event_fd=fd; writing=0; active=1;
    for (unsigned i=0;i<COUNT;i++) {
        struct sigaction previous, action;
        if (sigaction(fatal_signals[i],0,&previous)!=0) continue;
        /* Do not interfere with another reporter/guard. Its existing chain
           stays intact. Report coverage for these signals is intentionally absent. */
        if (previous.sa_handler != SIG_DFL) continue;
        memset(&action,0,sizeof action);
        action.sa_sigaction=handler;
        action.sa_flags=SA_SIGINFO;
        sigemptyset(&action.sa_mask);
        for(unsigned j=0;j<COUNT;j++) sigaddset(&action.sa_mask,fatal_signals[j]);
        struct sigaction captured;
        prior[i]=previous; installed[i]=1;
        if(sigaction(fatal_signals[i],&action,&captured)==0) {
            if(captured.sa_handler!=SIG_DFL) {
                (void)sigaction(fatal_signals[i],&captured,0);
                installed[i]=0;
                continue;
            }
            prior[i]=captured;
        } else installed[i]=0;
    }
    return 1;
}
void mirsa_bb_note_exception(void) { if(active) { volatile unsigned char stack_marker=0; persist(0,1,(uintptr_t)&stack_marker); } }
void mirsa_bb_stop(void) {
    active=0;
    for(unsigned i=0;i<COUNT;i++) if(installed[i]) {
        struct sigaction now;
        if(sigaction(fatal_signals[i],0,&now)==0 && (now.sa_flags&SA_SIGINFO) && now.sa_sigaction==handler)
            (void)sigaction(fatal_signals[i],&prior[i],0);
        installed[i]=0;
    }
    if(event_fd>=0)close(event_fd);
    event_fd=-1;
}
