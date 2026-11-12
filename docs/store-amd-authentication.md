# Native Store machine provisioning

The advertised bag endpoint is retained verbatim. The original SAP signer signs every authentication POST, including retries, over one frozen serialized body per password/code attempt. This supersedes and removes the unverified `/native/fast/` workaround in d106bfe.

Store device challenges are not two-factor authentication. HTTP 200 with X-Apple-AMD-Action SP or customerMessage AMD-Action::SP requires a bounded canonical base64 X-Apple-AMD-Data challenge. A local Store (-1) profile is provisioned without the Apple ID/password: native CPIM goes only to Apple's fixed HTTPS otp/1.5/finish endpoint; settingInfo and transportKey complete provisioning locally. Subsequent POSTs receive freshly generated X-Apple-AMD and X-Apple-AMD-M. RP erases the device-bound Keychain profile. Only one reset and at most two provisions separated by that reset are allowed, with eight total authentication rounds including redirects. Repeated SP/RP fails closed. No proxies, emulated Apple binaries, remote anisette services, or extra credential transmission are introduced.

The independent exact MZFinance.BadLogin.Configurator_message response with an empty failureType triggers the existing verification-code UI. The same SAP session is retained; the next attempt appends the code to the password, attempt 2, and freezes/signs the new body.

## Dependency provenance

Native algorithms are from apple-auth/apple-auth, MIT, pinned source 98c862f7bebc8283a9b87f1578e703f0765dc81d, release v0.1.3. The downloaded AppleAuth.zip SHA256 is 183c9bb77a97f98d2c1369be0ade5a5238170b8598536c050dc52213550b98fd, checked against upstream SHA256SUMS. The unmodified static libraries are vendored in an XCFramework to avoid an unpinned build-time dependency. Core C++ is exposed through a small Mirsa C bridge that explicitly selects ProfileKind::store; the library's generic C provisioning API defaults to GrandSlam and is intentionally not used.

Inspected upstream LICENSE, THIRD_PARTY_NOTICES, src/adi, include/apple_auth/core.hpp, src/client/store.cpp, and pinned Swift packaging. Upstream declares clean-room native ADI/SAP with recovered algorithm parameters and no emulated proprietary libraries. Its Apple binary uses CoreFoundation, not optional LGPL libplist. MIT and dependency notices are retained in LICENSES and bundled in ApplePackage's resources. GPL iPadn was consulted only for protocol interoperability, not copied or linked. Existing Mirsa SAP code remains unchanged.

## Validation

Offline regressions cover SP and RP, malformed/noncanonical/oversized challenges, retry bounds, unchanged endpoint and body, ActionSignature, fresh machine headers, Configurator code separation, and native malformed-input rejection. Xcode device compilation and tests must pass before the IPA is delivered. No credentials are used by these tests. No real-device or successful Apple-account login is claimed.

Xcode static XCFramework headers share the build product include directory. The apple_auth module map lives inside Headers/apple_auth (with its local client_c_api.h reference), avoiding a root include/module.modulemap collision with AirliftFFI. Static library bytes are unchanged.


## Owner review follow-up

AMD errors expose only an allowlisted step and numeric HTTP/Keychain status. The authentication diagnostic wrapper preserves this safe text for the existing login alert. No response payload, challenge, proof, profile, credentials or arbitrary transport description is included.

The same bounded handshake runs before HTTP status/redirect rejection, including non-200 challenges. A valid Apple HTTP Date synchronizes a local OTP time offset, used for both provisioning begin and fresh proof headers. A challenge without a valid Date fails with a distinct clock diagnostic rather than silently exhausting provisioning retries.

The production login loop accepts an internal injected signer/provider/executor for offline testing. Full-loop tests cover SP on 200/403/500/302 followed by success, repeated SP budget rejection, and SP then Configurator 2FA then code on the same Authenticator/signing state. Clock-skew and diagnostic wrapping regressions require no credentials or network. Device acceptance remains unproven until tested on the owner's iPhone.

## Additional owner review

AMD action headers are trimmed and uppercased; AMD-Action customer messages use the last colon component. Unknown challenges show تسجيل الجهاز ما كمل with only header-presence and challenge byte length in addition to the prior step/numeric-status diagnostics, never challenge contents.

A device-only random 32-byte Keychain salt binds the native hardware value and rotates on RP. An RP without a loaded profile is ignored. Unreadable profile Keychain results are no-profile, never a stale usable profile; persistence errors still fail safely during provisioning.

The bounded challenge responder also covers buyProduct and download dispatch before status/redirect handling. Fresh proof headers are allowed only on native/native-fast authentication and buyProduct, not dispatch, other Apple routes, or CDN. Dispatch retries preserve request parameters and the existing bounded pod redirects; no proof headers are sent on that route.

Configurator/2.21 is intentional protocol metadata, retained from the independently inspected iPadn protocol reference at 6adae1f0b32f0858fbbac0abad82ec9e0ffb6821, Services/HTTPClient.swift constant (not copied implementation). This confirms the reference choice, not Apple acceptance on a physical device.

Verification codes are trimmed and must be exactly six ASCII digits when supplied. Rejection has distinct الرمز مرفوض text; the existing UI retains its same Authenticator. Offline tests include SP during attempt 2 with the unchanged password-plus-code body, same signer and session.

MIRSA-PROVENANCE.txt is bundled with the existing MIT notices and lists each unmodified release static archive SHA256. Release binary provenance is not a reproducible source-build claim.

## Device second-step rejection investigation

The owner reached Apple's six-digit challenge on 4.86.1. The screenshot alone does not distinguish an expired/rejected code, changed re-entered password or a lost session. The existing client uses the same Authenticator, endpoint, SAP signer, merged response cookies and password-plus-trimmed-code attempt 2, matching the inspected protocol reference. No separate code-verification endpoint is indicated by that protocol.

A concrete cookie defect was found locally: Domain=.itunes.apple.com was compared including its leading dot, so it failed even for auth.itunes.apple.com and never reached the continuation. RFC 6265 domain matching ignores that leading dot. The correction retains HTTPS, path, expiry and hostname-boundary checks. Offline coverage now drives a real two-step Authenticator sequence with a dotted-domain Set-Cookie and asserts that attempt 2 carries the cookie and exact signed password-plus-code payload. A device confirmation is still needed; this source defect is not proof it caused this particular Apple rejection. No credentials or live authentication were used.


## 2FA rejection diagnostics after device build 4.89.1
The device still rejected verification after the cookie-domain correction. No
root cause can be determined from the old generic “code rejected” alert.
Inspection proves that two response branches discarded Apple's diagnostic and
classified unrelated failures as a bad code. They now preserve HTTP status,
password/2FA phase, bounded numeric failureType, and finite customerMessage
identifiers. Missing, empty and unrecognized fields are distinguished. Arbitrary
dialog text, names, headers, cookies, tokens and response bodies are never exported.
The alert does not assert an incorrect OTP when Apple only reports incomplete
verification.

The existing protocol is unchanged: first POST password with attempt=1; second
POST password+six-digit-code with attempt=2 on the same Authenticator, GUID,
signer and cookie jar, refreshing machine OTP headers. Offline regressions cover
a failed second POST and successful corrected-code retry on that same session,
plus exact signed bytes, fresh OTP/stable machine ID, and non-200 rejections.
MIT apple-auth reference 98c862f7 confirms this flow; public ipatool issues
485 and 442 provide mixed anecdotal corroboration, not device proof.
No GPL reference source was copied. No account login was attempted during
development. A successful archive proves compilation, not working owner login.
The next device alert is needed to establish the actual rejection reason.

## 5020 continuation safety
Two device accounts returned 5020 during 2FA. This is not proof of a real account
lock or of a particular serialization defect. The request format remains unchanged.
No live authentication, account reset or credential export was performed.

Source review found that the UI clears the initial password and asks for it again,
while the client previously accepted any re-entered value for the same challenge.
The challenge now binds the original password in memory for its existing five-minute
lifetime and rejects a changed re-entry before touching the signer or network. It is
never written to the vault and is discarded on success, expiry, sign-out or terminal
failure. This fixes a real continuity gap, not a proven explanation of both reports.

The client and Authenticator now reject duplicate normalized codes locally. Apple
5020 permanently terminates that challenge/session; another code cannot trigger
another HTTP request on it. Only an explicit new sign-in can create a new session.
Other code corrections still have the existing three-submission bound.

Offline regression coverage includes changed password, duplicate code, terminal
5020, exact signed body bytes through pod redirect and two-step continuation,
cookies, GUID, attempt, rmp and why=signIn. X-Dsid is not added speculatively:
the inspected reference extracts dsPersonId for the resulting account, which is
not evidence that an unknown pre-login DSID header should be synthesized.
The owner still needs to validate login on-device after an actual CI archive.


## Owner's hardware and 2FA routing hypotheses

Inspected pinned apple-auth `src/client/store.cpp` at
98c862f7bebc8283a9b87f1578e703f0765dc81d and the vendored `core.hpp`.
This dependency explicitly requires a 20-byte HardwareId and creates an independent
random 20-byte hardware binding beside a six-byte GUID and UUID device ID. The
binding is used consistently to provision/import/export the profile. It is not
the six-byte SAP machine ID in ipatool v2.6, nor the six-byte commerce GUID in
ipatool main's separate AppleMediaServices emulator. Substituting six bytes at
our C bridge would cause a 20-byte out-of-bounds read. No such change was made.
The dependency's X-Mme-Device-Id is on its separate GSA provisioning calls, not
its configurator authentication POST. Adding it to this POST is not supported
by the inspected reference, so no speculative identity headers were added.

The existing Authenticator persists the redirected endpoint, signer, cookies and
GUID across the code challenge. StoreClient.verify uses that same session,
without a bag request. AMD challenges are handled before HTTP failure/code
classification, including on attempt two. Added a combined offline regression
with pod redirect, first-step challenge/cookie, forbidden SP during code, updated
cookie, then success. It asserts the pod remains unchanged and the exact signed
password-plus-code body survives the AMD retry. These are offline protocol
properties, not proof of successful device login.

The prior generic alert could be generated locally before Apple was contacted:
UI password reentry conflicted with the frozen challenge password. The UI now
submits only the verification code and the original password remains in the
five-minute memory-only challenge. Distinct local validation messages say no
Apple request was made. Explicit Apple's failureType and bounded/redacted
customerMessage are retained on actual rejection. Malformed AMD messages remain
private and use safe device-challenge diagnostics instead.

The combined pod/SP regression exposed a real proof-header scope gap: after
provisioning on the legacy commerce authenticate endpoint, the retry omitted
AMD headers. The allowlist now includes only that exact path on buy.itunes.apple.com
and numeric pNN-buy pods, alongside the existing native and purchase paths.
Negative tests retain HTTP, lookalike host, other Apple host and extra-path denial.
This fixes an offline-observed protocol gap, not a verified on-device login.
