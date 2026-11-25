// Test-only Deno preload. Never imported by any application/server module.
// Intercepts the exact provider origin with an explicitly fake credential, no network fallback.
const path=Deno.env.get('RUNTIME_E2E_PROVIDER_OUTPUTS');
if(!path?.startsWith('/home/kit/queue25-proof-'))throw Error('isolated fixture required');
const original=globalThis.fetch;
globalThis.fetch=async(input:RequestInfo|URL,init?:RequestInit):Promise<Response>=>{
 const url=typeof input==='string'?new URL(input):input instanceof URL?input:new URL(input.url);
 if(url.origin!=='https://generativelanguage.googleapis.com')return await original(input,init);
 if(url.pathname!=='/v1beta/openai/chat/completions'||new Headers(init?.headers).get('authorization')!=='Bearer isolated-fixture-not-a-key')throw Error('fixture request escaped its provider contract');
 const body=JSON.parse(String(init?.body));
 if(body.model!=='gemini-2.5-flash')throw Error('wrong model');
 const requested=JSON.parse(body.messages.at(-1).content);
 const answers=JSON.parse(await Deno.readTextFile(path));
 const out=Object.fromEntries(Object.entries(requested).filter(([,text])=>Object.hasOwn(answers,String(text))).map(([id,text])=>[id,answers[String(text)]]));
 return Response.json({model:'gemini-2.5-flash',choices:[{message:{content:JSON.stringify(out)}}]});
};
