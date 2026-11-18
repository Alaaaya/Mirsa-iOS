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

Owner superseding instruction, automatic LCSign behavior
The visible App Group toggle and option plumbing are REMOVED in the follow-up commit. Preservation/profile fallback is always automatic; no hidden opt-out. Initial toggle/21-test description above is historical. Current actual-policy test suite has 19 passing tests.

Files access is now ON for NEW projects and direct signing options. Existing saved project choices stay as selected; do not silently override an explicit saved OFF.
Screenshots show a selected app.local.iPadn project, not a factory reset, so individual visible states are observed configuration, not independently established LCSign factory defaults. New tweaks first is OFF in IMG2167/2168 but ON in IMG2169, proving at least one user selection changed. Retained OFF default rather than infer conflicting defaults.

Observed comparison to current Mirsa
Files access ON, now matched.
Remove URL schemes OFF, matched.
White icon fix OFF, matched, though implementation differs: Mirsa flattens transparent PNGs, LCSign label says rewrite icon references.
Dark icon fix ON in LCSign, NOT matched. Mirsa control is truthfully disabled because Assets.car repair is unimplemented. Do not turn this cosmetic switch ON and claim repair exists.
Direct injection OFF observed, Mirsa legacy default direct ON (nil interpreted direct), NOT changed: needs focused LoadControl behavior review before silently changing injection strategy.
Remove embedded OFF observed, matched default only. LCSign says omit final embedded.mobileprovision for TrollStore/no-profile; Mirsa removes old profile then always embeds selected new profile. Different semantics remain, not faked.
Watch removal OFF, matched.
New tweaks first OFF/ON across screenshots, default remains OFF. Mirsa reorder behavior should be checked against LCSign's stated replacement-preserves-position behavior.
Game mode Keep, matched.
Minimum iOS Keep, matched.
Entitlements import, already available and constrained by profile. Main app only in Mirsa.
Main binary dependencies view already enumerates actual dependency rows from inspection; no hardcoded count 56. Need same original IPA to compare exact list/count. Screens supplied here show collapsed view, not actual 56-row inventory.

Remaining parity work is NOT completed. No device verification, native build, dark icon repair, embedded-profile omission, or LoadControl-default behavioral proof is claimed. Keep all this for 2.9, no 2.8 changes.
