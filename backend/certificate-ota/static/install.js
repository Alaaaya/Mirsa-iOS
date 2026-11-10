"use strict";
(() => {
 const params = new URLSearchParams(location.hash.slice(1));
 const token = params.get("token") || "";
 const expires = Date.parse(params.get("expires") || "");
 const status = document.getElementById("status");
 const button = document.getElementById("install");
 // Server checks authoritative expiry for BOTH manifest and IPA, independently.
 // These checks only prevent displaying an obviously expired or malformed link.
 if (!/^[a-f0-9]{64}$/.test(token) || !Number.isFinite(expires)) {
  status.textContent = "Invalid link / الرابط غير صحيح"; return;
 }
 const manifest = "https://hirebeofomiyumwysppj.supabase.co/functions/v1/certificate-ota?kind=manifest&token=" + token;
 button.href = "itms-services://?action=download-manifest&url=" + encodeURIComponent(manifest);
 function update() {
  const expired = expires <= Date.now();
  button.hidden = expired;
  status.textContent = expired ? "Link expired / انتهت صلاحية الرابط" : "Expires / ينتهي " + new Date(expires).toLocaleString();
  if (expired) button.removeAttribute("href");
 }
 update();
 setInterval(update, 10000);
})();
