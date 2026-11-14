# video wallpaper progress
base 163e740 (identity fix 5.58.1). feature = SYSTEM lock-screen wallpaper via tendies, not app background.
5cbc73f first restore (no DE) CI superseded. Next head: see git log. Runs recorded below.

Exact head ee93d7f902273f19745b1683cf3becafe5c57ddb
CI [{"id": 43490185925, "name": "Combined launch smoke", "head_sha": "ee93d7f902273f19745b1683cf3becafe5c57ddb", "status": "queued", "conclusion": null, "run_attempt": 1}, {"id": 43490182434, "name": "Unsigned Mirsa IPA", "head_sha": "ee93d7f902273f19745b1683cf3becafe5c57ddb", "status": "queued", "conclusion": null, "run_attempt": 1}]
Primary completion c3fa14d7, guard6298ef7f coordination only. No duplicate dispatch. Require license/source distribution compliance from VIDEO-WALLPAPER.md plus artifact verification before delivery.
- head 40890e1 pushed (inspector in-sheet confirm, localized preview, raw logs hidden); unsigned-ipa+smoke dispatched once; ee93d7f superseded
- head 00a1b9c (separate hidden attachedClasses state + chip, composed at send); unsigned+smoke dispatched once; followup ddeaac32 updated

ExactHEAD 00a1b9cc996609197b051c62b50d50009210b232 runs [{"id": 43491263779, "name": "Combined launch smoke", "head_sha": "00a1b9cc996609197b051c62b50d50009210b232", "status": "queued", "conclusion": null}, {"id": 43491259725, "name": "Unsigned Mirsa IPA", "head_sha": "00a1b9cc996609197b051c62b50d50009210b232", "status": "queued", "conclusion": null}]
Solefinisher ddeaac32; no duplicate dispatch.
- 00a1b9c runs: IPA 43491259725, smoke 43491263779, forge-validation 43491352015 (tests). ForgeProjectView made per NavigationLink so State not shared across projects

Nov13 primary followup: 00a1b9c all 3 failed. Logs read in full locally /tmp/video-{132112743107,132112757522,14071785093}.log. Syntax TendiesView143 Text closing parenthesis fixed; SourceDeletionTests UUID suite per invocation avoids shared persistent-domain interference. No production SourcesStore changes. New head 1ceca81fb0c1c670c163c08e8e8447bbeff998f3 pushed. Local wallpaper regression functions 3 PASS, no Swift on Linux, actual compilation pending CI. Exact new runs unsigned43494358295 smoke43494362658 forge43494366836 queued. All dispatched ONCE no duplicates. Sole successor 8e385314 handles all three and delivery, no IPA until passed. User notified actual failure once. Logs Azure redirect must not carry Authorization; no-redirect getLocation then GET location without auth.
- 1ceca81 runs: IPA 43494358295 smoke 43494362658 forge-val 43494366836 + cleanup19-tests dispatched once (SourceDeletion)
- 1ceca81 also sources-libraries-validation 43494520905 (SourceDeletion); cleanup19 only triggers on kat/cleanup19
- Fri Nov 13 14:21:12 PST 2026 new finisher took over head 13540a6; runs identity 43510021262 smoke 43510023002 IPA 43510020328 forge 43510026323 sources 43510029794 running. TODO: chat black/gradient toggle, download-resume merge, license row/FlekDeck, first-search identity wait. no dup dispatch.

## Isolated tendies maker, 2026-11-14

Owner scope: maker INSIDE existing Video Wallpaper. Separate photo layers,
drag reorder, background/middle/foreground roles, preview, manual crop/zoom/position,
save/share and explicit gallery import; never autoapply. Video pipeline reused.
Default-OFF experimental foreground depth uses existing real Floating routing,
not a fabricated motion-parallax feature. All new copy AR/EN/DE/kmr/ckb.
Text-only AI layout route staged only, client gate OFF. Parser bounded/allowlisted;
invalid/off/unavailable falls back to unchanged manual photos. No provider calls,
no paid requests and no production/server/main/release/feed/latest changes.
Offline Node contract tests passed 4/4. Actual simulator archive tests added to
Forge workflow (real generated image/multilayer/video ZIP inspection + parser/
manual fallback/locales). Local WEB has no Swift/Xcode; CI required before delivery.

Tendies maker reference integration, 2026-11-14.
All 140 gallery archives inventoried individually with SHA256 reconciliation; 1007 XML/CAML documents parsed, two malformed upstream Waves documents explicitly recorded. Exact animation keys, state setters/transitions, motion and timing evidence is in docs/tendies-inventory.json and docs/tendies-techniques.md. No reference artwork shipped.
Photo output now simple one wallpaper.ca by default, or opt-in genuine Background/Floating/Foreground LayeredAnimation. Every bundle has separate own PNG assets, index.xml, main.caml and assetManifest.caml. Authored keyed metadata resources, fresh descriptor UUID and generated snapshot colour metadata. Optional system-state unlock zoom/slide, six-second floating and experimental gyro mappings default OFF. Preview remains layout-only. Runtime support on iOS 27 is unverified.
Expanded actual generated-archive XCTest covers both modes, every referenced image, metadata, UUID freshness, all three optional effects and existing generated video. Tests remain explicitly selected in Forge workflow. CI required before delivery; no production or source feed changes.
