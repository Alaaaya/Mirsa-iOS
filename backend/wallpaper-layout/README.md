# Wallpaper layout, STAGED ONLY

No production route is installed and no provider calls were made for this implementation.
Owner authorization is REQUIRED before connecting this adapter to the existing Mirsa free-text lane.
App gate WallpaperLayoutAI.enabled is false. No image upload, generation, editing or paid fallback.

Proposed POST existing authenticated Forge endpoint, action wallpaper-layout, version 1.
Keep existing device-token/account auth, request-size limits, and rate/quota reservations before this adapter.
App sends description (max 2000 UTF8 bytes), photos [{id UUID,width,height}] max8 and
capabilities {parallaxStrength:0,segmentation:false}. No pixels or local paths.
Server returns the bare plan object on 200, or 400/503 {error:"manual_layout"}.
Do not pass normal Forge envelopes (action/device_udid) into the strict plan decoder.

Plan exact keys version=1, layers, parallaxStrength=0, clockArea none|avoidTop.
layers is complete unique known UUID order, each exact id,role background|middle|foreground,
zoom finite1..4, x/y finite-1..1 and crop boolean. Unknown keys/types/URLs rejected, max16KiB.
No motion-parallax implementation is available, so any nonzero strength is rejected.
avoidTop shifts foreground photo centers down to y>=0.35 (fraction of half screen).
This is geometric placement, NOT subject recognition or guaranteed clock avoidance.
Returned plans update local manual controls and preview only. Export/import/apply remain explicit.
Failed/off/invalid model requests leave photos unchanged and show localized manual fallback.

staged.mjs exports a dependency-injected adapter, not a server. ownerEnabled, authenticated,
rateLimitGranted and freeTextOnly MUST come from trusted server context. runExistingFreeText
MUST enforce current $0 provider quota and timeout, without image APIs or paid fallbacks.
Production's current routing is maintained outside this legacy edge snapshot; do not deploy
backend/tweak-forge/index.ts to enable this feature. Integrate only after fresh owner approval.
Run node --test backend/wallpaper-layout/staged.test.mjs.
