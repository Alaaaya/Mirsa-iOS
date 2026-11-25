// Disposable test-only durable relay base. Exercises the real translation extension, no callbacks.
import {DatabaseSync} from 'node:sqlite';
import {timingSafeEqual} from 'node:crypto';
export const equal=(a,b)=>{const x=Buffer.from(a||''),y=Buffer.from(b||'');return x.length===y.length&&timingSafeEqual(x,y);};
export class Service {
 constructor({dbPath,token,hookToken}) {
  this.token=token;this.hookToken=hookToken;this.db=new DatabaseSync(dbPath);
  this.db.exec('create table if not exists events(id text primary key,body text not null,acknowledged integer not null default 0,created integer not null);');
 }
 persist(data,name,eventId) {
  this.db.prepare('insert or ignore into events(id,body,created) values(?,?,?)').run(eventId,JSON.stringify({eventId,name,data}),Date.now());
  return {eventId};
 }
 async drain(){}
 handler(){return async(req,res)=>{
  if(req.url!='/mcp'||!equal(req.headers.authorization,'Bearer '+this.token)){res.writeHead(401);res.end();return;}
  let chunks=[];for await(const c of req)chunks.push(c);
  const p=JSON.parse(Buffer.concat(chunks));const result=await this.rpc(p.method,p.params);
  res.writeHead(200,{'content-type':'application/json'});res.end(JSON.stringify({jsonrpc:'2.0',id:p.id,result}));
 };}
 async rpc(){return {tools:[]};}
}
