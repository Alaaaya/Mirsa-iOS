// Shared, pure validation. No certificate, password or private-key upload API exists.
export const MAX_IPA_BYTES = 30 * 1024 * 1024;
export const TTL_SECONDS = 900;
export function validateMetadata(value) {
  if (!value || typeof value !== "object") throw new Error("metadata");
  const keys = Object.keys(value);
  if (keys.some(k => !["bundleID", "version", "title", "bytes"].includes(k))) throw new Error("unexpected_field");
  const { bundleID, version, title, bytes } = value;
  if (typeof bundleID !== "string" || bundleID.length > 255 || !/^[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+$/.test(bundleID)) throw new Error("bundle_id");
  if (typeof version !== "string" || !/^\d+(?:\.\d+){0,3}$/.test(version) || version.length > 40) throw new Error("version");
  if (typeof title !== "string" || !title.trim() || title.length > 100 || /[\x00-\x1f\x7f]/.test(title)) throw new Error("title");
  if (!Number.isSafeInteger(bytes) || bytes < 4 || bytes > MAX_IPA_BYTES) throw new Error("size");
  return { bundleID, version, title: title.trim(), bytes };
}
export function xml(text) {
  return text.replaceAll("&", "&amp;").replaceAll("<", "&lt;").replaceAll(">", "&gt;").replaceAll('"', "&quot;").replaceAll("'", "&apos;");
}
export function manifest(metadata, signedIPAURL) {
  const m = validateMetadata(metadata);
  const u = new URL(signedIPAURL);
  if (u.protocol !== "https:" || u.username || u.password || u.hash) throw new Error("https_required");
  return '<?xml version="1.0" encoding="UTF-8"?>\n<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n<plist version="1.0"><dict><key>items</key><array><dict><key>assets</key><array><dict><key>kind</key><string>software-package</string><key>url</key><string>' + xml(u.href) + '</string></dict></array><key>metadata</key><dict><key>bundle-identifier</key><string>' + xml(m.bundleID) + '</string><key>bundle-version</key><string>' + xml(m.version) + '</string><key>kind</key><string>software</string><key>title</key><string>' + xml(m.title) + '</string></dict></dict></array></dict></plist>';
}
export function isExpired(expiresAt, now = Date.now()) {
  const time = Date.parse(expiresAt);
  return !Number.isFinite(time) || time <= now;
}

export function lifetime(value) {
  if (value === null || value === undefined || value === "900") return 900;
  if (value === "172800") return 172800;
  throw new Error("lifetime");
}
export function linkPage(metadata, manifestURL, expiresAt) {
  const m = validateMetadata(metadata);
  manifest(m, manifestURL); // Same URL security policy as the manifest.
  const expires = new Date(expiresAt);
  if (!Number.isFinite(expires.getTime())) throw new Error("expiry");
  const install = "itms-services://?action=download-manifest&url=" + encodeURIComponent(manifestURL);
  return '<!doctype html><html lang="en" dir="ltr"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="referrer" content="no-referrer"><title>Mirsa installation</title><style>body{background:#10131c;color:#f8f8ff;font:17px system-ui;max-width:480px;margin:12vh auto;padding:28px}a{display:block;padding:20px;background:#96bfff;color:#10131c;text-decoration:none;text-align:center;border-radius:12px}p{line-height:1.6;color:#b8bfd1}</style><main><small>MIRSA</small><h1>' + xml(m.title) + '</h1><p>' + xml(m.bundleID) + ' · ' + xml(m.version) + '</p><a href="' + xml(install) + '">Install / تثبيت / دامەزراندن / Saz bike</a><p>Open in Safari on iPhone or iPad. A valid signing certificate and device-compatible profile are required. Sharing this link grants access to this IPA until expiry.</p><p>Expires ' + xml(expires.toISOString()) + '</p></main></html>';
}
