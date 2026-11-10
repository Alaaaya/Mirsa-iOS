# 1.3.240 sign-in investigation

The device report is immediate generic failure on LTE, with no code received on any trusted
device. No authenticated Apple request from that device was observed. Diagnostics and a
verification form are not proof of fixing the original authentication failure, and absence
of a code is not proof that Apple rejected the endpoint.

## Independently observed public behavior

The account-free probe at 2026-11-09T16:51:19Z used the package's Configurator user-agent,
no cookies, no account, no credential guesses, no automatic redirects and no login POST.
The two bag GETs (guid only and maintained ipatool's ix=6 plus guid) both returned HTTP 200.
Both advertised the same authenticateAccount legacy buy endpoint, sign-sap-version 200,
fpinit legacy SAP setup URL and mzstatic setupCert URL. Certificate GET returned HTTP 200
with a 2385-byte sign-sap-setup-cert value.

The bare legacy authenticate GET returned 404 with an empty body. The trailing-slash
legacy GET returned 500 HTML. The native/fast/ GET returned 404 HTML. Earlier GET observations
differed (including 403); none of these GET requests is a signed authentication POST.
They do not establish account acceptance, lack of LTE support, or the root cause.
Raw-body hashes and exact public URLs are in the separate public-probe-latest.json proof.

The opt-in CI preflight fetches the real bag, validates protocol 200, performs the real
SAP certificate/setup exchange and signs public test bytes locally. It never calls
Authenticator.authenticate or sends test credentials. Its result must be reported separately
from offline tests, device compilation and real-device account sign-in.

## Exact source comparisons

ApplePackage remote HEAD independently checked as
391bfe6ee6598d73e4f94b88b38b50bd6f6ec67b, identical to our original pin.
Our vendored source therefore does not solve this by merely updating a stale dependency.
Upstream is https://github.com/Lakr233/ApplePackage .

Maintained ipatool main independently resolved to
536d7bacc1c579d4420d0f4d2045368dcbf68732. Source snapshots for appstore_bag.go,
appstore_login.go, appstore_native_login.go, action_signer.go, signer_local.go and HTTP
constants are retained in the evidence directory. https://github.com/majd/ipatool

Both use an Apple bag, the Configurator 2.17 user-agent, protocol-200 SAP setup,
X-Apple-ActionSignature over exact serialized request bytes, a GUID in the plist,
password plus code when verifying, rmp=0 and why=signIn. Mirsa's app generates a
six-byte random identifier once, stores its uppercase 12-hex representation in device-only
Keychain and reuses it across sessions. This is an app identity, not a claim to read the
iPhone's restricted MAC. The same GUID is passed to bag and login.

Important differences remain. ipatool derives hardware identity from the host MAC and passes
it into its Apple runtime; ApplePackage's reconstructed native SAP handshake has no
hardware-ID argument. There is no evidence that supplying a GUID to Configuration also
binds it cryptographically into this handshake. This difference is documented, not
papered over by fake MACs, headers, extracted Apple runtime blobs or an unsigned fallback.
Current ipatool additionally has a native provisioning backend, AMD proof headers and
machine-action handling. Porting it is not a one-line header change, and those fields
must not be fabricated. We do not assume those paths are required by this device report.

Mirsa previously used initial attempt=4, unlike maintained ipatool's attempt=1. The local
patch aligns initial attempt=1 and verification attempt=2. This is a contract correction,
not evidence that attempt=4 caused this failure. The signing tests assert those fields
and that the exact bytes sent are the bytes signed.

ApplePackage's bag parser permits a default auth route when configuration is missing.
Authentication now explicitly requires the advertised supported protocol and known SAP
endpoints before accepting credentials. Download-only parsing remains unchanged. A future
unsupported Apple configuration fails closed instead of signing against stale assumptions.
No automatic password resubmission is added.

## Remaining acceptance boundary

Offline diagnostics tests, a successful public SAP exchange, and a compiled IPA cannot
prove account login, delivered 2FA, or LTE behavior. The release may improve safe reporting
and correct the request contract; it must not be described as proven LTE-login repair.
Only a real-device sign-in result with the new safe stage/status/code can close that gap.


## 2026-11-10 device HTTP 204 follow-up

Owner tested 1.6 and received HTTP 204 at authentication, with no 2FA notification.
This is not evidence of an accepted password or a verification-code request.

Fresh upstream ipatool checkout e0e2908dc866651cbd6ad86edd954119c003c46b
includes the native Store AMD implementation from merged PR 643.
See https://github.com/majd/ipatool/issues/642 and
https://github.com/majd/ipatool/pull/643 .
The newer Apple bag advertises https://auth.itunes.apple.com/auth/v1/native .
The existing native-to-fast rewrite is incorrect and has been removed in this branch.
This does NOT establish that Mirsa's reported 204 used that endpoint; no owner
credentials or private device HTTP capture were collected.

Native sign-in needs actual X-Apple-AMD and X-Apple-AMD-M proof and RP/SP machine
provisioning. AuthKit X-Apple-I-MD data is not a substitute. Upstream obtains these
locally through emulated AppleMediaServices/ADI/FairPlay with persistent machine state.
Its tools/build-ios.sh explicitly builds a standalone executable for JAILBROKEN iOS.
The Unicorn iOS patch changes memory from writable to executable with mprotect, and
the executable uses a private no-container entitlement. This is not a supported
drop-in backend for an ordinary signed, sandboxed Mirsa install. We did not copy
binary blobs, invent AMD fields, invoke private AMS APIs, or proxy login credentials.

Apple AuthenticationServices documents signing into one's own service, AutoFill,
and web authentication. It does not document obtaining the App Store passwordToken
and Store AMD proof needed by this downloader.
https://developer.apple.com/documentation/authenticationservices

Safety-only branch kat/auth20-safe is based on exact 1.9 production 674042d.
It preserves native URLs and fails closed for an advertised native flow BEFORE
password storage or submission. Legacy 204 keeps the real HTTP status and gives
localized guidance, not a fake verification form or fake resend-code button.
Existing explicit Apple challenge continuation remains unchanged and bounded.
The official App Store is a temporary option for normal app installs, not a claim
that it exports an IPA into Mirsa. Existing owned IPA imports still work unchanged.

No real-device sign-in repair is claimed. A supported local native-proof provider
remains the blocker. This branch must not be promoted as a working auth hotfix.
Feature CI is deliberately separate from all production publishers. Version 2.0
is used only for its isolated test artifact; 1.8/1.9 are not overwritten.
