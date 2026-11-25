// Pinned staging issuer. This installation claim is NOT physical device binding.
import {SignJWT, jwtVerify, importPKCS8, importSPKI} from 'npm:jose@6.2.18';
import {fail} from './logic.mjs';
const PUBLIC_KEY = `-----BEGIN PUBLIC KEY-----
MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAszNffSzpRV0wgpSs916a
2dB4p+tSYjvS74er3mokWC88GRjUH2KH9vDkGRjN2R5JXGyaH6PPHfN9vN26/7QJ
yupoxDzwZtg8FyG23fuUhbPEacqq8D/xwubSuI0rK2c+t9Wb8RlMkEWnVtE9nJ0j
TJEUDoBz9vwlqhhVhZnshk0b3kpBx7dXBV9itCSkJHVJA4mQs6KdgixDyNKkKuPi
lyuMO54NyRmfk7uAEJ2MyWHj+EB+C+UAljMJt/NVwkRiIJtTTGDQbm5RmUjZPw75
ruQ8CXE5VOHQ1jdUrA4o0QxXv293G84afblAvPCAkHtlXm0EeOiLrUSrMqd9M+io
MwIDAQAB
-----END PUBLIC KEY-----
`;
const publicKey=importSPKI(PUBLIC_KEY,'RS256');
export async function issueActivation(pem: string | undefined, claims: Record<string,string>, now=Date.now(), lifetime=86400) {
 if(!pem) fail('activation_not_configured',503);
 const key=await importPKCS8(pem!,'RS256');
 return await new SignJWT(claims).setProtectedHeader({alg:'RS256',typ:'JWT'})
  .setIssuer('urn:mirsa:translation25').setAudience('mirsa-translated-app')
  .setIssuedAt(Math.floor(now/1000)).setExpirationTime(Math.floor(now/1000)+lifetime)
  .setJti(crypto.randomUUID()).sign(key);
}
export async function verifyActivation(token: string, scope: {bundleId:string,revision:string}, hash: string|null, user:string|null, now=Date.now()) {
 try {
  if(token.length>4096) throw Error();
  const {payload:p}=await jwtVerify(token,await publicKey,{algorithms:['RS256'],issuer:'urn:mirsa:translation25',
   audience:'mirsa-translated-app',requiredClaims:['sub','iat','exp','jti','bundleId','revision','installationId','capHash'],maxTokenAge:'24h',currentDate:new Date(now)});
  if(p.bundleId!==scope.bundleId || p.revision!==scope.revision || (hash!==null && p.capHash!==hash) ||
    (user!==null && p.sub!==user) || Number(p.exp)-Number(p.iat)>86400 ||
    typeof p.installationId!=='string' || !/^[a-f0-9-]{36}$/i.test(p.installationId)) throw Error();
  return p;
 } catch {fail('activation_denied',403);}
}
