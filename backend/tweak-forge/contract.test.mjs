import assert from "node:assert/strict";
import { test } from "node:test";
import { validateLogos, validateSettings, assembleSource, parseModelJSON, validateName } from "./contract.mjs";
test("rejects dangerous code", () => {
  for (const bad of ['system("id");', '[[NSTask alloc] init];', 'dlopen("x",1);', '#import "/etc/passwd"', '__asm__("nop");', 'NSURLSession *s;'])
    assert.ok(validateLogos("%hook A\n" + bad + "\n%end"));
});
test("accepts plain hook and reserves ctor", () => {
  assert.equal(validateLogos("%hook UIView\n- (void)layoutSubviews { %orig; }\n%end"), null);
  assert.equal(validateLogos("%ctor { }  %hook A\n%end"), "ctor_reserved");
});
test("settings", () => {
  assert.ok(validateSettings([{ key: "dark", title: "Dark", default: true }]));
  assert.ok(!validateSettings([{ key: "Dark", title: "x", default: true }]));
  assert.ok(!validateSettings([{ key: "a", title: "x", default: 1 }]));
});
test("assemble wraps in group with guard and macros", () => {
  const s = assembleSource({ id: "abc", bundleID: "a.b", code: "%hook A\n%end", settings: [{ key: "dark", title: "d", default: true }], values: { dark: false } });
  assert.match(s, /#define MIRSA_SETTING_dark 0/);
  assert.match(s, /%group Main/);
  assert.match(s, /crashes >= 2/);
  assert.match(s, /%init\(Main\)/);
});
test("parse model json and names", () => {
  assert.equal(parseModelJSON('x {"code":"c","settings":[]} y').code, "c");
  assert.throws(() => parseModelJSON("none"));
  assert.ok(validateName("My Tweak") && !validateName("../x"));
});

import { isExpired, TEMP_TTL_MS, MAX_DYLIB_BYTES } from "./contract.mjs";
test("24h boundary", () => { assert.equal(isExpired(0, TEMP_TTL_MS - 1, TEMP_TTL_MS), false); assert.equal(isExpired(0, TEMP_TTL_MS, TEMP_TTL_MS), true); assert.equal(MAX_DYLIB_BYTES, 4194304); });
