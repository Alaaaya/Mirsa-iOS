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
