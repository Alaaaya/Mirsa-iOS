// Local-only prefix handling. Never relax DictionarySourceSafe or transmit a date/history.
static BOOL HasLocalHistoryPrefix(NSString *source) {
 if(![source isKindOfClass:NSString.class] || !source.length)return NO;
 // Unknown numeric histories stay local even with leading whitespace/bidi
 // formatting or non-ASCII decimal digits. Only the strict ASCII parser below
 // may opt a finite reviewed template suffix into outgoing missing requests.
 NSCharacterSet *ignorable=[NSCharacterSet.whitespaceAndNewlineCharacterSet mutableCopy];
 NSMutableCharacterSet *leading=[ignorable mutableCopy];
 [leading formUnionWithCharacterSet:NSCharacterSet.controlCharacterSet];
 NSUInteger index=0;
 while(index<source.length && [leading characterIsMember:[source characterAtIndex:index]])index++;
 if(index==source.length)return NO;
 NSRange first=[source rangeOfComposedCharacterSequenceAtIndex:index];
 NSString *character=[source substringWithRange:first];
 return [character rangeOfCharacterFromSet:NSCharacterSet.decimalDigitCharacterSet].location!=NSNotFound;
}
static NSDictionary *LocalTemplateParts(NSString *source) {
 if(!HasLocalHistoryPrefix(source) || source.length>256)return nil;
 static NSRegularExpression *pattern;static NSSet *publicSuffixes;static dispatch_once_t once;
 dispatch_once(&once,^{
  pattern=[NSRegularExpression regularExpressionWithPattern:@"^([0-9]{4}-[0-9]{2}-[0-9]{2} +|[0-9]{1,3}[.)、]? +)([^\\r\\n]+)$" options:0 error:NULL];
  // Exact, reviewed UI vocabulary only. Unknown history suffixes are NOT templates.
  publicSuffixes=[NSSet setWithArray:@[@"一次恢复刷入",@"刷入记录",@"日志",@"应用",@"检查更新",@"有新版",@"清除缓存"]];
 });
 NSTextCheckingResult *match=[pattern firstMatchInString:source options:0 range:NSMakeRange(0,source.length)];
 if(!match || !NSEqualRanges(match.range,NSMakeRange(0,source.length)))return nil;
 NSString *prefix=[source substringWithRange:[match rangeAtIndex:1]],*suffix=[source substringWithRange:[match rangeAtIndex:2]];
 if(![publicSuffixes containsObject:suffix])return nil;
 if(prefix.length>=11 && [prefix characterAtIndex:4]=='-'){
  NSInteger year=[[prefix substringWithRange:NSMakeRange(0,4)] integerValue];
  NSInteger month=[[prefix substringWithRange:NSMakeRange(5,2)] integerValue];
  NSInteger day=[[prefix substringWithRange:NSMakeRange(8,2)] integerValue];
  if(year<1900 || year>2199 || month<1 || month>12 || day<1 || day>31)return nil;
  NSCalendar *calendar=[[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
  calendar.timeZone=[NSTimeZone timeZoneForSecondsFromGMT:0];
  NSDateComponents *parts=[NSDateComponents new];parts.year=year;parts.month=month;parts.day=day;
  NSDate *date=[calendar dateFromComponents:parts];
  if(!date)return nil;
  NSDateComponents *check=[calendar components:NSCalendarUnitYear|NSCalendarUnitMonth|NSCalendarUnitDay fromDate:date];
  if(check.year!=year || check.month!=month || check.day!=day)return nil;
 }
 return @{@"prefix":prefix,@"source":suffix};
}
