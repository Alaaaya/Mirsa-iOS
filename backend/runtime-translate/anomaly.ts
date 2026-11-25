import {isIP} from 'node:net';
import {fail} from './logic.mjs';
type Env=(name:string)=>string|undefined;
// Only the immediate transport peer is trusted by default. Arbitrary XFF is ignored.
export function sourceIP(req:Request,peerIP:string|undefined,env:Env) {
 if(!peerIP || !isIP(peerIP)) return null;
 const peers=(env('RUNTIME_TRUSTED_PROXY_PEERS')||'').split(',').map(x=>x.trim());
 const header=env('RUNTIME_TRUSTED_PROXY_IP_HEADER');
 if(!header || !peers.includes(peerIP)) return peerIP;
 const value=req.headers.get(header)||'';
 return isIP(value)?value:null; // no comma splitting, hop guessing or untrusted forwarding
}
export async function anomalyIP(req:Request,peerIP:string|undefined,env:Env) {
 if(env('RUNTIME_IP_AUDIT_ENABLED')!=='true') return null;
 const ip=sourceIP(req,peerIP,env), secret=env('RUNTIME_IP_AUDIT_KEY')||'';
 if(!ip || secret.length<32) fail('ip_audit_unavailable',503);
 const key=await crypto.subtle.importKey('raw',new TextEncoder().encode(secret),{name:'HMAC',hash:'SHA-256'},false,['sign']);
 return Array.from(new Uint8Array(await crypto.subtle.sign('HMAC',key,new TextEncoder().encode(ip!))),b=>b.toString(16).padStart(2,'0')).join('');
}
