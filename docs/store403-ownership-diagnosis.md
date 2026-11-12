Scoped offline diagnosis, 2026-11-12

Working device base 2f15e577d949a539a1b3a60ed350a2d42e31e027 and incoming HEAD ff179dcf545b142791df9e251334f0dd4ba52b87 have identical vendor ApplePackage request source and identical StoreClient/StoreOnDeviceClient. The new source invariant test independently compares the complete makeRequest implementation to that working commit. X-Token, full X-Apple-Store-Front, both DSID headers, cookies, guid/payload and AMD are unchanged. VersionFinder and Download use the same fetchProductWithFallback chain, preserving selected version and account across recovery. Existing StoreDownloadRecoveryTests cover headers for all three endpoints and metadata mismatch rejection.

Latest owner correction confirms BOTH YouTube and WhatsApp are owned. Earlier YouTube-unowned statement is superseded. Bare Apple redownload HTTP403 with missing failureType is not ownership evidence. No live Apple traffic was made, and the actual provider-side 403 cause is not established. Runtime token/cookie/account validity cannot be proved from source parity.

Implementation keeps unknown ownership distinct from explicit Apple9610/licenseRequired and positive session evidence. Unknown free apps offer explicit Get; opening/search/versions/download/retry never calls acquisition. Known licence-required blocks download and version-list requests until explicit Get succeeds. Successful acquire, successful authenticated version lookup or download records owned. Explicit acquisition response5002 (already purchased) also succeeds;2040/2059 are not treated as owned. Paid/unknown-price acquisitions are rejected before provider calls. UI never auto-downloads after Get; selected external version is preserved for the separate Download tap. Numeric Apple failure types are normalized before existing Download/VersionFinder string handling. HTTP403 alone does not change ownership or trigger any purchase.

Existing purchase-history records are private @State inside AppStorePurchasesPage, not exposed by AppStoreSectionModel or a shared cache. No change to AppStoreSection was made by this worker, and no extra automatic purchase-history call was added. Absence of history never means unowned. Current session ownership evidence is local to AppStoreAccountView and cleared on account change.

Edited by this worker only
ios-app/Apps/AppStoreAccountView.swift
vendor/ApplePackage/Sources/ApplePackage/Commands/StoreDownloadEndpoint+Fetch.swift
vendor/ApplePackage/Sources/ApplePackage/Commands/Purchase.swift
vendor/ApplePackage/Tests/ApplePackageTests/StoreOwnershipEvidenceTests.swift
scripts/tests/store_ownership_intent_test.py
docs/store403-ownership-diagnosis.md

Verification
python3 scripts/tests/store_ownership_intent_test.py passes all six offline tests.
git diff --check passes.
Swift compiler absent. New Swift evidence tests and existing request/recovery tests require caller's macOS CI. No commit, push, build, CI, publication, login, server or feed action was performed.

Concurrent AppStoreSection.swift edits belong to the caller and must not be attributed to this worker.


Owned-app follow-up and bounded diagnostics

No source request regression was found in the scoped comparison. ParkingPro success does not establish that redownload itself ever worked. The original view's searchCountry stays public-catalogue-only; authenticated download still re-looks up the bundle in the persisted account country, verifies itemID, then uses the original manifest path. Older versions still passes the same selected app into the same account-bound engine. New chart details verify the lookup result itemID equals the chart itemID before selecting it. The action call arguments and engines are covered by an additional offline parity test. No evidence supports reverting that unchanged engine or switching to a speculative alternate redownload endpoint.

Fallback inspection finds volumeStore triggers redownload only for5002 or an empty successful no-dialog/no-action response; chosen explicit version survives, otherwise PlatformVersionLookup resolves an account-store/entity-specific version. The same account cookie mutations survive into redownload. AMD header scope and guid construction are identical to the working-base source. Recovery response still validates itemID, bundleID and versionID. No demonstrated bug was found in these branches. Live session/content/provider behaviour remains unproven.

Diagnostic throws now append bounded requested appID, bundleID, external versionID (or latest), and numeric account store alongside existing endpoint/status/failureType. They expose no token, cookie, DSID, guid, account email, headers, URL, or raw body. These fields identify device-side argument differences for owned latest/older-version failures. A new offline Swift WhatsApp detail/older-version fixture checks identity/version diagnostics, credential non-disclosure and recovery identity validation. This is a DIAGNOSTIC change for the owned403 case, NOT a claim that owned downloads have been fixed. The integration caller must decide whether to ship this diagnostic build or continue investigation. No live Apple calls were made.

Final local checks also pass scripts/appstore/store-section-state-tests.py. Discovery and search-state scripts were attempted but stop at missing swiftc; not reported passing. Swift test loops now use explicitly typed arrays instead of typed for-in patterns.

Caller CI commands
python3 scripts/tests/store_ownership_intent_test.py
python3 scripts/appstore/store-section-state-tests.py
cd vendor/ApplePackage && swift test --filter StoreOwnershipEvidenceTests
Existing StoreDownloadRecoveryTests must also run using the caller's established macOS package test setup.

Canonical list follow-up, same diagnostic build

Exact 2f15e57 already included the list, the Older versions fetch button and optional manual field. Latest and rows appeared only after a successful nonempty version response. This is a demonstrated presentation dependency, not proof of a commerce regression: a 403 leaves the pre-load UI visible. Old versionRow appearance and official metadata name lookup are preserved. Manual version input is now removed, Latest is always visible, and opening details attempts the official list once per app/account. A failed load remains explicit with a user-triggered retry, not an endless retry loop. Account change clears cached versions and choices.

Actual row action assigns the external ID from the returned list; the human version string is display-only. Latest removes that choice and uses the unchanged nil/latest engine path. New offline source and executed Swift row-action regression tests cover both apps, selection isolation, and unchanged account-bound request engine. Numeric salableAdamId remains Software.id from the selected item, not any task/thread identifier. Actual failing runtime payload has NOT been observed; owned YouTube/WhatsApp403 remains unresolved. No claim that restoring the presentation fixes Apple's rejection.
