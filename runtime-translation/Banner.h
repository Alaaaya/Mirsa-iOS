// All pending-notice UI and state lives on main. Never interrupt another modal.
static NSString *const BannerText=@"في كم كلمة لسا مو معرّبة. سكّر التطبيق وارجع بعدين، بتتعرّب لحالها";
static UIAlertController *pendingTranslationAlert;
static BOOL bannerShownThisProcess,bannerRendering,bannerPending;
static NSString *BannerPreferenceKey(NSString *bundle) {
 return [@"MirsaTranslationNoticeEver25." stringByAppendingString:bundle?:@""];
}
static BOOL BannerShouldShow(NSUserDefaults *prefs,NSString *bundle,BOOL pending) {
 return pending && ![prefs boolForKey:BannerPreferenceKey(bundle)];
}
// Explicit teardown only. A resolved queue must not dismiss a notice being read.
static void BannerRemove(void) {
 NSCAssert(NSThread.isMainThread,@"main");
 UIAlertController *alert=pendingTranslationAlert;
 pendingTranslationAlert=nil;bannerRendering=NO;
 [alert dismissViewControllerAnimated:NO completion:nil];
}
static void BannerPresentInWindow(UIWindow *window,NSUserDefaults *prefs,NSString *bundle,BOOL pending) {
 NSCAssert(NSThread.isMainThread,@"main");
 bannerPending=pending;
 if(!pending || bannerShownThisProcess || bannerRendering || pendingTranslationAlert ||
    !window || window.hidden || window.alpha<=0 || window.windowLevel!=UIWindowLevelNormal ||
    !BannerShouldShow(prefs,bundle,pending))return;
 if(window.windowScene && window.windowScene.activationState!=UISceneActivationStateForegroundActive)return;
 UIViewController *presenter=window.rootViewController;
 // Do not present over somebody else's modal, even a container child's modal.
 while(presenter){
  if(presenter.presentedViewController || presenter.isBeingPresented || presenter.isBeingDismissed || presenter.transitionCoordinator)return;
  UIViewController *child=nil;
  if([presenter isKindOfClass:UINavigationController.class])child=((UINavigationController *)presenter).visibleViewController;
  else if([presenter isKindOfClass:UITabBarController.class])child=((UITabBarController *)presenter).selectedViewController;
  if(!child || child==presenter)break;
  presenter=child;
 }
 if(!presenter || !presenter.isViewLoaded || presenter.view.window!=window ||
    presenter.view.hidden || presenter.view.alpha<=0)return;
 bannerRendering=YES;BOOL previous=translating;translating=YES;
 @try {
  UIAlertController *alert=[UIAlertController alertControllerWithTitle:nil message:BannerText preferredStyle:UIAlertControllerStyleAlert];
  __weak UIAlertController *weakAlert=alert;
  [alert addAction:[UIAlertAction actionWithTitle:@"موافق" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action){
   NSCAssert(NSThread.isMainThread,@"main");
   // UIKit performs the normal action dismissal. No timer or queue update does.
   if(pendingTranslationAlert==weakAlert){pendingTranslationAlert=nil;bannerRendering=NO;}
  }]];
  alert.view.semanticContentAttribute=UISemanticContentAttributeForceRightToLeft;
  pendingTranslationAlert=alert;
  [presenter presentViewController:alert animated:YES completion:^{
   NSCAssert(NSThread.isMainThread,@"main");
   if(pendingTranslationAlert!=alert)return;
   UIWindow *visibleWindow=alert.viewIfLoaded.window;
   BOOL active=!visibleWindow.windowScene || visibleWindow.windowScene.activationState==UISceneActivationStateForegroundActive;
   if(alert.presentingViewController && visibleWindow==window && !window.hidden && window.alpha>0 &&
      active && !alert.view.hidden && alert.view.alpha>0 &&
      !CGRectIsEmpty(CGRectIntersection([alert.view convertRect:alert.view.bounds toView:window],window.bounds))){
    // Only a completed, actually visible native presentation consumes the notice.
    [prefs setBool:YES forKey:BannerPreferenceKey(bundle)];bannerShownThisProcess=YES;
    bannerRendering=NO;
   } else BannerRemove();
  }];
  // UIKit can reject a presentation without calling its completion.
  if(!alert.presentingViewController && pendingTranslationAlert==alert)BannerRemove();
 } @finally {translating=previous;}
}
static void BannerUpdate(BOOL pending) {
 dispatch_async(dispatch_get_main_queue(),^{
  bannerPending=pending;
  if(!bannerPending)return;
  UIWindow *window=nil;
  for(UIScene *scene in UIApplication.sharedApplication.connectedScenes){
   if(scene.activationState!=UISceneActivationStateForegroundActive || ![scene isKindOfClass:UIWindowScene.class])continue;
   for(UIWindow *candidate in ((UIWindowScene*)scene).windows)
    if(candidate.isKeyWindow && candidate.windowLevel==UIWindowLevelNormal && !candidate.hidden){window=candidate;break;}
   if(window)break;
  }
  BannerPresentInWindow(window,NSUserDefaults.standardUserDefaults,NSBundle.mainBundle.bundleIdentifier,bannerPending);
 });
}
