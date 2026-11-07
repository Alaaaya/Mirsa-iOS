// Shared rules for generated tweak source. Pure functions, no I/O.
export const MAX_PROMPT = 2000;
export const MAX_CODE = 24000;
export const MAX_SETTINGS = 8;
const FORBIDDEN = [
  /\bsystem\s*\(/, /\bpopen\s*\(/, /\bposix_spawn/, /\bfork\s*\(/, /\bexec[lv]p?e?\s*\(/, /\bNSTask\b/,
  /\bdlopen\s*\(/, /\bdlsym\s*\(/, /\b__asm__?\b/, /\basm\s*(volatile)?\s*\(/, /\bptrace\b/,
  /\bsyscall\b/, /\bNSURLSession\b/, /\bNSURLConnection\b/, /\bCFNetwork\b/, /\bsocket\s*\(/,
  /\bKeychain\b/i, /\bSecItem/, /#\s*(include|import)\s*["<]\s*\//, /#\s*(include|import)\s*"\.\./, /\bMSHookFunction\b.*\bsec/i,
  /\bfopen\s*\(\s*"\/(etc|var\/mobile\/Library\/Keychains)/, /\bunlink\s*\(/, /\bremove\s*\(/, /\bremoveItemAtPath/,
];
export function validateName(s) { return typeof s === "string" && /^[A-Za-z][A-Za-z0-9 _.-]{0,39}$/.test(s); }
export function validateBundleID(s) { return typeof s === "string" && /^[A-Za-z0-9.-]{3,155}$/.test(s) && s.includes("."); }
export function validateSettings(list) {
  if (!Array.isArray(list) || list.length > MAX_SETTINGS) return false;
  const seen = new Set();
  return list.every(s => s && /^[a-z][a-z0-9_]{0,23}$/.test(s.key) && !seen.has(s.key) && seen.add(s.key) &&
    typeof s.title === "string" && s.title.length <= 60 && typeof s.default === "boolean");
}
export function validateLogos(code) {
  if (typeof code !== "string" || code.length < 8 || code.length > MAX_CODE) return "size";
  for (const r of FORBIDDEN) if (r.test(code)) return "forbidden:" + r.source;
  if (/%ctor|%dtor|%group|%end\s*\n.*%end/s.test(code) && /%group\s+Main/.test(code) === false && /%group/.test(code)) return "group";
  if (/%ctor|%dtor/.test(code)) return "ctor_reserved";
  // Only plain Foundation/UIKit/objc imports; no other preprocessor, attributes, module imports or build escapes.
  for (const line of code.split("\n")) {
    const t = line.trim();
    if (t.startsWith("#")) { if (!/^#\s*(import|include)\s*<(Foundation\/Foundation|UIKit\/UIKit|objc\/runtime|objc\/message)\.h>\s*$/.test(t)) return "directive"; }
  }
  if (/@import\b|__attribute__|\$\(|\\\s*$|%config|%subclass|%new\s*\(.*\)\s*\{.*system/m.test(code)) return "escape";
  return null;
}
export function settingsHeader(settings, values = {}) {
  return settings.map(s => "#define MIRSA_SETTING_" + s.key + " " + ((s.key in values ? values[s.key] : s.default) ? 1 : 0)).join("\n");
}
// The builder wraps generated hooks in %group Main and installs the crash guard.
export function assembleSource({ id, bundleID, code, settings, values }) {
  const guard = `#import <Foundation/Foundation.h>
// Crash guard: a launch that never reached the 8s "ok" mark counts as a crash. Two in a row disables the tweak.
static BOOL MirsaGuardAllow(void) {
  NSString *dir = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Caches"];
  NSString *path = [dir stringByAppendingPathComponent:@"mirsa_guard_${id}.plist"];
  NSMutableDictionary *d = [NSMutableDictionary dictionaryWithContentsOfFile:path] ?: [NSMutableDictionary dictionary];
  int crashes = [d[@"crashes"] intValue];
  if (![d[@"ok"] boolValue] && d[@"launched"]) crashes++; else if ([d[@"ok"] boolValue]) crashes = 0;
  if (crashes >= 2) { d[@"disabled"] = @YES; }
  d[@"crashes"] = @(crashes);
  d[@"ok"] = @NO; d[@"launched"] = @YES;
  [d writeToFile:path atomically:YES];
  if ([d[@"disabled"] boolValue]) return NO;
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 8 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
    NSMutableDictionary *e = [NSMutableDictionary dictionaryWithContentsOfFile:path] ?: [NSMutableDictionary dictionary];
    e[@"ok"] = @YES; e[@"crashes"] = @0; [e writeToFile:path atomically:YES];
  });
  return YES;
}`;
  return [settingsHeader(settings, values), guard, "%group Main", code, "%end",
    "%ctor { if (MirsaGuardAllow()) { %init(Main); } }", ""].join("\n");
}
export function parseModelJSON(text) {
  const m = String(text).match(/\{[\s\S]*\}/);
  if (!m) throw Error("model_json");
  const o = JSON.parse(m[0]);
  if (typeof o.code !== "string") throw Error("model_code");
  o.settings = Array.isArray(o.settings) ? o.settings : [];
  return o;
}

export const TEMP_TTL_MS = 24 * 3600_000;   // built dylib/.deb results in private storage
export const JOB_TTL_MS = 3600_000;         // queued source
export const MAX_DYLIB_BYTES = 4 * 1024 * 1024;
export const MAX_GALLERY_PER_USER = 20;
export function isExpired(createdMs, nowMs, ttl) { return nowMs - createdMs >= ttl; }
