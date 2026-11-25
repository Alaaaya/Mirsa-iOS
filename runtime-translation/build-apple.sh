#!/bin/bash
# Builds the generic device library from this exact checkout. No deployment.
set -euo pipefail
cd "$(dirname "$0")"
SDK=$(xcrun --sdk iphoneos --show-sdk-path)
python3 - <<'PY'
from pathlib import Path
d=Path('runtime-table.json').read_bytes()
Path('Table.h').write_text('static const unsigned char runtime_table[] = {'+','.join(map(str,d))+'};\nstatic const unsigned long runtime_table_len = sizeof(runtime_table);\n')
PY
mkdir -p ../ios-app/RuntimeTranslationAssets
xcrun --sdk iphoneos clang -target arm64-apple-ios15.0 -isysroot "$SDK" -fobjc-arc -fblocks -O2 -fvisibility=hidden -Wall -Wextra -Werror -dynamiclib RuntimeTranslate.m fishhook.c -framework UIKit -framework Foundation -framework CoreText -framework CoreGraphics -framework Security -Wl,-install_name,@rpath/MirsaTranslate.dylib -o ../ios-app/RuntimeTranslationAssets/MirsaTranslate.dylib
xcrun strip -S -x ../ios-app/RuntimeTranslationAssets/MirsaTranslate.dylib
codesign --force --sign - ../ios-app/RuntimeTranslationAssets/MirsaTranslate.dylib
codesign --verify --strict ../ios-app/RuntimeTranslationAssets/MirsaTranslate.dylib
python3 provenance.py
