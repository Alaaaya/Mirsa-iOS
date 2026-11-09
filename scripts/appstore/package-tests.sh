#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/Sources/MirsaStoreKit" "$WORK/Tests/MirsaStoreKitTests"
cp "$ROOT"/ios-app/AppStore/*.swift "$WORK/Sources/MirsaStoreKit/"
cp "$ROOT/tests/StoreClientTests.swift" "$WORK/Tests/MirsaStoreKitTests/"
cat > "$WORK/Package.swift" <<'SWIFT'
// swift-tools-version: 6.2
import PackageDescription
let package = Package(name: "MirsaStoreKit", platforms: [.macOS(.v14), .iOS(.v18)],
    products: [.library(name: "MirsaStoreKit", targets: ["MirsaStoreKit"])],
    dependencies: [
        .package(url: "https://github.com/Lakr233/ApplePackage.git", revision: "391bfe6ee6598d73e4f94b88b38b50bd6f6ec67b"),
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
cd "$WORK"
swift test
