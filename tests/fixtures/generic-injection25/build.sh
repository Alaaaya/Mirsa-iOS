#!/bin/sh
# Reproduce own inert arm64-device Mach-O fixtures on Linux; native execution is not part of this fixture.
set -eu
cd "$(dirname "$0")/../../.."
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
out=tests/fixtures/generic-injection25
clang-21 -target arm64-apple-ios15.0 -Os -fno-stack-protector -c "$out/Marker.c" -o "$work/marker.o"
ld64.lld-21 -dylib -arch arm64 -platform_version ios 15.0 15.0 -install_name @rpath/GenericMarker25.dylib -headerpad 4096 -no_uuid "$work/marker.o" -o "$out/GenericMarker25.dylib"
clang-21 -target arm64-apple-ios15.0 -Os -fno-stack-protector -DMIRSA_HOOK_DEPENDENCY -c "$out/Marker.c" -o "$work/hook.o"
ld64.lld-21 -dylib -arch arm64 -platform_version ios 15.0 15.0 -install_name @rpath/GenericHookMarker25.dylib -headerpad 4096 -no_uuid "$work/hook.o" hook-engine/dist/CydiaSubstrate.framework/CydiaSubstrate "$out/objc.tbd" -o "$out/GenericHookMarker25.dylib"
sha256sum "$out/"*.dylib > "$out/SHA256SUMS"
