// No ambiguous submission may cause a second compiler to run.
export async function routeOracle(base, secret, job, request = fetch) {
  const headers = {"x-builder-secret": secret, "content-type": "application/json"};
  const send = async (url, init) => {
    try { const r = await request(url, {...init, signal: AbortSignal.timeout(8000)}); return {status:r.status, body:await r.json().catch(()=>null)}; }
    catch { return null; }
  };
  const r = await send(base + "/jobs", {method:"POST", headers, body:JSON.stringify({job})});
  if ((r?.status === 200 || r?.status === 202) && r.body?.accepted === true) return "oracle";
  if (r?.status === 503 && r.body?.accepted === false) return "github";
  const q = await send(base + "/jobs/" + job, {method:"GET", headers});
  if (q?.status === 404 || (q?.status === 503 && q.body?.accepted === false)) return "github";
  if ((q?.status === 200 || q?.status === 202) && q.body?.accepted === true) return "oracle";
  return "uncertain";
}
export function splitSource(source) {
 const start = source.indexOf("\n%group Main\n"), end = source.lastIndexOf("\n%end\n%ctor { if (MirsaGuardAllow()) { %init(Main); } }\n");
 if (start < 0 || end <= start) throw Error("source_scaffold");
 return {prefix:source.slice(0,start+13), code:source.slice(start+13,end), suffix:source.slice(end)};
}
