#!/bin/bash
set -euo pipefail
sdk="${1:?expected iphoneos or iphonesimulator}"
case "$sdk" in iphoneos|iphonesimulator) ;; *) exit 2 ;; esac
root="$(cd "$(dirname "$0")/.." && pwd)"
sdkroot="$(xcrun --sdk "$sdk" --show-sdk-path)"
out="$root/build/privatekits-sdk-$sdk"
mkdir -p "$out"
for framework in CoreUI CoreSVG; do
    source="$sdkroot/System/Library/PrivateFrameworks/$framework.framework/$framework.tbd"
    test -s "$source" || { echo "Missing genuine $sdk SDK stub for $framework" >&2; exit 1; }
    cp "$source" "$out/$framework.tbd"
    cp "$source" "$root/vendor/PrivateKits/Sources/CFrameworks/$framework/$framework.tbd"
    shasum -a 256 "$out/$framework.tbd"
done
printf '%s\n' "$sdkroot" > "$out/sdk-path.txt"
