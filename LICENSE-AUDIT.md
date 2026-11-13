# License audit (mirsa/video-wallpaper lineage, base 050fda5)

Method: read rust-core/Cargo.toml + Cargo.lock, project.yml, build-ios.sh, workflows, vendor dirs, Swift imports. Swift imports alone were NOT used as proof of absence: all Rust code reaches the app as one static library inside AirliftFFI.xcframework.

Linking: rust-core/Cargo.toml [lib] crate-type = ["staticlib"] -> libairlift_ffi.a (AirliftFFI.xcframework/ios-arm64/libairlift_ffi.a), linked via project.yml:48 (framework: AirliftFFI.xcframework); built by build-ios.sh:26-37. Swift side: import AirliftFFI in ios-app/Models.swift:743, RespringHelper.swift:12, Discovery/DiscoveryDownloader.swift:3 and others.

| Entry | Result | Evidence |
|---|---|---|
| isideload (MIT) | KEEP, statically linked | Cargo.toml:66 isideload = 0.5.2 (features install, tokio-mt); Cargo.lock:1783 name isideload 0.5.2 from crates.io |
| idevice (MIT) | KEEP, statically linked + vendored | Cargo.toml:14 idevice dep, patched to path vendor/idevice (lines 78-84); rust-core/vendor/idevice (license = MIT), vendor/idevice-ffi; Cargo.lock:1631 idevice 0.1.63 |
| apple-codesign-quick (LGPL-2.1-or-later) | KEEP, statically linked + vendored (LGPL notice required) | Cargo.toml:70 dep, patched to vendor/apple-codesign-quick (line 86); its Cargo.toml:24 license LGPL-2.1-or-later; Cargo.lock:176 |
| Mirsa base code (MIT, Johnny Franks) | KEEP | LICENSE: MIT, Copyright (c) 2026 Johnny Franks; original code remains throughout ios-app and rust-core (git history starts with upstream commits 848bf27/81854c0) |
| FlekDeck UI inspiration | REMOVED from About | owner confirmed no FlekDeck code bundled; only comments in ios-app/Apps/MirsaHomeScreen.swift:3-4 and LICENSES/FlekDeck-inspiration.md remain (files untouched) |

Uncertain / not in About list, left untouched: LICENSES/ also holds Pocket-Poster-GPL-3.0.txt, VideoCAML-NOTICE.md, Sideloader-NOTICE.md, apple-auth-MIT.txt and apple-auth-dependencies/ (MbedTLS, curl, libplist, nlohmann-json, zlib). They are not shown in About today; this change neither adds nor removes them. Whether each is actually bundled was not audited here.
