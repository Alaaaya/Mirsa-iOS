// The staging service reads/verifies the CURRENT Mirsa account. It never signs up,
// changes Auth settings, creates a production account, or trusts a decoded JWT.
import {createClient} from 'npm:@supabase/supabase-js@2.106.2';
import {jwtVerify,decodeJwt} from 'npm:jose@6.2.18';
const project='https://hirebeofomiyumwysppj.supabase.co';
const publicKey='sb_publishable_o3dt8riPdpZHazjpPgG25Q_HgGfnub5';
export async function verifyStagingAccount(token:string,secret:Uint8Array,deadline:AbortSignal,
    getUser?:(token:string)=>Promise<any>) {
 try {
  if(token.length>4096) throw Error();
  const claims=decodeJwt(token); // Routing only, NOT authorization.
  if(claims.iss==='urn:mirsa:runtime-staging25') {
   const {payload}=await jwtVerify(token,secret,{algorithms:['HS256'],issuer:'urn:mirsa:runtime-staging25',
    audience:'mirsa-runtime-staging25',requiredClaims:['sub','iat','exp','jti'],maxTokenAge:'1h'});
   if(payload.sub!=='eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee' || payload.scope!=='runtime:bootstrap' ||
      Number(payload.exp)-Number(payload.iat)>3600) throw Error();
   return {data:{user:{id:payload.sub}},error:null};
  }
  if(claims.iss!==project+'/auth/v1' || claims.aud!=='authenticated') throw Error();
  // Pinned origin/public key, no caller-controlled URL and no persistence/refresh/signup.
  const verify=getUser ?? ((jwt:string)=>createClient(project,publicKey,{auth:{persistSession:false,autoRefreshToken:false},
    global:{fetch:(input,init)=>fetch(input,{...init,signal:deadline,redirect:'error'})}}).auth.getUser(jwt));
  const result=await verify(token);
  if(result.error || !result.data?.user || result.data.user.id!==claims.sub ||
     !/^[a-f0-9-]{36}$/i.test(result.data.user.id) ||
     Number(claims.exp)*1000<=Date.now()) throw Error();
  return {data:{user:{id:result.data.user.id}},error:null};
 } catch {return {data:{user:null},error:true};}
}
