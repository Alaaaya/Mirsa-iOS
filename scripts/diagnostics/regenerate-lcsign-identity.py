#!/usr/bin/env python3
"""Regenerate PUBLIC, synthetic signing material. Never use for distribution.

Only the dedicated LCSign fixture is replaced, not the P12 parser fixtures.
Apple TN2206 requires critical, codeSigning-only EKU for strict codesign.
The profile's other fields and the inert IPA remain unchanged.
"""
from pathlib import Path
import plistlib
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
FIXTURES = ROOT / 'tests/Fixtures'


def openssl(*args):
    return subprocess.run(['openssl', *map(str, args)], check=True, capture_output=True).stdout


def main():
    profile = FIXTURES / 'LCSignSynthetic.mobileprovision'
    content = plistlib.loads(openssl('cms', '-verify', '-inform', 'DER', '-in', profile, '-noverify'))
    with tempfile.TemporaryDirectory(prefix='mirsa-public-identity-') as temporary:
        work = Path(temporary)
        ca_key, ca = work / 'ca.key', work / 'ca.pem'
        leaf_key, csr, leaf = work / 'leaf.key', work / 'leaf.csr', work / 'leaf.pem'
        extensions = work / 'leaf.ext'
        extensions.write_text('basicConstraints=critical,CA:FALSE\n'
                              'keyUsage=critical,digitalSignature\n'
                              'extendedKeyUsage=critical,codeSigning\n'
                              'subjectKeyIdentifier=hash\n'
                              'authorityKeyIdentifier=keyid,issuer\n')
        openssl('req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-sha256',
                '-subj', '/O=Mirsa Public Test Only/CN=Mirsa-Test-CodeSign-CA',
                '-keyout', ca_key, '-out', ca, '-days', '3650',
                '-addext', 'basicConstraints=critical,CA:TRUE',
                '-addext', 'keyUsage=critical,keyCertSign,cRLSign')
        openssl('req', '-newkey', 'rsa:2048', '-nodes', '-sha256',
                '-subj', '/O=Mirsa Public Test Only/CN=Mirsa-Test-CodeSign-Leaf',
                '-keyout', leaf_key, '-out', csr)
        openssl('x509', '-req', '-in', csr, '-CA', ca, '-CAkey', ca_key,
                '-CAcreateserial', '-out', leaf, '-days', '3650', '-sha256', '-extfile', extensions)
        content['DeveloperCertificates'] = [openssl('x509', '-in', leaf, '-outform', 'DER')]
        payload = work / 'profile.plist'
        payload.write_bytes(plistlib.dumps(content))
        openssl('pkcs12', '-export', '-inkey', leaf_key, '-in', leaf,
                '-out', work / 'identity.p12', '-keypbe', 'AES-256-CBC', '-certpbe', 'AES-256-CBC',
                '-passout', 'pass:mirsa-test')
        openssl('cms', '-sign', '-binary', '-nodetach', '-in', payload,
                '-signer', leaf, '-inkey', leaf_key, '-certfile', ca, '-md', 'sha256',
                '-outform', 'DER', '-out', work / 'profile.der')
        # Verify actual CMS bytes before replacing the two public fixtures.
        assert plistlib.loads(openssl('cms', '-verify', '-inform', 'DER', '-in',
                                      work / 'profile.der', '-noverify')) == content
        (FIXTURES / 'LCSignSynthetic.p12').write_bytes((work / 'identity.p12').read_bytes())
        profile.write_bytes((work / 'profile.der').read_bytes())
    print('Regenerated dedicated PUBLIC code-signing fixture identity and matching profile')


if __name__ == '__main__':
    main()
