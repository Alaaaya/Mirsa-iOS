#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
SDK=$(xcrun --sdk iphoneos --show-sdk-path)
mkdir -p ../ios-app/BackgroundNotificationAssets
xcrun --sdk iphoneos clang -target arm64-apple-ios15.0 -isysroot "$SDK" -fobjc-arc -fblocks -O2 -Wall -Wextra -Werror -dynamiclib BackgroundNotifications.m -framework UIKit -framework Foundation -framework AVFoundation -framework CoreLocation -framework UserNotifications -Wl,-install_name,@rpath/MirsaBackground.dylib -o ../ios-app/BackgroundNotificationAssets/MirsaBackground.dylib
codesign --force --sign - ../ios-app/BackgroundNotificationAssets/MirsaBackground.dylib
codesign --verify --strict ../ios-app/BackgroundNotificationAssets/MirsaBackground.dylib
python3 provenance.py --toolchain apple
