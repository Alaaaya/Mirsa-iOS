// Exact patterns and argument-order policy from ArabicIPALocalizer.swift.
static NSRegularExpression *PrintfRegex(void) {
 static NSRegularExpression *re;static dispatch_once_t once;
 dispatch_once(&once,^{re=[NSRegularExpression regularExpressionWithPattern:@"%(?:\\d+\\$)?#@\\w+@|%(?:\\d+\\$)?[-+ 0#']*(?:\\d+|\\*(?:\\d+\\$)?)?(?:\\.(?:\\d+|\\*(?:\\d+\\$)?))?(?:hh|h|ll|l|q|L|z|t|j)?[@diDuUoOxXeEfFgGaAcCsSpn]|%%" options:0 error:NULL];});return re;
}
static NSRegularExpression *TokenRegex(void) {
 static NSRegularExpression *re;static dispatch_once_t once;
 dispatch_once(&once,^{re=[NSRegularExpression regularExpressionWithPattern:[PrintfRegex().pattern stringByAppendingString:@"|\\$\\{[^}]*\\}|\\{\\{[^}]*\\}\\}|\\{[^{}]*\\}|</?[A-Za-z][^<>]*>|\\\\[nrt]"] options:0 error:NULL];});return re;
}
static NSArray *MatchedTokens(NSRegularExpression *re,NSString *s,BOOL arguments) {
 NSMutableArray *tokens=[NSMutableArray array];
 for(NSTextCheckingResult *m in [re matchesInString:s options:0 range:NSMakeRange(0,s.length)]){
  NSString *t=[s substringWithRange:m.range];if(!arguments || ![t isEqual:@"%%"])[tokens addObject:t];
 }return tokens;
}
static NSArray *Placeholders(NSString *s) {
 return [MatchedTokens(TokenRegex(),s,NO) sortedArrayUsingSelector:@selector(compare:)];
}
static BOOL PlaceholdersPreserved(NSString *source,NSString *translated) {
 if(![Placeholders(source) isEqual:Placeholders(translated)])return NO;
 NSArray *a=MatchedTokens(PrintfRegex(),source,YES),*b=MatchedTokens(PrintfRegex(),translated,YES);
 if(![[a sortedArrayUsingSelector:@selector(compare:)] isEqual:[b sortedArrayUsingSelector:@selector(compare:)]])return NO;
 static NSRegularExpression *explicit,*implicitStar;static dispatch_once_t once;
 dispatch_once(&once,^{
  explicit=[NSRegularExpression regularExpressionWithPattern:@"^%[1-9][0-9]*\\$" options:0 error:NULL];
  implicitStar=[NSRegularExpression regularExpressionWithPattern:@"\\*(?![1-9][0-9]*\\$)" options:0 error:NULL];
 });
 for(NSString *arg in a){
  if(![explicit firstMatchInString:arg options:0 range:NSMakeRange(0,arg.length)] ||
    [implicitStar firstMatchInString:arg options:0 range:NSMakeRange(0,arg.length)])return [a isEqual:b];
 }return YES;
}
