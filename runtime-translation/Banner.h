// All banner state lives on main. A UILabel cannot steal touches from the host.
static NSString *const BannerText=@"في كم كلمة لسه مو معرّبة، ارجع للتطبيق بعد كم دقيقة وبتتعرّب";
static UILabel *pendingBanner;
static BOOL bannerShownThisProcess,bannerRendering;
static NSString *BannerPreferenceKey(NSString *bundle) {
 return [@"MirsaTranslationNoticeEver25." stringByAppendingString:bundle?:@""];
}
static BOOL BannerShouldShow(NSUserDefaults *prefs,NSString *bundle,BOOL pending) {
 return pending && ![prefs boolForKey:BannerPreferenceKey(bundle)];
}
static void BannerRemove(void) {NSCAssert(NSThread.isMainThread,@"main");[pendingBanner removeFromSuperview];pendingBanner=nil;}
static void BannerPresentInWindow(UIWindow *window,NSUserDefaults *prefs,NSString *bundle,BOOL pending) {
 NSCAssert(NSThread.isMainThread,@"main");
 if(!pending){BannerRemove();return;}
 if(bannerShownThisProcess || bannerRendering || !window || window.hidden || window.alpha<=0 ||
    !BannerShouldShow(prefs,bundle,pending))return;
 bannerRendering=YES;BOOL previous=translating;translating=YES;
 @try {
  UILabel *label=[UILabel new];label.userInteractionEnabled=NO;
  label.text=BannerText;label.numberOfLines=0;label.textAlignment=NSTextAlignmentNatural;
  label.semanticContentAttribute=UISemanticContentAttributeForceRightToLeft;
  label.font=[UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];label.adjustsFontForContentSizeCategory=YES;
  label.textColor=UIColor.whiteColor;label.backgroundColor=[UIColor colorWithWhite:0.08 alpha:0.94];
  label.layer.cornerRadius=12;label.clipsToBounds=YES;label.translatesAutoresizingMaskIntoConstraints=NO;
  [window addSubview:label];pendingBanner=label;
  UILayoutGuide *safe=window.safeAreaLayoutGuide;
  [NSLayoutConstraint activateConstraints:@[
    [label.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:16],
    [label.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-16],
    [label.topAnchor constraintEqualToAnchor:safe.topAnchor constant:8],
    [label.heightAnchor constraintLessThanOrEqualToAnchor:safe.heightAnchor multiplier:0.25]]];
  [window layoutIfNeeded];
  if(label.window && !label.hidden && label.alpha>0 && !CGRectIsEmpty(CGRectIntersection(label.frame,window.bounds))){
   // Persist only after an actual visible attachment, never on mere detection.
   [prefs setBool:YES forKey:BannerPreferenceKey(bundle)];bannerShownThisProcess=YES;
   dispatch_after(dispatch_time(DISPATCH_TIME_NOW,5*NSEC_PER_SEC),dispatch_get_main_queue(),^{if(pendingBanner==label)BannerRemove();});
  } else BannerRemove();
 } @finally {translating=previous;bannerRendering=NO;}
}
static void BannerUpdate(BOOL pending) {
 dispatch_async(dispatch_get_main_queue(),^{
  if(!pending){BannerRemove();return;}
  UIWindow *window=nil;
  for(UIScene *scene in UIApplication.sharedApplication.connectedScenes){
   if(scene.activationState!=UISceneActivationStateForegroundActive || ![scene isKindOfClass:UIWindowScene.class])continue;
   for(UIWindow *candidate in ((UIWindowScene*)scene).windows)
    if(candidate.isKeyWindow && candidate.windowLevel==UIWindowLevelNormal && !candidate.hidden){window=candidate;break;}
   if(window)break;
  }
  BannerPresentInWindow(window,NSUserDefaults.standardUserDefaults,NSBundle.mainBundle.bundleIdentifier,pending);
 });
}
