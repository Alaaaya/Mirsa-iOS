// Supabase Edge Function: Mirsa Tools Store (tweaks, wallpapers, app tweaks, sounds, fonts).
// Auth: each app install signs in anonymously (Supabase Auth) and sends its own user JWT; verified here.
// Every upload starts as `uploading`, becomes `pending_review` once the bytes are verified, and is only listed
// after an admin approves it (x-admin-token, secret TOOLS_STORE_ADMIN_TOKEN). Files live in a private bucket and
// are served through short-lived signed URLs. Secrets (names only): TOOLS_STORE_ADMIN_TOKEN. SUPABASE_* are provided.
import { createClient } from "npm:@supabase/supabase-js@2.106.2";
import {
  MAX_PENDING_PER_USER, UUID_RE, MAX_BYTES, inspectHeader, readBounded, cleanText, publicItem, safeEqual, validateList, validateStars, validateUpload,
} from "./logic.mjs";

const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false } });
const BUCKET = "mirsa-tools";
const SIGNED_TTL = 600; // seconds
const LIMITS: Record<string, { n: number; windowMs: number }> = {
  upload_begin: { n: 10, windowMs: 86_400_000 },
  rate: { n: 60, windowMs: 3_600_000 },
  download: { n: 120, windowMs: 3_600_000 },
};
const H = { "cache-control": "no-store", "x-content-type-options": "nosniff" };
const json = (d: unknown, s = 200) => new Response(JSON.stringify(d), { status: s, headers: { ...H, "content-type": "application/json" } });
const LIST_COLUMNS = "id,category,title,description,target_app,version,author_name,file_name,file_size,preview_path,downloads,rating_sum,rating_count,created_at";

async function user(req: Request) {
  const a = req.headers.get("authorization") ?? "";
  if (!/^Bearer [A-Za-z0-9._-]+$/.test(a)) return null;
  const { data, error } = await db.auth.getUser(a.slice(7));
  return !error && data.user ? data.user : null;
}

function isAdmin(req: Request) {
  const expected = Deno.env.get("TOOLS_STORE_ADMIN_TOKEN") ?? "";
  return expected.length >= 24 && safeEqual(req.headers.get("x-admin-token") ?? "", expected);
}

async function allow(uid: string, action: string) {
  const limit = LIMITS[action];
  if (!limit) return true;
  const { data, error } = await db.rpc("mirsa_tools_allow", {
    p_user: uid, p_action: action, p_limit: limit.n, p_window_ms: limit.windowMs,
  });
  if (error) throw new Error("rate_limit_unavailable");
  return data === true;
}

async function previews(rows: any[]): Promise<Map<string, string>> {
  const paths = rows.map((r) => r.preview_path).filter((p): p is string => typeof p === "string" && p.length > 0);
  const out = new Map<string, string>();
  if (!paths.length) return out;
  const { data } = await db.storage.from(BUCKET).createSignedUrls(paths, SIGNED_TTL);
  for (const s of data ?? []) if (s.path && s.signedUrl) out.set(s.path, s.signedUrl);
  return out;
}

async function myRatings(uid: string, ids: string[]): Promise<Map<string, number>> {
  const out = new Map<string, number>();
  if (!ids.length) return out;
  const { data } = await db.from("mirsa_tools_ratings").select("item_id,stars").eq("user_id", uid).in("item_id", ids);
  for (const r of data ?? []) out.set(r.item_id, r.stars);
  return out;
}

async function shape(rows: any[], uid: string) {
  const [pv, mine] = await Promise.all([previews(rows), myRatings(uid, rows.map((r) => r.id))]);
  return rows.map((r) => publicItem(r, mine.get(r.id) ?? null, r.preview_path ? pv.get(r.preview_path) ?? null : null));
}

async function list(body: any, uid: string) {
  const v = validateList(body);
  if (v.error) return json({ error: v.error }, 400);
  const { category, column, limit, offset, q } = v.value!;
  let query = db.from("mirsa_tools_items").select(LIST_COLUMNS).eq("status", "approved").eq("category", category);
  if (q) query = query.ilike("title", `%${q}%`);
  if (column === "rating_avg") {
    // Generated column (schema.sql); ties go to the item with more ratings.
    query = query.gt("rating_count", 0).order("rating_avg", { ascending: false }).order("rating_count", { ascending: false });
  } else {
    query = query.order(column, { ascending: false });
  }
  const { data, error } = await query.order("created_at", { ascending: false }).range(offset, offset + limit - 1);
  if (error) return json({ error: "server_error" }, 500);
  return json({ items: await shape(data ?? [], uid) });
}

async function myUploads(uid: string) {
  const { data, error } = await db.from("mirsa_tools_items").select(LIST_COLUMNS + ",status,review_note")
    .eq("uploader", uid).order("created_at", { ascending: false }).limit(50);
  if (error) return json({ error: "server_error" }, 500);
  const rows = (data ?? []) as any[];
  const shaped = await shape(rows, uid);
  return json({ items: shaped.map((it, i) => ({ ...it, status: rows[i].status, review_note: rows[i].review_note ?? null })) });
}

async function rate(body: any, uid: string) {
  const stars = validateStars(body.stars);
  if (!UUID_RE.test(String(body.id)) || !stars) return json({ error: "bad_request" }, 400);
  const { data, error } = await db.rpc("mirsa_tools_rate", { p_item: body.id, p_user: uid, p_stars: stars });
  if (error) return String(error.message).includes("not_found") ? json({ error: "not_found" }, 404) : json({ error: "server_error" }, 500);
  const row = Array.isArray(data) ? data[0] : data;
  const sum = row?.rating_sum ?? 0, count = row?.rating_count ?? 0;
  return json({ rating_avg: count ? Math.round((sum / count) * 10) / 10 : 0, rating_count: count, my_rating: stars });
}

async function download(body: any, uid: string) {
  if (!UUID_RE.test(String(body.id))) return json({ error: "bad_request" }, 400);
  const { data: row } = await db.from("mirsa_tools_items").select("id,storage_path,file_name").eq("id", body.id).eq("status", "approved").maybeSingle();
  if (!row) return json({ error: "not_found" }, 404);
  const { data, error } = await db.storage.from(BUCKET).createSignedUrl(row.storage_path, SIGNED_TTL, { download: row.file_name });
  if (error || !data?.signedUrl) return json({ error: "server_error" }, 500);
  await db.rpc("mirsa_tools_count_download", { p_item: row.id, p_user: uid });
  return json({ url: data.signedUrl });
}

async function uploadBegin(req: Request, body: any, uid: string) {
  const v = validateUpload(body);
  if (v.error) return json({ error: v.error }, v.error === "too_large" ? 413 : 400);
  const { count, error: countError } = await db.from("mirsa_tools_items").select("id", { count: "exact", head: true })
    .eq("uploader", uid).in("status", ["uploading", "pending_review", "held"]);
  if (countError) return json({ error: "server_error" }, 500);
  if ((count ?? 0) >= MAX_PENDING_PER_USER) return json({ error: "pending_limit" }, 429);
  const id = crypto.randomUUID();
  const path = `uploads/${uid}/${id}/${v.value!.file_name}`;
  const device = req.headers.get("x-mirsa-device") ?? "";
  const { error } = await db.from("mirsa_tools_items").insert({
    id, ...v.value!, storage_path: path, status: "uploading", uploader: uid,
    uploader_device: UUID_RE.test(device) ? device : null,
  });
  if (error) return json({ error: error.message.includes("pending_limit") ? "pending_limit" : "server_error" }, error.message.includes("pending_limit") ? 429 : 500);
  const { data, error: se } = await db.storage.from(BUCKET).createSignedUploadUrl(path, { upsert: false });
  if (se || !data?.signedUrl) { await db.from("mirsa_tools_items").delete().eq("id", id); return json({ error: "server_error" }, 500); }
  return json({ id, upload_url: data.signedUrl });
}

async function uploadCommit(body: any, uid: string) {
  if (!UUID_RE.test(String(body.id))) return json({ error: "bad_request" }, 400);
  const { data: row, error: re } = await db.from("mirsa_tools_items").select("id,storage_path,file_size,file_ext,file_name,status")
    .eq("id", body.id).eq("uploader", uid).maybeSingle();
  if (re) return json({ error: "server_error" }, 500);
  if (!row) return json({ error: "not_found" }, 404);
  if (row.status !== "uploading") return json({ status: row.status });
  // Copy to an unpredictable service-only path BEFORE inspection. A reusable signed upload
  // capability can never mutate the reviewed object. Never publish the original uploads/ path.
  const sealed = `review/${row.id}/${crypto.randomUUID()}/${row.file_name}`;
  const { error: ce } = await db.storage.from(BUCKET).copy(row.storage_path, sealed);
  if (ce) return json({ error: "upload_unavailable" }, 409);
  const folder = sealed.split("/").slice(0, -1).join("/");
  const name = sealed.split("/").pop()!;
  const { data: objects, error: le } = await db.storage.from(BUCKET).list(folder, { limit: 5, search: name });
  if (le) { await db.storage.from(BUCKET).remove([sealed]); return json({ error: "server_error" }, 500); }
  const object = (objects ?? []).find((o: any) => o.name === name);
  const size = Number(object?.metadata?.size ?? 0);
  let flag = !object || size <= 0 || size > MAX_BYTES || size !== Number(row.file_size) ? "size_mismatch" : null;
  if (!flag) {
    const { data, error } = await db.storage.from(BUCKET).createSignedUrl(sealed, 60);
    if (error || !data?.signedUrl) { await db.storage.from(BUCKET).remove([sealed]); return json({ error: "server_error" }, 500); }
    try {
      const res = await fetch(data.signedUrl, { headers: { Range: "bytes=0-511" }, redirect: "error", signal: AbortSignal.timeout(15_000) });
      if (!res.ok) throw new Error("inspection_unavailable");
      flag = inspectHeader(row.file_ext, await readBounded(res.body, 512, true));
    } catch {
      await db.storage.from(BUCKET).remove([sealed]);
      return json({ error: "inspection_unavailable" }, 503);
    }
  }
  // Held state and owner alert outbox are committed atomically by the SQL trigger.
  const status = flag ? "held" : "pending_review";
  const { data: updated, error } = await db.from("mirsa_tools_items").update({
    status, storage_path: sealed, submitted_at: new Date().toISOString(),
    review_note: flag ? "Held for suspicious file: " + flag : null,
  }).eq("id", row.id).eq("uploader", uid).eq("status", "uploading").select("id");
  if (error || !updated?.length) {
    await db.storage.from(BUCKET).remove([sealed]);
    return json({ error: error ? "server_error" : "state_changed" }, error ? 500 : 409);
  }
  await db.storage.from(BUCKET).remove([row.storage_path]);
  return json({ status });
}

async function adminPending() {
  const { data, error } = await db.from("mirsa_tools_items")
    .select("id,category,title,description,target_app,version,author_name,file_name,file_ext,file_size,storage_path,status,review_note,submitted_at,uploader_device")
    .in("status", ["pending_review", "held"]).order("submitted_at", { ascending: true }).limit(100);
  if (error) return json({ error: "server_error" }, 500);
  const rows = data ?? [];
  const { data: signed } = rows.length
    ? await db.storage.from(BUCKET).createSignedUrls(rows.map((r) => r.storage_path), SIGNED_TTL)
    : { data: [] as any[] };
  const urls = new Map((signed ?? []).map((s: any) => [s.path, s.signedUrl]));
  return json({ items: rows.map(({ storage_path, ...r }) => ({ ...r, review_url: urls.get(storage_path) ?? null })) });
}

async function adminReview(body: any) {
  if (!UUID_RE.test(String(body.id)) || !["approve", "reject", "hold"].includes(String(body.decision))) return json({ error: "bad_request" }, 400);
  const { data: row } = await db.from("mirsa_tools_items").select("id,storage_path,status").eq("id", body.id).maybeSingle();
  if (!row) return json({ error: "not_found" }, 404);
  if (!["pending_review", "held", "approved"].includes(row.status)) return json({ error: "bad_state", status: row.status }, 409);
  const approve = body.decision === "approve";
  const hold = body.decision === "hold";
  if (hold && cleanText(body.note, 300).length < 3) return json({ error: "hold_reason_required" }, 400);
  // Acknowledgement is required for every file, including every dylib. Header checks
  // are not a review. Suspicious files cannot be approved through this endpoint.
  if (approve && (row.status === "held" || body.file_reviewed !== true || cleanText(body.note, 300).length < 3 ||
      !row.storage_path.startsWith("review/"))) return json({ error: "review_required" }, 409);
  const patch: Record<string, unknown> = {
    status: approve ? "approved" : hold ? "held" : "rejected", reviewed_at: new Date().toISOString(), review_note: cleanText(body.note, 300) || null,
  };
  if (approve && typeof body.preview_path === "string" && /^previews\/[A-Za-z0-9_-]{1,100}\.(png|jpg|jpeg|webp)$/.test(body.preview_path)) {
    patch.preview_path = body.preview_path;
  }
  const { data: changed, error } = await db.from("mirsa_tools_items").update(patch).eq("id", row.id).eq("status", row.status).select("id");
  if (error) return json({ error: "server_error" }, 500);
  if (!changed?.length) return json({ error: "state_changed" }, 409);
  // A rejected file is never served; remove the bytes and keep only the row for the uploader's status list.
  if (!approve && !hold) await db.storage.from(BUCKET).remove([row.storage_path]);
  return json({ ok: true, status: patch.status });
}

Deno.serve(async (req) => {
  try {
    if (req.method !== "POST") return json({ error: "method" }, 405);
    let body;
    try { body = JSON.parse(new TextDecoder().decode(await readBounded(req.body, 16_384))); }
    catch (e) { return json({ error: "bad_request" }, String((e as Error).message) === "body_too_large" ? 413 : 400); }
    if (!body || typeof body !== "object" || Array.isArray(body)) return json({ error: "bad_request" }, 400);
    const action = String(body.action ?? "");
    if (action === "admin_pending" || action === "admin_review" || action === "admin_alerts" || action === "admin_ack_alert") {
      if (!isAdmin(req)) return json({ error: "forbidden" }, 403);
      if (action === "admin_alerts") {
        const { data, error } = await db.from("mirsa_tools_alerts").select("*").is("acknowledged_at", null).order("created_at").limit(100);
        return error ? json({ error: "server_error" }, 500) : json({ alerts: data });
      }
      if (action === "admin_ack_alert") {
        if (!UUID_RE.test(String(body.id))) return json({ error: "bad_request" }, 400);
        const { error } = await db.from("mirsa_tools_alerts").update({ acknowledged_at: new Date().toISOString() }).eq("id", body.id);
        return error ? json({ error: "server_error" }, 500) : json({ ok: true });
      }
      return action === "admin_pending" ? await adminPending() : await adminReview(body);
    }
    const u = await user(req);
    if (!u) return json({ error: "unauthorized" }, 401);
    if (!(await allow(u.id, action))) return json({ error: "rate_limited" }, 429);
    switch (action) {
      case "list": return await list(body, u.id);
      case "my_uploads": return await myUploads(u.id);
      case "rate": return await rate(body, u.id);
      case "download": return await download(body, u.id);
      case "upload_begin": return await uploadBegin(req, body, u.id);
      case "upload_commit": return await uploadCommit(body, u.id);
      default: return json({ error: "bad_request" }, 400);
    }
  } catch (e) {
    console.error("tools_store_err"); // Never log signed URLs, tokens or untrusted exception text.
    return json({ error: "server_error" }, 500);
  }
});
