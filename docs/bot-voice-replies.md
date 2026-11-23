# Bot voice reply app support

Isolated from combined/22nov at 6022e95. No chat redesign or new transport.
Existing assistant-side ChatAttachmentStrip already passes audio attachments to the
same ChatVoiceBubble used by users. This change carries bot identity only for
localized playback accessibility labels and exposes duration as the button value.

## Existing backend contract, unchanged

A voice-only reply has a non-user server role, optional nil/empty text and
attachments containing id, kind audio, name, mime audio/mp4, size, durationMS,
sha256, available and optional expiresAt. Audio must be real M4A/MP4 bytes.
Limits remain 5 MiB and 300 seconds. No url, object path or signed URL is required.

Playback posts the attachment id and thread id to authenticated chat-attachment-read.
It verifies size, SHA-256, duration metadata and MP4 ftyp before AVAudioPlayer.
There is no raw URL fetching or signed URL refresh path to add. Unavailable or
expired metadata disables playback using the existing unavailable label. The
existing foreground chat refresh obtains current metadata. No client TTS key,
microphone permission or speech service is involved in playing a bot reply.

## Evidence obtained on Linux

Swift 6.0.3 parse audit passed across all ios-app, tests and uitests Swift sources.
git diff --check passed.
scripts/tests/test_bot_voice_contract_runtime.py compiled unchanged production
ChatVoiceText and projection models with minimal iOS-free seams, then passed
five-locale bot/user play/pause labels, three non-user role roundtrips, preservation
of private-ID audio metadata without URLs, and absolute/unavailable expiry checks.

Reproduce with SWIFTC set to a Swift compiler, then run
python3 scripts/tests/test_bot_voice_contract_runtime.py.

## Added but not executed here

Hosted ChatVoiceTests cover the projection/expiry and five-locale labels.
MirsaVoiceUITests/testBotVoiceRepliesReusePlaybackInAllFiveLanguages covers real
ChatVoiceBubble idle/play/pause/resume/background-return with a local sine-tone
fixture in ar, en, de, kmr and ckb. It also checks voice-only assistant controls
and no pending-user waiting label. testUnavailableBotVoiceDoesNotOfferPlayback
covers unavailable bot metadata. These require the normal Xcode simulator job.

No Xcode SDK, iOS typecheck/link, simulator run, screenshots, physical-device test,
production TTS roundtrip or IPA was performed by this worker. This is not a claim
that Linux projection tests prove AVAudioPlayer or production backend behavior.
