// Pure helpers for mirsa-ar-localize (no I/O). Shared contract with ArabicIPALocalizer.swift.
export const MAX_ITEMS = 1500, MAX_TEXT = 2000, MAX_TOTAL = 150_000, MAX_ID = 300;
export const BUNDLE_RE = /^[A-Za-z0-9]([A-Za-z0-9.\-]{0,126}[A-Za-z0-9])?$/;
export const HASH_RE = /^[0-9a-f]{64}$/;
// Tokens that must survive translation unchanged (as a multiset): printf-style, %%, {braces}, ${x}, <tags>, escapes.
const PRINTF_RE = /%(?:\d+\$)?#@\w+@|%(?:\d+\$)?[-+ 0#']*(?:\d+|\*(?:\d+\$)?)?(?:\.(?:\d+|\*(?:\d+\$)?))?(?:hh|h|ll|l|q|L|z|t|j)?[@diDuUoOxXeEfFgGaAcCsSpn]|%%/g;
const TOKEN_RE = new RegExp(PRINTF_RE.source + String.raw`|\$\{[^}]*\}|\{\{[^}]*\}\}|\{[^{}]*\}|<\/?[A-Za-z][^<>]*>|\\[nrt]`, "g");
export const tokens = (s) => (String(s).match(TOKEN_RE) ?? []).slice().sort();
export function sameTokens(a, b) {
  const x = tokens(a), y = tokens(b);
  if (x.length !== y.length || !x.every((v, i) => v === y[i])) return false;
  // Ignore %% (consumes no argument). Require original order if any conversion
  // or dynamic width/precision uses an implicit argument, including named plurals.
  const args = (s) => (s.match(PRINTF_RE) ?? []).filter(t => t !== "%%");
  const source = args(a), translated = args(b);
  const orderedSource = source.slice().sort(), orderedTranslation = translated.slice().sort();
  if (orderedSource.length !== orderedTranslation.length || orderedSource.some((v, i) => v !== orderedTranslation[i])) return false;
  const explicit = t => /^%[1-9][0-9]*\$/.test(t) && !/\*(?![1-9][0-9]*\$)/.test(t);
  return source.every(explicit) || source.every((v, i) => v === translated[i]);
}
// A translation is acceptable when non-empty, bounded, token-multiset identical, and not just an echo of control chars.
export function acceptable(src, out) {
  if (typeof out !== "string") return false;
  const t = out.trim();
  if (!t || t.length > MAX_TEXT * 2) return false;
  if (/[\u0000-\u0008\u000B\u000C\u000E-\u001F]/.test(t)) return false;
  return sameTokens(src, out);
}
// A genuine Arabic translation: placeholders intact, actually Arabic, and
// different from the source. An echo of the English source is NOT a translation:
// it used to pass `acceptable`, get cached, and get written into ar.lproj as an
// "Arabic" value (Reloc shipped 240 English values that way). Keep `acceptable`
// itself a pure placeholder validator: its unit tests assert token-only cases.
export const hasArabic = (s) => /[\u0600-\u06FF\u0750-\u077F\u08A0-\u08FF\uFB50-\uFDFF\uFE70-\uFEFF]/.test(String(s));
export function isRealTranslation(src, out) {
  if (!acceptable(src, out)) return false;
  const t = String(out).trim();
  return t !== String(src).trim() && hasArabic(t);
}
export function validateRequest(b) {
  if (!b || typeof b !== "object") return "bad_body";
  if (typeof b.bundleId !== "string" || !BUNDLE_RE.test(b.bundleId)) return "bad_bundle";
  if (typeof b.version !== "string" || b.version.length < 1 || b.version.length > 64 || /[\u0000-\u001F]/.test(b.version)) return "bad_version";
  if (typeof b.contentHash !== "string" || !HASH_RE.test(b.contentHash)) return "bad_hash";
  if (!Array.isArray(b.items) || b.items.length < 1 || b.items.length > MAX_ITEMS) return "bad_items";
  let total = 0; const seen = new Set();
  for (const it of b.items) {
    if (!it || typeof it.id !== "string" || typeof it.text !== "string") return "bad_item";
    if (it.id.length < 1 || it.id.length > MAX_ID || seen.has(it.id)) return "bad_item";
    if (it.text.length < 1 || it.text.length > MAX_TEXT) return "bad_item";
    seen.add(it.id); total += it.text.length + it.id.length;
    if (total > MAX_TOTAL) return "too_large";
  }
  return null;
}
export function parseModelMap(text) {
  const m = String(text).match(/\{[\s\S]*\}/);
  if (!m) return null;
  try { const o = JSON.parse(m[0]); return o && typeof o === "object" && !Array.isArray(o) ? o : null; } catch { return null; }
}
export const chunk = (arr, n) => { const o = []; for (let i = 0; i < arr.length; i += n) o.push(arr.slice(i, i + n)); return o; };

// Bind cache entries to the actual requested English strings, not just an untrusted client hash.
export async function cacheHash(contentHash, items) {
  const canonical = [...items].sort((a, b) => a.id < b.id ? -1 : a.id > b.id ? 1 : 0).map(({ id, text }) => [id, text]);
  const bytes = new TextEncoder().encode(JSON.stringify([contentHash, canonical]));
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return Array.from(new Uint8Array(digest), (v) => v.toString(16).padStart(2, "0")).join("");
}
// Never claim a cache hit if any requested string is absent, corrupt or has different placeholders.
// An echoed (untranslated) cached value is not a hit either: it must be re-translated, not served.
export function completeCachedTranslations(items, translations) {
  if (!translations || typeof translations !== "object" || Array.isArray(translations)) return null;
  const out = Object.create(null);
  for (const it of items) {
    if (!Object.hasOwn(translations, it.id) || !isRealTranslation(it.text, translations[it.id])) return null;
    out[it.id] = translations[it.id];
  }
  return out;
}
