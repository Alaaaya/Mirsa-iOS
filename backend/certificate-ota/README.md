# Private certificate OTA

Deployed only to Mirsa project hirebeofomiyumwysppj. Never use the Player project.
Owner authorized additive infrastructure for this private batch, not app publication.

Dedicated private bucket mirsa-ota-private, 30 MiB upload maximum.
User JWT checked with Auth getUser on every upload. Server-generated 256-bit bearer download tokens.
RLS denies direct anonymous/authenticated table access. Only service_role invokes quota functions.
Atomic quotas: three uploads/user/hour, five active global, twenty/day, 200 MiB/day, 400 MiB/31 days.
Manifest and IPA use the same strict fifteen-minute expiry, enforced independently of cleanup.
Eight GETs total per reservation; no redirect to a longer-lived storage URL. No-store responses.
pg_cron every five minutes requests cleanup using a separate Vault-backed secret.
Service-role, cleanup secret, P12, password and private keys are never shipped in the app.
Only locally signed IPA with embedded PUBLIC profile is uploaded.
Archive central-directory bounds reject traversal, duplicates, excessive expansion and signing-key extensions.
This is structural validation, not cryptographic signature verification or iOS installation proof.

Live tests passed authenticated structural-fixture upload, manifest XML GET and byte-identical IPA GET,
unauthenticated 401, unknown token 410, expired manifest and IPA 410 BEFORE cleanup,
and cleanup 200 with fixture object no longer downloadable afterward.
Fixture was NOT an installable signed app. Real-device OTA install remains untested.

Apple ID is the default. Own-certificate mode routes Mirsa self-install/update only.
Local signer still uses the existing real-device pairing/VPN UDID check. OTA delivery uses HTTPS,
not VPN. This batch does NOT remove that local signing dependency or weaken actual-UDID verification.
Profile matching is strict for Mirsa self-install, normal certificate compatibility stays strict-OFF.
The first locally selected saved certificate is used, matching the existing vault selection semantics.

## Explicit 48-hour links

Apply share-links.sql after schema.sql before deploying this revision of index.ts.
POST defaults to 900 seconds for all existing installation clients. Only the explicit
x-mirsa-lifetime: 172800 header selects 48 hours; arbitrary lifetimes are rejected.
The authenticated request still uploads only the signed IPA. Both flows retain the
same private bucket, 256-bit download token and all existing upload/egress quotas.
Response adds shareURL, an HTTPS static page with a Safari install link. The app generates
the QR locally using CoreImage, so no QR service receives the bearer token.
Manifest and IPA requests check the same database expiry and readiness.
Each consumes one of the existing eight GETs; a 48h lifetime is NOT unlimited downloads.
The static page is not proof that the link is live; iOS must request the manifest.
No automatic trust, revocation bypass or proof of device installation is claimed.
Cleanup deletes database rows only one day AFTER expiry, not one day after upload.
This is necessary so a 48h link survives the first daily cleanup.
UI is embedded in project detail only for a retained signed export, not unsigned output.
User must explicitly tap Create link after reading the disclosure.
This revision has NOT been deployed or real-device tested by its source worker.


Deploy static/install.html, install.js and install.css to the free existing-repo
GitHub Pages origin https://alaaaya.github.io/Mirsa-iOS/install.html and verify
HTML/JS/CSS availability before setting MIRSA_OTA_SHARE_PAGE_URL to that exact URL.
The function fails closed for 48h requests until that setting exists and matches.
Supabase rewrites HTML to plain text on its shared hostname; do NOT serve this page
as an Edge HTML response or buy a custom domain as a workaround.
Reference https://supabase.com/docs/guides/functions/limits.
The download bearer lives in the URL fragment, never in Pages HTTP requests.
The static page has no analytics, network fetches or external assets. Its script
constructs only the fixed Mirsa manifest origin and never accepts an arbitrary URL.
Deployment of Pages, SQL migration and Edge source remains a coordinator step.
