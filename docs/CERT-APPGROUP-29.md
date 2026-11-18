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

Icon editing requested by owner
Uncommitted follow-up adds pencil menu overlay to header icon, Photos picker, Files image importer, reset-to-original, bounded ImageIO thumbnail conversion (16MiB input, 16 megapixels, 1024px normalized PNG), optional persisted draft/options iconPNG, and applies the existing IPAEditorService.installIcon renderer to the staged app BEFORE certificate signing. Name/bundle/version fields already exist in header and are applied by prepare/signing flow. Original IPA remains untouched. Reuses existing renderer rather than inventing new icon metadata logic. No new Xcode source file needed.

Swift native compile is unavailable on this Linux host. Icon changes intentionally remain uncommitted until native compile. Actual-policy Rust harness still 19 PASS; this does NOT compile/test Swift. Photos loadTransferable allocates encoded asset before size check, identical to standard PhotosPicker data flow; Files checks file size before reading. Real image/device tests pending. Latest remote push attempt returned HTTP502; no remote availability claimed.

Sole backend continuation, 2026-11-18
Backend compiled atomic commits now override historical incomplete profile notes. 5560591 adds explicit serde-default-OFF omit_embedded_profile; vendor omit_embedded_mobileprovision removes profiles BEFORE final resource collection/sealing, overriding both root and nested supplied profile bytes at every recursion. Certificate/profile entitlement authorization is unchanged. Normal default keeps selected profile. Actual ad-hoc Mach-O bundle signing fixtures cover replacement/final profile hash, root+nested omission/final parent seal/re-signing, already absent, directory fail closed, and symlink unlink without touching target. Focused vendor bundle tests 8 PASS. Full vendor suite 17/18 PASS, unrelated rustcrypto_cms::tests::apple_code_directory_digest_includes_every_code_directory currently FAILS (left1 right2); not waived, baseline verification pending. Options/nested policy harness 21 PASS with true/false/default/non-boolean coverage.
63ecbd4 imports exact read-only b8c1f1d diff from DEFAULT mirsa-preinjected (original commit not remotely addressable), adds separate disabled list to production library edits. Disabled commands get same all-slice ordinal-safe unlink as delete, but their files are protected from deletion even across multiple owner edits. Delete remains distinct, removes only unshared safe standalone dylibs. Actual production graph/editor harness 12 PASS including fixture IPA import, disable retains bytes, delete removes bytes, legacy plan default, unknown/conflicting/bound failure before writes. Does not execute user binaries.
Both commits and existing 1d26b6b/dafc123 uploaded as IDENTICAL Git objects through GitHub API because git transport502; remote branch mirsa/cert-appgroup verified at 63ecbd4. Receipt WEB /home/kit/cert29-push.json. No 2.8 branch/live updates.
Uncommitted Swift integration now forwards omit_embedded_profile and updates truthful option text, adds actual disable toggle with optional backwards-compatible draft field, preserves original-dependency warning and original owner labels, new draft directInjection=false (LoadControl) while explicit saved component/global choices and older decoded nil legacy-direct choices stay unchanged. Direct signing options useLoader=true. Icon picker predecessor changes preserved. New CertificateParity29Tests.swift covers defaults/saved choices, legacy edit decoding, disable/delete separation and plan preservation. Swift native compile NOT YET checked. CI snapshot required, these Swift changes are not a proven build yet.
Remaining scope includes REAL dark icon/Assets.car repair (control still disabled, not faked). File-only library inventory cannot disable dlopen-loaded code; text explicitly says so. External LCSign LoadControl sidecar format is NOT verified, don't infer runtime method from filename alone. Our current exact owner label for Frameworks/LoadControl.dylib must not be generalized to original app dependencies. Real LCSign-engine/runtime-list detection requires inspection of actual format and fixtures.

Follow-up native candidate b, not yet accepted
Upstream CMS regression is now proven on UNMODIFIED ea747e5 vendor source in a separate extracted crate. Source mtimes forced fresh compile (to avoid Cargo shared-target fingerprint reuse). /home/kit/cert29-vendor-baseline.log shows Compiling /home/kit/vendor29-baseline then same apple_code_directory_digest failure, 17 filtered tests. This establishes pre-existing failure, not permission to suppress it.

Dark icon repair candidate now uses MIT NSAntoine/PrivateKits AssetCatalogWrapper pinned157c45b2eecad87a8ac6123ef5caaf2c730afd7a (85stars/89commits checked). New PersonalDarkIconFixer rewrites an Assets.car TEMP COPY, removes ONLY primary named dark/highcontrast-dark icon/image renditions with an exact appearance-independent-key default counterpart, reloads/revalidates every remaining rendition multiset, then atomically replaces original staged catalog BEFORE signing. Never deletes entire catalog, never edits unrelated assets, doesn't touch original IPA. No usable primary name/default => safe no-op. It does NOT yet establish every icon naming style matches, nor device compatibility. New actual asset-catalog fixture test requires >0 real removals, changed bytes, default kept, unrelated images byte-for-byte PNG-preserved, dark-only/no-default and idempotency no-op. Package pin+test resource sources are uncommitted until native gate. Fix currently defaults OFF, matching old absence, but LCSign owner screenshot showed ON, decide enabling NEW-only default after actual tests (saved choices stay). This is an implemented candidate, not a proven repair.

Native CI access is working. Current candidate b3d193150d64c4f20b7dd8ec8a9750a704594723 on mirsa/cert-appgroup-native29b contains all pending Swift/icon/profile wiring + dark fixer/package/tests/fixtures. Actual workflow personal-certificate-validation.yml run44273982622 IN_PROGRESS as last checked, full Rust/native app + simulator FFI/tests. Receipt /home/kit/cert29-native-candidate-b.json and dispatcher /home/kit/cert29-ci-b.py. Old04ea9394 run44273490282 canceled superseded, not a native pass. Remote accepted work branch remains63ecbd4; local preserved Swift uncommitted, NO claim of native success. No2.8 edits, live update, or server changes.

Misleading LoadControl filename special-case removed from pending Swift. Ordinary dependencies remain labeled via actual main/framework owner, never claim any arbitrary LoadControl.dylib is injected/runtime verified. Fixed reorder UI indexing to exclude disabled/file-only rows. Runtime sidecar detection/editing is still pending. Own loader known exact source loader/MirsaLoader.c uses Frameworks/MirsaLoader.dylib + newline ASCII MirsaLoadOrder.txt, 64entries, validates contained canonical paths before any dlopen. External LCSign runtime format unknown. Do not pretend load-command unlink disables dynamic sidecar entry. Need investigate safely and add distinct genuine sidecar edits with fixtures, or report precise unsupported external format with no fabricated parity. Preserve backend ordinal-safe semantics and never execute imported code.
