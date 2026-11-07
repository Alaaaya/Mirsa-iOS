import { isExpired, TEMP_TTL_MS, JOB_TTL_MS } from "./contract.mjs";
// Collect all pages before deleting: removals must not shift later page offsets.
// Only server callers supply root and now; neither comes from request parameters.
export async function cleanupStorage(db: any, bucket: string, root: string, now: number): Promise<string[]> {
  const old: string[] = [];
  const storage = db.storage.from(bucket);
  const pageSize = 1000;
  for (const [dir, ttl] of [[root + "/jobs", JOB_TTL_MS], [root + "/out", TEMP_TTL_MS]] as const) {
    for (let offset = 0; ; offset += pageSize) {
      const { data, error } = await storage.list(dir, {
        limit: pageSize, offset, sortBy: { column: "name", order: "asc" }
      });
      if (error || !Array.isArray(data)) throw Error("storage_list");
      for (const f of data) {
        // Virtual folder entries have no id. Never treat absent timestamps as epoch.
        if (!f.id) continue;
        const created = Date.parse(f.created_at);
        if (!Number.isFinite(created)) throw Error("storage_timestamp");
        if (isExpired(created, now, ttl)) old.push(dir + "/" + f.name);
      }
      if (data.length < pageSize) break;
    }
  }
  for (let start = 0; start < old.length; start += 100) {
    const r = await storage.remove(old.slice(start, start + 100));
    if (r.error) throw Error("storage_remove");
  }
  return old;
}
