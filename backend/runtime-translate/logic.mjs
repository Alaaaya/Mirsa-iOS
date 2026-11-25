import { BUNDLE_RE, HASH_RE, acceptable, parseModelMap } from '../ar-localize/logic.mjs';
export { parseModelMap };
export class Fault extends Error { constructor(code, status = 400) { super(code); this.status = status; } }
export const fail = (code, status) => { throw new Fault(code, status); };
export const byteLength = s => new TextEncoder().encode(s).length;
export function safeText(s) {
  return typeof s === 'string' && s.trim().length > 0 && s.length <= 1024 &&
    !/[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f\u202a-\u202e\u2066-\u2069]/u.test(s) &&
    !/(?:https?:|www\.|mailto:|[\w.+-]+@[\w.-]+|\b[a-z0-9-]+\.(?:com|net|org|de|io|app)\b|(?:\d[\s().+-]*){7}|(?:bearer|password|passwd|secret|api[_ -]?key|token|address|phone|email|iban|ssn|姓名|身份证|手机号|密码|邮箱|住址)\s*[:=：]|(?:sk-|eyJ)[a-zA-Z0-9_-]{12}|[a-zA-Z0-9_+/=-]{40,}|(?:\/Users\/|\/home\/|file:\/\/))/iu.test(s);
}
export function validate(body) {
  if (!body || typeof body !== 'object' || Array.isArray(body)) fail('bad_body');
  if (!['issue','dictionary','missing'].includes(body.action)) fail('bad_action');
  const keys = ['action','bundleId','revision','consent',...(body.action === 'issue' ? [] : ['items'])];
  if (Object.keys(body).some(k => !keys.includes(k))) fail('bad_fields');
  if (typeof body.bundleId !== 'string' || !BUNDLE_RE.test(body.bundleId) || !body.bundleId.includes('.')) fail('bad_bundle');
  if (typeof body.revision !== 'string' || !HASH_RE.test(body.revision)) fail('bad_revision');
  if (body.consent !== true) fail('consent_required',403);
  if (body.action === 'issue') return { ...body, chars: 0 };
  const runtime = body.action === 'missing', maxItems = runtime ? 16 : 128, maxTotal = runtime ? 2048 : 8192;
  if (!Array.isArray(body.items) || !body.items.length || body.items.length > maxItems) fail('bad_items');
  const ids = new Set(); let chars = 0;
  for (const item of body.items) {
    if (!item || Object.keys(item).some(k => !['id','text'].includes(k)) || typeof item.id !== 'string' || !/^[A-Za-z0-9_-]{1,64}$/.test(item.id) || ids.has(item.id)) fail('bad_item');
    ids.add(item.id);
    if (!safeText(item.text) || item.text.length > 256) fail('unsafe_text');
    if (runtime && !/[\u3040-\u30ff\u3400-\u9fff\uac00-\ud7af\uf900-\ufaff]/u.test(item.text)) fail('not_cjk');
    chars += item.text.length;
  }
  if (chars > maxTotal) fail('too_large',413);
  return { ...body, chars };
}
export function scopeAllowed(cap, body, now = Date.now()) {
  return !!cap && cap.revoked === false && cap.bundle_id === body.bundleId && cap.revision === body.revision &&
    Number.isFinite(Date.parse(cap.expires_at)) && Date.parse(cap.expires_at) > now;
}
export function filterTranslations(items, map) {
  const result = Object.create(null);
  if (!map || typeof map !== 'object' || Array.isArray(map)) return result;
  for (const {id,text} of items) {
    const out = Object.hasOwn(map,id) ? map[id] : undefined;
    if (typeof out === 'string' && safeText(out) && acceptable(text,out) && /[\u0600-\u06ff]/u.test(out) &&
      !/[\u3400-\u9fff]/u.test(out)) result[id] = out.trim();
  }
  return result;
}
export function providerConfig(env) {
  const model = env('RUNTIME_LLM_MODEL'), key = env('RUNTIME_LLM_API_KEY'), base = env('RUNTIME_LLM_BASE_URL');
  const allowed = (env('RUNTIME_STRONG_MODELS') || '').split(',').map(x=>x.trim()).filter(Boolean);
  const origins = (env('RUNTIME_PROVIDER_ORIGINS') || '').split(',').map(x=>x.trim());
  let url; try { url = new URL(base); } catch { fail('not_configured',503); }
  if (!model || !key || !allowed.includes(model) || /(?:lite|mini|nano|flash|small|weak)/i.test(model) ||
      url.protocol !== 'https:' || url.username || url.password || url.search || url.hash || !origins.includes(url.origin)) fail('not_configured',503);
  return { model, key, url: url.href.replace(/\/$/,'') + '/chat/completions' };
}
export async function readBounded(stream, max, signal) {
  if (!stream) fail('bad_body');
  const reader = stream.getReader(); let size = 0; const parts = [];
  const abort = () => { void reader.cancel().catch(()=>{}); };
  signal?.addEventListener('abort',abort,{once:true});
  try {
    while (true) {
      if (signal?.aborted) fail('timeout',503);
      const {done,value} = await reader.read();
      if (signal?.aborted) fail('timeout',503);
      if(done) break;
      size += value.byteLength; if(size > max) { await reader.cancel(); fail('too_large',413); }
      parts.push(value);
    }
    const data = new Uint8Array(size); let at = 0;
    for (const part of parts) { data.set(part,at); at += part.length; }
    return new TextDecoder('utf-8',{fatal:true}).decode(data);
  } finally { signal?.removeEventListener('abort',abort); reader.releaseLock(); }
}
export async function digest(token) {
  return Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',new TextEncoder().encode(token))),x=>x.toString(16).padStart(2,'0')).join('');
}
export function newToken() { return 'mrt1.' + Array.from(crypto.getRandomValues(new Uint8Array(32)),x=>x.toString(16).padStart(2,'0')).join(''); }
