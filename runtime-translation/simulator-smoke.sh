#!/bin/bash
# macOS/Xcode fixture smoke. Does not change shipped empty table.
set -euo pipefail
cd "$(dirname "$0")"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
cp RuntimeTranslate.m Online.h Bidi.h Tokens.h fishhook.[ch] Smoke.m NativePolicySmoke.m "$TMP/"
cd "$TMP"
python3 - <<'PY'
import json
from pathlib import Path
d=json.dumps({"translations":{"取消":"إلغاء","确定":"تأكيد","设置":"الإعدادات"},"substrings":{},"regex":[]}).encode()
Path("MirsaTranslations.json").write_bytes(d)
Path("Table.h").write_text("static const unsigned char runtime_table[]={"+",".join(map(str,d))+"};\nstatic const unsigned long runtime_table_len=sizeof(runtime_table);\n")
PY
SDK=$(xcrun --sdk iphonesimulator --show-sdk-path)
ARCH=$(uname -m)
xcrun clang -target "$ARCH-apple-ios17.0-simulator" -isysroot "$SDK" -fobjc-arc -fblocks -Wall -Wextra -Werror -dynamiclib RuntimeTranslate.m fishhook.c -framework UIKit -framework Foundation -framework CoreText -o MirsaTranslate.dylib
xcrun clang -target "$ARCH-apple-ios17.0-simulator" -isysroot "$SDK" -fobjc-arc -fblocks Smoke.m -framework UIKit -framework Foundation -framework CoreText -o smoke
DEVICE=$(xcrun simctl list devices available -j | python3 -c 'import json,sys;print(next(d["udid"] for g in json.load(sys.stdin)["devices"].values() for d in g if "iPhone" in d["name"]))')
xcrun simctl boot "$DEVICE" || true
xcrun simctl bootstatus "$DEVICE" -b
xcrun simctl spawn "$DEVICE" "$TMP/smoke" "$TMP/MirsaTranslate.dylib"

xcrun clang -target "$ARCH-apple-ios17.0-simulator" -isysroot "$SDK" -fobjc-arc -fblocks -Wall -Wextra -Werror NativePolicySmoke.m fishhook.c -framework UIKit -framework Foundation -framework CoreText -o policy-smoke
xcrun simctl spawn "$DEVICE" "$TMP/policy-smoke"
