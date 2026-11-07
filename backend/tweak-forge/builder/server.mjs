// Isolated Theos builder. Runs on a Linux host with Docker; each build is a throwaway container with NO network, no secrets.
import http from "node:http";
import { mkdtempSync, writeFileSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { spawn } from "node:child_process";
const SECRET = process.env.TWEAK_BUILDER_SECRET;
const IMAGE = process.env.THEOS_IMAGE ?? "mirsa-theos:latest";
if (!SECRET) throw Error("TWEAK_BUILDER_SECRET required");
let busy = 0;
function run(cmd, args, timeout) {
  return new Promise(res => { const p = spawn(cmd, args); let out = ""; p.stdout.on("data", d => out += d); p.stderr.on("data", d => out += d);
    const t = setTimeout(() => p.kill("SIGKILL"), timeout); p.on("close", c => { clearTimeout(t); res({ code: c, out }); }); });
}
http.createServer(async (req, res) => {
  if (req.method !== "POST" || req.url !== "/build" || req.headers.authorization !== "Bearer " + SECRET) { res.writeHead(401).end(); return; }
  if (busy >= 2) { res.writeHead(429).end("busy"); return; }
  const chunks = []; let size = 0;
  for await (const c of req) { size += c.length; if (size > 100000) { res.writeHead(413).end(); return; } chunks.push(c); }
  busy++;
  const dir = mkdtempSync(join(tmpdir(), "forge-"));
  try {
    const { name, bundleID, source } = JSON.parse(Buffer.concat(chunks));
    if (!/^[A-Za-z0-9]{1,40}$/.test(name) || !/^[A-Za-z0-9.-]{3,155}$/.test(bundleID)) throw Error("bad input");
    writeFileSync(join(dir, "Tweak.xm"), source);
    writeFileSync(join(dir, "Makefile"), `TARGET := iphone:clang:latest:14.0\nARCHS = arm64 arm64e\ninclude $(THEOS)/makefiles/common.mk\nTWEAK_NAME = ${name}\n${name}_FILES = Tweak.xm\n${name}_CFLAGS = -fobjc-arc -Wno-error\ninclude $(THEOS_MAKE_PATH)/tweak.mk\n`);
    writeFileSync(join(dir, "control"), `Package: com.mirsa.forge.${name.toLowerCase()}\nName: ${name}\nVersion: 1.0\nArchitecture: iphoneos-arm\nDescription: Mirsa generated tweak\nMaintainer: Mirsa\nAuthor: Mirsa\nSection: Tweaks\n`);
    const r = await run("docker", ["run", "--rm", "--network", "none", "--read-only", "--tmpfs", "/tmp", "--memory", "1g", "--cpus", "1", "--pids-limit", "256",
      "--cap-drop", "ALL", "--security-opt", "no-new-privileges", "-v", dir + ":/work", "-w", "/work", IMAGE, "sh", "-c", "make package FINALPACKAGE=1 THEOS_PACKAGE_SCHEME= 2>&1 | tail -60"], 150000);
    let dylib;
    try { dylib = readFileSync(join(dir, ".theos/obj/" + name + ".dylib")); } catch {}
    if (!dylib) { try { dylib = readFileSync(join(dir, ".theos/obj/arm64/" + name + ".dylib")); } catch {} }
    if (r.code !== 0 || !dylib) { res.writeHead(422).end(r.out.slice(-4000)); return; }
    res.writeHead(200, { "content-type": "application/octet-stream" }).end(dylib);
  } catch (e) { res.writeHead(400).end(String(e.message)); }
  finally { busy--; rmSync(dir, { recursive: true, force: true }); }
}).listen(Number(process.env.PORT ?? 8787), "0.0.0.0");
