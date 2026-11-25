#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
[[ "$(uname -s)" == Darwin ]] || { echo "macOS with Xcode required" >&2; exit 1; }
WORK=$(mktemp -d "${TMPDIR:-/tmp}/mirsa-hook-smoke.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
python3 prepare-fishhook.py "$WORK/fishhook.c"
SDK=$(xcrun --sdk macosx --show-sdk-path)
ARCH=$(uname -m)
FLAGS=(-arch "$ARCH" -isysroot "$SDK" -mmacosx-version-min=12.0 -O0 -Wall -Wextra -Werror)
# Avoid modern chained imports for this positive legacy-fishhook test.
LINK=(-Wl,-no_fixup_chains)
mkdir -p "$WORK/CydiaSubstrate.framework"
xcrun clang "${FLAGS[@]}" -fobjc-arc -fvisibility=hidden -dynamiclib \
  -I include -I vendor/fishhook src/MirsaHook.m "$WORK/fishhook.c" \
  -framework Foundation -lobjc "${LINK[@]}" \
  -Wl,-install_name,@rpath/CydiaSubstrate.framework/CydiaSubstrate \
  -o "$WORK/CydiaSubstrate.framework/CydiaSubstrate"
xcrun clang "${FLAGS[@]}" -dynamiclib tests/Provider.c "${LINK[@]}" \
  -Wl,-install_name,@rpath/libMirsaProvider.dylib -o "$WORK/libMirsaProvider.dylib"
xcrun clang "${FLAGS[@]}" -dynamiclib tests/Future.c -L "$WORK" -lMirsaProvider \
  "${LINK[@]}" -Wl,-rpath,"$WORK" -o "$WORK/libMirsaFuture.dylib"
xcrun clang "${FLAGS[@]}" -fobjc-arc -I include tests/Smoke.m \
  -F "$WORK" -framework CydiaSubstrate -framework Foundation \
  -L "$WORK" -lMirsaProvider "${LINK[@]}" -Wl,-rpath,"$WORK" -o "$WORK/smoke"
xcrun clang "${FLAGS[@]}" -fobjc-arc -I include -dynamiclib tests/SampleTweak.m \
  -F "$WORK" -framework CydiaSubstrate -framework Foundation "${LINK[@]}" \
  -Wl,-rpath,"$WORK" -o "$WORK/libMirsaSampleTweak.dylib"
for f in "$WORK/CydiaSubstrate.framework/CydiaSubstrate" "$WORK/"*.dylib "$WORK/smoke"; do
  codesign --force --sign - "$f"
done
"$WORK/smoke" "$WORK/libMirsaFuture.dylib" "$WORK/libMirsaSampleTweak.dylib"
# A chained-fixup importer is a separate negative test.
xcrun clang "${FLAGS[@]}" -fobjc-arc -I include tests/Chained.m \
  -F "$WORK" -framework CydiaSubstrate -framework Foundation \
  -L "$WORK" -lMirsaProvider -Wl,-fixup_chains -Wl,-rpath,"$WORK" -o "$WORK/chained"
codesign --force --sign - "$WORK/chained"
"$WORK/chained"
