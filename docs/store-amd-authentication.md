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
