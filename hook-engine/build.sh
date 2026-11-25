#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
ROOT="$PWD"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
python3 prepare-fishhook.py "$WORK/fishhook.c"
if [[ "$(uname -s)" == Darwin ]]; then
  SDK=$(xcrun --sdk iphoneos --show-sdk-path)
  CC=(xcrun --sdk iphoneos clang)
  LINK=()
else
  SDK="${SDK:-/home/kit/drift-runtime25/iPhoneOS16.5.sdk}"
  CC=("${CC:-clang-18}")
  LINK=(-fuse-ld=lld -Wl,-adhoc_codesign)
fi
[[ -d "$SDK" ]] || { echo "Set SDK to an iPhoneOS SDK" >&2; exit 1; }
"${CC[@]}" -target arm64-apple-ios15.0 -isysroot "$SDK" -fobjc-arc \
  -O2 -Wall -Wextra -Werror -fvisibility=hidden -dynamiclib \
  -I include -I vendor/fishhook src/MirsaHook.m "$WORK/fishhook.c" \
  -lobjc -framework Foundation ${LINK[@]+"${LINK[@]}"} \
  -Wl,-install_name,@rpath/CydiaSubstrate.framework/CydiaSubstrate \
  -Wl,-current_version,1.0.0,-compatibility_version,1.0.0 \
  -o "$WORK/CydiaSubstrate"
[[ -s "$WORK/CydiaSubstrate" ]] || { echo "Fresh hook engine build produced no binary" >&2; exit 1; }
if [[ "$(uname -s)" == Darwin ]]; then
  codesign --force --sign - "$WORK/CydiaSubstrate"
  codesign --verify --strict "$WORK/CydiaSubstrate"
fi
# Device only. Simulator/macOS tests have their own private temporary build.
OUT="$ROOT/dist/CydiaSubstrate.framework"
mkdir -p "$OUT/Headers" "$OUT/Modules"
cp "$WORK/CydiaSubstrate" "$OUT/CydiaSubstrate"
cp include/*.h "$OUT/Headers/"
cp include/module.modulemap "$OUT/Modules/"
cp vendor/fishhook/LICENSE "$OUT/LICENSE.fishhook"
cp LICENSE "$OUT/LICENSE.Mirsa"
python3 - "$OUT" <<'PY'
import hashlib,plistlib,sys
from pathlib import Path
out = Path(sys.argv[1])
plist = dict(CFBundleExecutable="CydiaSubstrate", CFBundleIdentifier="com.mirsa.hookshim",
    CFBundleName="CydiaSubstrate", CFBundlePackageType="FMWK",
    CFBundleShortVersionString="1.0", CFBundleVersion="1",
    MinimumOSVersion="15.0", CFBundleSupportedPlatforms=["iPhoneOS"])
(out / "Info.plist").write_bytes(plistlib.dumps(plist, sort_keys=True))
binary = out / "CydiaSubstrate"
(out.parent / "SHA256SUMS").write_text(hashlib.sha256(binary.read_bytes()).hexdigest() +
    "  CydiaSubstrate.framework/CydiaSubstrate\n")
print((out.parent / "SHA256SUMS").read_text(), end="")
PY
