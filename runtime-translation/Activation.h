// Offline signature + account/app/revision/capability binding, NOT physical device proof.
#import <Security/Security.h>
#import <CommonCrypto/CommonDigest.h>
#import "ActivationKey.h"
static NSData *ActivationDecode(NSString *s) {
 if(![s isKindOfClass:NSString.class] || s.length>4096)return nil;
 NSString *b=[[s stringByReplacingOccurrencesOfString:@"-" withString:@"+"] stringByReplacingOccurrencesOfString:@"_" withString:@"/"];
 while(b.length%4)b=[b stringByAppendingString:@"="];
 return [[NSData alloc] initWithBase64EncodedString:b options:0];
}
static NSString *ActivationHash(NSString *s) {
 unsigned char hash[CC_SHA256_DIGEST_LENGTH];NSData *d=[s dataUsingEncoding:NSUTF8StringEncoding];
 CC_SHA256(d.bytes,(CC_LONG)d.length,hash);NSMutableString *out=[NSMutableString string];
 for(unsigned int i=0;i<sizeof(hash);i++)[out appendFormat:@"%02x",hash[i]];return out;
}
static BOOL ValidActivation(NSDictionary *c,NSString *bundle,NSTimeInterval now) {
 NSString *jwt=c[@"activation"];if(![jwt isKindOfClass:NSString.class] || jwt.length>4096)return NO;
 NSArray *parts=[jwt componentsSeparatedByString:@"."];if(parts.count!=3)return NO;
 NSData *h=ActivationDecode(parts[0]),*p=ActivationDecode(parts[1]),*sig=ActivationDecode(parts[2]);
 if(!h || !p || !sig)return NO;
 id header=[NSJSONSerialization JSONObjectWithData:h options:0 error:NULL];
 id claims=[NSJSONSerialization JSONObjectWithData:p options:0 error:NULL];
 if(![header isKindOfClass:NSDictionary.class] || ![claims isKindOfClass:NSDictionary.class] ||
   ![header[@"alg"] isEqual:@"RS256"] || header[@"crit"] ||
   ![claims[@"iss"] isEqual:@"urn:mirsa:translation25"] || ![claims[@"aud"] isEqual:@"mirsa-translated-app"] ||
   ![claims[@"bundleId"] isEqual:bundle] || ![claims[@"revision"] isEqual:c[@"revision"]] ||
   ![claims[@"installationId"] isEqual:c[@"installationId"]] ||
   ![claims[@"sub"] isKindOfClass:NSString.class] || ![claims[@"sub"] length] ||
   ![claims[@"capHash"] isEqual:ActivationHash(c[@"token"])] ||
   ![claims[@"exp"] isKindOfClass:NSNumber.class] || ![claims[@"iat"] isKindOfClass:NSNumber.class] ||
   [claims[@"exp"] doubleValue]<=now || [claims[@"iat"] doubleValue]>now+30 ||
   [claims[@"exp"] doubleValue]-[claims[@"iat"] doubleValue]>86400)return NO;
 NSData *keyData=[NSData dataWithBytes:activation_key length:sizeof(activation_key)];
 SecKeyRef key=SecKeyCreateWithData((__bridge CFDataRef)keyData,(__bridge CFDictionaryRef)@{
   (__bridge id)kSecAttrKeyType:(__bridge id)kSecAttrKeyTypeRSA,
   (__bridge id)kSecAttrKeyClass:(__bridge id)kSecAttrKeyClassPublic,
   (__bridge id)kSecAttrKeySizeInBits:@2048},NULL);
 if(!key)return NO;
 NSData *message=[[NSString stringWithFormat:@"%@.%@",parts[0],parts[1]] dataUsingEncoding:NSUTF8StringEncoding];
 BOOL ok=SecKeyVerifySignature(key,kSecKeyAlgorithmRSASignatureMessagePKCS1v15SHA256,(__bridge CFDataRef)message,(__bridge CFDataRef)sig,NULL);
 CFRelease(key);return ok;
}
