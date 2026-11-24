import test from "node:test";
import assert from "node:assert/strict";
import { fetchModelJSON } from "./provider.mjs";
const result = { choices: [{ message: { content: '{"0":"مرحبا %@"}' } }] };
const ok = () => new Response(JSON.stringify(result));
function fixture(steps) {
  const calls = [], delays = [], warnings = [], signals = [];
  const runtime = {
    fetchImpl: async (...args) => { calls.push(args); const step = steps.shift(); if (step instanceof Error) throw step; return step; },
    pause: async ms => { delays.push(ms); },
    signal: () => { const signal = new AbortController().signal; signals.push(signal); return signal; },
    warn: reason => warnings.push(reason)
  };
  return { runtime, calls, delays, warnings, signals };
}
const url = "https://provider.invalid/chat/completions";
const options = { method: "POST", headers: { authorization: "Bearer test-only" }, body: JSON.stringify({ model: "configured-smart-model", messages: [] }) };
test("successful calls have no retry or delay", async () => {
  const f = fixture([ok()]); assert.deepEqual(await fetchModelJSON(url, options, f.runtime), result);
  assert.equal(f.calls.length, 1); assert.deepEqual(f.delays, []); assert.deepEqual(f.warnings, []);
});
test("a provider timeout retries once on the identical route/model/payload with a fresh deadline", async () => {
  const f = fixture([new DOMException("private upstream detail", "TimeoutError"), ok()]);
  assert.deepEqual(await fetchModelJSON(url, options, f.runtime), result);
  assert.equal(f.calls.length, 2); assert.deepEqual(f.delays, [1000]);
  for (const [target, init] of f.calls) { assert.equal(target, url); assert.equal(init.body, options.body); assert.deepEqual(init.headers, options.headers); }
  assert.notEqual(f.signals[0], f.signals[1]); assert.deepEqual(f.warnings, ["transport_or_timeout"]);
});
for (const status of [408, 429, 500, 502, 503, 504]) {
  test("transient HTTP " + status + " retries once without exposing the body", async () => {
    const f = fixture([new Response("private upstream text", { status }), ok()]);
    assert.deepEqual(await fetchModelJSON(url, options, f.runtime), result);
    assert.equal(f.calls.length, 2); assert.deepEqual(f.warnings, ["http_" + status]);
  });
}
for (const status of [400, 401, 403, 404]) {
  test("terminal HTTP " + status + " never retries or switches credentials", async () => {
    const f = fixture([new Response("private secret", { status }), ok()]);
    await assert.rejects(fetchModelJSON(url, options, f.runtime), /^Error: llm_failed$/);
    assert.equal(f.calls.length, 1); assert.deepEqual(f.warnings, []); assert.deepEqual(f.delays, []);
  });
}
test("two timeouts fail bounded, with no third call or untrusted diagnostic", async () => {
  const f = fixture([new DOMException("private token", "TimeoutError"), new TypeError("private body"), ok()]);
  await assert.rejects(fetchModelJSON(url, options, f.runtime), /^Error: llm_failed$/);
  assert.equal(f.calls.length, 2); assert.deepEqual(f.delays, [1000]); assert.deepEqual(f.warnings, ["transport_or_timeout"]);
});
test("exhausted provider quota stays busy after exactly two calls", async () => {
  const f = fixture([new Response("quota", { status: 429 }), new Response("quota", { status: 429 }), ok()]);
  await assert.rejects(fetchModelJSON(url, options, f.runtime), /^Error: busy$/); assert.equal(f.calls.length, 2);
});
test("malformed upstream JSON is retried once, never reported as a translation", async () => {
  const f = fixture([new Response("not JSON"), ok()]);
  assert.deepEqual(await fetchModelJSON(url, options, f.runtime), result); assert.equal(f.calls.length, 2);
});
