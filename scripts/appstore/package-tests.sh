#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/Sources/MirsaStoreKit" "$WORK/Tests/MirsaStoreKitTests"
cp "$ROOT"/ios-app/AppStore/*.swift "$WORK/Sources/MirsaStoreKit/"
cp "$ROOT/tests/StoreClientTests.swift" "$WORK/Tests/MirsaStoreKitTests/"
cp "$ROOT/ios-app/Apps/UpdateNetworkPath.swift" "$WORK/Sources/MirsaStoreKit/"
cp "$ROOT/tests/UpdateNetworkPathTests.swift" "$WORK/Tests/MirsaStoreKitTests/"
# UI localization is outside this standalone backend package.
cat > "$WORK/Sources/MirsaStoreKit/TestLocalization.swift" <<'SWIFT'
func tr(_ en: String, _ ar: String, ckb: String, kmr: String) -> String { en }
SWIFT
cat > "$WORK/Package.swift" <<'SWIFT'
// swift-tools-version: 6.2
import PackageDescription
let package = Package(name: "MirsaStoreKit", platforms: [.macOS(.v14), .iOS(.v18)],
    products: [.library(name: "MirsaStoreKit", targets: ["MirsaStoreKit"])],
    dependencies: [
        .package(path: "__APPLEPACKAGE_PATH__"),
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", from: "0.9.20"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.5.0")
    ],
    targets: [
        .target(name: "MirsaStoreKit", dependencies: [
            .product(name: "ApplePackage", package: "ApplePackage"),
            .product(name: "ZIPFoundation", package: "ZIPFoundation"),
            .product(name: "Logging", package: "swift-log")
        ]),
        .testTarget(name: "MirsaStoreKitTests", dependencies: ["MirsaStoreKit",
            .product(name: "ApplePackage", package: "ApplePackage"),
            .product(name: "ZIPFoundation", package: "ZIPFoundation")
        ])
    ], swiftLanguageModes: [.v5])
SWIFT
python3 - "$WORK/Package.swift" "$ROOT/vendor/ApplePackage" <<'PYTHON'
import sys
from pathlib import Path
p=Path(sys.argv[1]);p.write_text(p.read_text().replace("__APPLEPACKAGE_PATH__", sys.argv[2]))
PYTHON
cd "$WORK"
swift test
