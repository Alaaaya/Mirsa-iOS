// Pure validation/shaping for the Mirsa Tools Store edge function. No I/O here, so it is unit-testable with node --test.

export const CATEGORIES = ["tweaks", "wallpapers", "app_tweaks", "sounds", "fonts"];
export const EXTENSIONS = {
  tweaks: ["dylib", "deb", "zip"],
  app_tweaks: ["dylib", "deb", "zip"],
  wallpapers: ["tendies"],
  sounds: ["m4r", "m4a", "mp3", "caf", "wav"],
  fonts: ["ttf", "otf", "ttc"],
};
export const MAX_BYTES = 150 * 1024 * 1024;
export const MAX_PENDING_PER_USER = 5;
export const SORTS = { downloads: "downloads", new: "created_at", rating: "rating_avg" };
export const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
export const STATUSES = ["uploading", "pending_review", "approved", "rejected"];

/** Trims, drops control characters, caps length. Returns "" for non-strings. */
export function cleanText(v, max) {
  if (typeof v !== "string") return "";
  return v.replace(/[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F]/g, "").trim().slice(0, max);
}

/** Lower-case extension of a file name, "" when missing. */
export function extensionOf(name) {
  const m = /\.([A-Za-z0-9]{1,8})$/.exec(String(name ?? ""));
  return m ? m[1].toLowerCase() : "";
}

/** Storage-safe file name: letters/digits/-/_ only, keeps the extension. */
export function safeFileName(name) {
  const ext = extensionOf(name);
  const base = String(name ?? "").replace(/\.[A-Za-z0-9]{1,8}$/, "").normalize("NFKD")
    .replace(/[^A-Za-z0-9_-]+/g, "-").replace(/-+/g, "-").replace(/^-|-$/g, "").slice(0, 60) || "item";
  return ext ? `${base}.${ext}` : base;
}

/** Target app for app_tweaks: a known slug or a bundle identifier. */
export function cleanTarget(v) {
  const t = cleanText(v, 120).toLowerCase();
  if (["youtube", "instagram", "tiktok"].includes(t)) return t;
  if (/^[a-z0-9][a-z0-9-]*(\.[a-z0-9-]+){1,8}$/.test(t)) return t;
  return null;
}

/** Validates an upload_begin body. Returns { value } or { error }. */
export function validateUpload(body) {
  const category = String(body?.category ?? "");
  if (!CATEGORIES.includes(category)) return { error: "bad_category" };
  const title = cleanText(body.title, 80);
  if (title.length < 2) return { error: "bad_title" };
  const fileName = cleanText(body.file_name, 120);
  const ext = extensionOf(fileName);
  if (!EXTENSIONS[category].includes(ext)) return { error: "bad_extension" };
  const size = Number(body.file_size);
  if (!Number.isInteger(size) || size <= 0) return { error: "bad_file" };
  if (size > MAX_BYTES) return { error: "too_large" };
  let target = null;
  if (category === "app_tweaks") {
    target = cleanTarget(body.target_app);
    if (!target) return { error: "bad_target" };
  }
  const version = cleanText(body.version, 40) || null;
  const author = cleanText(body.author_name, 40) || null;
  return {
    value: {
      category, title, description: cleanText(body.description, 1000), target_app: target, version,
      author_name: author, file_name: safeFileName(fileName), file_ext: ext, file_size: size,
    },
  };
}

export function validateList(body) {
  const category = String(body?.category ?? "");
  if (!CATEGORIES.includes(category)) return { error: "bad_category" };
  const sort = Object.hasOwn(SORTS, String(body.sort)) ? String(body.sort) : "new";
  const limit = Math.max(1, Math.min(100, Number.parseInt(body.limit ?? 60, 10) || 60));
  const offset = Math.max(0, Math.min(10_000, Number.parseInt(body.offset ?? 0, 10) || 0));
  // Only letters, digits, spaces and a few separators reach the ilike pattern.
  const q = cleanText(body.q, 80).replace(/[^\p{L}\p{N} ._-]/gu, " ").trim();
  return { value: { category, sort, column: SORTS[sort], limit, offset, q } };
}

export function validateStars(v) {
  const n = Number(v);
  return Number.isInteger(n) && n >= 1 && n <= 5 ? n : null;
}

export function ratingAvg(sum, count) {
  return count > 0 ? Math.round((sum / count) * 10) / 10 : 0;
}

/** Public JSON for an item row (never exposes uploader ids or storage paths).
 * @param {any} row
 * @param {number|null} myRating
 * @param {string|null} previewURL
 */
export function publicItem(row, myRating = null, previewURL = null) {
  return {
    id: row.id, category: row.category, title: row.title, description: row.description ?? "",
    target_app: row.target_app ?? null, version: row.version ?? null, file_name: row.file_name,
    file_size: row.file_size ?? null, preview_url: previewURL, author_name: row.author_name ?? null,
    downloads: row.downloads ?? 0, rating_avg: ratingAvg(row.rating_sum ?? 0, row.rating_count ?? 0),
    rating_count: row.rating_count ?? 0, my_rating: myRating, created_at: row.created_at ?? null,
  };
}

/** Constant-time string comparison for the admin token. */
export function safeEqual(a, b) {
  const x = new TextEncoder().encode(String(a ?? "")), y = new TextEncoder().encode(String(b ?? ""));
  let diff = x.length ^ y.length;
  for (let i = 0; i < Math.max(x.length, y.length); i++) diff |= (x[i] ?? 0) ^ (y[i] ?? 0);
  return diff === 0;
}

/** Magic bytes are a mismatch detector, NOT a malware verdict. Never execute/extract uploads. */
export function inspectHeader(ext, bytes) {
  const b = bytes instanceof Uint8Array ? bytes : new Uint8Array(bytes);
  const at = (s, n = 0) => [...s].every((c, i) => b[n + i] === c.charCodeAt(0));
  const hex = [...b.slice(0, 4)].map(n => n.toString(16).padStart(2, "0")).join("");
  const zip = ["504b0304", "504b0506", "504b0708"].includes(hex);
  let valid = false;
  if (ext === "dylib") valid = ["feedface", "cefaedfe", "feedfacf", "cffaedfe", "cafebabe", "bebafeca", "cafebabf", "bfbafeca"].includes(hex);
  if (ext === "deb") valid = at("!<arch>\n");
  if (ext === "zip" || ext === "tendies") valid = zip;
  if (["m4a", "m4r"].includes(ext)) valid = at("ftyp", 4);
  if (ext === "mp3") valid = at("ID3") || (b[0] === 0xff && (b[1] & 0xe0) === 0xe0);
  if (ext === "caf") valid = at("caff");
  if (ext === "wav") valid = at("RIFF") && at("WAVE", 8);
  if (ext === "ttf") valid = hex === "00010000" || at("true");
  if (ext === "otf") valid = at("OTTO");
  if (ext === "ttc") valid = at("ttcf");
  return valid ? null : "header_mismatch";
}

/** Bound request/header reads even when Content-Length/Range is absent or ignored. */
export async function readBounded(stream, max, prefixOnly = false) {
  if (!stream) throw new Error("empty_body");
  const reader = stream.getReader();
  const out = new Uint8Array(max);
  let size = 0;
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) return out.slice(0, size);
      if (!prefixOnly && size + value.length > max) throw new Error("body_too_large");
      const take = Math.min(value.length, max - size);
      out.set(value.subarray(0, take), size);
      size += take;
      if (prefixOnly && size === max) return out;
    }
  } finally { await reader.cancel(); reader.releaseLock(); }
}
