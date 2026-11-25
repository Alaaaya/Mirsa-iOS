#import <Foundation/Foundation.h>
#import <os/lock.h>
// Requires onlinePositive, onlineMeta, onlineUncovered, onlineLock declared before inclusion.
// Monotonic merge, atomic under the lock. Kat-approved text is never replaced by Gemini,
// regardless of arrival order (cached, in-flight, late). Gemini only wins with a strictly newer version.
// Caller holds onlineLock.
static BOOL MergeOnlineLocked(NSString *source,NSString *value,NSInteger version,NSString *prov) {
 NSDictionary *old=onlineMeta[source];
 BOOL newKat=[prov isEqual:@"kat"];
 if(old){
  BOOL oldKat=[old[@"p"] isEqual:@"kat"];NSInteger ov=[old[@"v"] integerValue];
  if(oldKat && !newKat)return NO;
  if(oldKat==newKat && version<=ov)return NO;
  if(oldKat && newKat && version<=ov)return NO;
 }
 if(!onlinePositive[source] && onlinePositive.count>=2048)return NO;
 onlinePositive[source]=value;onlineMeta[source]=@{@"v":@(version),@"p":newKat?@"kat":@"gemini"};
 [onlineUncovered removeObject:source];return YES;
}
static BOOL ProvenanceValid(id p){return [p isEqual:@"kat"] || [p isEqual:@"gemini"];}
static BOOL VersionValid(id v){return [v isKindOfClass:NSNumber.class] && [v doubleValue]>=0 && [v doubleValue]<=9007199254740991.0 && floor([v doubleValue])==[v doubleValue];}
