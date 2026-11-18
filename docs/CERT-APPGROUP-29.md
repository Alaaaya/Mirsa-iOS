Mirsa 2.9 certificate App Group handoff

Isolated branch mirsa/cert-appgroup, based on main ea747e5. Do not merge into 2.8.

Owner reports same input IPA + purchased certificate works in LCSign but no usable App Group after Mirsa signing. Screenshot says no usable container, not proof of a particular missing entitlement or profile. Exact owner input IPA, resulting signatures, and selected profile have NOT been inspected. Device root cause remains unconfirmed.

Confirmed signing difference
Mirsa starts with existing Mach-O entitlements plus optional custom plist, then constrains them to the selected profile. Existing app_group_plan already preserves authorized original groups or maps requested groups consistently across parent/extensions. Bundle identity changes do not rewrite group names.
If a stripped/unsigned app has NO application-groups key, Mirsa previously never claimed any groups even if its profile explicitly allowed them.
Upstream zsign initializes entitlements from the selected profile when no custom entitlements file is supplied. Inspected zhlynn/zsign src/openssl.cpp ZSignAsset::Init, lines 853-867, master at investigation. This is NOT confirmation of LCSign internals.

Change
Preserve App Group toggle defaults ON, including old saved drafts and omitted FFI options. Keeps existing requested-group mapping. Only when the key is absent, seeds concrete profile-authorized group identifiers before existing whole-tree mapping/constraining. No wildcard IDs emitted or invented team/bundle-derived permissions. Explicit custom empty array is honored. OFF removes groups including custom ones. Profile validation and strict authorization remain in force. No networking, account registration, signing identity or bundle rewrite changes.

Custom entitlements already work
PersonalCertificateView stages the imported plist and sends custom_entitlements_path. personal_sign::custom_entitlements permits com.apple.security.application-groups (strips only identity/get-task-allow/no-container keys), merges into MAIN APP request, then applies profile constraints/mapping. Thus importing a group plist can already work if profile authorizes a group. It cannot grant absent profile permissions, does not affect extensions, and a requested original ID can map to a different authorized profile group.

Verification
scripts/test-cert-app-groups.py compiles actual personal_nested.rs plus actual Options struct/serde/Default in a small offline harness. 21 tests pass including existing shared-extension collision/disjoint-profile mapping and new missing/empty/custom/off/wildcard/default tests. File-walk/encryption stubs are not exercised. git diff --check passes.
No macOS/Xcode available in this environment. Full Rust/iOS app compile, Swift UI native build, actual signed IPA XML+DER inspection, and owner device installation/containerURL checks remain REQUIRED for 2.9. Do not describe this as device-verified or a confirmed fix for owner's input.

Source references
https://github.com/zhlynn/zsign/blob/master/src/openssl.cpp
https://developer.apple.com/documentation/technotes/tn3125-inside-code-signing-provisioning-profiles

No 2.8 source, CI, feeds, server or published files touched.
