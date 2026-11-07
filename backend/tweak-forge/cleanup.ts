import { isExpired, TEMP_TTL_MS, JOB_TTL_MS } from "./contract.mjs";
// Shared by production cleanup and the isolated test. root is a storage prefix, now is injectable.
export async function cleanupStorage(db: any, bucket: string, root: string, now: number): Promise<string[]> {
  const old: string[] = [];
  for (const [dir, ttl] of [[root + "/jobs", JOB_TTL_MS], [root + "/out", TEMP_TTL_MS]] as const) {
    const { data } = await db.storage.from(bucket).list(dir, { limit: 1000 });
    for (const f of data ?? []) if (isExpired(new Date(f.created_at ?? 0).getTime(), now, ttl)) old.push(dir + "/" + f.name);
  }
  if (old.length) { const r = await db.storage.from(bucket).remove(old); if (r.error) throw Error("storage_remove"); }
  return old;
}
