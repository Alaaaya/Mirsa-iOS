// Pure helpers for mirsa-ar-localize (no I/O). Shared contract with ArabicIPALocalizer.swift.
export const MAX_ITEMS = 1500, MAX_TEXT = 2000, MAX_TOTAL = 150_000, MAX_ID = 300;
export const BUNDLE_RE = /^[A-Za-z0-9]([A-Za-z0-9.\-]{0,126}[A-Za-z0-9])?$/;
export const HASH_RE = /^[0-9a-f]{64}$/;
// Tokens that must survive translation unchanged (as a multiset): printf-style, %%, {braces}, ${x}, <tags>, escapes.
const TOKEN_RE = /%#@\w+@|%(?:\d+\$)?[-+ 0#']*(?:\d+|\*)?(?:\.(?:\d+|\*))?(?:hh|h|ll|l|q|L|z|t|j)?[@diouxXeEfFgGaAcCsSp]|%%|\$\{[^}]*\}|\{\{[^}]*\}\}|\{[^{}]*\}|<\/?[A-Za-z][^<>]*>|\\[nrt]/g;
export const tokens = (s) => (String(s).match(TOKEN_RE) ?? []).slice().sort();
export function sameTokens(a, b) {
  const x = tokens(a), y = tokens(b);
  return x.length === y.length && x.every((v, i) => v === y[i]);
}
// A translation is acceptable when non-empty, bounded, token-multiset identical, and not just an echo of control chars.
export function acceptable(src, out) {
  if (typeof out !== "string") return false;
  const t = out.trim();
  if (!t || t.length > MAX_TEXT * 2) return false;
  if (/[\u0000-\u0008\u000B\u000C\u000E-\u001F]/.test(t)) return false;
  return sameTokens(src, out);
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
