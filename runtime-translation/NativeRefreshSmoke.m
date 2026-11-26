// Real UIKit objects and real asynchronous main-queue dictionary merge.
// No provider, private signing key, live service, or user content.
#define MIRSA_RUNTIME_TESTING 1
#import "RuntimeTranslate.m"
#import <assert.h>
static NSTimeInterval fixtureTime=2000000010;
static NSTimeInterval FixtureNow(void){return fixtureTime;}
static void Spin(NSTimeInterval seconds){
 NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:seconds];
 while(deadline.timeIntervalSinceNow>0)[NSRunLoop.currentRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
}
static NSDictionary *Entry(NSString *source,NSString *value,NSUInteger version){
 return @{@"source":source,@"translation":value,@"provenance":@"kat",@"version":@(version)};
}
static void ResetMaps(void){
 onlinePositive=[NSMutableDictionary dictionary];onlineMeta=[NSMutableDictionary dictionary];
 onlineNegative=[NSMutableDictionary dictionary];onlinePending=[NSMutableSet set];onlineUncovered=[NSMutableSet set];
 onlineAttempts=[NSMutableDictionary dictionary];onlineIssued=0;onlineWaiting=0;onlineBudgetStart=0;onlineAttemptStart=0;
 onlineDenied=NO;onlineFlushScheduled=NO;onlineFlushRunning=NO;onlineFlushGeneration++;onlineFlushDeadline=0;onlineRefreshScheduled=NO;onlineRefreshAttempt=0;
 [cache removeAllObjects];
}
int main(int argc,char **argv){@autoreleasepool{
 assert(argc==2);(void)argv;
 enabled=YES;table=@{};pieces=@{};rules=@[];cache=[NSCache new];cache.countLimit=2048;
 ResetMaps();onlineConfig=nil;
 HookString(UILabel.class,@selector(setText:));HookAttr(UILabel.class,@selector(setAttributedText:));
 HookButton(@selector(setTitle:forState:),NO);HookButton(@selector(setAttributedTitle:forState:),YES);
 HookString(UINavigationItem.class,@selector(setTitle:));
 // A label rendered BEFORE the asynchronous answer changes without another setter from the host.
 UILabel *label=[UILabel new];label.text=@"晚到设置";assert([label.text isEqual:@"晚到设置"]);
 UILabel *attributed=[UILabel new];
 attributed.attributedText=[[NSAttributedString alloc] initWithString:@"晚到说明" attributes:@{NSForegroundColorAttributeName:UIColor.redColor}];
 UIButton *button=[UIButton new];[button setTitle:@"晚到按钮" forState:UIControlStateNormal];
 UINavigationItem *navigation=[UINavigationItem new];navigation.title=@"晚到标题";
 dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT,0),^{
  ApplyOnlineEntries(@[Entry(@"晚到设置",@"الإعدادات الجديدة",2),Entry(@"晚到说明",@"شرح جديد",2),
   Entry(@"晚到按钮",@"زر جديد",2),Entry(@"晚到标题",@"عنوان جديد",2)]);
 });
 Spin(0.3);
 assert([label.text isEqual:@"الإعدادات الجديدة"]);
 assert([attributed.attributedText.string isEqual:@"شرح جديد"]);
 assert([[attributed.attributedText attribute:NSForegroundColorAttributeName atIndex:0 effectiveRange:NULL] isEqual:UIColor.redColor]);
 assert([[button titleForState:UIControlStateNormal] isEqual:@"زر جديد"]);
 assert([navigation.title isEqual:@"عنوان جديد"]);
 // Repeated approved versions use the ORIGINAL CJK, never try to translate existing Arabic.
 ApplyOnlineEntries(@[Entry(@"晚到设置",@"خيارات محدثة",3),Entry(@"晚到说明",@"شرح محدث",3)]);
 Spin(0.2);assert([label.text isEqual:@"خيارات محدثة"] && [attributed.attributedText.string isEqual:@"شرح محدث"]);
 ApplyOnlineEntries(@[Entry(@"晚到设置",@"نسخة قديمة",1)]);Spin(0.1);assert([label.text isEqual:@"خيارات محدثة"]);
 label.text=@"تعديل المستخدم";ApplyOnlineEntries(@[Entry(@"晚到设置",@"تحديث آخر",4)]);Spin(0.1);
 assert([label.text isEqual:@"تعديل المستخدم"]); // host changes replace old snapshots
 // Clearing source snapshots remains cleared.
 attributed.attributedText=nil;ReapplyTranslations();Spin(0.1);assert(!attributed.attributedText.length);
 // Local date/number roundtrip. Outgoing candidate is ONLY the exact reviewed UI suffix.
 assert(!DictionarySourceSafe(@"2026-11-10 一次恢复刷入"));
 NSDictionary *parts=LocalTemplateParts(@"2026-11-10 一次恢复刷入");
 assert([parts[@"prefix"] isEqual:@"2026-11-10 "] && [parts[@"source"] isEqual:@"一次恢复刷入"]);
 assert(NetworkSafe(parts[@"source"]) && !HasLocalHistoryPrefix(parts[@"source"]));
 assert(!LocalTemplateParts(@"2026-02-30 一次恢复刷入"));
 assert(LocalTemplateParts(@"2024-02-29 一次恢复刷入"));
 for(NSString *private in @[@"2026-11-10 聊天记录",@"2026-11-10 Alice 账户",@"12 私人日记",@"12 密码",@"2026-11-10 一次恢复刷入 https://private.invalid",
  @"２０２６-11-10 一次恢复刷入",@"2026-11-10 一次恢复刷入\n秘密",@"2026-11-10 一次恢复刷入 Alice"]){
  assert(!LocalTemplateParts(private));assert(HasLocalHistoryPrefix(private));
  assert([Translate(private) isEqual:private]);
 }
 ApplyOnlineEntries(@[Entry(@"一次恢复刷入",@"استعادة التفليش مرة واحدة",2)]);Spin(0.1);
 assert([Translate(@"2026-11-10 一次恢复刷入") isEqual:@"2026-11-10 استعادة التفليش مرة واحدة"]);
 assert([Translate(@"12. 一次恢复刷入") isEqual:@"12. استعادة التفليش مرة واحدة"]);
 ApplyOnlineEntries(@[Entry(@"2026-11-10 一次恢复刷入",@"لا يجوز قبول هذا",4)]);
 assert(!OnlineLookup(@"2026-11-10 一次恢复刷入"));
 // Actual outgoing queue observes only the suffix, including when no translation is cached.
 ResetMaps();onlineClock=FixtureNow;onlineTestActivationBundle=@"com.example.activationfixture";
 onlineConfig=[NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:@(argv[1])] options:0 error:NULL];
 onlineQueue=dispatch_queue_create("mirsa.refresh.no-network",DISPATCH_QUEUE_SERIAL);
 // Suspend before queuing so tests can inspect the ACTUAL network candidates without any HTTP.
 dispatch_suspend(onlineQueue);
 assert([Translate(@"2026-11-10 一次恢复刷入") isEqual:@"2026-11-10 一次恢复刷入"]);
 for(NSString *private in @[@"2026-11-10 Alice 聊天",@"12 私人日记",@"2026-11-10 一次恢复刷入 Alice"])Translate(private);
 assert(onlinePending.count==1 && [onlinePending containsObject:@"一次恢复刷入"]);
 // A fresh label replaces a delayed timer, while stale callbacks retain an obsolete generation.
 os_unfair_lock_lock(&onlineLock);
 onlineFlushScheduled=NO;onlineFlushDeadline=0;
 ScheduleOnlineFlushLocked(900);NSUInteger oldGeneration=onlineFlushGeneration;
 ScheduleOnlineFlushLocked(0.15);assert(onlineFlushGeneration>oldGeneration && onlineFlushDeadline<fixtureTime+1);
 NSUInteger currentGeneration=onlineFlushGeneration;
 ScheduleOnlineFlushLocked(900);assert(onlineFlushGeneration==currentGeneration);
 os_unfair_lock_unlock(&onlineLock);
 // Rolling budget resets instead of poisoning a process lifetime.
 onlineIssued=128;onlineBudgetStart=fixtureTime;ResetOnlineBudgetLocked(fixtureTime+59);assert(onlineIssued==128);
 ResetOnlineBudgetLocked(fixtureTime+60);assert(onlineIssued==0);
 assert(OnlineBackoff(1)==60 && OnlineBackoff(2)==300 && OnlineBackoff(3)==900);
 onlineAttempts[@"重试按钮"]=@4;onlineAttemptStart=fixtureTime;
 ResetOnlineBudgetLocked(fixtureTime+899);assert(onlineAttempts.count==1);
 ResetOnlineBudgetLocked(fixtureTime+900);assert(!onlineAttempts.count);
 // Generic legacy403 cannot prove authenticated revocation; signed expiry still fails closed.
 assert(OnlineUsable());fixtureTime=2000086401;assert(!OnlineUsable());
 NSLog(@"Native async UIKit reapply, source preservation, private date templates, rolling budgets and expiry passed");
 // Suspended fixture queue deliberately dies with this isolated test process; zero network calls.
 return 0;
}}
