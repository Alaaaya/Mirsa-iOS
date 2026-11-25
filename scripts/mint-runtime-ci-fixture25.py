#!/usr/bin/env python3
"""Mint the dedicated synthetic CI account fixture at job start, never in the app.
This key is accepted only by the staging auth realm, with an exact synthetic UUID,
bootstrap scope, audience and maximum one-hour lifetime. No production auth.
"""
import base64,hashlib,hmac,json,os,time,uuid

def mint(secret, now):
    def b64(raw): return base64.urlsafe_b64encode(raw).rstrip(b'=')
    claims={'iss':'urn:mirsa:runtime-staging25','aud':'mirsa-runtime-staging25',
            'sub':'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee','scope':'runtime:bootstrap',
            'iat':now,'exp':now+3600,'jti':str(uuid.uuid4())}
    data=b'.'.join(b64(json.dumps(v,separators=(',',':')).encode()) for v in ({'alg':'HS256'},claims))
    return (data+b'.'+b64(hmac.new(secret,data,hashlib.sha256).digest())).decode()

if __name__=='__main__':
    secret=os.environ.get('MIRSA_RT_CI_ISSUER_SECRET','').encode()
    if len(secret)<32: raise SystemExit('Private staging CI issuer secret is missing')
    token=mint(secret,int(time.time()))
    print('::add-mask::'+token)
    with open(os.environ['GITHUB_ENV'],'a') as output:
        output.write('MIRSA_RT_STAGING_TOKEN='+token+'\n')
        output.write('TEST_RUNNER_MIRSA_RT_STAGING_TOKEN='+token+'\n')
    print('One-hour synthetic staging fixture minted at runner start; no account creation or app credential embedding')
