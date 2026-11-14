import test from "node:test";
import assert from "node:assert/strict";
import { stagedLayout, validatePlan } from "./staged.mjs";
const id = "11111111-1111-1111-1111-111111111111";
const valid = () => ({version:1,parallaxStrength:0,clockArea:"none",layers:[{id,role:"background",zoom:1,x:0,y:0,crop:true}]});
const body = {action:"wallpaper-layout",version:1,description:"put foreground below clock",photos:[{id,width:120,height:200}],capabilities:{parallaxStrength:0,segmentation:false}};
test("strict valid plan",()=>assert.deepEqual(validatePlan(JSON.stringify(valid()),[id]),valid()));
test("reject unknown keys, invalid IDs, duplicate/missing order, transforms, types and URLs",()=>{
  const mutations=[p=>p.url="https://example.com",p=>p.version=true,p=>p.parallaxStrength=.3,p=>p.clockArea="eval()",
    p=>p.layers[0].zoom=5,p=>p.layers[0].x=true,p=>p.layers[0].y=-2,p=>p.layers[0].crop=1,
    p=>p.layers[0].id="file:///x",p=>p.layers[0].role="evil",p=>p.layers.push(p.layers[0]),p=>p.layers=[],
    p=>p.layers[0].code="exec"];
  for(const mutate of mutations){const p=valid(); mutate(p);assert.throws(()=>validatePlan(JSON.stringify(p),[id]));}
  assert.throws(()=>validatePlan(" ".repeat(16385),[id]));
});
test("default off and unauthenticated never call model",async()=>{
  for(const context of [{},{ownerEnabled:true},{ownerEnabled:true,authenticated:true,rateLimitGranted:true,freeTextOnly:false}]){
    let called=false; const result=await stagedLayout(body,{...context,runExistingFreeText:async()=>{called=true;}});
    assert.equal(result.status,503);assert.equal(called,false);
  }
});
test("existing free TEXT lane only, no image API, invalid/unavailable fallback",async()=>{
  const context={ownerEnabled:true,authenticated:true,rateLimitGranted:true,freeTextOnly:true,
    runExistingFreeText:async args=>{assert.equal(args.allowPaid,false);assert.equal(args.imageGeneration,false);assert.equal(args.maxTokens,1800);return JSON.stringify(valid());}};
  assert.equal((await stagedLayout(body,context)).status,200);
  assert.equal((await stagedLayout({...body,photos:[...body.photos,...body.photos]},context)).status,400);
  assert.equal((await stagedLayout(body,{...context,runExistingFreeText:async()=> '{"url":"https://example.com"}'})).status,503);
  assert.equal((await stagedLayout(body,{...context,runExistingFreeText:async()=> {throw Error("quota");}})).status,503);
});
