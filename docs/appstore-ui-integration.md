# App Store account UI hook

File: ios-app/Apps/AppStoreAccountView.swift (self-contained, uses only base design helpers and MirsaStoreClient.shared).

Hook after merging hark/encrypted-apps: push or sheet from EncryptedAppsTab (e.g. a second button under importButton):

    .sheet(isPresented: $showStore) {
        AppStoreAccountView { url in
            let entry = try await EncryptedAppsStore.adopt(file: url, move: false)
            await MainActor.run { EncryptedAppsStore.shared.add(entry) }
        }
    }

The view removes the downloaded file's private temp directory only after the closure returns without throwing. Nothing is signed or modified.

Status: not compiled locally (no Swift toolchain on Linux); needs the device CI build. Uses onChange two-parameter form (iOS 17+). Password lives only in SwiftUI state, copied to a local and cleared before the call; code cleared likewise; all fields cleared on sign out and on disappear. Device behavior untested.
