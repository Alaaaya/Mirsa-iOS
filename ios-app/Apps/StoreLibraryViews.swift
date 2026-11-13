import SwiftUI

/// Library tools sheet: updates, wishlist, pinned versions, cleanup setting.
/// Backed by StoreLibraryModel (core worker). Downloaded updates are adopted and installed by the caller.
struct StoreLibraryToolsView: View {
    @ObservedObject private var model = StoreLibraryModel.shared
    let country: String
    let onAccountSwitched: () -> Void
    let onAddAccount: () -> Void
    @State private var accounts: [MirsaStoreOnDeviceClient.SavedAccount] = []
    @State private var selectedID: String?
    /// Caller adopts the downloaded file into the library and starts the existing install path.
    let onUpdateDownloaded: (URL) async -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var checking = false
    @State private var busyID: String?
    @State private var message: String?
    @AppStorage("mirsa.store.autoCleanIPA") private var autoClean = false
    @State private var notify = false

    private typealias T = StoreFeatureText

    var body: some View {
        NavigationStack {
            List {
                Section(T.updates) {
                    if model.updatesChecked && model.updates.isEmpty { Text(T.upToDate).foregroundStyle(.secondary) }
                    ForEach(model.updates) { item in updateRow(item) }
                    Button { Task { await check() } } label: {
                        HStack { if checking { ProgressView() }; Text(T.checkNow) }
                    }.disabled(checking)
                }
                Section(T.wishlist) {
                    if model.wishlist.isEmpty { Text(T.noWishes).foregroundStyle(.secondary) }
                    ForEach(model.wishlist) { w in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(w.name)
                                Text(w.becameFree ? T.becameFree : String(format: "%.2f %@", w.price, w.currency))
                                    .font(.caption).foregroundStyle(w.becameFree ? .green : .secondary)
                            }
                            Spacer()
                            Button(T.remove, role: .destructive) { model.removeWish(id: w.id) }.buttonStyle(.borderless)
                        }
                    }
                    Toggle(T.notifications, isOn: $notify)
                        .onChange(of: notify) { _, on in
                            if on { Task { notify = await StoreWishlistNotifications.enable() } }
                            else { StoreWishlistNotifications.disable() }
                        }
                    Text(T.wishlistNote).font(.footnote).foregroundStyle(.secondary)
                }
                Section(T.pins) {
                    let pinned = model.pins.values.sorted { $0.bundleID < $1.bundleID }
                    if pinned.isEmpty { Text(T.noPins).foregroundStyle(.secondary) }
                    ForEach(pinned, id: \.bundleID) { pin in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(pin.bundleID).font(.footnote)
                                Text("\(pin.version) · \(pin.country.uppercased())").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button(T.unpin) { model.clearPin(bundleID: pin.bundleID, country: pin.country) }.buttonStyle(.borderless)
                        }
                    }
                }
                Section(T.accounts) {
                    ForEach(accounts) { a in
                        Button {
                            guard a.id != selectedID else { return }
                            Task {
                                do { try await MirsaStoreOnDeviceClient.shared.selectAccount(id: a.id); selectedID = a.id; onAccountSwitched() }
                                catch { message = error.localizedDescription }
                            }
                        } label: {
                            HStack { Text(a.account.email); Spacer(); if a.id == selectedID { Image(systemName: "checkmark") } }
                        }
                    }
                    Button(T.addAccount) { onAddAccount() }
                }
                Section(T.settings) {
                    Toggle(T.autoClean, isOn: $autoClean)
                    Text(T.autoCleanNote).font(.footnote).foregroundStyle(.secondary)
                }
                if let message = message ?? model.error { Section { Text(message).foregroundStyle(.orange) } }
            }
            .navigationTitle(T.tools)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("OK") { dismiss() } } }
        }
        .preferredColorScheme(.dark)
        .task {
            notify = UserDefaults.standard.bool(forKey: StoreWishlistNotifications.preference)
            accounts = (try? await MirsaStoreOnDeviceClient.shared.listAccounts()) ?? []
            selectedID = try? await MirsaStoreOnDeviceClient.shared.selectedAccountID()
            await model.checkWishlist()
        }
    }

    private func updateRow(_ item: StoreUpdateItem) -> some View {
        let osNewer = StoreVersionPolicy.newer(item.latest.minimumOSVersion ?? "", than: UIDevice.current.systemVersion)
        return VStack(alignment: .leading, spacing: 4) {
            Text(item.latest.app.name)
            Text("\(item.installedVersion) → \(item.latest.app.version)").font(.caption).foregroundStyle(.secondary)
            if let notes = item.latest.notes(forVersion: nil), !notes.isEmpty {
                DisclosureGroup(T.whatsNew) { Text(notes).font(.footnote) }
            }
            if osNewer == true { Text(T.minOSWarn).font(.caption).foregroundStyle(.orange) }
            Button {
                Task { await download(item) }
            } label: {
                HStack { if busyID == item.id { ProgressView() }; Text(T.download) }
            }.disabled(busyID != nil)
        }
    }

    private func check() async {
        checking = true; defer { checking = false }
        do { try await model.checkUpdates(country: country); message = nil }
        catch { message = error.localizedDescription }
    }

    private func download(_ item: StoreUpdateItem) async {
        busyID = item.id; defer { busyID = nil }
        do { let url = try await model.downloadUpdate(item: item); message = nil; await onUpdateDownloaded(url) }
        catch { message = error.localizedDescription }
    }

}

/// Native share sheet for the saved IPA, untouched file URL, protected from cleanup while presented.
struct StoreShareIPAButton: View {
    let entry: EncryptedIPAEntry
    @State private var sharing = false
    @State private var confirming = false
    @State private var shareURL: URL?
    @State private var shareError: String?

    var body: some View {
        Button { confirming = true } label: {
            Label(StoreFeatureText.share, systemImage: "square.and.arrow.up")
        }
        .confirmationDialog(StoreFeatureText.share, isPresented: $confirming, titleVisibility: .visible) {
            Button(StoreFeatureText.share) {
                do { shareURL = try StoreIPAProtection.shareURL(id: entry.id); sharing = true }
                catch { shareError = error.localizedDescription }
            }
            Button(StoreFeatureText.cancel, role: .cancel) {}
        } message: { Text(StoreFeatureText.shareWarning) }
        .sheet(isPresented: $sharing, onDismiss: { StoreIPAProtection.endSharing(id: entry.id) }) {
            if let shareURL { StoreActivitySheet(url: shareURL).presentationDetents([.medium, .large]) }
        }
        .alert(StoreFeatureText.share, isPresented: Binding(get: { shareError != nil }, set: { if !$0 { shareError = nil } })) {
            Button("OK") { shareError = nil }
        } message: { Text(shareError ?? "") }
    }
}

private struct StoreActivitySheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: [url], applicationActivities: nil) }
    func updateUIViewController(_ c: UIActivityViewController, context: Context) {}
}

/// App detail extras from the fresh catalogue lookup: rating, size, screenshots, what's new, OS warning, pin, wishlist.
struct StoreCatalogDetailCard: View {
    let app: MirsaStoreApp
    let country: String
    /// Selected external version ID, nil means latest.
    let externalVersionID: String?
    let versionLabel: String
    @ObservedObject private var library = StoreLibraryModel.shared
    @State private var item: StoreCatalogItem?
    @State private var failed = false
    @State private var message: String?
    private typealias T = StoreFeatureText

    /// nil unknown, true means the chosen version needs a newer iOS. Never blocks.
    static func osWarning(_ item: StoreCatalogItem?, externalVersionID: String?) -> Bool {
        guard let min = item?.minimumOS(forVersion: externalVersionID) else { return false }
        return StoreVersionPolicy.newer(min, than: UIDevice.current.systemVersion) == true
    }

    var body: some View {
        VStack(alignment: .leading, spacing: MirsaSpacing.s) {
            if Self.osWarning(item, externalVersionID: externalVersionID) {
                Text(T.minOSWarn).font(MirsaFont.caption).foregroundStyle(MirsaPalette.warning)
            }
            if let item {
                HStack(spacing: MirsaSpacing.m) {
                    if let r = item.rating { Label(String(format: "%.1f", r) + (item.ratingCount.map { " (\($0))" } ?? ""), systemImage: "star.fill") }
                    if let s = item.sizeBytes { Label(ByteCountFormatter.string(fromByteCount: s, countStyle: .file), systemImage: "externaldrive") }
                }.font(MirsaFont.caption).foregroundStyle(MirsaPalette.textSecondary)
                if !item.screenshots.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack { ForEach(item.screenshots, id: \.self) { u in
                            AsyncImage(url: u) { $0.resizable().scaledToFit() } placeholder: { Color.gray.opacity(0.2) }
                                .frame(height: 180).clipShape(RoundedRectangle(cornerRadius: 10))
                        } }
                    }
                }
                Text(T.whatsNew).font(MirsaFont.sectionTitle).foregroundStyle(.white)
                if let notes = item.notes(forVersion: externalVersionID), !notes.isEmpty {
                    Text(notes).font(MirsaFont.secondary).foregroundStyle(MirsaPalette.textSecondary)
                } else {
                    Text(T.notesUnavailable).font(MirsaFont.caption).foregroundStyle(MirsaPalette.textTertiary)
                }
            } else if failed { Text(T.notesUnavailable).font(MirsaFont.caption).foregroundStyle(MirsaPalette.textTertiary) }
            else { ProgressView() }
            HStack {
                if let id = externalVersionID {
                    Button(T.pins + ": " + versionLabel) { library.setPin(app: app, country: country, externalVersionID: id, version: versionLabel) }
                        .buttonStyle(.mirsaSecondary)
                }
                if library.pin(bundleID: app.bundleID, country: country) != nil {
                    Button(T.unpin) { library.clearPin(bundleID: app.bundleID, country: country) }.buttonStyle(.mirsaSecondary)
                }
                if (app.price ?? 0) > 0 {
                    Button(T.wishlist) { Task { do { try await library.addWish(app: app, country: country) } catch { message = error.localizedDescription } } }
                        .buttonStyle(.mirsaSecondary)
                }
            }
            if let message { Text(message).font(MirsaFont.caption).foregroundStyle(MirsaPalette.warning) }
        }
        .task(id: app.id) {
            item = nil; failed = false
            do { item = try await StoreCatalog.fetch(appID: app.id, bundleID: nil, country: country) } catch { failed = true }
        }
    }
}
