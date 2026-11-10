Source detail listing failure and source-control evidence

The screenshot is ryP0 detail with an empty-state message, not a search result or an error banner. Its persisted badge can be 163 even when the process-local apps dictionary has no entry. AppTesters likewise persists 10,098 independently of its in-memory catalogue.

The exact earliest introduction of this defective loading contract is 4a286fd471da63840fd170481e389d89a286595c, the initial Sources implementation. SourceDetailView only read apps[source.url] and supported manual pull-to-refresh, but had no on-entry load. The parent only refreshed when the entire apps dictionary was empty, not when this URL was missing. The parent-owned structured refresh could also be cancelled by screen navigation; an error was written globally but never shown by detail. These states were all presented as a successfully loaded empty source.

This is NOT an established new regression in 1.9. Actual release history comparison:
1.7 ff4920982459d1b6dcee017d9fc3a6609dd1993c SourcesTab blob 96bf9926095b71eeb016528e09fb736563751eeb.
1.8 2e467c6e4497f7f421e0205e9a94216c7f8f68db has the identical blob.
1.9 674042d05e5e894ae7bf407ba8d3e28089030de9 blob 5a858c8b0d12d5dc7be3ef1af20ca890d679e375 changes ONLY RepoAppRow temporary-download cleanup, not feed parsing/loading/detail. No evidence supports blaming source deletion or temp cleanup for introducing this listing bug.
910e432bbc30c7cfd6c94c208853e577e0b9df21 separately introduced injectable parent stores while detail remained on the singleton. Production normally used the shared store; that mismatch alone is not a demonstrated explanation of the owner's screenshot. It is fixed by forwarding the exact parent store.

Fix coverage
Per-URL on-entry ensureLoaded and missing-source refresh replace the global cache gate. Requests are deduplicated and owned by the store, independent of the departing list task. Per-source errors, progress, retry, loaded-empty and no-search-match states are distinct; failures retain an already loaded list. Full JSON parsing/date work runs off the UI actor. SwiftUI List/ForEach stays lazy; existing install, update and IPA-selection actions are retained. Stable-UID confirmed source deletion and duplicate handling remain intact, including deletion during a request without resurrection.

Pinned complete configured feeds, not guessed endpoints or truncated samples
AppTesters https://repository.apptesters.org, 10,392,165 bytes, 10,130 raw rows, 10,098 unique parsed apps. SHA256 0559987a4c45cdb075f55d5d70877c997c71bf784dcdbfd75f2ee1d73a9ba418.
ryP0 https://raw.githubusercontent.com/Sami-Wali/ryP0-repository/main/repo.json, 2,366,545 bytes, 178 raw rows, 13 without usable downloads and 2 duplicates, 163 unique parsed apps. SHA256 ce917635a094e7c9738ee48de8e9d5398d55c876a9a6b69a74695de9ff3fba4e.
Complete data is stored gzip-compressed under tests/SourceFixtures. It is untrusted data, never executed. Tests use the actual production store, model, parser, feed-migration and screenshot URL policy, extracted without unrelated installation UI entrypoints for macOS standalone compilation. The complete iOS file is separately compiled in the device IPA build.

Runtime tests cover both full feed counts/search/URLs including tail rows; persisted-count/missing-memory detail entry; partial global cache; navigation cancellation with same-URL request joining; per-source network failure and retry; HTTP failure retaining existing rows; real loaded-empty distinction; in-flight deletion; malformed/duplicate/unsafe rows; malformed JSON and bare arrays; duplicate-source refresh and badges. Existing ten source-deletion regressions also run. Wiring guards verify injected-store propagation, per-URL task, lazy List, actual install and selection callsites, and all five new states in four languages.

Physical-device UI and actual third-party installation remain owner-untested. This evidence identifies the exact code origin and reproduces the defective state contract, not the precise network event that occurred on the owner's phone.
