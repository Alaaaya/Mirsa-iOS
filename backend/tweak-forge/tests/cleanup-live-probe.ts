import { createClient } from "npm:@supabase/supabase-js@2.106.2";
import { cleanupStorage } from "./cleanup.ts";
const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false } });
const B = "mirsa-ota-private", R = "forge-test";
Deno.serve(async (req) => {
  if (req.headers.get("x-builder-secret") !== Deno.env.get("BUILDER_SECRET")) return new Response("no", { status: 401 });
  const names = [R + "/jobs/a.bin", R + "/out/b.enc", R + "/out/c.err"];
  for (const n of names) { const u = await db.storage.from(B).upload(n, new Uint8Array(64), { upsert: true, contentType: "application/octet-stream" }); if (u.error) return new Response("up " + u.error.message, { status: 500 }); }
  const exists = async (n: string) => !(await db.storage.from(B).download(n)).error;
  const state = async () => Object.fromEntries(await Promise.all(names.map(async n => [n, await exists(n)])));
  const t = Date.now(), H = 3600_000, out: any = { before: await state() };
  out.p0 = (await cleanupStorage(db, B, R, t)).length; out.s0 = await state();
  out.p23 = (await cleanupStorage(db, B, R, t + 23 * H)).length; out.s23 = await state();
  out.p25 = (await cleanupStorage(db, B, R, t + 25 * H)).length; out.s25 = await state();
  const other = await db.storage.from(B).list("forge/out", { limit: 100 }); out.realUntouched = (other.data ?? []).length;
  return new Response(JSON.stringify(out));
});
