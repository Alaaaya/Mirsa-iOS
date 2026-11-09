# On-device App Store backend

Isolated backend only, with no UI or release publication.

## API for the UI integration worker

Use the single actor `MirsaStoreClient.shared`. Do not create separate production actors because ApplePackage's machine identifier is process-wide.

- `currentAccount()` returns only email, display name and account storefront.
- `search(term:country:limit:)` searches the public iPhone App Store. Results are not a license guarantee.
- `signIn(email:password:)` establishes a fresh SAP handshake directly with Apple and returns signedIn or verificationRequired.
- `verify(code:)` reuses the same SAP signer, cookies, routing and machine identifier. Three code submissions maximum, five-minute challenge expiry.
- `acquireFreeApp(app)` is a separate, explicit free-license action. It refreshes metadata in the authenticated account's storefront and rejects missing, negative, nonfinite or nonzero prices. No paid acquisitions.
- `availableVersions(app)` returns Apple's external version IDs. These are not human-readable version labels and availability is not guaranteed.
- `downloadOwnedApp(app, externalVersionID:)` downloads the account-owned encrypted IPA and assembles its original SINF and metadata. It never acquires a license automatically. The returned local URL may be passed to the existing local importer, then its UUID temporary directory must be removed after a successful copy.
- `signOut()` deletes account and challenge secrets, clears challenge memory, actively cancels a CDN transfer and prevents an in-flight response from restoring the account. Account secrets are loaded from Keychain only for each operation, not cached on the client. ApplePackage does not expose its underlying auth HTTP handle; an already-sent Apple authentication request may finish within its bounded timeout, but its response is discarded after sign-out. A failed Keychain deletion is reported and must not be presented as a successful sign-out.

Do not claim encrypted apps can be re-signed, decrypted, installed or run merely because a download succeeded. There is no decryption or certificate bypass in this backend.

## Security boundary

Credentials, account cookies and tokens are persisted only in a separate non-synchronizing, this-device-only Keychain service requiring an unlocked device. There is no file-backed account helper, shared access group, server endpoint, telemetry or credential log. The process necessarily holds request secrets briefly in memory for Apple authentication. Pending verification passwords are read from Keychain and expire after five minutes. App archive metadata contains Apple's original account-bound licensing information; files are private protected temporary files and must never be shared/uploaded automatically.

Only HTTPS Apple CDN hosts are allowed, including every redirect. The CDN session is ephemeral and has no account headers, credential store or cookie jar. Downloads are capped at 4 GiB, five redirects and 30 minutes. ZIP packaging caps total entries, expanded bytes and plist reads, rejects duplicates/symlinks/traversal, checks bundle/version identity and modifies only SINF/metadata entries. Executable bytes remain unchanged.

The code depends on MIT ApplePackage pinned at 391bfe6ee6598d73e4f94b88b38b50bd6f6ec67b, plus ZIPFoundation and swift-log. ApplePackage contains a native Swift/C SAP implementation using OpenSSL, not ipatool's executable/Unicorn or a jailbroken-only private framework. ApplePackage's optional file-account APIs and CLI executable are not used. Network logging is disabled using a no-op logger.

## Verification status

Offline mock-backed auth/session/license policy tests and synthetic archive tests are run on macOS, never an iOS simulator. The isolated branch also receives the complete unsigned generic iOS device build. Neither CI nor unit tests can establish real account login, real 2FA, license acquisition, older-version eligibility, successful device download or installation. Those require owner device testing with their own account after separate UI integration.

This branch started from release 1.3.222. It must be rebased/merged with the separately owned Hark integration only after that integration is live. Do not push to apps-sideloader or publish from this worker.
