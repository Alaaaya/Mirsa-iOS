#!/usr/bin/env python3
"""Fail early on stale CI fixture setup without logging credentials.
This only checks structural claims/time budget. The required native HTTPS gate
and staging server still verify the real signature, scope and network behavior.
"""
import base64
import json
import os
import sys
import time

def validate_budget(token, now, minimum=2700):
    try:
        parts = token.split(".")
        if len(parts) != 3 or len(token) > 4096:
            raise ValueError
        claims = json.loads(base64.urlsafe_b64decode(parts[1] + "=" * (-len(parts[1]) % 4)))
        exp, iat = claims["exp"], claims["iat"]
        if any(isinstance(v, bool) or not isinstance(v, (int, float)) for v in (exp, iat)):
            raise ValueError
        if (claims["iss"] != "urn:mirsa:runtime-staging25"
            or claims["aud"] != "mirsa-runtime-staging25"
            or claims["sub"] != "eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee"
            or claims["scope"] != "runtime:bootstrap"
            or claims["role"] != "authenticated"
            or not 0 < exp - iat <= 3600 or iat > now + 60):
            raise ValueError
    except (ValueError, KeyError, TypeError, UnicodeError):
        raise ValueError("Invalid staging fixture claims; refresh the private CI fixture.") from None
    if not minimum <= exp - now <= 3600:
        raise ValueError("Staging fixture has insufficient lifetime for native CI; refresh it before dispatch.")
    return int(exp - now)

if __name__ == "__main__":
    try:
        remaining = validate_budget(os.environ.get("MIRSA_RT_STAGING_TOKEN", ""), time.time())
        print(f"Staging fixture budget checked ({remaining} seconds remaining); native HTTPS verification remains required.")
    except ValueError as exc:
        print(str(exc), file=sys.stderr)
        sys.exit(1)
