#!/bin/bash
# macOS + Xcode only. A real simulator UI app, no fake SwiftUI state mutation.
# Leaves PNGs + machine-readable JSON in SWIFTUI_REFRESH_OUTPUT (default mktemp).
set -euo pipefail
ROOT=$(cd "$(dirname "$0")" && pwd)
OUT=${SWIFTUI_REFRESH_OUTPUT:-$(mktemp -d "${TMPDIR:-/tmp}/mirsa-swiftui-refresh.XXXXXX")}
mkdir -p "$OUT"
OUT=$(cd "$OUT" && pwd)
WORK=$(mktemp -d "${TMPDIR:-/tmp}/mirsa-swiftui-build.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
command -v xcrun >/dev/null || { echo "Requires macOS Xcode simulator" >&2; exit 2; }
SDK=$(xcrun --sdk iphonesimulator --show-sdk-path)
DEVICE=${SWIFTUI_REFRESH_DEVICE:-$(xcrun simctl list devices available -j | python3 -c 'import json,sys; ds=json.load(sys.stdin)["devices"]; print(next(d["udid"] for k,v in ds.items() if "iOS" in k for d in v if "iPhone" in d["name"]))')}
# Reuse a CI-owned device, never erase or shut down anyone else's simulator.
xcrun simctl boot "$DEVICE" >/dev/null 2>&1 || true
xcrun simctl bootstatus "$DEVICE" -b
# Simulator runtimes do not ship the Unix uname executable. The selected
# simulator uses the runner host architecture, as the native smoke harness does.
ARCH=$(uname -m)
APP="$WORK/SwiftUIRefreshSmoke.app"
mkdir -p "$APP"
BUNDLE="app.mirsa.tests.swiftui-refresh"
cat > "$APP/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>app.mirsa.tests.swiftui-refresh</string>
<key>CFBundleExecutable</key><string>SwiftUIRefreshSmoke</string>
<key>CFBundleName</key><string>SwiftUIRefreshSmoke</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>MinimumOSVersion</key><string>17.0</string>
<key>LSRequiresIPhoneOS</key><true/>
<key>UIDeviceFamily</key><array><integer>1</integer></array>
<key>UILaunchScreen</key><dict/>
<key>UISupportedInterfaceOrientations</key><array><string>UIInterfaceOrientationPortrait</string></array>
</dict></plist>
PLIST
if [ -n "${SWIFTUI_REFRESH_DYLIB:-}" ]; then
  cp "$SWIFTUI_REFRESH_DYLIB" "$APP/MirsaTranslate.dylib"
else
  xcrun clang -target "$ARCH-apple-ios17.0-simulator" -isysroot "$SDK" \
    -DMIRSA_RUNTIME_TESTING=1 -fobjc-arc -fblocks -Wall -Wextra -Werror \
    -dynamiclib "$ROOT/RuntimeTranslate.m" "$ROOT/fishhook.c" \
    -framework UIKit -framework Foundation -framework CoreText -framework CoreGraphics \
    -framework Security -o "$APP/MirsaTranslate.dylib"
fi
xcrun swiftc -target "$ARCH-apple-ios17.0-simulator" -sdk "$SDK" \
  -swift-version 5 -parse-as-library "$ROOT/SwiftUIRefreshSmoke.swift" \
  -framework UIKit -framework SwiftUI -framework CoreGraphics \
  -o "$APP/SwiftUIRefreshSmoke"
codesign --force --sign - "$APP/MirsaTranslate.dylib"
codesign --force --sign - "$APP"
xcrun simctl terminate "$DEVICE" "$BUNDLE" >/dev/null 2>&1 || true
xcrun simctl install "$DEVICE" "$APP"
CONTAINER=$(xcrun simctl get_app_container "$DEVICE" "$BUNDLE" data)
# Only this synthetic fixture's stale evidence, never runtime app/user data.
rm -f "$CONTAINER/Documents/refresh-result.json"
xcrun simctl launch --terminate-running-process \
  --stdout="$OUT/app.stdout.log" --stderr="$OUT/app.stderr.log" "$DEVICE" "$BUNDLE"
for _ in $(seq 1 90); do
  [ ! -f "$CONTAINER/Documents/refresh-result.json" ] || break
  sleep 1
done
if [ ! -f "$CONTAINER/Documents/refresh-result.json" ]; then
  xcrun simctl io "$DEVICE" screenshot "$OUT/timeout-screen.png" || true
  echo "FAIL no runtime refresh receipt. Evidence $OUT" >&2
  exit 1
fi
cp "$CONTAINER/Documents/refresh-result.json" "$OUT/"
for file in swiftui-before.png swiftui-after-retained.png swiftui-reference-arabic.png uikit-after.png screen-after-retained.png; do
  [ ! -f "$CONTAINER/Documents/$file" ] || cp "$CONTAINER/Documents/$file" "$OUT/"
done
python3 - "$OUT" <<'PY'
import json, pathlib, sys
root=pathlib.Path(sys.argv[1])
r=json.loads((root/"refresh-result.json").read_text())
print(json.dumps(r,ensure_ascii=False,indent=2))
print("Evidence",root)
required=("swiftui-before.png","swiftui-after-retained.png","swiftui-reference-arabic.png","uikit-after.png")
if not r.get("passed") or not all((root/f).is_file() for f in required):
    sys.exit(1)
PY
