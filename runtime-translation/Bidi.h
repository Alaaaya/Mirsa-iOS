// Isolate Latin/version runs only in newly translated Arabic. Skip all pre-existing
// directional-isolate ranges and printf/template placeholders byte-for-byte.
static NSString *IsolateLatin(NSString *s) {
 if([s rangeOfCharacterFromSet:[NSCharacterSet characterSetWithRange:NSMakeRange(0x600,0x100)]].location==NSNotFound)return s;
 static NSRegularExpression *runs;static dispatch_once_t once;
 dispatch_once(&once,^{
  runs=[NSRegularExpression regularExpressionWithPattern:@"[A-Za-z0-9]+(?:[._+\\-][A-Za-z0-9]+)*(?:[ ][A-Za-z0-9]+(?:[._+\\-][A-Za-z0-9]+)*)*" options:0 error:NULL];

 });
 NSMutableIndexSet *skip=[NSMutableIndexSet indexSet];
 NSUInteger depth=0,begin=0;
 for(NSUInteger i=0;i<s.length;i++){
  unichar c=[s characterAtIndex:i];
  if(c>=0x2066 && c<=0x2068){if(!depth)begin=i;depth++;}
  else if(c==0x2069 && depth && --depth==0)[skip addIndexesInRange:NSMakeRange(begin,i-begin+1)];
 }
 if(depth)[skip addIndexesInRange:NSMakeRange(begin,s.length-begin)];
 for(NSTextCheckingResult *m in [TokenRegex() matchesInString:s options:0 range:NSMakeRange(0,s.length)])[skip addIndexesInRange:m.range];
 NSMutableString *out=[s mutableCopy];
 for(NSTextCheckingResult *m in [[runs matchesInString:s options:0 range:NSMakeRange(0,s.length)] reverseObjectEnumerator]){
  if([skip intersectsIndexesInRange:m.range])continue;
  NSString *word=[s substringWithRange:m.range];
  [out replaceCharactersInRange:m.range withString:[NSString stringWithFormat:@"\u2066%@\u2069",word]];
 }
 return out;
}
