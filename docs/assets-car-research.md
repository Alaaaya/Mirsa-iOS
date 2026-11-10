# Assets.car editor research, not delivered functionality

Samra (https://github.com/NSAntoine/Samra), MIT, 430 stars at inspection, provides
real rendition editing through NSAntoine/PrivateKits AssetCatalogWrapper.
The actual API was read at
https://raw.githubusercontent.com/NSAntoine/PrivateKits/main/Sources/AssetCatalogWrapper/AssetCatalogWrapper.swift
and Package.swift was inspected at commit 457d34b3af7249d9999542809b16300f17082f6e.

The package declares iOS 13 support but depends on private CoreUI/CoreSVG bridges,
CSIGenerator and CUIMutableCommonAssetStorage. Its inspected main source contains
a nonexhaustive UIKit switch over Representation (.rawData is not handled).
It is not safe to assume it compiles unchanged, or that its private editing classes
exist on the current iOS build. Appearance enum includes any/dark/high-contrast/light,
not modern tinted or Icon Composer variants. Existing named-lookup keys must be
preserved; tint must not be guessed as an appearance integer.

Other inspected sources
https://github.com/insidegui/AssetCatalogTinkerer (macOS extraction, not rebuild)
https://github.com/showxu/cartools (CoreUI/CoreThemeDefinition, macOS)
https://github.com/xtool-org/AssetKit (clean-room xcassets compiler, not demonstrated
lossless in-place rewrite of arbitrary modern catalog renditions).

No fake .car rebuild, replacement icon PNG pretending to edit the catalog, or
enabled-but-inert dark-icon switch has been added. Existing unavailable switch
remains truthful. Required follow-up is to isolate/fix and pin the iOS library,
compile it, probe actual CoreUI runtime support, and round-trip real normal/dark/
tinted samples with unchanged rendition keys before enabling edits.
