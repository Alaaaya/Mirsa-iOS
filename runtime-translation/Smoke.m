#import <UIKit/UIKit.h>
#import <CoreText/CoreText.h>
#import <dlfcn.h>
#import <assert.h>
#import "Tokens.h"
#import "Bidi.h"
static void check(NSString *s,NSString *expect){if(![s isEqualToString:expect]){NSLog(@"Expected %@ got %@",expect,s);abort();}}
int main(int argc,char **argv){@autoreleasepool{
 check(IsolateLatin(@"iOS 27.0.1 (البنية 24A446)"),@"\u2066iOS 27.0.1\u2069 (البنية \u206624A446\u2069)");
 check(IsolateLatin(@"الإصدار %1$@ و%d و{build}"),@"الإصدار %1$@ و%d و{build}");
 check(IsolateLatin(IsolateLatin(@"بناء App Group 24A446")),IsolateLatin(@"بناء App Group 24A446"));
 assert(PlaceholdersPreserved(@"设置 %lld %.*f %%",@"إعدادات %lld %.*f %%"));
 assert(!PlaceholdersPreserved(@"设置 %lld %.*f",@"إعدادات %.*f %lld"));
 check(IsolateLatin(@"قيمة %lld و%.*f و%1$*2$.*3$f %%"),@"قيمة %lld و%.*f و%1$*2$.*3$f %%");
 assert(argc==2);void*h=dlopen(argv[1],RTLD_NOW);if(!h){fprintf(stderr,"%s",dlerror());return 2;}
 UILabel*l=[UILabel new];l.text=@"取消";check(l.text,@"إلغاء");
 l.attributedText=[[NSAttributedString alloc]initWithString:@"确定" attributes:@{NSForegroundColorAttributeName:UIColor.redColor}];check(l.attributedText.string,@"تأكيد");
 UIButton*b=[UIButton new];[b setTitle:@"设置" forState:UIControlStateNormal];check([b titleForState:UIControlStateNormal],@"الإعدادات");
 UITextField*f=[UITextField new];f.placeholder=@"取消";check(f.placeholder,@"إلغاء");
 UINavigationItem*n=[UINavigationItem new];n.title=@"确定";check(n.title,@"تأكيد");
 UITabBarItem*t=[UITabBarItem new];t.title=@"设置";check(t.title,@"الإعدادات");
 UIAlertController*a=[UIAlertController alertControllerWithTitle:@"确定" message:@"取消" preferredStyle:UIAlertControllerStyleAlert];check(a.title,@"تأكيد");check(a.message,@"إلغاء");
 UIAlertAction*aa=[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil];check(aa.title,@"إلغاء");
 l.text=@"Unmatched harmless text";check(l.text,@"Unmatched harmless text");l.text=nil;assert(l.text==nil||l.text.length==0);
 for(int i=0;i<5000;i++){l.text=@"设置";check(l.text,@"الإعدادات");}
 NSAttributedString*cs=[[NSAttributedString alloc]initWithString:@"取消"];CTLineRef line=CTLineCreateWithAttributedString((__bridge CFAttributedStringRef)cs);assert(line);CFRelease(line);
 NSLog(@"Runtime translation simulator smoke checks passed");return 0;
}}
