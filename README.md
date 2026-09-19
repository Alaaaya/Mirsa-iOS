# AirCard-iOS

<p align="center">
  <img src="ios-app/Assets.xcassets/AppIcon.appiconset/AppIcon.png" width="128" height="128" alt="AirCard-iOS Icon" style="border-radius: 28px; box-shadow: 0 8px 24px rgba(0,0,0,0.18);" />
</p>

<p align="center">
  Apple Wallet card skins and lock screen passcode themes directly on iOS 27.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Platform-iOS%2027-blue?style=flat-square&logo=apple" alt="Platform" />
  <img src="https://img.shields.io/badge/Swift-5.0-orange?style=flat-square&logo=swift" alt="Swift" />
  <img src="https://img.shields.io/badge/Rust-FFI%20Core-red?style=flat-square&logo=rust" alt="Rust" />
  <img src="https://img.shields.io/badge/License-MIT-green?style=flat-square" alt="License" />
  <a href="https://www.paypal.com/donate/?hosted_button_id=98QRTC2HFRA4Y"><img src="https://img.shields.io/badge/Donate-PayPal-00457C?style=flat-square&logo=paypal" alt="Donate with PayPal" /></a>
</p>

## Overview

AirCard-iOS writes custom artwork to iOS system caches over a local loopback connection. It allows you to customize Apple Wallet card artwork and the passcode dialer directly from an iPhone running iOS 27 without keeping a computer connected.

Core file injection is handled by a Rust static library (`AirliftFFI`) that uses the AirTraffic protocol over a local tunnel provided by LocalDevVPN.

## Features

### Wallet card skins
- Renders images to Wallet specifications (`cardBackgroundCombined@3x.png` at 1536×969, `@2x` at 1024×646, and `cardBackgroundCombined.pdf` for Suica and transit passes).
- Invalidates local pass cache files (`FrontFace`, `Preview`, `PlaceHolder`) so changes show up when Wallet restarts.
- Lets you set artwork for individual cards or apply one skin across all detected cards.
- Live card detection identifies passes as you use Apple Pay.

### Passcode keypad themes
- Interactive dialer preview with touch panning and zoom framing.
- Poster layout: spans one image across all ten keypad buttons.
- Circle button layout: fits images directly inside each button dial.
- Supports system cache targets including `TelephonyUI-10`.
- Supports localized number subtexts, including Ukrainian and Russian Cyrillic variants.
- Imports and exports themes as `.passthm` archives.

### Pairing
- Advertises locally over Bonjour so the phone can pair with itself in Settings › Privacy & Security › Developer Mode › Pair with AirCard-iOS.
- Reads and syncs pairing records automatically into `aircard_pairing.plist`.

## Installation

Install `AirCard-iOS.ipa` using any standard sideloading tool:

- SideStore or AltStore
- TrollStore
- LiveContainer
- Xcode or iOS App Signer

## Prerequisites

1. **LocalDevVPN**: Running with loopback routing (`10.7.0.1` or `127.0.0.1`) so local connections reach internal device services.
2. **Device pairing**: Pair in Settings › Privacy & Security › Developer Mode › Pair with AirCard-iOS, or place an existing pairing plist in the app's document folder.

## Building from source

### Requirements
- macOS 14.0 or newer with Xcode 16 or newer
- XcodeGen (`brew install xcodegen`)
- Rust toolchain (only if rebuilding `rust-core`)

### Build the IPA
```bash
git clone https://github.com/mak5er/AirCard-iOS.git
cd AirCard-iOS
./build-ipa.sh
```
The packaged archive will be saved at `build/AirCard-iOS.ipa`.

### Rebuilding the Rust framework
If you make changes in `rust-core`:
```bash
./build-ios.sh
```

## Repository structure

```
AirCard-iOS/
├── ios-app/                   # SwiftUI application
│   ├── AirCardApp.swift       # App lifecycle
│   ├── AppViewModel.swift     # State management and exploit orchestration
│   ├── ContentView.swift      # Main UI views
│   ├── Models.swift           # Image slicing, theme layout, archive packing
│   ├── PairingController.swift# Bonjour host and pairing sync
│   ├── NetworkStatus.swift    # VPN loopback detection
│   ├── Utilities.swift        # Audio keep-alive and helpers
│   ├── GrappaHelper.[h,m]     # ATC protocol helpers
│   ├── Info.plist             # Bundle configuration
│   └── Assets.xcassets/       # App icons and assets
├── AirliftFFI.xcframework/    # Compiled arm64 Rust static library and headers
├── rust-core/                 # Rust core source code
├── project.yml                # XcodeGen project definition
├── build-ipa.sh               # Build script producing the IPA
├── build-ios.sh               # Script to rebuild the xcframework
├── LICENSE                    # MIT License
└── README.md                  # Project documentation
```

## Credits

- **[@mak5er](https://github.com/mak5er)**: Architecture, UI, passcode theming, pairing automation.
- **[@merybist](https://github.com/merybist)**: Initial base port.
- **[AirLift](https://github.com/0xjohnnydev/airlift)** by **[0xjohnny (@0xjohnnydev)](https://github.com/0xjohnnydev)**: Original AirTraffic/ATAirlock sandbox escape and proof of concept underlying `AirliftFFI`.
- Built upon concepts from the **AirCard** project.

## Support

If you would like to support the development of AirCard-iOS:

- **PayPal**: [Donate via PayPal](https://www.paypal.com/donate/?hosted_button_id=98QRTC2HFRA4Y)
- **TON**: `UQBm9KPhtMw-XVVjirUoa09wzrlyWsbeZhKfefl1Uw-qNZ-r`
- **USDT (TRC20)**: `TDkDMCyjYxgvkWUnQiF5Erk2RyPQMT6G1n`
- **USDT / BNB (BEP20)**: `0x0954dc491c502849d04956ef74634aa5931a08e8`

## License

MIT License. See [LICENSE](LICENSE) for details.
