import test from "node:test"; import assert from "node:assert/strict";
import { acceptable, sameTokens, validateRequest, parseModelMap, chunk } from "./logic.mjs";
test("placeholders must match as multiset", () => {
  assert.ok(sameTokens("%d items in %@", "%d عناصر في %@"));
  assert.ok(!sameTokens("%d items", "عناصر"));
  assert.ok(!sameTokens("%1$@ and %2$@", "%1$@ و %1$@"));
  assert.ok(sameTokens("100%% done {name}", "تم 100%% {name}"));
  assert.ok(!sameTokens("<b>Hi</b>", "<b>مرحبا"));
});
test("stringsdict token", () => { assert.ok(sameTokens("%#@items@", "%#@items@ عنصر")); assert.ok(!sameTokens("%#@items@", "%#@x@")); });
test("acceptable rejects empty and control", () => {
  assert.ok(!acceptable("Hi", "  ")); assert.ok(!acceptable("Hi", "x\u0001")); assert.ok(acceptable("Hi", "مرحبا"));
  assert.ok(!acceptable("Hi", 5));
});
const ok = { bundleId: "com.a.b", version: "1.0", contentHash: "a".repeat(64), items: [{ id: "x", text: "Hi" }] };
test("request bounds", () => {
  assert.equal(validateRequest(ok), null);
  assert.equal(validateRequest({ ...ok, bundleId: "../x" }), "bad_bundle");
  assert.equal(validateRequest({ ...ok, contentHash: "zz" }), "bad_hash");
  assert.equal(validateRequest({ ...ok, items: [{ id: "x", text: "a" }, { id: "x", text: "b" }] }), "bad_item");
  assert.equal(validateRequest({ ...ok, items: [{ id: "x", text: "a".repeat(2001) }] }), "bad_item");
  assert.equal(validateRequest({ ...ok, items: [] }), "bad_items");
});
test("model map and chunk", () => {
  assert.deepEqual(parseModelMap('```json\n{"a":"b"}\n```'), { a: "b" });
  assert.equal(parseModelMap("nope"), null);
  assert.deepEqual(chunk([1,2,3],2), [[1,2],[3]]);
});

import { cacheHash, completeCachedTranslations } from "./logic.mjs";
test("cache requires every requested ID and placeholder, never a partial hit", () => {
  const items = [{ id: "0.0", text: "Hello %@" }, { id: "0.1", text: "Settings" }];
  assert.equal(completeCachedTranslations(items, { "0.1": "الإعدادات" }), null);
  assert.equal(completeCachedTranslations(items, { "0.0": "مرحبا %d", "0.1": "الإعدادات" }), null);
  assert.equal(completeCachedTranslations(items, { "0.0": " ", "0.1": "الإعدادات" }), null);
  assert.deepEqual({ ...completeCachedTranslations(items, { "0.0": "مرحبا %@", "0.1": "الإعدادات", other: "ignored" }) }, { "0.0": "مرحبا %@", "0.1": "الإعدادات" });
});
test("cache fingerprint binds actual source, IDs and supplied content hash", async () => {
  const h = "a".repeat(64), first = [{ id: "1", text: "Hello %@" }, { id: "0", text: "Settings" }];
  const key = await cacheHash(h, first);
  assert.match(key, /^[a-f0-9]{64}$/);
  assert.equal(key, await cacheHash(h, [...first].reverse()));
  assert.notEqual(key, await cacheHash(h, [{ id: "1", text: "Goodbye %@" }, first[1]]));
  assert.notEqual(key, await cacheHash(h, [{ id: "1", text: "Hello %d" }, first[1]]));
  assert.notEqual(key, await cacheHash(h, [{ id: "2", text: "Hello %@" }, first[1]]));
  assert.notEqual(key, await cacheHash("b".repeat(64), first));
});
test("cache lookup rejects inherited properties and arrays", () => {
  assert.equal(completeCachedTranslations([{ id: "a", text: "Hello" }], Object.create({ a: "مرحبا" })), null);
  assert.equal(completeCachedTranslations([{ id: "0", text: "Hello" }], ["مرحبا"]), null);
  assert.equal(completeCachedTranslations([{ id: "a", text: "Hello" }], null), null);
});

test("implicit arguments preserve order, explicit index and star mappings may reorder", () => {
  for (const [source, translated, expected] of [
    ["Plain text", "نص %n", false],
    ["%D %@", "%@ %D", false],
    ["%1$#@items@ %2$@", "%2$@ %1$#@items@", true],
    ["%1$#@items@ %2$@", "%2$@ %1$#@other@", false],
    ["%@ has %d items", "%d عناصر عند %@", false],
    ["%1$@ has %2$d items", "%2$d عناصر عند %1$@", true],
    ["%1$@ has %2$d items", "%1$d عناصر عند %2$@", false],
    ["%1$*2$.*3$f and %4$@", "%4$@ و %1$*2$.*3$f", true],
    ["%1$*2$.*3$f and %4$@", "%4$@ و %1$*3$.*2$f", false],
    ["%1$*f and %2$@", "%2$@ و %1$*f", false],
    ["%*.*f and %@", "%@ و %*.*f", false],
    ["%#@items@ for %@", "%@ مع %#@items@", false],
    ["%% %@ %d", "%@ %d %%", true],
    ["%%@ %d", "%d %%@", true],
  ]) assert.equal(sameTokens(source, translated), expected, source);
});
