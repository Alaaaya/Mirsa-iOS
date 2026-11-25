#import <UIKit/UIKit.h>
static void showAlert(void){
  UIWindow *win=nil;
  for(UIScene *s in UIApplication.sharedApplication.connectedScenes){
    if([s isKindOfClass:UIWindowScene.class]){ for(UIWindow *w in ((UIWindowScene*)s).windows){ if(w.isKeyWindow){win=w;break;} } if(!win) win=((UIWindowScene*)s).windows.firstObject; }
    if(win) break;
  }
  UIViewController *vc=win.rootViewController;
  while(vc.presentedViewController) vc=vc.presentedViewController;
  if(!vc){ dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(1*NSEC_PER_SEC)),dispatch_get_main_queue(),^{showAlert();}); return; }
  UIAlertController *a=[UIAlertController alertControllerWithTitle:@"علاء" message:nil preferredStyle:UIAlertControllerStyleAlert];
  [a addAction:[UIAlertAction actionWithTitle:@"تمام" style:UIAlertActionStyleDefault handler:nil]];
  [vc presentViewController:a animated:YES completion:nil];
}
__attribute__((constructor)) static void init(void){
  [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n){
    static dispatch_once_t once; dispatch_once(&once,^{ dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(1.5*NSEC_PER_SEC)),dispatch_get_main_queue(),^{showAlert();}); });
  }];
}
