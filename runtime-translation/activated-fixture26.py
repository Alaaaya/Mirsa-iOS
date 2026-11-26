#!/usr/bin/env python3
"""Generate a fresh CI-only RSA key and capability, never use production credentials."""
import base64, hashlib, json, pathlib, plistlib, subprocess, time
p=pathlib.Path('.')
def b64(b): return base64.urlsafe_b64encode(b).rstrip(b'=').decode()
def compact(x): return json.dumps(x,separators=(',',':')).encode()
subprocess.run(['openssl','genpkey','-algorithm','RSA','-pkeyopt','rsa_keygen_bits:2048','-out','ci-key.pem'],check=True,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
subprocess.run(['openssl','rsa','-in','ci-key.pem','-RSAPublicKey_out','-outform','DER','-out','ci-public.der'],check=True,stderr=subprocess.DEVNULL)
key=p.joinpath('ci-public.der').read_bytes()
p.joinpath('ActivationKey.h').write_text('static const unsigned char activation_key[]={'+','.join(map(str,key))+'};\n')
now=int(time.time());token='mrt1.'+'a'*64;revision='b'*64;bundle='com.mirsa.ci.translationlaunch26'
claims=dict(iss='urn:mirsa:translation25',aud='mirsa-translated-app',sub='local-fixture',bundleId=bundle,revision=revision,installationId='local-fixture',capHash=hashlib.sha256(token.encode()).hexdigest(),iat=now,exp=now+3600)
message=(b64(compact(dict(alg='RS256',typ='JWT')))+'.'+b64(compact(claims))).encode()
p.joinpath('ci-message').write_bytes(message)
subprocess.run(['openssl','dgst','-sha256','-sign','ci-key.pem','-out','ci-signature','ci-message'],check=True)
import datetime
online=dict(endpoint='https://activated.fixture.invalid/runtime',token=token,bundleId=bundle,revision=revision,installationId='local-fixture',activation=message.decode()+'.'+b64(p.joinpath('ci-signature').read_bytes()),expiresAt=datetime.datetime.fromtimestamp(now+3600,datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'))
config=dict(translations={},substrings={},regex=[],online=online)
p.joinpath('MirsaTranslations.json').write_bytes(compact(config))
data=compact(config)
p.joinpath('Table.h').write_text('static const unsigned char runtime_table[]={'+','.join(map(str,data))+'};\nstatic const unsigned long runtime_table_len=sizeof(runtime_table);\n')
app=p.joinpath('Activated.app');app.mkdir(exist_ok=True)
app.joinpath('Info.plist').write_bytes(plistlib.dumps(dict(CFBundleIdentifier=bundle,CFBundleExecutable='Activated',CFBundlePackageType='APPL',CFBundleName='Activated',CFBundleVersion='1',CFBundleShortVersionString='1.0',LSRequiresIPhoneOS=True,UIDeviceFamily=[1,2],UILaunchScreen={})))
