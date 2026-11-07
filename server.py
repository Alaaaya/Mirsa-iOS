"""Manifest-only MIME adapter. Fixed upstream, no credentials, request logging or disk."""
import os
import re
import urllib.request
import urllib.error
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlsplit, parse_qs

UPSTREAM = "https://hirebeofomiyumwysppj.supabase.co/functions/v1/certificate-ota"
class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass  # Capability tokens must never reach logs.
    def reply(self, status, body, mime="application/json"):
        self.send_response(status)
        for key, val in {"Content-Type": mime, "Content-Length": str(len(body)),
            "Cache-Control": "no-store, max-age=0", "Referrer-Policy": "no-referrer",
            "X-Content-Type-Options": "nosniff"}.items():
            self.send_header(key, val)
        self.end_headers()
        self.wfile.write(body)
    def do_GET(self):
        url = urlsplit(self.path)
        if url.path == "/health" and not url.query:
            return self.reply(200, b'{"ok":true}')
        args = parse_qs(url.query)
        tokens = args.get("token", [])
        if url.path != "/manifest.plist" or set(args) != {"token"} or len(tokens) != 1 or not re.fullmatch("[0-9a-f]{64}", tokens[0]):
            return self.reply(404, b'{"error":"not_found"}')
        req = urllib.request.Request(UPSTREAM + "?kind=manifest&token=" + tokens[0])
        try:
            with urllib.request.urlopen(req, timeout=15) as response:
                body = response.read(65537)
                if len(body)>65536 or not body.startswith(b'<?xml') or b'<plist' not in body:
                    return self.reply(502, b'{"error":"upstream"}')
                return self.reply(200, body, "text/xml; charset=utf-8")
        except urllib.error.HTTPError as error:
            return self.reply(error.code if error.code in (404,410,429) else 502, b'{"error":"unavailable"}')
        except Exception:
            return self.reply(502, b'{"error":"upstream"}')
    def do_POST(self):
        return self.reply(405, b'{"error":"method"}')
if __name__ == "__main__":
    ThreadingHTTPServer(("0.0.0.0", int(os.environ.get("PORT", "8080"))), Handler).serve_forever()
