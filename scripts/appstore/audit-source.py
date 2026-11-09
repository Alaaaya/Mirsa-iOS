#!/usr/bin/env python3
"""Deterministic integration-boundary checks. Not runtime authentication proof."""
import pathlib
import subprocess
import sys

repo = pathlib.Path(__file__).resolve().parents[2]
source = repo / "ios-app" / "AppStore"
text = "\n".join(p.read_text() for p in source.glob("*.swift"))
checks = {
    "no file-account persistence helpers": "saveLoginAccount(" not in text and "withAccount(" not in text,
    "no UserDefaults secret persistence": "UserDefaults" not in text,
    "no logging in integration": all(s not in text for s in ["print(", "debugPrint(", "NSLog(", "Logger.info", "Logger.debug"]),
    "no-op dependency logger": "SwiftLogNoOpLogHandler()" in text,
    "non-sync Keychain": "kSecAttrSynchronizable as String: false" in text,
    "unlocked device-only Keychain": "kSecAttrAccessibleWhenUnlockedThisDeviceOnly" in text,
    "CDN no cookie jar": "config.httpCookieStorage = nil" in text and "config.httpShouldSetCookies = false" in text,
    "CDN no credential storage or cache": "config.urlCredentialStorage = nil" in text and "config.urlCache = nil" in text,
    "ephemeral CDN": "URLSessionConfiguration.ephemeral" in text,
    "account is not cached in actor": "private var account: Account" not in text,
    "no unsigned authentication fallback": "try await Authenticator()" in text and "URLSession" not in (source / "StoreEngine.swift").read_text(),
    "signout invalidates generations": "generation &+= 1" in text and "run == generation" in text,
    "CDN cancellation on signout": "packages.cancel()" in text,
}
if len(sys.argv) == 2:
    reference = pathlib.Path(sys.argv[1])
    revision = subprocess.check_output(["git", "-C", str(reference), "rev-parse", "HEAD"], text=True).strip()
    checks["pinned dependency source"] = revision == "391bfe6ee6598d73e4f94b88b38b50bd6f6ec67b"
    auth = (reference / "Sources/ApplePackage/Commands/Authenticate.swift").read_text()
    sap = (reference / "Sources/ApplePackage/SAP/SAPSigner+Connect.swift").read_text()
    http = (reference / "Sources/ApplePackage/Configuration/Configuration+HTTPClient.swift").read_text()
    checks["native actor auth signature"] = 'public func authenticate(email: String, password: String, code: String = "") async throws -> Account' in auth
    checks["fresh signer required in auth init"] = "signer = try await SAPSigner.connect()" in auth
    checks["exact login bytes signed"] = "let signature = try await sapSigner.sign(data)" in auth and '("X-Apple-ActionSignature", signature.base64EncodedString())' in auth
    checks["native SAP fresh setup required"] = "static func connect() async throws -> SAPSigner" in sap and "SAPHandshake(certificate: certificate)" in sap and "handshake.complete(reply)" in sap
    checks["dependency HTTP uses NIO not Foundation disk storage"] = "HTTPClient(" in http and "URLSession" not in http
for name, passed in checks.items():
    print(("PASS " if passed else "FAIL ") + name)
raise SystemExit(0 if all(checks.values()) else 1)
