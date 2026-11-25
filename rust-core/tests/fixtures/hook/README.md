Mirsa-owned clean-room UIKit MSHookMessageEx test package, originally delivered for the owner's private hook-engine test on November 25, 2026.

HookTest.m is the complete tweak source. The constructor hooks UIViewController.viewDidAppear: through the absolute dependency /Library/Frameworks/CydiaSubstrate.framework/CydiaSubstrate. Its alert is scheduled only from the hooked method. The package contains no third-party hook engine. The BSD-licensed Mirsa shim is supplied separately by the editor.

The Rust integration test imports this actual DEB through the bounded inert tweak importer, injects its dylib through direct and load-control paths, verifies local engine resolution and runpaths, and verifies the saved package and candidate bytes remain unchanged. This is packaging proof, not UIKit execution or iPhone installation proof. The native macOS smoke uses a separate Foundation tweak because UIKit is not available there.
