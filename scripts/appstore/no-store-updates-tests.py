#!/usr/bin/env python3
"""Store updates checker removed; other store tools must remain."""
from pathlib import Path
r = Path(__file__).resolve().parents[2]
production = "\n".join(p.read_text() for folder, suffix in [("ios-app", "*.swift"), ("rust-core/src", "*.rs")] for p in (r/folder).rglob(suffix))
for removed in ("StoreUpdateItem", "updatesChecked", "func checkUpdates(", "func downloadUpdate(", "onUpdateDownloaded", "installed-store-apps"):
    assert removed not in production, removed
v = (r/"ios-app/Apps/StoreLibraryViews.swift").read_text()
for removed in ("Section(T.updates)", "T.checkNow", "T.upToDate"):
    assert removed not in v, removed
for kept in ("Section(T.wishlist)", "Section(T.pins)", "Section(T.accounts)", "Section(T.settings)", "StoreShareIPAButton", "StoreCatalogDetailCard"):
    assert kept in v, kept
m = (r/"ios-app/Apps/StoreLibraryModel.swift").read_text()
for kept in ("func checkWishlist()", "func setPin(", "enum StoreIPAProtection", "enum StoreWishlistNotifications"):
    assert kept in m, kept
print("PASS store update checker removed, wishlist/pins/accounts/cleanup/share/details preserved")
