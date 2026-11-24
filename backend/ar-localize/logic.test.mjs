import test from "node:test"; import assert from "node:assert/strict";
import { acceptable, sameTokens, validateRequest, parseModelMap, chunk } from "./logic.mjs";
test("placeholders must match as multiset", () => {
  assert.ok(sameTokens("%d items in %@", "%@ في %d"));
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
