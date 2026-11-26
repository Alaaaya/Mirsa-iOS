#!/usr/bin/env python3
# Proof-only isolated source: serves VERBATIM bytes of an authenticated staging feed snapshot (scripts/proof/snap).
import json, ssl, sys, os, http.server
SNAP = os.path.join(os.path.dirname(os.path.abspath(__file__)), "snap")
LOG = open(sys.argv[2], "a")
class H(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers.get("Content-Length","0"))) or b"{}")
        cat = body.get("category") if body.get("action")=="list" else None
        LOG.write(json.dumps({"action":body.get("action"),"category":cat,"bearer_present":bool(self.headers.get("Authorization"))})+"\n"); LOG.flush()
        path = os.path.join(SNAP, "%s.json" % cat) if cat in ("app_tweaks","tweaks","wallpapers") else os.path.join(SNAP, "wallpapers.json")
        out = open(path,"rb").read()
        self.send_response(200); self.send_header("Content-Type","application/json"); self.send_header("Content-Length",str(len(out))); self.end_headers(); self.wfile.write(out)
    def log_message(self,*a): pass
ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER); ctx.load_cert_chain("proof/server.pem","proof/server.key")
s = http.server.ThreadingHTTPServer(("127.0.0.1", int(sys.argv[1])), H); s.socket = ctx.wrap_socket(s.socket, server_side=True); s.serve_forever()
