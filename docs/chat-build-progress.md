# Chat build progress

Setting: Mirsa AI chat, palette button menu, section "Build progress" (key `mirsa.chat.buildProgressStyle`, `terminal` default or `pill`). Exactly one style is shown.

## Real source today: chat-read top-level `lifecycle`
Rows `{id, sourceMessageID, kind, state, version, artifactID?}`. Bound only by exact `sourceMessageID == user message id`.
queued -> "In queue", working -> "Building" (indeterminate spinner, no steps, no percent). ready is shown only if a thread message has `result.artifact.id == artifactID`. clarification, unknown and others show nothing.

## Optional future contract: per-user-message `buildProgress`
```json
{"requestMessageID":"<uuid, must equal the message id>","buildID":"str?","phase":"understood|building|check|ready",
 "fraction":0.0-1.0 (optional; out of range or non-finite = unknown),"title":"str?","failed":false,
 "events":[{"phase":"...","line":"backend log line (max 160 chars, last 40 kept)","at":"iso?"}]}
```
Unknown phase, missing ids or mismatched requestMessageID drop the snapshot. Explicit snapshot wins over lifecycle. Nothing is simulated or parsed from assistant text. Existing delivery buttons are untouched.
Code: ios-app/Apps/ForgeChatBuildProgress.swift. Tests: tests/ForgeChatBuildProgressTests.swift (screenshots are SYNTHETIC attachments).

## Backend work still required for detailed terminal events

The current server provides only request lifecycle snapshots. This branch does not deploy backend changes and never invents compiler logs or elapsed-time percentages. A privileged build worker must emit durable, idempotent ordered events, scoped to request, approved spec revision and build attempt with the current lease/spec fence. Use allowlisted stage codes and safe public arguments, not raw compiler output or internal paths/secrets. The authenticated chat-read projection must bind these to the existing source message under the same user/device/thread scope. Compiled is not delivered: ready needs the real artifact-backed delivery. Optional fractions must be measured by the worker; omit if unknown.

The floating pill is in-app only, not an iOS Lock Screen Live Activity. Existing delivery attachments/actions remain in their original delivery message; ready progress is an indicator, not a duplicate download action. Screenshots from fixtures are labelled synthetic and do not prove a live build.
