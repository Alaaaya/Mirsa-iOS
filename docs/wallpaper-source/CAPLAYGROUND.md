# CAPlayground third-party source review

Inspected 2026-11-22. Opt-in only, not enabled by default. No art, manifest copy or upstream code is bundled or rehosted.

Repository https://github.com/CAPlayground/wallpapers
Manifest https://raw.githubusercontent.com/CAPlayground/wallpapers/main/wallpapers.json
License https://github.com/CAPlayground/wallpapers/blob/main/LICENSE
README https://github.com/CAPlayground/wallpapers/blob/main/README.md

Repository LICENSE is GPL-3.0. README says submitted wallpapers made in CAPlayground, credits SerStars/Nugget-Wallpapers for workflow inspiration. This does not independently establish rights to every submitted artwork. Hosted editor README links separate service terms at https://caplayground.vercel.app/tos with attribution requirements. That terms page could not be retrieved during review (login/subscription error), so default enablement remains blocked pending that review. Linking a public catalog is not a blanket rights clearance. Preserve creator and source attribution, provide direct repository/license link, no rehosting.

Live manifest was 89,324 bytes and 287 entries. Fields name/id/creator/file/preview/date/from, root base_url. No byte-size metadata. Adapter ignores untrusted base_url, anchors paths to upstream raw GitHub, rejects traversal, absolute paths, query/fragment/percent/backslash, duplicate IDs and unsupported preview types. No borrowed implementation code. Sizes displayed with ≤ denote a 32 MiB download ceiling, not a known exact size. Larger packages fail closed. Actual archive validation remains existing safe import.

HEAD sample verification, both status 200, no artwork downloaded for tests:
https://raw.githubusercontent.com/CAPlayground/wallpapers/main/wallpapers/11037_Case_1.tendies
Content-Length 1560371, application/octet-stream.
https://raw.githubusercontent.com/CAPlayground/wallpapers/main/previews/gif/11037_Case_1.gif
Content-Length 5276170, image/gif.
https://raw.githubusercontent.com/CAPlayground/wallpapers/main/wallpapers/17e_Black_with_AOD.tendies
Content-Length 14136257, application/octet-stream.
https://raw.githubusercontent.com/CAPlayground/wallpapers/main/previews/gif/17e_Black_with_AOD.gif
Content-Length 989594, image/gif.

The successor preserves the base's existing safe import/preselect/return-to-Tendies CTA unchanged. It adds only opt-in source selection in the existing UI and attribution link. No direct installation, automatic installation, engine changes, Drift integration, system writes, release or publication.

Tests contain only invented metadata with reserved hosts and do not download upstream artwork. Full app/simulator compilation remains required; Swift parse alone is not a compile or runtime pass.
