#!/bin/bash
# macOS + Xcode only. A real simulator UI app, no fake SwiftUI state mutation.
# Leaves PNGs + machine-readable JSON in LAUNCH_PROOF_OUTPUT (default mktemp).
set -euo pipefail
ROOT=$(cd "$(dirname "$0")" && pwd)
OUT=${LAUNCH_PROOF_OUTPUT:-$(mktemp -d "${TMPDIR:-/tmp}/mirsa-launch-proof.XXXXXX")}
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
BUNDLE="com.example.activationfixture"
cat > "$APP/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.example.activationfixture</string>
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
# Fresh install = empty app container, so no stale cache. Every mode is a REAL separate process.
xcrun simctl terminate "$DEVICE" "$BUNDLE" >/dev/null 2>&1 || true
xcrun simctl uninstall "$DEVICE" "$BUNDLE" >/dev/null 2>&1 || true
xcrun simctl install "$DEVICE" "$APP"
CONTAINER=$(xcrun simctl get_app_container "$DEVICE" "$BUNDLE" data)
for MODE in control english-control embedded english-embedded ota-seed ota-verify; do
  rm -f "$CONTAINER/Documents/launch-$MODE.json"
  xcrun simctl terminate "$DEVICE" "$BUNDLE" >/dev/null 2>&1 || true
  sleep 1
  python3 - "$ROOT/fixtures/ActivationPublicVector.json" "$OUT/config-$MODE.json" "$MODE" <<'PY2'
import json,sys
v=json.load(open(sys.argv[1]));m=sys.argv[3]
src="Settings" if m.startswith("english-") else "异步刷新验证";ar="الإعدادات" if m.startswith("english-") else "التحقق من التحديث"
c={"translations":{src:ar} if m.endswith("embedded") else {},"substrings":{},"regex":[],"revision":v["revision"]}
if not m.endswith("control"):c["online"]=v
json.dump(c,open(sys.argv[2],"w"),ensure_ascii=False)
PY2
  export SIMCTL_CHILD_MIRSA_TEST_CONFIG="$OUT/config-$MODE.json" SIMCTL_CHILD_MIRSA_TEST_NOW=2000000010
  xcrun simctl launch --terminate-running-process --stdout="$OUT/$MODE.stdout.log" --stderr="$OUT/$MODE.stderr.log" "$DEVICE" "$BUNDLE" -LaunchProof "$MODE"
  for _ in $(seq 1 60); do [ ! -f "$CONTAINER/Documents/launch-$MODE.json" ] || break; sleep 1; done
  [ -f "$CONTAINER/Documents/launch-$MODE.json" ] || { echo "FAIL no receipt for $MODE" >&2; exit 1; }
  cp "$CONTAINER/Documents/launch-$MODE.json" "$OUT/"
  cp "$CONTAINER/Documents/launch-$MODE.png" "$OUT/" 2>/dev/null || true
done
xcrun simctl terminate "$DEVICE" "$BUNDLE" >/dev/null 2>&1 || true
python3 - "$OUT" <<'PY'
import json,pathlib,sys
root=pathlib.Path(sys.argv[1]);ok=True
for m in ("control","english-control","embedded","english-embedded","ota-seed","ota-verify"):
    r=json.loads((root/f"launch-{m}.json").read_text());print(m,r.get("reason"),r.get("arabicReferenceMismatchFraction"))
    ok=ok and r.get("passed") is True
sys.exit(0 if ok else 1)
PY

# The independent modal XCTest needs this host after the temporary build is removed.
# Give it a separate bundle ID so its persisted notice flag cannot touch launch/cache proof.
MODAL_APP="$OUT/modal-host/SwiftUIRefreshSmoke.app"
mkdir -p "$(dirname "$MODAL_APP")"
cp -R "$APP" "$MODAL_APP"
/usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier app.mirsa.tests.swiftui-refresh' "$MODAL_APP/Info.plist"
codesign --force --sign - "$MODAL_APP"
