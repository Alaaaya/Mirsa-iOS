# tools-store

Supabase Edge Function for the in-app **Tools Store** (Tools tab › Store): deb/dylib tweaks, `.tendies` wallpapers, ready-made tweaks for popular apps (YouTube, Instagram, TikTok), ringtones/sounds and fonts.

- Auth: same as discovery-search / tweak-forge. The app signs in anonymously (Supabase Auth) and sends its per-install user JWT; verified in code. No secret ships in the app.
- Nothing is published automatically. `upload_begin` creates the row as `uploading` and returns a signed upload URL; `upload_commit` verifies the stored object (exists, size matches) and moves the row to `pending_review`. Only `admin_review` with `decision: "approve"` makes it visible. Rejected files are deleted from storage.
- Files live in the private bucket `mirsa-tools` (created by schema.sql) and are only served through 10-minute signed URLs.
- Allowed types (also enforced by the app): tweaks/app_tweaks `.dylib .deb .zip`, wallpapers `.tendies`, sounds `.m4r .m4a .mp3 .caf .wav`, fonts `.ttf .otf .ttc`. Max 150 MB. Max 5 uploads waiting for review per user.
- Downloads are counted once per user and item (`mirsa_tools_downloads`), ratings once per user and item (1–5, upsert).
- Rate limits per user (Postgres, durable): upload_begin 10/day, rate 60/hour, download 120/hour.

## Secrets (names only)
- `TOOLS_STORE_ADMIN_TOKEN`: random string, 24+ characters. Sent by the reviewer as header `x-admin-token`. Never put it in the app.
- `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`: provided by the platform.

## Deploy (after owner approval, Mirsa project only)
1. Apply `schema.sql` in the SQL editor.
2. `supabase functions deploy mirsa-tools-store --no-verify-jwt --project-ref <ref>` from this folder (JWT is verified in code), and `supabase secrets set TOOLS_STORE_ADMIN_TOKEN=<random>`.
3. In the app set Info.plist `MirsaToolsStoreEndpoint` to `https://<ref>.supabase.co/functions/v1/mirsa-tools-store` (or the UserDefaults key `mirsa.toolsStore.endpoint`). Empty = the store shows its "not configured" state. The app authenticates against `WebBackendConfig.defaultProject`, so deploy into that same project.

## API (POST JSON, `Authorization: Bearer <user JWT>`)
| action | body | answer |
|---|---|---|
| `list` | `category`, `sort` (`downloads` \| `new` \| `rating`), `q?`, `limit≤100`, `offset` | `{items:[…]}` approved only |
| `download` | `id` | `{url}` signed, counts once per user |
| `rate` | `id`, `stars` 1–5 | `{rating_avg, rating_count, my_rating}` |
| `upload_begin` | `category`, `title`, `description?`, `version?`, `author_name?`, `target_app` (app_tweaks: `youtube`/`instagram`/`tiktok`/bundle id), `file_name`, `file_size` | `{id, upload_url}` → PUT the bytes |
| `upload_commit` | `id` | `{status:"pending_review"}` |
| `my_uploads` | – | `{items:[…, status, review_note]}` |

Admin (header `x-admin-token`, no user JWT needed):
```sh
curl -s -X POST "$FN" -H "x-admin-token: $TOKEN" -H 'content-type: application/json' -d '{"action":"admin_pending"}'
curl -s -X POST "$FN" -H "x-admin-token: $TOKEN" -H 'content-type: application/json' \
  -d '{"action":"admin_review","id":"<uuid>","decision":"approve","file_reviewed":true,"note":"checked"}'
```
`admin_pending` returns each pending item with a 10-minute `review_url` so the file (every dylib) can be inspected before approval. An optional `preview_path` (an object you uploaded under `previews/` in the bucket) can be attached on approve.

Tests: `node --test backend/tools-store/logic.test.mjs`

## Staged security review, not production-ready

Nothing in this directory has been deployed. Apply only to a fresh test schema first. If an older schema has ever been applied, write an explicit migration for its status constraint before using held; CREATE TABLE IF NOT EXISTS does not migrate existing columns or constraints.

Every file, including every dylib, requires manual review. Approval now requires file_reviewed: true and a review note of at least 3 characters. Neither magic bytes nor this checkbox establishes that a binary is safe. Reviewers must inspect uploads using an isolated analysis environment, never execute uploaded code on the server or personal device. ZIP/deb/tendies archives are not extracted or recursively scanned here, so nested payloads, archive bombs, malformed fonts/media, malicious valid Mach-O files and disguised icon-pack contents require review. No icon category is accepted.

upload_commit copies the upload to an unpredictable service-only review/ path before inspecting it. The original signed upload URL never addresses the reviewed/published object. Exact stored size and bounded prefix checks detect obvious type mismatches. Only approved rows can download; direct app-client access to the bucket is denied by a restrictive storage policy, even if a preexisting permissive policy would allow it. Existing buckets are explicitly made private with the configured size cap.

Mismatched size/header uploads become held, stay private, and create a durable mirsa_tools_alerts entry atomically. They cannot be approved through the API. admin_pending includes held items with the reason. Reviewers can also send admin_review with decision hold and a reason in note to quarantine any suspicious pending or previously approved item. Rejection deletes bytes best-effort; failed deletion leaves private objects, not publicly listed content.

An authenticated admin integration must poll admin_alerts, actually notify Alaa, and then use admin_ack_alert with the alert id. This is only a prepared durable report mechanism. No polling worker, owner notification destination, production secrets, or malware scanner is configured. DO NOT enable production uploads until owner approval, a functioning review workflow, and this owner-notification consumer are configured and tested. Held files count toward the five-item outstanding quota until rejected.

Signed download/review URLs are bearer capabilities valid for up to 10 minutes; keep them private. A hold stops new links but cannot instantly revoke links already issued. Do not claim instant revocation. Pending-review copies and abandoned/replayed original uploads need a service-only retention/cleanup job. Usage rows need bounded retention. Anonymous identities are per-install, not per-person; reinstalling/re-registering can bypass user quotas, so deployment also needs signup/IP controls and monitoring. Admin tokens are server/operator-only and should be rotated; never ship one in the app.

## Verification

node --test backend/tools-store/logic.test.mjs covers validation, file signatures and bounded stream reads.

deno check backend/tools-store/index.ts and deno test --allow-env backend/tools-store/index.test.ts type-check and exercise the real handler against a mocked Supabase HTTP boundary. Tests use fake credentials and no network access.

psql -v ON_ERROR_STOP=1 -f backend/tools-store/schema.test.sql runs SQL regressions in a transaction, then rolls back. Run ONLY in an isolated PostgreSQL test database after applying schema.sql. It checks privileges, approval/hold gates, durable alerts, aggregate counters, caps, rate limits and restrictive storage policy interactions. Test database bootstrap must supply Supabase-equivalent anon, authenticated, service_role roles and storage.buckets/storage.objects tables. This is not a real Supabase Storage integration test.

Unverified deployment gates include real Supabase signed PUT compatibility, private bucket signed capability behavior alongside restrictive RLS, copy semantics/metadata, real JWTs, real valid file fixtures (especially tendies), owner-alert delivery, anonymous signup abuse controls, moderation operations, and device verification of the held-status display. Never auto-approve a held file to work around a fixture mismatch.
