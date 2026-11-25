#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
SDK="${SDK:-$PWD/iPhoneOS16.5.sdk}"
mkdir -p out
python3 - <<'PY'
from pathlib import Path
d=Path('runtime-table.json').read_bytes()
Path('Table.h').write_text('static const unsigned char runtime_table[] = {'+','.join(map(str,d))+'};\nstatic const unsigned long runtime_table_len = sizeof(runtime_table);\n')
PY
clang-18 -target arm64-apple-ios15.0 -isysroot "$SDK" -fobjc-arc -fblocks -O2 -fvisibility=hidden -Wall -Wextra -Werror -dynamiclib RuntimeTranslate.m fishhook.c -framework UIKit -framework Foundation -framework CoreText -framework CoreGraphics -framework Security -fuse-ld=lld -Wl,-adhoc_codesign -Wl,-install_name,@rpath/MirsaTranslate.dylib -o out/MirsaTranslate.dylib
llvm-objdump-18 --macho --private-headers out/MirsaTranslate.dylib > out/macho-headers.txt
cp runtime-table.json out/MirsaTranslations.json
sha256sum out/MirsaTranslate.dylib out/MirsaTranslations.json
