#!/bin/bash
# Private isolated simulator-host recreation, never runs the real device Drift binary.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")" && pwd)
TMP=$(mktemp -d)
OUT="$ROOT/../build/activated26"
mkdir -p "$OUT"
echo "$TMP" > "$OUT/temp-path.txt"
cp "$ROOT"/{RuntimeTranslate.m,Online.h,OnlineMerge.h,Activation.h,ActivationKey.h,Banner.h,Bidi.h,Tokens.h,fishhook.c,fishhook.h,ActivatedSmoke26.m,activated-fixture26.py} "$TMP/"
cp "$ROOT/fixtures/DriftExact128Translations26.json" "$TMP/"
cd "$TMP"
python3 activated-fixture26.py
# Temporary diagnostic-only traces; runtime hook implementation remains unmodified.
python3 - <<'PY'
from pathlib import Path
p=Path('RuntimeTranslate.m');s=p.read_text()
s=s.replace('static void Start(void) {','static void Start(void) {\n fprintf(stderr,"ACTIVE26 constructor begin\\n");fflush(stderr);')
for token in ['ConfigureOnline(config);','enabled=YES;','for(Class c in attrClasses)HookAttributedInit(c);','for(Class c in stringClasses)HookDrawing(c);','if(n)rebind_symbols(rb,n);']:
 s=s.replace(token,'fprintf(stderr,"ACTIVE26 before '+token.replace('"','')+'\\n");fflush(stderr);'+token+'fprintf(stderr,"ACTIVE26 after stage\\n");fflush(stderr);')
p.write_text(s)
# Keep constructor and mock protocol in an actual LC_LOAD_DYLIB dependency.
p=Path('ActivatedSmoke26.m');s=p.read_text();cut=s.index('@interface ActivatedDelegate26')
Path('ActivatedLibrary26.m').write_text(s[:cut].replace('static void RunActivatedChecks26(void)', 'void RunActivatedChecks26(void)'))
Path('ActivatedHost26.m').write_text('#import <UIKit/UIKit.h>\nextern void RunActivatedChecks26(void);\n'+s[cut:])
PY
SDK=$(xcrun --sdk iphonesimulator --show-sdk-path)
ARCH=$(uname -m)
mkdir -p Activated.app/Frameworks
xcrun clang -target "$ARCH-apple-ios17.0-simulator" -isysroot "$SDK" -g -O0 -fobjc-arc -fblocks -Wall -Wextra -dynamiclib ActivatedLibrary26.m fishhook.c -framework UIKit -framework Foundation -framework CoreText -framework CoreGraphics -framework Security -Wl,-install_name,@loader_path/Frameworks/MirsaTranslate.dylib -o Activated.app/Frameworks/MirsaTranslate.dylib
xcrun clang -target "$ARCH-apple-ios17.0-simulator" -isysroot "$SDK" -g -O0 -fobjc-arc -fblocks ActivatedHost26.m Activated.app/Frameworks/MirsaTranslate.dylib -framework UIKit -framework Foundation -o Activated.app/Activated
xcrun otool -L Activated.app/Activated > "$OUT/host-loads.txt"
cp MirsaTranslations.json Activated.app/Frameworks/
cp MirsaTranslations.json DriftExact128Translations26.json Activated.app/
codesign --force --sign - Activated.app/Frameworks/MirsaTranslate.dylib
codesign --force --sign - Activated.app
DEVICE=$(xcrun simctl list devices available -j | python3 -c 'import json,sys; print(next(d["udid"] for g in json.load(sys.stdin)["devices"].values() for d in g if "iPhone" in d["name"]))')
xcrun simctl boot "$DEVICE" || true
xcrun simctl bootstatus "$DEVICE" -b
xcrun simctl install "$DEVICE" "$TMP/Activated.app"
set +e
xcrun simctl launch --console "$DEVICE" com.mirsa.ci.translationlaunch26 > "$OUT/launch.log" 2>&1
RESULT=$?
set -e
cat "$OUT/launch.log"
CONTAINER=$(xcrun simctl get_app_container "$DEVICE" com.mirsa.ci.translationlaunch26 data)
if [ -f "$CONTAINER/Documents/Activated26.result" ]; then cp "$CONTAINER/Documents/Activated26.result" "$OUT/result.txt"; fi
mkdir -p "$OUT/crashes"
find "$HOME/Library/Logs/DiagnosticReports" -name 'Activated*' -exec cp {} "$OUT/crashes/" \; 2>/dev/null || true
cp "$TMP/RuntimeTranslate.m" "$OUT/instrumented-source.m"
test "$RESULT" = 0
test "$(cat "$OUT/result.txt" 2>/dev/null)" = PASS
