#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
: "${SDK:?Set SDK to an iPhoneOS SDK}"
mkdir -p out
clang-18 -target arm64-apple-ios15.0 -isysroot "$SDK" -fobjc-arc -fblocks -O2 -Wall -Wextra -Werror -dynamiclib BackgroundNotifications.m -framework UIKit -framework Foundation -framework AVFoundation -framework CoreLocation -framework UserNotifications -fuse-ld=lld -Wl,-adhoc_codesign -Wl,-install_name,@rpath/MirsaBackground.dylib -o out/MirsaBackground.dylib
llvm-objdump-18 --macho --private-headers out/MirsaBackground.dylib > out/macho-headers.txt
sha256sum out/MirsaBackground.dylib
