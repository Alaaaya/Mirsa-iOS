import { validateMetadata } from "./contract.mjs";
export const ORACLE_MAX_BYTES = 2 * 1024 ** 3;
const b64 = bytes => btoa(String.fromCharCode(...bytes)).replaceAll("+","-").replaceAll("/","_").replace(/=+$/,"");
export async function oracleSession(raw, owner, secret, now = Math.floor(Date.now()/1000)) {
 if(typeof secret!=="string" || secret.length<32) throw Error("oracle_unconfigured");
 if(!raw || !Number.isSafeInteger(raw.bytes) || raw.bytes<4 || raw.bytes>ORACLE_MAX_BYTES) throw Error("size");
 const metadata={...validateMetadata({...raw,bytes:4}),bytes:raw.bytes};
 const sid=Array.from(crypto.getRandomValues(new Uint8Array(16)), b=>b.toString(16).padStart(2,"0")).join("");
 const payload=b64(new TextEncoder().encode(JSON.stringify({aud:"mirsa-ota-upload",sid,sub:owner,iat:now,exp:now+900,metadata})));
 const key=await crypto.subtle.importKey("raw",new TextEncoder().encode(secret),{name:"HMAC",hash:"SHA-256"},false,["sign"]);
 const signature=b64(new Uint8Array(await crypto.subtle.sign("HMAC",key,new TextEncoder().encode(payload))));
 return {uploadURL:"https://mirsa-app.mooo.com/ota/sessions/"+sid,uploadToken:payload+"."+signature,maxChunkBytes:8388608,expiresAt:new Date((now+900)*1000).toISOString()};
}
