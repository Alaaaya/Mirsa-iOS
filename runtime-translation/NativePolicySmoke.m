// Compile/link on iOS simulator and execute via simulator-smoke.sh.
#import "RuntimeTranslate.m"
#import <assert.h>
int main(void) {@autoreleasepool {
 assert(NetworkSafe(@"设置"));
 assert(NetworkSafe(@"设置 %@") && NetworkSafe(@"설정 %lld") && NetworkSafe(@"せってい %.*f"));
 assert(HasCJK(@"せってい") && HasCJK(@"설정") && HasCJK(@"ㄱ"));
 assert(PlaceholdersPreserved(@"设置 %lld %.*f %%",@"الإعدادات %lld %.*f %%"));
 assert(!PlaceholdersPreserved(@"设置 %lld %.*f",@"الإعدادات %.*f %lld"));
 assert(!PlaceholdersPreserved(@"设置 %lld",@"الإعدادات %ld"));
 assert(!PlaceholdersPreserved(@"设置 %.*f",@"الإعدادات %.2f"));
 assert(!PlaceholdersPreserved(@"设置 %%",@"الإعدادات %"));
 assert(PlaceholdersPreserved(@"设置 %1$*2$.*3$f %4$lld",@"الإعدادات %4$lld %1$*2$.*3$f"));
 assert(!PlaceholdersPreserved(@"设置 %1$*2$.*3$f",@"الإعدادات %1$*3$.*2$f"));
 assert(!PlaceholdersPreserved(@"设置 %1$*.*3$f %4$lld",@"الإعدادات %4$lld %1$*.*3$f"));
 assert(!PlaceholdersPreserved(@"<b data='%lld'>设置 %.*f</b>",@"<b data='%.*f'>إعدادات %lld</b>"));
 assert([IsolateLatin(@"قيمة %lld و%.*f و%1$*2$.*3$f %%") isEqual:@"قيمة %lld و%.*f و%1$*2$.*3$f %%"]);

 for(NSString *s in @[@"用户邮件 test@example.com",@"设置 https://example.com",@"设置 /private/test",@"密码 abc",@"订单 123456",@"设置 api_key=abc",@"设置 example.org"]){assert(!NetworkSafe(s));}
 assert([Placeholders(@"النسخة %1$@ %@ %02d {build}") isEqual:Placeholders(@"版本 %1$@ %@ %02d {build}")]);
 assert(![Placeholders(@"版本 %@") isEqual:Placeholders(@"النسخة %d")]);
 NSMutableString *s=[NSMutableString string];
 for(int i=0;i<4095;i++)[s appendString:@"中"];
 [s appendString:@"𠀀"];
 NSString *cut=SafePrefix(s,4096);
 assert(cut.length==4095 && [cut dataUsingEncoding:NSUTF8StringEncoding]);
 assert(HasCJK(@"𠀀") && !HasCJK(@"مرحبا"));
 // Verify permission repair of an existing app-local diagnostic file.
 NSString *dir=[NSHomeDirectory() stringByAppendingPathComponent:@"Documents"];
 [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:NULL];
 NSString *path=[dir stringByAppendingPathComponent:@"MirsaTranslateMissing.txt"];
 [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
 int fd=open(path.fileSystemRepresentation,O_WRONLY|O_CREAT,0644);assert(fd>=0);close(fd);chmod(path.fileSystemRepresentation,0644);
 LogMissing(s,s);dispatch_sync(missingQueue,^{});
 struct stat st;assert(lstat(path.fileSystemRepresentation,&st)==0 && (st.st_mode&0777)==0600);
 NSData *lines=[NSData dataWithContentsOfFile:path];assert(lines.length>0);
 // Symlinks must not be followed or modify the target.
 [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
 NSString *target=[dir stringByAppendingPathComponent:@"MirsaTranslateSmokeTarget"];
 [@"sentinel" writeToFile:target atomically:YES encoding:NSUTF8StringEncoding error:NULL];
 assert(symlink(target.fileSystemRepresentation,path.fileSystemRepresentation)==0);
 LogMissing(@"另一项",@"另一项");dispatch_sync(missingQueue,^{});
 assert([[NSString stringWithContentsOfFile:target encoding:NSUTF8StringEncoding error:NULL] isEqual:@"sentinel"]);
 [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
 [[NSFileManager defaultManager] removeItemAtPath:target error:NULL];
 NSLog(@"Native policy/logger smoke passed");return 0;
}}
