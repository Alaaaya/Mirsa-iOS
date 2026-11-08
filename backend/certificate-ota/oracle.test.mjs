import {test} from "node:test";
import assert from "node:assert/strict";
import {createHmac,webcrypto} from "node:crypto";
import {oracleSession,ORACLE_MAX_BYTES} from "./oracle.mjs";
globalThis.crypto??=webcrypto;
const meta={bundleID:"com.example.app",version:"1.0",title:"Test & <app>",bytes:2147483648};
test("Oracle capability signs exact metadata with bounded lifetime and no client secret",async()=>{
 const secret="fixture-secret-not-real".repeat(3);
 const r=await oracleSession(meta,"11111111-1111-4111-8111-111111111111",secret,12345);
 assert.equal(r.maxChunkBytes,8388608); assert.match(r.uploadURL,/^https:\/\/mirsa-app\.mooo\.com\/ota\/sessions\/[a-f0-9]{32}$/);
 const [p,s]=r.uploadToken.split(".");assert.equal(createHmac("sha256",secret).update(p).digest("base64url"),s);
 const body=JSON.parse(Buffer.from(p,"base64url"));assert.equal(body.exp-body.iat,900);assert.equal(body.aud,"mirsa-ota-upload");assert.deepEqual(body.metadata,meta);
 assert.equal(r.expiresAt,new Date((12345+900)*1000).toISOString());assert.ok(!JSON.stringify(r).includes(secret));
});
test("Oracle fails closed on excess size, secrets fields and missing server key",async()=>{
 for(const bytes of [0,ORACLE_MAX_BYTES+1,NaN,1.1])await assert.rejects(oracleSession({...meta,bytes},"u","s".repeat(32)));
 await assert.rejects(oracleSession({...meta,password:"bad"},"u","s".repeat(32)));
 await assert.rejects(oracleSession(meta,"u",undefined));
});
