import {createHash} from 'node:crypto';
const sha=s=>createHash('sha256').update(s).digest('hex');
const IDENT='[A-Za-z_][A-Za-z0-9_]*';
function mask(source) {
 return source.replace(/\/\/[^\n]*|\/\*[\s\S]*?\*\/|@?"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'/g,
  v=>v.replace(/[^\n]/g,' '));
}
export function instrumentHooks(source,expectedSourceSHA256) {
 if(sha(source)!==expectedSourceSHA256||Buffer.byteLength(source)>196608)throw Error('source_changed');
 const body=mask(source);
 if(/#|__mirsa_bb_|%((?!hook\b|end\b|orig\b)[A-Za-z_]+)|\b(setjmp|longjmp|asm|__asm__|naked|co_return)\b/.test(body))
  throw Error('instrumentation_unsupported');
 const hookRE=new RegExp('^[ \\t]*%hook[ \\t]+('+IDENT+')[ \\t]*$','gm');
 const edits=[],hooks=[];let m,cursor=0;
 while((m=hookRE.exec(body))) {
  if(body.slice(cursor,m.index).trim())throw Error('instrumentation_unsupported');
  const end=body.indexOf('%end',hookRE.lastIndex);
  if(end<0)throw Error('instrumentation_unsupported');
  const text=body.slice(hookRE.lastIndex,end);
  let offset=0;
  while(offset<text.length) {
   while(/\s/.test(text[offset]??'')&&offset<text.length)offset++;
   if(offset===text.length)break;
   const rest=text.slice(offset);
   const head=/^([+-])\s*\(\s*([A-Za-z_][A-Za-z0-9_ *<>]*)\s*\)\s*([^{;]+)\{/.exec(rest);
   if(!head)throw Error('instrumentation_unsupported');
   const signature=head[3].trim();
   let selector;
   if(new RegExp('^'+IDENT+'$').test(signature))selector=signature;
   else {
    const param=new RegExp('('+IDENT+')\\s*:\\s*\\(\\s*[A-Za-z_][A-Za-z0-9_ *<>]*\\)\\s*'+IDENT+'\\s*','g');
    let x,at=0,names=[];
    while((x=param.exec(signature))){if(x.index!==at)throw Error('instrumentation_unsupported');names.push(x[1]+':');at=param.lastIndex;}
    if(at!==signature.length||!names.length)throw Error('instrumentation_unsupported');
    selector=names.join('');
   }
   const open=hookRE.lastIndex+offset+head[0].length-1;
   let pos=open+1,depth=1;
   for(;pos<end&&depth;pos++){if(body[pos]==='{')depth++;else if(body[pos]==='}')depth--;}
   if(depth)throw Error('instrumentation_unsupported');
   const close=pos-1,index=hooks.length+1;
   hooks.push({hookIndex:index,className:m[1],selector,kind:head[1],sourceSHA256:expectedSourceSHA256});
   edits.push([open+1,'\nuint32_t __mirsa_bb_token_'+index+'=mirsa_bb_hook_enter('+index+');\n@try {\n'],
    [close,'\n} @finally { mirsa_bb_hook_exit(__mirsa_bb_token_'+index+'); }\n']);
   offset=pos-hookRE.lastIndex;
  }
  cursor=end+4;hookRE.lastIndex=cursor;
 }
 if(body.slice(cursor).trim()||!hooks.length||hooks.length>2048)throw Error('instrumentation_unsupported');
 let code=source;for(const [at,value]of edits.sort((a,b)=>b[0]-a[0]))code=code.slice(0,at)+value+code.slice(at);
 code='#include "breadcrumb.h"\n'+code;
 const manifest={schema:1,sourceSHA256:expectedSourceSHA256,evidence:'active-on-interrupted-thread-not-cause',hooks};
 return {code,manifest,manifestSHA256:sha(JSON.stringify(manifest)),originalSourceSHA256:expectedSourceSHA256,instrumentedSHA256:sha(code)};
}
