import { createClient } from "npm:@supabase/supabase-js@2.106.2";
import { MAX_PROMPT, validateLogos, validateSettings, validateName, validateBundleID, assembleSource, parseModelJSON } from "./contract.mjs";

const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false } });
const LLM_URL = Deno.env.get("LLM_BASE_URL") ?? "https://api.openai.com/v1";
const LLM_KEY = Deno.env.get("LLM_API_KEY");
const LLM_MODEL = Deno.env.get("LLM_MODEL") ?? "gpt-4.1";
const BUILDER_URL = Deno.env.get("TWEAK_BUILDER_URL");
const BUILDER_SECRET = Deno.env.get("TWEAK_BUILDER_SECRET");
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
async function llm(system: string, userText: string, maxTokens: number) {
  if (!LLM_KEY) throw Error("llm_not_configured");
  const r = await fetch(LLM_URL + "/chat/completions", {
    method: "POST", headers: { authorization: "Bearer " + LLM_KEY, "content-type": "application/json" },
    body: JSON.stringify({ model: LLM_MODEL, temperature: 0.2, max_tokens: maxTokens, messages: [{ role: "system", content: system }, { role: "user", content: userText }] }),
  });
  if (!r.ok) throw Error("llm_failed");
  return (await r.json()).choices?.[0]?.message?.content ?? "";
}
const LANGS: Record<string, string> = { ar: "Arabic", ckb: "Sorani Kurdish", kmr: "Kurmanji Kurdish (Latin script)", en: "English" };

async function translate(body: any) {
  const lang = LANGS[body.target]; const items = body.items;
  if (!lang || !Array.isArray(items) || items.length === 0 || items.length > 120) return json({ error: "bad_request" }, 400);
  const clean = items.map((i: any) => ({ k: String(i.k).slice(0, 200), v: String(i.v).slice(0, 600) }));
  const sys = "Translate UI strings of an iOS app into " + lang + ". Keep format specifiers (%@ %d %1$@ etc), placeholders in braces, newlines, and HTML/markup unchanged. Do not translate brand names. Reply ONLY with JSON object mapping each key to its translation.";
  const out = await llm(sys, JSON.stringify(clean), 6000);
  const m = out.match(/\{[\s\S]*\}/); if (!m) return json({ error: "model_json" }, 502);
  const parsed = JSON.parse(m[0]); const result: Record<string, string> = {};
  for (const i of clean) if (typeof parsed[i.k] === "string" && parsed[i.k].length < 1500) result[i.k] = parsed[i.k];
  return json({ translations: result });
}
async function generate(body: any) {
  const prompt = String(body.prompt ?? "").slice(0, MAX_PROMPT);
  const classes = Array.isArray(body.classes) ? body.classes.filter((c: unknown) => typeof c === "string" && /^[A-Za-z_][A-Za-z0-9_.$]{0,80}$/.test(c)).slice(0, 400) : [];
  if (!prompt || !validateBundleID(body.bundleID) || !validateName(body.name)) return json({ error: "bad_request" }, 400);
  const sys = "You write iOS tweaks in Theos Logos for ONE target app. Reply ONLY JSON: {\"code\": string, \"settings\": [{\"key\",\"title\",\"default\"(bool)}], \"explain\": string}. "
    + "code contains ONLY %hook/%end blocks (no %ctor, no %group, no #include of absolute paths). Use only classes from the provided list. "
    + "Optional user toggles are compile-time macros MIRSA_SETTING_<key> (0/1), e.g. if (MIRSA_SETTING_dark) {...}; max 8, keys lowercase [a-z0-9_]. "
    + "Forbidden: networking, process spawning, dlopen/dlsym, asm, deleting files, keychain access. Keep it simple and safe. Previous version, if any, is provided: modify it.";
  const user = JSON.stringify({ app: body.bundleID, classes, previousCode: body.previousCode ?? null, request: prompt });
  const o = parseModelJSON(await llm(sys, user, 4000));
  const bad = validateLogos(o.code);
  if (bad || !validateSettings(o.settings)) return json({ error: "unsafe_or_invalid_code", detail: bad }, 422);
  return json({ code: o.code, settings: o.settings, explain: String(o.explain ?? "").slice(0, 600) });
}
async function build(body: any) {
  if (!BUILDER_URL || !BUILDER_SECRET) return json({ error: "builder_not_configured" }, 503);
  if (!validateName(body.name) || !validateBundleID(body.bundleID) || !/^[0-9a-f-]{36}$/.test(String(body.id)) || !validateSettings(body.settings ?? [])) return json({ error: "bad_request" }, 400);
  const bad = validateLogos(body.code); if (bad) return json({ error: "unsafe_or_invalid_code", detail: bad }, 422);
  const source = assembleSource({ id: body.id, bundleID: body.bundleID, code: body.code, settings: body.settings ?? [], values: body.values ?? {} });
  const r = await fetch(BUILDER_URL + "/build", { method: "POST", headers: { authorization: "Bearer " + BUILDER_SECRET, "content-type": "application/json" },
    body: JSON.stringify({ name: body.name.replace(/[^A-Za-z0-9]/g, ""), bundleID: body.bundleID, source }), signal: AbortSignal.timeout(170_000) });
  if (!r.ok) return json({ error: "build_failed", log: (await r.text()).slice(0, 4000) }, 422);
  const bytes = new Uint8Array(await r.arrayBuffer());
  if (bytes.length < 1000 || bytes.length > 8 * 1024 * 1024) return json({ error: "bad_artifact" }, 502);
  return new Response(bytes, { headers: { ...H, "content-type": "application/octet-stream" } });
}
Deno.serve(async req => {
  try {
    const u = await user(req); if (!u) return json({ error: "unauthorized" }, 401);
    const url = new URL(req.url);
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
    if (action === "translate") return await translate(body);
    if (action === "generate") return await generate(body);
    if (action === "build") return await build(body);
    // publish
    const bad = validateLogos(body.code);
    if (bad || !validateName(body.name) || !validateBundleID(body.bundleID) || !validateSettings(body.settings ?? [])) return json({ error: "unsafe_or_invalid_code" }, 422);
    const { data, error } = await db.from("mirsa_forge_gallery").insert({ user_id: u.id, name: body.name, target_bundle_id: body.bundleID,
      description: String(body.description ?? "").slice(0, 300), code: body.code, settings: body.settings ?? [] }).select("id").single();
    if (error) return json({ error: "publish_failed" }, 500);
    return json({ id: data.id });
  } catch (e) {
    const m = String((e as Error).message);
    return json({ error: m === "llm_not_configured" ? m : "server_error" }, m === "llm_not_configured" ? 503 : 500);
  }
});
