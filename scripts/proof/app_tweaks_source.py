#!/usr/bin/env python3
# Proof-only isolated catalog source: speaks the existing tools-store POST contract. Not production.
import json, ssl, sys, http.server
LOG = open(sys.argv[2], "a")
ITEM = {"id":"proof-scinsta","category":"app_tweaks","title":"SCInsta","description":"تويك لإنستغرام (مصدر الإثبات المعزول)",
 "target_app":"instagram","version":"1.0.0","file_name":"SCInsta.dylib","file_size":4096,"author_name":"SoCuul",
 "downloads":0,"rating_avg":0,"rating_count":0,"status":"approved"}
class H(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers.get("Content-Length","0"))) or b"{}")
        LOG.write(json.dumps({"action":body.get("action"),"category":body.get("category"),"auth":bool(self.headers.get("Authorization"))})+"\n"); LOG.flush()
        items = [ITEM] if body.get("action")=="list" and body.get("category")=="app_tweaks" else []
        out = json.dumps({"items":items}).encode()
        self.send_response(200); self.send_header("Content-Type","application/json"); self.send_header("Content-Length",str(len(out))); self.end_headers(); self.wfile.write(out)
    def log_message(self,*a): pass
ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER); ctx.load_cert_chain("proof/server.pem","proof/server.key")
s = http.server.ThreadingHTTPServer(("127.0.0.1", int(sys.argv[1])), H); s.socket = ctx.wrap_socket(s.socket, server_side=True); s.serve_forever()
