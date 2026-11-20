import assert from "node:assert/strict";
import { test } from "node:test";
import { validateUpload, validateList, validateStars, ratingAvg, safeFileName, cleanTarget, publicItem, safeEqual, MAX_BYTES } from "./logic.mjs";

const base = { category: "tweaks", title: "Dark mode", file_name: "Dark.dylib", file_size: 1024 };

test("upload accepts allowed types per category", () => {
  assert.ok(validateUpload(base).value);
  assert.equal(validateUpload({ ...base, category: "wallpapers", file_name: "a.tendies" }).value.file_ext, "tendies");
  assert.equal(validateUpload({ ...base, category: "fonts", file_name: "x.ttf" }).value.category, "fonts");
  assert.equal(validateUpload({ ...base, category: "sounds", file_name: "r.m4r" }).value.file_ext, "m4r");
});

test("upload rejects wrong extension, size, category and missing target", () => {
  assert.equal(validateUpload({ ...base, file_name: "x.ipa" }).error, "bad_extension");
  assert.equal(validateUpload({ ...base, category: "wallpapers" }).error, "bad_extension");
  assert.equal(validateUpload({ ...base, category: "icons" }).error, "bad_category");
  assert.equal(validateUpload({ ...base, file_size: MAX_BYTES + 1 }).error, "too_large");
  assert.equal(validateUpload({ ...base, file_size: 0 }).error, "bad_file");
  assert.equal(validateUpload({ ...base, title: " " }).error, "bad_title");
  assert.equal(validateUpload({ ...base, category: "app_tweaks" }).error, "bad_target");
  assert.equal(validateUpload({ ...base, category: "app_tweaks", target_app: "YouTube" }).value.target_app, "youtube");
  assert.equal(validateUpload({ ...base, category: "app_tweaks", target_app: "com.burbn.instagram" }).value.target_app, "com.burbn.instagram");
});

test("file names are storage safe", () => {
  assert.equal(safeFileName("../../evil name!.dylib"), "evil-name.dylib");
  assert.equal(safeFileName("خط.ttf"), "item.ttf");
  assert.equal(cleanTarget("rm -rf /"), null);
});

test("list clamps and sanitizes", () => {
  const v = validateList({ category: "fonts", sort: "downloads", limit: 999, q: "a%_'b" }).value;
  assert.equal(v.limit, 100);
  assert.equal(v.column, "downloads");
  assert.ok(!v.q.includes("%") && !v.q.includes("'"));
  assert.equal(validateList({ category: "fonts", sort: "drop table" }).value.sort, "new");
  assert.equal(validateList({ category: "x" }).error, "bad_category");
});

test("ratings", () => {
  assert.equal(validateStars(5), 5);
  assert.equal(validateStars(0), null);
  assert.equal(validateStars(2.5), null);
  assert.equal(ratingAvg(9, 2), 4.5);
  assert.equal(ratingAvg(0, 0), 0);
});

test("public item hides private fields", () => {
  const out = publicItem({ id: "1", category: "fonts", title: "t", file_name: "a.ttf", uploader: "u", storage_path: "p", rating_sum: 7, rating_count: 2 });
  assert.equal(out.uploader, undefined);
  assert.equal(out.storage_path, undefined);
  assert.equal(out.rating_avg, 3.5);
});

test("admin token compare", () => {
  assert.ok(safeEqual("abc", "abc"));
  assert.ok(!safeEqual("abc", "abd"));
  assert.ok(!safeEqual("abc", "abcd"));
});

test("headers reject renamed scripts and accept supported containers without executing them", async () => {
  const { inspectHeader } = await import("./logic.mjs");
  const bytes = s => new TextEncoder().encode(s);
  assert.equal(inspectHeader("dylib", bytes("#!/bin/sh\n")), "header_mismatch");
  assert.equal(inspectHeader("dylib", Uint8Array.from([0xcf,0xfa,0xed,0xfe])), null);
  assert.equal(inspectHeader("deb", bytes("!<arch>\n")), null);
  assert.equal(inspectHeader("tendies", bytes("PK\x03\x04")), null);
  assert.equal(inspectHeader("zip", bytes("<html>")), "header_mismatch");
  assert.equal(inspectHeader("m4r", bytes("\0\0\0\x18ftypM4A ")), null);
  assert.equal(inspectHeader("wav", bytes("RIFFxxxxWAVE")), null);
  assert.equal(inspectHeader("ttf", Uint8Array.from([0,1,0,0])), null);
  assert.equal(inspectHeader("otf", bytes("OTTO")), null);
  assert.equal(inspectHeader("ttc", bytes("ttcf")), null);
  for (const ext of ["dylib","deb","zip","tendies","mp3","caf","wav","ttf","otf","ttc"]) {
    assert.equal(inspectHeader(ext, new Uint8Array()), "header_mismatch");
  }
});

test("bounded reads stop oversized bodies and cancel ignored Range responses", async () => {
  const { readBounded } = await import("./logic.mjs");
  const stream = () => new Response(new Uint8Array(100_000)).body;
  await assert.rejects(readBounded(stream(), 100), /body_too_large/);
  assert.equal((await readBounded(stream(), 512, true)).length, 512);
  assert.equal((await readBounded(new Response("abc").body, 100)).length, 3);
});
