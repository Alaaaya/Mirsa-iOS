Generic per-app Arabic runtime translator

The shipped embedded table is intentionally empty. Place a generated MirsaTranslations.json adjacent to the dylib. The fixtures directory contains a separate Drift device-feedback dictionary, never embedded in the generic library.

Online missing-only translation is off without explicit per-app capability configuration. Its online object must match backend/runtime-translate/CONTRACT.md. Uses endpoint only from that object, strict mrt1 capability format, exact bundle ID/revision scope, ISO8601 expiry no longer than 24 hours. No provider credentials or user JWT. Conservative privacy screening precedes queueing. Requests are single-item missing batches, capped at 256 UTF16 units, 16 pending and 128 attempts per launch. Only original untranslated CJK is eligible; partial translations are not sent. Positive cache is process-memory only, revision-scoped and lock-protected, max128 entries; negative cache60 seconds, max128. No cross-launch text persistence except the local missing diagnostic log. Network errors leave UI unchanged; later natural render uses cached translation. No forced redraw.

The worker never blocks UI. Ephemeral session timeout5s, worker timeout6s, serial worker, redirects refused, streamed response cap64KiB, status/scope/schema/placeholders checked. URLs, domains, email, paths, credentials, private markers, controls and long numbers are rejected locally. Privacy heuristics cannot prove arbitrary text is nonprivate; online requires explicit app-level consent in capability issuance.

Local Missing JSONL log lives in Documents/MirsaTranslateMissing.txt, max1MiB, max1024 unique per launch, max16 queued, max4096 UTF16 units cut without splitting a surrogate pair. O_NOFOLLOW, regular single-link file and fchmod0600, including pre-existing file. Never uploaded.

Latin/version runs in translated Arabic get LRI/PDI directional isolation. Existing isolates and printf/template placeholders are not wrapped again. Embedded generic table remains empty.

Linux build requires clang18 and lld18 with an iPhoneOS SDK. Run SDK=/path/iPhoneOS16.5.sdk bash build-linux.sh, then python3 test_runtime.py. Build uses Werror. Simulator smoke script requires macOS/Xcode and a bootable iPhone simulator. Smoke.m contains native UIKit hooks and bidi assertions. Simulator/device execution has not been performed for this generic version. Linux cross-compilation is not runtime proof.

fishhook BSD license is retained verbatim in fishhook.c and fishhook.h. Binary distributions must reproduce it in the application's third-party notices. Hook coverage is best-effort, not universal SwiftUI coverage. No deployment or production changes.

Placeholder recognition and implicit-argument order checks exactly mirror ArabicIPALocalizer printfRegex/tokenRegex, shared with bidi protection. Unnumbered arguments (including dynamic widths) retain original order; fully positional arguments may reorder only with identical tokens. %% remains literal. Both local dictionary transformations and online results are validated. Network privacy screening masks only recognized printf tokens, not HTML or brace contents, to avoid hiding private data. Generic missing detection includes Kana, Hangul and supplementary Han. Updated native policy tests cover these cases, but are cross-compiled only, not executed.
