#define _GNU_SOURCE 1
#define _DARWIN_C_SOURCE 1
#include "breadcrumb.h"
#include <pthread.h>
#include <stdatomic.h>
#include <stdlib.h>
#include <limits.h>
#define SLOTS 128
#define DEPTH 32
_Static_assert(ATOMIC_INT_LOCK_FREE==2,"signal path requires lockfree unsigned atomics");
_Static_assert(ATOMIC_POINTER_LOCK_FREE==2,"signal path requires lockfree uintptr");
struct slot { atomic_uint seq,used,hook,depth; _Atomic(uintptr_t) low,high; };
static struct slot slots[SLOTS];
struct local_state { struct slot *slot; uint32_t depth,ids[DEPTH]; unsigned disabled; };
static _Thread_local struct local_state local;
static pthread_key_t key;static pthread_once_t once=PTHREAD_ONCE_INIT;
static int key_ok;
static void release(void *p) {
 struct slot *s=p;
 atomic_fetch_add_explicit(&s->seq,1,memory_order_seq_cst);
 atomic_store_explicit(&s->hook,0,memory_order_seq_cst);
 atomic_store_explicit(&s->low,0,memory_order_seq_cst);
 atomic_store_explicit(&s->high,0,memory_order_seq_cst);
 atomic_fetch_add_explicit(&s->seq,1,memory_order_seq_cst);
 atomic_store_explicit(&s->used,0,memory_order_seq_cst);
}
static void init_key(void){key_ok=pthread_key_create(&key,release)==0;}
static void publish(void) {
 struct slot *s=local.slot;if(!s)return;
 atomic_fetch_add_explicit(&s->seq,1,memory_order_seq_cst);
 atomic_store_explicit(&s->hook,local.depth&&local.depth<=DEPTH&&!local.disabled?local.ids[local.depth-1]:0,memory_order_seq_cst);
 atomic_store_explicit(&s->depth,local.depth,memory_order_seq_cst);
 atomic_fetch_add_explicit(&s->seq,1,memory_order_seq_cst);
}
uint32_t mirsa_bb_hook_enter(uint32_t id) {
 if(!id||local.disabled)return 0;
 if(!local.slot) {
  pthread_once(&once,init_key);if(!key_ok){local.disabled=1;return 0;}
  uintptr_t lo=0,hi=0;
#if defined(__APPLE__)
  hi=(uintptr_t)pthread_get_stackaddr_np(pthread_self());
  size_t size=pthread_get_stacksize_np(pthread_self());if(hi>size)lo=hi-size;
#elif defined(__linux__)
  pthread_attr_t attr;void *addr=0;size_t size=0;
  if(pthread_getattr_np(pthread_self(),&attr)==0){
   if(pthread_attr_getstack(&attr,&addr,&size)==0){lo=(uintptr_t)addr;hi=lo+size;}
   pthread_attr_destroy(&attr);
  }
#endif
  if(!lo||hi<=lo){local.disabled=1;return 0;}
  for(unsigned i=0;i<SLOTS;i++) {
   unsigned expected=0;
   if(atomic_compare_exchange_strong_explicit(&slots[i].used,&expected,1,memory_order_seq_cst,memory_order_seq_cst)){
    struct slot *s=&slots[i];
    atomic_fetch_add_explicit(&s->seq,1,memory_order_seq_cst);
    atomic_store_explicit(&s->low,lo,memory_order_seq_cst);
    atomic_store_explicit(&s->high,hi,memory_order_seq_cst);
    atomic_store_explicit(&s->hook,0,memory_order_seq_cst);
    atomic_store_explicit(&s->depth,0,memory_order_seq_cst);
    atomic_fetch_add_explicit(&s->seq,1,memory_order_seq_cst);
    if(pthread_setspecific(key,s)!=0){release(s);local.disabled=1;return 0;}
    local.slot=s;break;
   }
  }
  if(!local.slot){local.disabled=1;return 0;}
 }
 if(local.depth==UINT32_MAX){local.disabled=1;publish();return 0;}
 ++local.depth;
 if(local.depth<=DEPTH)local.ids[local.depth-1]=id;
 publish();return local.depth;
}
void mirsa_bb_hook_exit(uint32_t token) {
 if(!token)return;
 if(token!=local.depth){local.disabled=1;publish();return;}
 --local.depth;publish();
}
void mirsa_bb_breadcrumb_capture(uintptr_t sp,uint32_t *hook,uint32_t *depth) {
 *hook=0;*depth=0;if(!sp)return;
 unsigned matches=0;uint32_t found=0,nesting=0;
 for(unsigned i=0;i<SLOTS;i++){
  struct slot *s=&slots[i];
  unsigned a=atomic_load_explicit(&s->seq,memory_order_seq_cst);
  if(a&1)continue;
  uintptr_t lo=atomic_load_explicit(&s->low,memory_order_seq_cst),hi=atomic_load_explicit(&s->high,memory_order_seq_cst);
  unsigned used=atomic_load_explicit(&s->used,memory_order_seq_cst);
  uint32_t id=atomic_load_explicit(&s->hook,memory_order_seq_cst),d=atomic_load_explicit(&s->depth,memory_order_seq_cst);
  unsigned b=atomic_load_explicit(&s->seq,memory_order_seq_cst);
  if(a!=b||(b&1))continue;
  if(used&&sp>=lo&&sp<hi){++matches;found=id;nesting=d;}
 }
 if(matches==1&&found&&nesting&&nesting<=DEPTH){*hook=found;*depth=nesting;}
}
