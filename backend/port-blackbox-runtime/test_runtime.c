#define _POSIX_C_SOURCE 200809L
#include "runtime.h"
#include "breadcrumb.h"
#include <pthread.h>
#include <stdatomic.h>
#include <sched.h>
#include <unistd.h>
#include <fcntl.h>
#include <stdio.h>
#include <signal.h>
#include <sys/wait.h>
#include <sys/stat.h>
#include <stdlib.h>
#include <string.h>
#define CHECK(x) do{if(!(x)){fprintf(stderr,"failed line %d\n",__LINE__);return 1;}}while(0)
static void existing(int s){(void)s;_exit(77);}
static atomic_int ready;
static void *other_active(void *unused){(void)unused;uint32_t t=mirsa_bb_hook_enter(77);atomic_store(&ready,1);while(atomic_load(&ready)==1)sched_yield();mirsa_bb_hook_exit(t);return 0;}
static int breadcrumb_case(const char *path,int mode,uint32_t expected,uint32_t depth){
 pid_t child=fork();CHECK(child>=0);
 if(child==0){
  if(!mirsa_bb_start(path,1))_exit(3);
  uint32_t a=0,b=0;pthread_t thread;
  if(mode==0){a=mirsa_bb_hook_enter(1);b=mirsa_bb_hook_enter(2);}
  if(mode==1){a=mirsa_bb_hook_enter(1);b=mirsa_bb_hook_enter(2);mirsa_bb_hook_exit(b);}
  if(mode==2){for(unsigned i=0;i<33;i++)mirsa_bb_hook_enter(i+1);}
  if(mode==3){if(pthread_create(&thread,0,other_active,0))_exit(8);while(!atomic_load(&ready))sched_yield();}
  if(mode==4){a=mirsa_bb_hook_enter(1);mirsa_bb_hook_exit(a);}
  if(mode==5){a=mirsa_bb_hook_enter(1);b=mirsa_bb_hook_enter(2);mirsa_bb_hook_exit(a);}
  (void)a;(void)b;raise(SIGABRT);_exit(5);
 }
 int status;CHECK(waitpid(child,&status,0)==child);CHECK(WIFSIGNALED(status)&&WTERMSIG(status)==SIGABRT);
 int fd=open(path,O_RDONLY);CHECK(fd>=0);struct mirsa_bb_event e;CHECK(mirsa_bb_read_event(fd,&e));close(fd);unlink(path);
 CHECK(e.hook_index==expected);CHECK(e.hook_depth==depth);return 0;
}
int main(void) {
 char dir[]="/tmp/mirsa-runtime-XXXXXX";CHECK(mkdtemp(dir));
 char path[256],linkpath[256];snprintf(path,sizeof path,"%s/event",dir);
 snprintf(linkpath,sizeof linkpath,"%s/link",dir);
 CHECK(!breadcrumb_case(path,0,2,2));CHECK(!breadcrumb_case(path,1,1,1));
 CHECK(!breadcrumb_case(path,2,0,0));CHECK(!breadcrumb_case(path,3,0,0));
 CHECK(!breadcrumb_case(path,4,0,0));CHECK(!breadcrumb_case(path,5,0,0));
 CHECK(!mirsa_bb_start(path,0));CHECK(access(path,F_OK)!=0);
 CHECK(symlink(path,linkpath)==0);CHECK(!mirsa_bb_start(linkpath,1));unlink(linkpath);
 pid_t pid=fork();CHECK(pid>=0);
 if(pid==0){if(!mirsa_bb_start(path,1))_exit(3);raise(SIGABRT);_exit(4);}
 int status;CHECK(waitpid(pid,&status,0)==pid);CHECK(WIFSIGNALED(status));CHECK(WTERMSIG(status)==SIGABRT);
 int fd=open(path,O_RDONLY);CHECK(fd>=0);struct mirsa_bb_event e;
 CHECK(mirsa_bb_read_event(fd,&e));CHECK(e.signal_number==SIGABRT);CHECK(e.exception==0);close(fd);
 struct stat st;CHECK(stat(path,&st)==0);CHECK((st.st_mode&0777)==0600);unlink(path);
 pid=fork();CHECK(pid>=0);
 if(pid==0){struct sigaction a;memset(&a,0,sizeof a);a.sa_handler=existing;sigemptyset(&a.sa_mask);sigaction(SIGABRT,&a,0);
  if(!mirsa_bb_start(path,1))_exit(3);raise(SIGABRT);_exit(4);}
 CHECK(waitpid(pid,&status,0)==pid);CHECK(WIFEXITED(status)&&WEXITSTATUS(status)==77);
 fd=open(path,O_RDONLY);CHECK(fd>=0);CHECK(!mirsa_bb_read_event(fd,&e));close(fd);unlink(path);
 CHECK(mirsa_bb_start(path,1));mirsa_bb_note_exception();mirsa_bb_note_exception();mirsa_bb_stop();
 fd=open(path,O_RDONLY);CHECK(fd>=0);CHECK(mirsa_bb_read_event(fd,&e));CHECK(e.exception==1&&e.signal_number==0);close(fd);
 fd=open(path,O_WRONLY|O_APPEND);CHECK(fd>=0);CHECK(write(fd,"x",1)==1);close(fd);
 fd=open(path,O_RDONLY);CHECK(!mirsa_bb_read_event(fd,&e));close(fd);unlink(path);
 CHECK(mirsa_bb_start(path,1));mirsa_bb_stop();struct sigaction now;sigaction(SIGABRT,0,&now);CHECK(now.sa_handler==SIG_DFL);
 unlink(path);rmdir(dir);puts("runtime tests passed");return 0;
}
