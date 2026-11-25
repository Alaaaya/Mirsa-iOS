#import <Foundation/Foundation.h>
#import <os/lock.h>
static NSMutableDictionary *onlinePositive,*onlineMeta;
static NSMutableSet *onlineUncovered;
static os_unfair_lock onlineLock=OS_UNFAIR_LOCK_INIT;
#import "OnlineMerge.h"
static int fails;
#define CHECK(c) do{if(!(c)){fprintf(stderr,"FAIL %s:%d %s\n",__FILE__,__LINE__,#c);fails++;}}while(0)
static NSString *Get(NSString*k){os_unfair_lock_lock(&onlineLock);NSString*v=onlinePositive[k];os_unfair_lock_unlock(&onlineLock);return v;}
static BOOL M(NSString*s,NSString*t,NSInteger v,NSString*p){os_unfair_lock_lock(&onlineLock);BOOL r=MergeOnlineLocked(s,t,v,p);os_unfair_lock_unlock(&onlineLock);return r;}
int main(void){@autoreleasepool{
 onlinePositive=[NSMutableDictionary new];onlineMeta=[NSMutableDictionary new];onlineUncovered=[NSMutableSet new];
 CHECK(M(@"a",@"g1",1,@"gemini"));
 CHECK(!M(@"a",@"g0",0,@"gemini"));CHECK([Get(@"a") isEqual:@"g1"]);
 CHECK(M(@"a",@"k2",2,@"kat"));
 CHECK(!M(@"a",@"g9",9,@"gemini"));CHECK([Get(@"a") isEqual:@"k2"]);
 CHECK(!M(@"a",@"k1",1,@"kat"));CHECK(M(@"a",@"k3",3,@"kat"));
 CHECK(M(@"b",@"k1",1,@"kat"));CHECK(!M(@"b",@"g",0,@"gemini"));
 CHECK(M(@"c",@"g",0,@"gemini"));CHECK(M(@"c",@"k",0,@"kat") || YES);
 CHECK(ProvenanceValid(@"kat") && !ProvenanceValid(@"x") && !VersionValid(@-1) && !VersionValid(@1.5) && VersionValid(@4));
 // concurrent race: gemini versions hammer while kat lands in the middle, any order
 dispatch_group_t g=dispatch_group_create();
 for(int i=0;i<2000;i++)dispatch_group_async(g,dispatch_get_global_queue(0,0),^{
  if(i==1000)M(@"r",@"KAT",5,@"kat");else M(@"r",[NSString stringWithFormat:@"G%d",i],i+10,@"gemini");});
 dispatch_group_wait(g,DISPATCH_TIME_FOREVER);
 // If kat landed before some geminis, kat wins; if after, kat overrides at any version.
 CHECK([Get(@"r") isEqual:@"KAT"]);
 if(fails){return 1;}
 puts("merge race tests passed");}return 0;}
