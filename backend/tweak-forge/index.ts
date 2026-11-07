import { createClient } from "npm:@supabase/supabase-js@2.106.2";
import { cleanupStorage } from "./cleanup.ts";
import { isExpired, TEMP_TTL_MS, JOB_TTL_MS, MAX_DYLIB_BYTES, MAX_GALLERY_PER_USER, MAX_PROMPT, validateLogos, validateSettings, validateName, validateBundleID, assembleSource, parseModelJSON, classify429, retryDelayMs, seal, b64, unb64 } from "./contract.mjs";

const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false } });
const LLM_URL = Deno.env.get("LLM_BASE_URL") ?? "https://generativelanguage.googleapis.com/v1beta/openai";
// Fail-closed: provider calls only when the key is attested free-tier (owner attestation, not independently verified).
const FREE_ATTESTED = Deno.env.get("GEMINI_FREE_TIER_ATTESTED") === "owner-attested-2026-11-07";
const LLM_KEY = FREE_ATTESTED ? (Deno.env.get("LLM_API_KEY") ?? Deno.env.get("GEMINI_API_KEY")) : undefined;
const LLM_MODEL = Deno.env.get("LLM_MODEL") ?? "gemini-3.5-flash-lite";
const FLASH_MODEL = Deno.env.get("LLM_FALLBACK_MODEL") ?? "gemini-3.5-flash";
const num = (k: string, d: number) => Number(Deno.env.get(k) ?? d);
// Free-tier ceilings (Flash-Lite 15 RPM / 500 RPD, Flash 5 RPM / 20 RPD) minus headroom; every provider request is counted.
const TIERS = [
  { tier: "lite", model: LLM_MODEL, day: num("FORGE_LITE_DAY", 400), min: num("FORGE_LITE_MIN", 10) },
  { tier: "flash", model: FLASH_MODEL, day: num("FORGE_FLASH_DAY", 6), min: num("FORGE_FLASH_MIN", 4) },
];
const USER_DAY = num("FORGE_USER_DAY", 60);
class Quota extends Error { constructor(public kind: "daily" | "busy", public retry = 0) { super(kind); } }
const LIMITS: Record<string, number> = { translate: 30, generate: 20, build: 20, publish: 5 }; // per hour per user
const H = { "cache-control": "no-store", "x-content-type-options": "nosniff" };
const json = (d: unknown, s = 200) => new Response(JSON.stringify(d), { status: s, headers: { ...H, "content-type": "application/json" } });

async function user(req: Request) {
  const a = req.headers.get("authorization") ?? "";
  if (!/^Bearer [A-Za-z0-9._-]+$/.test(a)) return null;
  const { data, error } = await db.auth.getUser(a.slice(7));
  return !error && data.user ? data.user : null;
}
async function allow(uid: string, action: string) {
  const since = new Date(Date.now() - 3600_000).toISOString();
  const { count } = await db.from("mirsa_forge_usage").select("id", { count: "exact", head: true }).eq("user_id", uid).eq("action", action).gte("created_at", since);
  if ((count ?? 0) >= LIMITS[action]) return false;
  await db.from("mirsa_forge_usage").insert({ user_id: uid, action });
  return true;
}
const DEV_CAP: Record<string, number> = { generate: num("FORGE_DEV_GEN", 5), translate: num("FORGE_DEV_TR", 10) };
const IP_CAP: Record<string, number> = { generate: num("FORGE_IP_GEN", 15), translate: num("FORGE_IP_TR", 30) }; // 3x one device: shared Wi-Fi/NAT headroom
const MAX_DEV_PER_USER = num("FORGE_MAX_DEV", 2);
async function sha(s: string) { return [...new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(s)))].map((b) => b.toString(16).padStart(2, "0")).join(""); }
// Only the gateway-set cf-connecting-ip is trusted (client-sent X-Forwarded-For is ignored). Salt rotates daily so hashes expire.
async function ipHash(req: Request) {
  const ip = req.headers.get("cf-connecting-ip") ?? "unknown";
  const day = new Date().toLocaleDateString("en-CA", { timeZone: "America/Los_Angeles" });
  return await sha((Deno.env.get("IP_SALT") ?? "") + "|" + day + "|" + ip);
}
async function gate(req: Request, uid: string, action: string): Promise<string> {
  const device = req.headers.get("x-mirsa-device") ?? "";
  if (!/^[0-9a-f-]{36}$/.test(device)) return "bad_device";
  const { data, error } = await db.rpc("mirsa_forge_gate", { p_device: device, p_user: uid, p_iph: await ipHash(req), p_action: action, p_dev_cap: DEV_CAP[action], p_ip_cap: IP_CAP[action], p_max_dev: MAX_DEV_PER_USER });
  if (error) return "gate_error";
  return String(data);
}
async function llm(system: string, userText: string, maxTokens: number, uid: string) {
  if (!LLM_KEY) throw Error("llm_not_configured");
  let ti = 0, calls = 0, tempRetries = 0, serverRetries = 0;
  while (calls < 4) {
    const T = TIERS[ti];
    // Atomic server-side reservation (user daily cap, tier RPD, tier RPM). Nothing reaches the provider unless it is granted.
    const { data: res, error } = await db.rpc("mirsa_forge_reserve", { p_user: uid, p_tier: T.tier, p_user_day: USER_DAY, p_tier_day: T.day, p_tier_min: T.min });
    if (error) throw Error("quota_db");
    if (res === "user_day" || res === "tier_day") throw new Quota("daily");
    if (res === "busy") { if (tempRetries++ >= 1) throw new Quota("busy", 15); await new Promise((r) => setTimeout(r, 6000)); continue; }
    calls++;
    const r = await fetch(LLM_URL + "/chat/completions", {
      method: "POST", headers: { authorization: "Bearer " + LLM_KEY, "content-type": "application/json" },
      body: JSON.stringify({ model: T.model, temperature: 0.2, max_tokens: maxTokens, messages: [{ role: "system", content: system }, { role: "user", content: userText }] }),
    });
    if (r.ok) { const t = (await r.json()).choices?.[0]?.message?.content ?? ""; if (t) return t; throw Error("llm_unavailable"); }
    const txt = await r.text();
    if (r.status === 429) {
      if (classify429(txt) === "daily") { await db.rpc("mirsa_forge_flag", { p_tier: T.tier }); throw new Quota("daily"); }
      // Temporary RPM limit: wait the provider's retry delay once, same model, never fall back to the scarcer one.
      if (tempRetries++ >= 1) throw new Quota("busy", 15);
      await new Promise((res2) => setTimeout(res2, retryDelayMs(r.headers.get("retry-after"), txt)));
      continue;
    }
    if (r.status === 500 || r.status === 503) {
      if (serverRetries++ < 1) { await new Promise((res2) => setTimeout(res2, 1500)); continue; }
      if (ti === 0) { ti = 1; serverRetries = 0; continue; } // Flash only when Lite itself is failing
      throw Error("llm_unavailable");
    }
    throw Error("llm_failed");
  }
  throw Error("llm_unavailable");
}
const LANGS: Record<string, string> = { ar: "Arabic", ckb: "Sorani Kurdish", kmr: "Kurmanji Kurdish (Latin script)", en: "English" };

async function translate(body: any, uid: string) {
  const lang = LANGS[body.target]; const items = body.items;
  if (!lang || !Array.isArray(items) || items.length === 0 || items.length > 120) return json({ error: "bad_request" }, 400);
  const clean = items.map((i: any) => ({ k: String(i.k).slice(0, 200), v: String(i.v).slice(0, 600) }));
  const sys = "Translate UI strings of an iOS app into " + lang + ". Keep format specifiers (%@ %d %1$@ etc), placeholders in braces, newlines, and HTML/markup unchanged. Do not translate brand names. Reply ONLY with JSON object mapping each key to its translation.";
  const out = await llm(sys, JSON.stringify(clean), 6000, uid);
  const m = out.match(/\{[\s\S]*\}/); if (!m) return json({ error: "model_json" }, 502);
  const parsed = JSON.parse(m[0]); const result: Record<string, string> = {};
  for (const i of clean) if (typeof parsed[i.k] === "string" && parsed[i.k].length < 1500) result[i.k] = parsed[i.k];
  return json({ translations: result });
}
async function generate(body: any, uid: string) {
  const prompt = String(body.prompt ?? "").slice(0, MAX_PROMPT);
  const classes = Array.isArray(body.classes) ? body.classes.filter((c: unknown) => typeof c === "string" && /^[A-Za-z_][A-Za-z0-9_.$]{0,80}$/.test(c)).slice(0, 400) : [];
  if (!prompt || !validateBundleID(body.bundleID) || !validateName(body.name)) return json({ error: "bad_request" }, 400);
  const sys = "You write iOS tweaks in Theos Logos for ONE target app. Reply ONLY JSON: {\"code\": string, \"settings\": [{\"key\",\"title\",\"default\"(bool)}], \"explain\": string}. "
    + "code contains ONLY %hook/%end blocks (no %ctor, no %group, no #include of absolute paths). Use only classes from the provided list. "
    + "Optional user toggles are compile-time macros MIRSA_SETTING_<key> (0/1), e.g. if (MIRSA_SETTING_dark) {...}; max 8, keys lowercase [a-z0-9_]. "
    + "Forbidden: networking, process spawning, dlopen/dlsym, asm, deleting files, keychain access. Keep it simple and safe. Previous version, if any, is provided: modify it.";
  const user = JSON.stringify({ app: body.bundleID, classes, previousCode: body.previousCode ?? null, request: prompt });
  const o = parseModelJSON(await llm(sys, user, 4000, uid));
  const bad = validateLogos(o.code);
  if (bad || !validateSettings(o.settings)) return json({ error: "unsafe_or_invalid_code", detail: bad }, 422);
  return json({ code: o.code, settings: o.settings, explain: String(o.explain ?? "").slice(0, 600) });
}
const BUCKET = "mirsa-ota-private";
const GH_REPO = Deno.env.get("GH_BUILDER_REPO");
const GH_TOKEN = Deno.env.get("GH_DISPATCH_TOKEN");
const BSECRET = Deno.env.get("BUILDER_SECRET");
const hex32 = (v: unknown) => typeof v === "string" && /^[0-9a-f]{32}$/.test(v);
function builderReady() { return !!(GH_REPO && GH_TOKEN && BSECRET); }
// Build = dispatch an ephemeral GitHub Actions run in a separate public repo. Only an opaque job id goes to GitHub.
async function build(body: any, uid: string) {
  if (!builderReady()) return json({ error: "builder_not_configured" }, 503);
  if (!validateName(body.name) || !validateBundleID(body.bundleID) || !/^[0-9a-f-]{36}$/.test(String(body.id)) || !validateSettings(body.settings ?? [])) return json({ error: "bad_request" }, 400);
  const bad = validateLogos(body.code); if (bad) return json({ error: "unsafe_or_invalid_code", detail: bad }, 422);
  const source = assembleSource({ id: body.id, bundleID: body.bundleID, code: body.code, settings: body.settings ?? [], values: body.values ?? {} });
  const job = crypto.randomUUID().replaceAll("-", "");
  const master = crypto.getRandomValues(new Uint8Array(32));
  const sealed = await seal(master, job, "src", new TextEncoder().encode(source));
  const kr = await db.from("mirsa_forge_keys").insert({ job, user_id: uid, k: b64(master) }); if (kr.error) throw Error("keys");
  const up = await db.storage.from(BUCKET).upload("forge/jobs/" + job + ".bin", sealed, { contentType: "application/octet-stream", upsert: false });
  if (up.error) throw Error("storage");
  const r = await fetch("https://api.github.com/repos/" + GH_REPO + "/actions/workflows/build.yml/dispatches", {
    method: "POST", headers: { authorization: "Bearer " + GH_TOKEN, accept: "application/vnd.github+json", "content-type": "application/json", "user-agent": "mirsa-forge" },
    body: JSON.stringify({ ref: "main", inputs: { job } }) });
  if (r.status !== 204) { await r.text(); await db.storage.from(BUCKET).remove(["forge/jobs/" + job + ".bin"]); await db.from("mirsa_forge_keys").delete().eq("job", job); return json({ error: "builder_unavailable" }, 503); }
  return json({ job });
}
async function cleanupForge() {
  const old = await cleanupStorage(db, BUCKET, "forge", Date.now());
  const keys = await db.from("mirsa_forge_keys").delete().lt("created_at", new Date(Date.now() - TEMP_TTL_MS).toISOString());
  if (keys.error) throw Error("keys_cleanup");
  return old.length;
}
// Called only by the trusted workflow steps, authenticated with a shared secret held in the repo secrets.
async function builderCall(req: Request, url: URL) {
  if (!BSECRET || req.headers.get("x-builder-secret") !== BSECRET) return json({ error: "unauthorized" }, 401);
  if (url.searchParams.get("action") === "builder-cleanup") return json({ removed: await cleanupForge() });
  await cleanupForge().catch(() => {});
  if (url.searchParams.get("action") === "builder-done") {
    const job = url.searchParams.get("job"); if (!hex32(job)) return json({ error: "bad_request" }, 400);
    const body = new Uint8Array(await req.arrayBuffer());
    if (body.length > MAX_DYLIB_BYTES + 64) return json({ error: "too_big" }, 413);
    const ok = url.searchParams.get("ok") === "1";
    if (body.length < 1000 && ok) return json({ error: "bad_artifact" }, 422);
    const key = ok ? "forge/out/" + job + ".enc" : "forge/out/" + job + ".err";
    await db.storage.from(BUCKET).upload(key, body, { upsert: true, contentType: "application/octet-stream" });
    return json({ ok: true });
  }
  const j = await req.json(); if (j.action !== "builder-fetch" || !hex32(j.job)) return json({ error: "bad_request" }, 400);
  // One use: atomically claim the key row; a second fetch (or replay) gets nothing.
  const claim = await db.from("mirsa_forge_keys").update({ fetched: true }).eq("job", j.job).eq("fetched", false).gte("created_at", new Date(Date.now() - JOB_TTL_MS).toISOString()).select("user_id,k").maybeSingle();
  if (!claim.data) return json({ error: "not_found" }, 404);
  const path = "forge/jobs/" + j.job + ".bin";
  const { data, error } = await db.storage.from(BUCKET).download(path);
  if (error || !data) return json({ error: "not_found" }, 404);
  const ct = new Uint8Array(await data.arrayBuffer());
  await db.storage.from(BUCKET).remove([path]);
  return json({ source: b64(ct), key: claim.data.k });
}
async function buildStatus(url: URL, uid: string) {
  const job = url.searchParams.get("job"); if (!hex32(job)) return json({ error: "bad_request" }, 400);
  const row = await db.from("mirsa_forge_keys").select("user_id,k,fetched").eq("job", job).maybeSingle();
  if (!row.data || row.data.user_id !== uid) return json({ error: "not_found" }, 404);
  const own = async (p: string) => { const { data } = await db.storage.from(BUCKET).download(p); return data; };
  const d = await own("forge/out/" + job + ".enc"), e = await own("forge/out/" + job + ".err");
  if (d || e) {
    if (url.searchParams.get("fetch") !== "1") return json({ state: d ? "done" : "failed" });
    // Ciphertext only; the app decrypts locally with the per-job key (returned once, then everything is deleted).
    const bytes = new Uint8Array(await (d ?? e)!.arrayBuffer());
    await db.storage.from(BUCKET).remove(["forge/out/" + job + ".enc", "forge/out/" + job + ".err"]);
    await db.from("mirsa_forge_keys").delete().eq("job", job);
    return new Response(bytes, { headers: { ...H, "content-type": "application/octet-stream", "x-forge-key": row.data.k, "x-forge-kind": d ? "dylib" : "err" } });
  }
  return json({ state: row.data.fetched ? "running" : "queued" });
}
Deno.serve(async req => {
  try {
    const url = new URL(req.url);
    if (req.method === "POST" && (url.searchParams.get("action") ?? "").startsWith("builder-")) return await builderCall(req, url);
    const u = await user(req); if (!u) return json({ error: "unauthorized" }, 401);
    if (req.method === "GET" && url.searchParams.get("action") === "status") return json({ llm: !!LLM_KEY, builder: builderReady() });
    if (req.method === "GET" && url.searchParams.get("action") === "build-status") return await buildStatus(url, u.id);
    if (req.method === "GET" && url.searchParams.get("action") === "gallery") {
      const { data } = await db.from("mirsa_forge_gallery").select("id,name,target_bundle_id,description,installs,created_at").lt("reported", 3).order("installs", { ascending: false }).limit(50);
      return json({ items: data ?? [] });
    }
    if (req.method === "GET" && url.searchParams.get("action") === "gallery-item") {
      const id = url.searchParams.get("id") ?? "";
      if (!/^[0-9a-f-]{36}$/.test(id)) return json({ error: "bad_request" }, 400);
      const { data } = await db.from("mirsa_forge_gallery").select("name,target_bundle_id,code,settings").eq("id", id).lt("reported", 3).maybeSingle();
      if (!data || validateLogos(data.code)) return json({ error: "not_found" }, 404);
      await db.rpc("mirsa_forge_install", { p_id: id }).catch(() => {});
      return json(data);
    }
    if (req.method !== "POST") return json({ error: "method" }, 405);
    const body = await req.json();
    const action = String(body.action);
    if (!(action in LIMITS)) {
      if (action === "report" && /^[0-9a-f-]{36}$/.test(String(body.id))) { await db.rpc("mirsa_forge_report", { p_id: body.id }).catch(() => {}); return json({ ok: true }); }
      return json({ error: "bad_request" }, 400);
    }
    if (!(await allow(u.id, action))) return json({ error: "rate_limited" }, 429);
    if (action === "translate" || action === "generate") {
      const g = await gate(req, u.id, action);
      if (g === "bad_device") return json({ error: "bad_request" }, 400);
      if (g === "gate_error") return json({ error: "server_error" }, 500);
      if (g !== "ok") return json({ error: "daily_limit", message: "الحد اليومي خلص، جرّب بكرا" }, 429);
    }
    if (action === "translate") return await translate(body, u.id);
    if (action === "generate") return await generate(body, u.id);
    if (action === "build") return await build(body, u.id);
    // publish
    const bad = validateLogos(body.code);
    if (bad || !validateName(body.name) || !validateBundleID(body.bundleID) || !validateSettings(body.settings ?? [])) return json({ error: "unsafe_or_invalid_code" }, 422);
    const { count: mine } = await db.from("mirsa_forge_gallery").select("id", { count: "exact", head: true }).eq("user_id", u.id);
    if ((mine ?? 0) >= MAX_GALLERY_PER_USER) return json({ error: "rate_limited" }, 429);
    const { data, error } = await db.from("mirsa_forge_gallery").insert({ user_id: u.id, name: body.name, target_bundle_id: body.bundleID,
      description: String(body.description ?? "").slice(0, 300), code: body.code, settings: body.settings ?? [] }).select("id").single();
    if (error) return json({ error: "publish_failed" }, 500);
    return json({ id: data.id });
  } catch (e) {
    if (e instanceof Quota) return e.kind === "daily" ? json({ error: "daily_limit", message: "الحد اليومي خلص، جرّب بكرا" }, 429) : json({ error: "busy", retry_after: e.retry }, 429);
    const m = String((e as Error).message); console.error("forge_err", m.slice(0, 120));
    return json({ error: m === "llm_not_configured" || m === "llm_unavailable" ? m : "server_error" }, m === "llm_not_configured" || m === "llm_unavailable" ? 503 : 500);
  }
});
