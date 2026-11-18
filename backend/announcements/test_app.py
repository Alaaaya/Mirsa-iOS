import html
import hashlib
import io
import json
from unittest.mock import patch
from pathlib import Path
import re
import tempfile
import unittest
from werkzeug.security import generate_password_hash
from app import create_app, verified_owner

ORIGIN = "https://mirsa-app.mooo.com"
OWNER = {"uid": "test-user", "device": "test-device", "tokenHash": "a"*64}
class AnnouncementTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.password_hash = generate_password_hash("unit-test-password")
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.now = 1000000
        self.app = create_app(dict(TESTING=True, SECRET_KEY="unit-test-session-secret",
            PASSWORD_HASH=self.password_hash, OWNER=OWNER, DATABASE=str(Path(self.tmp.name)/"test.db")),
            verify=lambda headers, owner: headers.get("Authorization") == "Bearer verified-owner",
            clock=lambda: self.now)
        self.client = self.app.test_client()
    def tearDown(self):
        self.tmp.cleanup()
    def csrf(self, client=None):
        response = (client or self.client).get("/admin", base_url=ORIGIN)
        return html.unescape(re.search('name="csrf_token" value="([^"]+)"', response.text)[1])
    def post(self, path, data):
        return self.client.post(path, data={"csrf_token": self.csrf(), **data},
                                base_url=ORIGIN, headers={"Origin": ORIGIN, "Referer": ORIGIN+"/admin"})
    def login(self):
        self.assertEqual(self.post("/admin/login", {"password":"unit-test-password"}).status_code,303)
    def send(self, **kwargs):
        return self.post("/admin", dict(title="Hello", message="Body", language="all", target="owner", **kwargs))
    def test_real_identity_verifier_requires_signed_account_and_bound_device(self):
        token = "a-secure-unit-test-token-long-enough-for-binding"
        uid = "80dfdf2a-542c-4143-be94-5925aa805906"
        owner = dict(uid=uid, device="device-unit-test", authPublishableKey="public-unit-test-key", tokenHash=hashlib.sha256(token.encode()).hexdigest())
        headers = {"Authorization":"Bearer " + "x"*80, "x-mirsa-device":owner["device"], "x-mirsa-device-token":token}
        class Response(io.BytesIO):
            status = 200
        with patch("app.urllib.request.build_opener") as opener:
            for field, wrong in [("x-mirsa-device","someone-else"),("x-mirsa-device-token","x"*40),("Authorization","invalid")]:
                self.assertFalse(verified_owner(dict(headers, **{field:wrong}), owner))
            opener.assert_not_called()
            for body, expected in [
                (dict(id=uid, role="authenticated"),True),
                (dict(id="00000000-0000-0000-0000-000000000000",role="authenticated"),False),
                (dict(id=uid,role="anon"),False), ({},False)]:
                opener.return_value.open.return_value=Response(json.dumps(body).encode())
                self.assertEqual(verified_owner(headers,owner),expected)
            opener.return_value.open.side_effect=OSError("offline")
            self.assertFalse(verified_owner(headers,owner))
    def test_unauthenticated_write_and_wrong_password(self):
        self.assertEqual(self.send().status_code,401)
        self.assertEqual(self.post("/admin/login", {"password":"wrong"}).status_code,401)
    def test_csrf_origin_and_cookie_flags(self):
        token=self.csrf()
        response=self.client.post("/admin/login",data={"password":"unit-test-password"},base_url=ORIGIN,headers={"Origin":ORIGIN,"Referer":ORIGIN+"/admin"})
        self.assertEqual(response.status_code,400)
        response=self.client.post("/admin/login",data={"csrf_token":token,"password":"unit-test-password"},base_url=ORIGIN,headers={"Origin":"https://evil.example"})
        self.assertEqual(response.status_code,403)
        response=self.post("/admin/login",{"password":"unit-test-password"})
        cookie=response.headers["Set-Cookie"]
        for flag in ["Secure","HttpOnly","SameSite=Strict","Path=/"]:
            self.assertIn(flag,cookie)
    def test_target_never_leaks_public_or_wrong_identity(self):
        self.login()
        self.assertEqual(self.send().status_code,303)
        for headers in [{},{"Authorization":"Bearer impostor"}]:
            response=self.client.get("/announcements/v1/messages?language=ar",base_url=ORIGIN,headers=headers)
            self.assertEqual(response.json["messages"],[])
        response=self.client.get("/announcements/v1/messages?language=ar",base_url=ORIGIN,headers={"Authorization":"Bearer verified-owner"})
        rows=response.json["messages"]
        self.assertEqual(len(rows),1)
        self.assertEqual(rows[0]["target"],"owner")
        first=rows[0]["id"]
        self.assertEqual(first,self.client.get("/announcements/v1/messages?language=ar",base_url=ORIGIN,headers={"Authorization":"Bearer verified-owner"}).json["messages"][0]["id"])
        # Persistence across a new application instance, not an in-memory queue.
        second=create_app(dict(self.app.config),verify=lambda *_:True,clock=lambda:self.now)
        self.assertEqual(second.test_client().get("/announcements/v1/messages?language=ar",base_url=ORIGIN,headers={"Authorization":"Bearer x"}).json["messages"][0]["id"],first)
    def test_language_all_validation_plaintext_and_unique_ids(self):
        self.login()
        for language in ["de","all"]:
            self.assertEqual(self.post("/admin",dict(title="<script>alert(1)</script>",message="<b>text</b>",language=language,target="all")).status_code,303)
        for language,count in [("en",1),("de",2),("kmr",1),("ckb",1),("ar",1)]:
            rows=self.client.get("/announcements/v1/messages?language="+language,base_url=ORIGIN).json["messages"]
            self.assertEqual(len(rows),count)
            self.assertEqual(len({r["id"] for r in rows}),count)
        for field,value in [("language","tr"),("target","some-other-user"),("title","x"*101),("message",""),("message","bad\x00text")]:
            payload=dict(title="T",message="M",language="all",target="owner");payload[field]=value
            self.assertEqual(self.post("/admin",payload).status_code,400)
        self.assertEqual(self.client.get("/announcements/v1/messages?language=tr",base_url=ORIGIN).status_code,400)
    def test_rate_limit_expiry_and_logout(self):
        for _ in range(10):
            self.assertEqual(self.post("/admin/login",{"password":"wrong"}).status_code,401)
        self.assertEqual(self.post("/admin/login",{"password":"unit-test-password"}).status_code,429)
        self.now+=901
        self.login()
        self.now+=1801
        self.assertEqual(self.send().status_code,401)
        self.login()
        self.assertEqual(self.post("/admin/logout",{}).status_code,303)
        self.assertEqual(self.send().status_code,401)

if __name__=="__main__":
    unittest.main()
