# Wallpaper source contract and staging

This directory is local staging only. Its empty official catalog contains no artwork,
archives or third-party content. It is not an IPA source. The native implementation
is `WallpaperSourceFeed` in `ios-app/WallpaperSource.swift`.

## JSON contract

The root object requires a nonblank `name` (at most 160 Swift Characters), `author`
(at most 160), and a `wallpapers` array containing at most 1000 entries. An empty
array is valid. Entry IDs must be unique within that feed.

Each entry requires `id`, `name`, `author`, `previewImage`, `url`, `size`, and
`category`. `previewVideo` can be omitted or null. The ID and name must be
nonempty and at most 160 Characters; author is at most 160, category at most 100.
All asset URLs must be absolute HTTPS URLs with a host and without user/password.
The download URL path must end in `.tendies`, case-insensitively. Query strings
are allowed. Size is an integral byte count from 1 through 536870912 inclusive
and must match the downloaded archive exactly. Downloads are streamed to temporary
files with a hard size cap. The feed itself has a 2097152-byte network cap.

Example entry shape, illustrative reserved URLs only, not shipped in the official feed

```json
{
  "id": "original-001",
  "name": "Original title",
  "author": "Mirsa",
  "previewImage": "https://example.com/original-001.png",
  "previewVideo": "https://example.com/original-001.mp4",
  "url": "https://example.com/original-001.tendies",
  "size": 1048576,
  "category": "Original"
}
```

Codable ignores unknown JSON keys. This does not make an IPA feed valid.
The required wallpaper-specific fields and native validator still apply.
HTTPS does not establish provenance or archive safety. The source action downloads and imports the archive, preselects its returned IDs,
and navigates back to the existing Tendies ready screen. It never calls the flash
engine or writes system wallpaper state. Catalog acceptance does not
bypass the existing Tendies archive-import validation or prove device compatibility.

## Existing host and a future authorized deployment

Read-only inspection on 2026-11-22 found `https://mirsa-source.mooo.com/wallpapers.json`
returns HTTP 404. DNS/TLS already work. Oracle host `138.2.136.36` runs Caddy.
The `mirsa-source.mooo.com` site in `/etc/caddy/Caddyfile` currently permits only
`/source.json`, using root `/var/www/mirsa-source`, then returns 404 for all other
paths. Merely copying the new file would not make the endpoint available.

After explicit publication approval only, back up the existing Caddy config and
any previous wallpapers file. Copy the validated UTF-8 catalog into a temporary
sibling file in `/var/www/mirsa-source`, set root ownership/mode 0644 and atomically
rename it to `wallpapers.json`. Add an exact handle to the existing site without
changing the app source or its catch-all behavior

```caddy
handle /wallpapers.json {
  root * /var/www/mirsa-source
  header Content-Type "application/json; charset=utf-8"
  header Cache-Control "no-cache"
  header X-Content-Type-Options "nosniff"
  file_server
}
```

Validate with `sudo caddy validate --config /etc/caddy/Caddyfile` before a graceful
Caddy reload. Verify ordinary and cache-busted HTTPS GETs return 200, JSON MIME,
and the exact staged file SHA256. Recheck `/source.json` is unchanged and unknown
paths still return 404. Rollback restores the previous file and config, validates,
then reloads. No copy, config change, reload or deployment was performed by this task.

## Native CI transport

The workflow `.github/workflows/wallpaper-source-validation.yml` runs automatically
on pushes to `mirsa/wallpaper-source`. It builds real simulator Rust FFI and the
native application, runs `WallpaperSourceTests`, then runs the actual retained
Tools/Tendies navigation through `WallpaperSourceUITests`. The latter uses explicit
DEBUG harness fixture data with original procedural art, never invoking the card action or any system wallpaper operation.

Existing GitHub transport was verified read-only using the saved token on this
host. The token must never be printed or embedded in commands, URLs or commits.
A caller can supply it to `gh` in its process environment and run

```sh
gh workflow run wallpaper-source-validation.yml --repo Alaaaya/Mirsa-iOS --ref mirsa/wallpaper-source
```

For a new workflow not yet registered on the default branch, use the branch push
trigger instead of relying on workflow_dispatch registration. Draft commit-tree
pushes can compile an exact snapshot before the final branch commit. Inspect
`gh run list --repo Alaaaya/Mirsa-iOS --branch mirsa/wallpaper-source` and match
the exact head SHA. Download `wallpaper-source-native-evidence` only after completion.
A successful dispatch or queued job is not a successful compile or test result.
No external forge transport was required or claimed verified.
