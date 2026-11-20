// No network or real credentials. Runs the real handler with a fake Supabase HTTP boundary.
import assert from "node:assert/strict";
Deno.env.set("SUPABASE_URL", "https://test.invalid");
Deno.env.set("SUPABASE_SERVICE_ROLE_KEY", "test-service-role");
Deno.env.set("TOOLS_STORE_ADMIN_TOKEN", "test-admin-token-at-least-24-chars");
let handler: (r: Request) => Promise<Response>;
const originalServe = Deno.serve;
(Deno as any).serve = (fn: typeof handler) => { handler = fn; };
await import("./index.ts");
(Deno as any).serve = originalServe;

const uid = "11111111-1111-1111-1111-111111111111";
const id = "22222222-2222-2222-2222-222222222222";
const other = "33333333-3333-3333-3333-333333333333";
let route: (url: URL, init: RequestInit) => Response;
let calls: { url: URL; init: RequestInit }[] = [];
const originalFetch = globalThis.fetch;
const response = (v: unknown, status = 200) => new Response(JSON.stringify(v), { status, headers: { "content-type": "application/json" } });
function reset(fn: typeof route) {
  calls = []; route = fn;
  globalThis.fetch = ((input: string | URL | Request, init: RequestInit = {}) => {
    const url = new URL(typeof input === "object" && "url" in input ? input.url : String(input));
    calls.push({ url, init });
    if (url.pathname === "/auth/v1/user") return Promise.resolve(response({ id: uid, role: "authenticated" }));
    return Promise.resolve(route(url, init));
  }) as typeof fetch;
}
async function request(body: unknown, admin = false, auth = true) {
  const headers: Record<string, string> = { "content-type": "application/json" };
  if (auth) headers.authorization = "Bearer test.jwt.signature";
  if (admin) headers["x-admin-token"] = "test-admin-token-at-least-24-chars";
  const r = await handler!(new Request("https://edge.invalid", { method: "POST", headers, body: JSON.stringify(body) }));
  return { status: r.status, body: await r.json() };
}
const row = { id, storage_path: "uploads/test/a.dylib", file_size: 4, file_ext: "dylib", file_name: "a.dylib", status: "uploading" };

Deno.test("real handler security regressions with mocked Supabase", async () => {
  try {
    reset(() => { throw new Error("unexpected DB"); });
    assert.equal((await request({ action: "admin_pending" })).status, 403);
    assert.equal((await request({ action: "download", id }, false, false)).status, 401);
    assert.equal((await request({ action: "list", q: "x".repeat(17_000) })).status, 413);

    reset((url) => {
      assert.equal(url.pathname, "/rest/v1/rpc/mirsa_tools_allow");
      return response({ message: "database unavailable" }, 500);
    });
    assert.equal((await request({ action: "download", id })).status, 500);
    assert.ok(!calls.some(c => c.url.pathname.includes("storage")));

    reset((url) => {
      if (url.pathname.includes("rpc/")) return response(true);
      assert.equal(url.searchParams.get("status"), "eq.approved");
      return response(null);
    });
    assert.equal((await request({ action: "download", id })).status, 404);
    assert.ok(!calls.some(c => c.url.pathname.includes("storage")));

    reset((url) => {
      assert.equal(url.searchParams.get("uploader"), "eq." + uid);
      assert.equal(url.searchParams.get("id"), "eq." + other);
      return response(null);
    });
    assert.equal((await request({ action: "upload_commit", id: other })).status, 404);

    for (const suspicious of [false, true]) {
      let sealed = "";
      reset((url, init) => {
        if (url.pathname === "/rest/v1/mirsa_tools_items" && init.method !== "PATCH") return response(row);
        if (url.pathname.endsWith("/copy")) {
          sealed = JSON.parse(String(init.body)).destinationKey;
          assert.ok(sealed.startsWith("review/" + id + "/"));
          return response({ Key: sealed });
        }
        if (url.pathname.endsWith("/list/mirsa-tools")) return response([{ name: row.file_name, metadata: { size: 4 } }]);
        if (url.pathname.includes("/object/sign/")) return response({ signedURL: "/object/sign/mirsa-tools/" + sealed + "?token=test" });
        if (url.pathname.includes("/storage/v1/object/sign/") || url.pathname.includes("/object/sign/")) throw new Error("unexpected");
        if (url.pathname === "/rest/v1/mirsa_tools_items" && init.method === "PATCH") {
          const patch = JSON.parse(String(init.body));
          assert.equal(patch.storage_path, sealed);
          assert.equal(patch.status, suspicious ? "held" : "pending_review");
          assert.equal(url.searchParams.get("status"), "eq.uploading");
          return response([{ id }]);
        }
        if (url.pathname === "/storage/v1/object/mirsa-tools" && init.method === "DELETE") return response([]);
        throw new Error("unexpected " + url.pathname);
      });
      // Signed URL fetch uses the same path as createSignedUrl, distinguished by method.
      const baseRoute = route;
      route = (url, init) => {
        if (url.pathname.includes("/object/sign/") && (!init.method || init.method === "GET")) {
          assert.equal((init.headers as Record<string,string>).Range, "bytes=0-511");
          return new Response(suspicious ? new Uint8Array([35,33,47,98]) : new Uint8Array([0xcf,0xfa,0xed,0xfe]));
        }
        return baseRoute(url, init);
      };
      const result = await request({ action: "upload_commit", id });
      assert.equal(result.status, 200, JSON.stringify(result));
      assert.equal(result.body.status, suspicious ? "held" : "pending_review");
    }

    reset(() => response({ ...row, storage_path: "review/test/a", status: "held" }));
    assert.equal((await request({ action: "admin_review", id, decision: "approve", file_reviewed: true, note: "reviewed" }, true)).status, 409);
    assert.ok(!calls.some(c => c.init.method === "PATCH"));
    reset(() => response({ ...row, storage_path: "review/test/a", status: "pending_review" }));
    assert.equal((await request({ action: "admin_review", id, decision: "approve" }, true)).status, 409);
    assert.ok(!calls.some(c => c.init.method === "PATCH"));

    reset((url) => {
      assert.equal(url.pathname, "/rest/v1/mirsa_tools_alerts");
      assert.equal(url.searchParams.get("acknowledged_at"), "is.null");
      return response([{ id, reason: "header_mismatch" }]);
    });
    assert.equal((await request({ action: "admin_alerts" }, true)).body.alerts.length, 1);
  } finally { globalThis.fetch = originalFetch; }
});
