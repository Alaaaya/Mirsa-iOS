"""Mirsa announcements. Isolated data, no access or request-body logging."""
import contextlib
import datetime
import hashlib
import hmac
import json
import os
from pathlib import Path
import re
import secrets
import sqlite3
import time
import urllib.error
import urllib.request
import uuid

from flask import Flask, abort, redirect, render_template, request, session, url_for
from flask_wtf.csrf import CSRFProtect
from werkzeug.security import check_password_hash

ORIGIN = "https://mirsa-app.mooo.com"
LANGUAGES = ("ar", "en", "de", "kmr", "ckb", "all")
AUTH = "https://hirebeofomiyumwysppj.supabase.co/auth/v1/user"


def verified_owner(headers, owner):
    """Same signed-user + opaque-device binding as Store; never enrolls or writes."""
    device = headers.get("x-mirsa-device", "")
    token = headers.get("x-mirsa-device-token", "")
    bearer = headers.get("Authorization", "")
    if not (device == owner["device"] and 32 <= len(token) <= 256 and
            hmac.compare_digest(hashlib.sha256(token.encode()).hexdigest(), owner["tokenHash"])):
        return False
    if not re.fullmatch(r"Bearer [A-Za-z0-9_.-]{40,4096}", bearer):
        return False
    class NoRedirect(urllib.request.HTTPRedirectHandler):
        def redirect_request(self, *args, **kwargs):
            return None
    req = urllib.request.Request(AUTH, headers={"Authorization": bearer, "apikey": owner["authPublishableKey"]})
    try:
        with urllib.request.build_opener(NoRedirect).open(req, timeout=6) as response:
            if response.status != 200:
                return False
            body = response.read(65537)
        if len(body) > 65536:
            return False
        obj = json.loads(body)
        return obj.get("role") == "authenticated" and hmac.compare_digest(str(uuid.UUID(obj["id"])), owner["uid"])
    except (ValueError, KeyError, TypeError, OSError):
        return False


def create_app(config=None, verify=verified_owner, clock=time.time):
    app = Flask(__name__)
    app.config.update(
        SECRET_KEY=None, PASSWORD_HASH=None, DATABASE=None, OWNER=None,
        SESSION_COOKIE_NAME="__Host-mirsa-announcements",
        SESSION_COOKIE_SECURE=True, SESSION_COOKIE_HTTPONLY=True,
        SESSION_COOKIE_SAMESITE="Strict", SESSION_COOKIE_PATH="/",
        PERMANENT_SESSION_LIFETIME=datetime.timedelta(minutes=30),
        MAX_CONTENT_LENGTH=16384, MAX_FORM_MEMORY_SIZE=16384, MAX_FORM_PARTS=10,
        TRUSTED_HOSTS=["mirsa-app.mooo.com", "localhost"],
    )
    if config is None:
        conf = json.loads(Path(os.environ["MIRSA_BROADCAST_CONFIG"]).read_text())
        app.config.update(SECRET_KEY=conf["sessionKey"], PASSWORD_HASH=conf["passwordHash"],
                          DATABASE=conf["database"], OWNER=conf["owner"])
    else:
        app.config.update(config)
    if not all(app.config.get(k) for k in ("SECRET_KEY", "PASSWORD_HASH", "DATABASE", "OWNER")):
        raise ValueError("Missing private announcement configuration")
    dbpath = app.config["DATABASE"]
    @contextlib.contextmanager
    def connect():
        db = sqlite3.connect(dbpath, timeout=10)
        try:
            with db:
                yield db
        finally:
            db.close()
    with connect() as db:
        db.executescript("""
            CREATE TABLE IF NOT EXISTS messages(
                id TEXT PRIMARY KEY, title TEXT NOT NULL, message TEXT NOT NULL,
                language TEXT NOT NULL, target TEXT NOT NULL, created REAL NOT NULL);
            CREATE TABLE IF NOT EXISTS rate_limits(
                bucket TEXT PRIMARY KEY, count INTEGER NOT NULL, expires REAL NOT NULL);
        """)
    def rate(bucket, limit, seconds):
        now = clock()
        with connect() as db:
            db.execute("BEGIN IMMEDIATE")
            db.execute("DELETE FROM rate_limits WHERE expires <= ?", (now,))
            row = db.execute("SELECT count FROM rate_limits WHERE bucket=?", (bucket,)).fetchone()
            if row and row[0] >= limit:
                abort(429)
            if row:
                db.execute("UPDATE rate_limits SET count=count+1 WHERE bucket=?", (bucket,))
            else:
                if db.execute("SELECT COUNT(*) FROM rate_limits").fetchone()[0] >= 10000:
                    abort(503)
                db.execute("INSERT INTO rate_limits VALUES(?,?,?)", (bucket, 1, now + seconds))
    @app.before_request
    def boundary():
        # Proxy header is overwritten by Caddy, and upstream binds loopback only.
        if not app.testing and request.headers.get("X-Mirsa-Broadcast-Proxy") != "1":
            abort(403)
        if request.path.startswith("/admin"):
            if request.method == "POST":
                if request.headers.get("Origin") != ORIGIN:
                    abort(403)
                ip = request.headers.get("X-Mirsa-Broadcast-IP", request.remote_addr or "")
                rate("admin-ip:" + ip, 10, 900)
                rate("admin-global", 100, 900)
            if session.get("authenticated") and clock() > session.get("expires", 0):
                session.clear()
    csrf = CSRFProtect(app)
    @app.after_request
    def security(response):
        response.headers.update({
            "Cache-Control": "no-store", "X-Content-Type-Options": "nosniff",
            "X-Frame-Options": "DENY", "Referrer-Policy": "no-referrer",
            "Content-Security-Policy": "default-src 'none'; style-src 'self' 'unsafe-inline'; form-action 'self'; frame-ancestors 'none'; base-uri 'none'",
        })
        return response

    @app.route("/admin", methods=["GET", "POST"])
    def admin():
        if request.method == "POST":
            if not session.get("authenticated"):
                abort(401)
            title = request.form.get("title", "").strip()
            message = request.form.get("message", "").strip()
            language = request.form.get("language", "")
            target = request.form.get("target", "")
            if not (1 <= len(title) <= 100 and 1 <= len(message) <= 2000 and
                    language in LANGUAGES and target in ("all", "owner")):
                abort(400)
            if any(ord(c) < 32 and c not in "\n\t" for c in title + message):
                abort(400)
            ident = str(uuid.uuid4())
            with connect() as db:
                db.execute("INSERT INTO messages VALUES(?,?,?,?,?,?)",
                           (ident, title, message, language, target, clock()))
            return redirect(url_for("admin", sent=ident), code=303)
        sent = request.args.get("sent", "")
        if not re.fullmatch(r"[0-9a-f-]{36}", sent):
            sent = ""
        return render_template("admin.html", authenticated=bool(session.get("authenticated")),
                               sent=sent, languages=LANGUAGES)

    @app.post("/admin/login")
    def login():
        password = request.form.get("password", "")
        if len(password) > 256 or not check_password_hash(app.config["PASSWORD_HASH"], password):
            abort(401)
        session.clear()
        session.update(authenticated=True, expires=clock() + 1800)
        session.permanent = True
        return redirect(url_for("admin"), code=303)

    @app.post("/admin/logout")
    def logout():
        session.clear()
        return redirect(url_for("admin"), code=303)

    @app.get("/announcements/v1/messages")
    def messages():
        language = request.args.get("language", "")
        if language not in LANGUAGES[:-1]:
            abort(400)
        # Public messages are intentionally public. Private tests require *both*
        # the signed account and its server-approved opaque device token.
        owner = verify(request.headers, app.config["OWNER"]) if request.headers.get("Authorization") else False
        with connect() as db:
            rows = db.execute(
                "SELECT id,title,message,language,target,created FROM messages "
                "WHERE created>=? AND language IN (?, 'all') AND (target='all' OR (target='owner' AND ?)) "
                "ORDER BY created DESC LIMIT 50", (clock() - 30 * 86400, language, owner)).fetchall()
        return {"version": 1, "messages": [
            {"id": r[0], "title": r[1], "message": r[2], "language": r[3],
             "target": "owner" if r[4] == "owner" else "all", "createdAt": r[5]}
            for r in reversed(rows)]}
    return app
