import SwiftUI
import UniformTypeIdentifiers

// MARK: - Actions shared by the store page and the item sheet

private struct ToolsStoreFile: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

/// Runs every item action through Mirsa's existing flows:
/// wallpapers → AppViewModel.importTendieFiles / flashSelectedTendies (Tendies engine) and the existing respring view,
/// tweaks → IPATweakLibrary and the existing ForgeChatInjectSheet (container / real app / certificate projects),
/// sounds and fonts → the system share sheet (Save to Files).
@MainActor
final class ToolsStoreActions: ObservableObject {
    /// Which view currently owns presentations ("main" or "sheet"), so a sheet and its parent never present together.
    @Published var activeHost = "main"
    @Published var busyID: String?
    @Published fileprivate var injectFile: ToolsStoreFile?
    @Published fileprivate var shareFile: ToolsStoreFile?
    @Published var pendingWallpaper: UUID?
    @Published var offerRespring = false
    @Published var message: String?
    let respring = MirsaWallpaperRespringPresentation()
    weak var vm: AppViewModel?
    private var respringArmed = false

    private var model: AppViewModel? { vm ?? AppViewModel.shared }

    func isBusy(_ item: ToolsStoreItem) -> Bool { busyID == item.id }

    private func run(_ item: ToolsStoreItem, _ work: @escaping @MainActor () async throws -> Void) {
        guard busyID == nil else { return }
        busyID = item.id
        Task { @MainActor in
            defer { self.busyID = nil }
            do { try await work() }
            catch {
                if error is CancellationError || (error as? URLError)?.code == .cancelled { return }
                self.message = error.localizedDescription
            }
        }
    }

    /// Download: tweaks go to the tweak library, wallpapers to the wallpaper list, sounds and fonts to the share sheet.
    func download(_ item: ToolsStoreItem) {
        guard let kind = item.kind else { message = ToolsStoreText.badFile; return }
        run(item) {
            let file = try await ToolsStoreClient.fetchFile(item)
            let folder = file.deletingLastPathComponent()
            switch kind {
            case .tweaks, .appTweaks:
                defer { MirsaManagedTmp.end(folder) }
                // Same import as Mirsa AI's inject path (no multi-pick prompt here: a package with several
                // code files reports the library's own "selection required" message instead).
                _ = try await IPATweakLibrary.shared.addFile(file)
                self.message = ToolsStoreText.addedToLibrary
            case .wallpapers:
                defer { MirsaManagedTmp.end(folder) }
                guard let model = self.model else { throw ToolsStoreError.unavailable }
                let ids = await model.importTendieFiles(urls: [file])
                if !ids.isEmpty { self.message = ToolsStoreText.addedToWallpapers }
            case .sounds, .fonts:
                self.shareFile = ToolsStoreFile(url: file)   // folder ends when the share sheet closes
            }
        }
    }

    /// Inject: the file goes through the same sheet Mirsa AI uses for its tweak files.
    func inject(_ item: ToolsStoreItem) {
        run(item) {
            let file = try await ToolsStoreClient.fetchFile(item)
            self.injectFile = ToolsStoreFile(url: file)   // folder ends when the inject sheet closes
        }
    }

    /// Apply: import into the wallpaper list, then ask before copying it with the Tendies engine.
    func apply(_ item: ToolsStoreItem) {
        guard let model = self.model else { message = ToolsStoreText.unavailable; return }
        if case .running = model.tendiesFlashPhase { message = ToolsStoreText.wallpaperBusy; return }
        run(item) {
            let file = try await ToolsStoreClient.fetchFile(item)
            defer { MirsaManagedTmp.end(file.deletingLastPathComponent()) }
            let ids = await model.importTendieFiles(urls: [file])
            guard let id = ids.first else { return }   // import errors are already shown by the app's notice
            self.pendingWallpaper = id
        }
    }

    /// Confirmed install: select only the imported wallpaper (as the Wallpapers page does for a picked file) and copy it.
    func confirmApply() {
        guard let id = pendingWallpaper, let model = self.model else { pendingWallpaper = nil; return }
        pendingWallpaper = nil
        if case .running = model.tendiesFlashPhase { message = ToolsStoreText.wallpaperBusy; return }
        for index in model.tendieItems.indices {
            model.tendieItems[index].isSelected = model.tendieItems[index].id == id
        }
        model.saveTendieItems()
        model.errorMessage = nil
        Task { @MainActor in
            await model.flashSelectedTendies()
            if case .done(ok: true) = model.tendiesFlashPhase {
                if model.tendiesInstalledNew {
                    self.respringArmed = true
                    model.tendiesFlashLog.append("REFRESH PROMPT offered from Tools Store; awaiting explicit restart or not-now choice.")
                    self.offerRespring = true
                } else {
                    self.message = ToolsStoreText.wallpaperApplied
                }
            }
        }
    }

    func confirmRespring() {
        offerRespring = false
        guard respringArmed, let model = self.model else { return }
        respringArmed = false
        model.tendiesFlashLog.append("REFRESH TAP restart confirmation (Tools Store)")
        respring.start { model.tendiesFlashLog.append($0) }
    }

    func declineRespring() {
        offerRespring = false
        respringArmed = false
        model?.tendiesFlashLog.append("REFRESH declined by user; no restart requested.")
    }

    func logRespring(_ line: String) {
        MirsaWallpaperEvidence.record(line)
        model?.tendiesFlashLog.append(line)
    }

    fileprivate func endFile(_ file: ToolsStoreFile, keep: Bool = false) {
        if !keep { MirsaManagedTmp.end(file.url.deletingLastPathComponent()) }
    }
}

/// Presentations for store actions. Attached to the page and to the item sheet; only the active host presents.
private struct ToolsStorePresenters: ViewModifier {
    let host: String
    @ObservedObject var actions: ToolsStoreActions
    @ObservedObject var respring: MirsaWallpaperRespringPresentation

    private var active: Bool { actions.activeHost == host }
    private func ws(_ k: MirsaWallpaperActionStrings.Key) -> String { MirsaWallpaperActionStrings.text(k) }

    func body(content: Content) -> some View {
        content
            .sheet(item: Binding(get: { active ? actions.injectFile : nil }, set: { value in
                if value == nil, active { actions.injectFile = nil }
            })) { file in
                ForgeChatInjectSheet(file: file.url) { keep in actions.endFile(file, keep: keep) }
            }
            .sheet(item: Binding(get: { active ? actions.shareFile : nil }, set: { value in
                if value == nil, active, let file = actions.shareFile { actions.endFile(file); actions.shareFile = nil }
            })) { file in
                ForgeChatShare(url: file.url).presentationDetents([.medium, .large])
            }
            .alert(ws(.installTitle), isPresented: Binding(get: { active && actions.pendingWallpaper != nil }, set: { _ in
                // Cleared by the buttons themselves, so a dismissal that lands before the action cannot drop the confirmation.
            })) {
                Button(ws(.installConfirm)) { actions.confirmApply() }
                Button(ws(.cancel), role: .cancel) { actions.pendingWallpaper = nil }
            } message: { Text(ws(.installBody)) }
            .alert(ws(.respringTitle), isPresented: Binding(get: { active && actions.offerRespring }, set: { if !$0, active { actions.offerRespring = false } })) {
                Button(ws(.respringConfirm), role: .destructive) { actions.confirmRespring() }
                Button(ws(.respringLater), role: .cancel) { actions.declineRespring() }
            } message: { Text(ws(.respringBody)) }
            .alert(SourcesText.notice, isPresented: Binding(get: { active && actions.message != nil }, set: { if !$0, active { actions.message = nil } })) {
                Button(SourcesText.ok) { actions.message = nil }
            } message: { Text(actions.message ?? "") }
            // Same presentation as the Wallpapers page: one retained flag, WebKit payload, explicit cancel.
            .fullScreenCover(isPresented: Binding(get: { active && respring.isPresented }, set: { if !$0 { respring.isPresented = false } }), onDismiss: {
                actions.logRespring("REFRESH AFTER cover dismissed · system respring and picker visibility require device confirmation")
            }) {
                ZStack(alignment: .topTrailing) {
                    MirsaWallpaperRespringView(event: { line in actions.logRespring(line) }).ignoresSafeArea()
                    Button(ws(.cancel)) { respring.isPresented = false }
                        .padding().background(.black.opacity(0.8)).foregroundStyle(.white)
                }.interactiveDismissDisabled()
            }
    }
}

// MARK: - Store page

struct ToolsStoreView: View {
    @EnvironmentObject var vm: AppViewModel
    @StateObject private var model = ToolsStoreModel()
    @StateObject private var actions = ToolsStoreActions()
    @ObservedObject private var saved = ToolsStoreSaved.shared
    @State private var showSaved = false
    @State private var showUpload = false
    @State private var selected: ToolsStoreItem?
    @State private var loadedOnce = false
    @AppStorage(SourcesTheme.key) private var themeRaw = SourcesTheme.aurora.rawValue
    private var theme: SourcesTheme { SourcesTheme(rawValue: themeRaw) ?? .aurora }

    var body: some View {
        let t = theme
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header(t)
                reviewBanner(t)
                SourcesSearchField(placeholder: ToolsStoreText.search, theme: t, text: $model.query, identifier: "tools-store-search")
                    .onSubmit { model.reload() }
                categoryBar(t)
                if showSaved {
                    savedSection(t)
                } else if !model.isConfigured {
                    unavailableCard(t, message: ToolsStoreText.notConfigured)
                } else {
                    catalogue(t)
                }
            }
            .padding(.horizontal, MirsaSpacing.page)
            .padding(.top, 4)
            .padding(.bottom, 40)
        }
        .scrollDismissesKeyboard(.interactively)
        .refreshable { model.reload() }
        .background(SourcesThemeBackground(theme: t))
        .tint(t.accent[0])
        .environment(\.colorScheme, t.colorScheme)
        .modifier(ToolsStorePresenters(host: "main", actions: actions, respring: actions.respring))
        .sheet(item: $selected, onDismiss: { actions.activeHost = "main" }) { item in
            ToolsStoreItemSheet(item: item, actions: actions, model: model)
        }
        .sheet(isPresented: $showUpload) {
            ToolsStoreUploadSheet(initialCategory: model.category)
        }
        .onAppear {
            actions.vm = vm
            if !loadedOnce { loadedOnce = true; model.reload() }
        }
        .onChange(of: model.category) { _, _ in model.reload() }
        .onChange(of: model.query) { _, q in if q.isEmpty { model.reload() } }
        .accessibilityIdentifier("tools-store-root")
    }

    private func header(_ t: SourcesTheme) -> some View {
        HStack(alignment: .bottom, spacing: 8) {
            VStack(alignment: .leading, spacing: 0) {
                Text(ToolsStoreText.subtitle).font(.system(size: 12, weight: .medium)).foregroundStyle(t.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(ToolsStoreText.title).font(.system(size: 28, weight: .heavy, design: .rounded)).foregroundStyle(t.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .layoutPriority(1)
            Spacer(minLength: 4)
            SourcesThemeMenu()
            Button { withAnimation(.easeInOut(duration: 0.2)) { showSaved.toggle() } } label: {
                SourcesCircleLabel(systemName: showSaved ? "bookmark.fill" : "bookmark", theme: t)
            }
            .buttonStyle(.mirsaPress)
            .accessibilityLabel(ToolsStoreText.saved)
            .accessibilityIdentifier("tools-store-saved")
            Button { showUpload = true } label: {
                SourcesCircleLabel(systemName: "arrow.up", theme: t, filled: true)
            }
            .buttonStyle(.mirsaPress)
            .accessibilityLabel(ToolsStoreText.upload)
            .accessibilityIdentifier("tools-store-upload")
        }
        .padding(.top, 6)
    }

    private func reviewBanner(_ t: SourcesTheme) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(t.accentGradient)
            VStack(alignment: .leading, spacing: 2) {
                Text(ToolsStoreText.reviewTitle).font(.system(size: 13, weight: .bold)).foregroundStyle(t.text)
                Text(ToolsStoreText.reviewBanner).font(.system(size: 12)).foregroundStyle(t.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(LinearGradient(colors: [t.accent[0].opacity(t.isLight ? 0.12 : 0.28), t.accent[1].opacity(t.isLight ? 0.06 : 0.12)],
                                 startPoint: .topLeading, endPoint: .bottomTrailing)))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(t.stroke))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("tools-store-review-banner")
    }

    private func categoryBar(_ t: SourcesTheme) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                ForEach(ToolsStoreCategory.allCases) { c in
                    let selected = !showSaved && model.category == c
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { showSaved = false; model.category = c }
                    } label: {
                        Label(c.title, systemImage: c.icon)
                            .font(.system(size: 13, weight: .bold))
                            .fixedSize(horizontal: true, vertical: true)
                            .foregroundStyle(selected ? Color.white : t.text)
                            .padding(.horizontal, 13).padding(.vertical, 8)
                            .background {
                                if selected { Capsule().fill(t.accentGradient) }
                                else { Capsule().fill(t.card).overlay(Capsule().stroke(t.stroke)) }
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                    .accessibilityIdentifier("tools-store-cat-" + c.rawValue)
                }
            }
            .padding(.vertical, 2)
        }
    }

    @ViewBuilder
    private func catalogue(_ t: SourcesTheme) -> some View {
        switch model.phase {
        case .idle, .loading:
            HStack { Spacer(); ProgressView().tint(t.text); Spacer() }.padding(.vertical, 40)
        case .failed(let message):
            unavailableCard(t, message: message)
        case .loaded:
            if model.top.isEmpty && model.newest.isEmpty {
                emptyCard(t, ToolsStoreText.empty)
            } else {
                if !model.top.isEmpty {
                    sectionTitle(ToolsStoreText.mostDownloaded, icon: "flame.fill", t: t)
                    carousel(model.top, t: t)
                }
                let rated = model.topRated
                if !rated.isEmpty {
                    sectionTitle(ToolsStoreText.topRated, icon: "star.fill", t: t)
                    carousel(rated, t: t)
                }
                if !model.newest.isEmpty {
                    sectionTitle(ToolsStoreText.newest, icon: "sparkles", t: t)
                    LazyVStack(spacing: 10) {
                        ForEach(model.newest) { item in
                            ToolsStoreItemRow(item: item, actions: actions, theme: t) { selected = item }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func savedSection(_ t: SourcesTheme) -> some View {
        if saved.items.isEmpty {
            emptyCard(t, ToolsStoreText.emptySaved)
        } else {
            sectionTitle(ToolsStoreText.saved, icon: "bookmark.fill", t: t)
            LazyVStack(spacing: 10) {
                ForEach(saved.items) { item in
                    ToolsStoreItemRow(item: item, actions: actions, theme: t) { selected = item }
                }
            }
        }
    }

    private func sectionTitle(_ title: String, icon: String, t: SourcesTheme) -> some View {
        Label(title, systemImage: icon)
            .font(.system(size: 18, weight: .bold))
            .foregroundStyle(t.text)
            .padding(.top, 4)
            .accessibilityAddTraits(.isHeader)
    }

    private func carousel(_ items: [ToolsStoreItem], t: SourcesTheme) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .top, spacing: 10) {
                ForEach(items) { item in
                    ToolsStoreCard(item: item, theme: t) { selected = item }
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func unavailableCard(_ t: SourcesTheme, message: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "bag.badge.questionmark").font(.system(size: 34)).foregroundStyle(t.accentGradient)
            Text(ToolsStoreText.unavailableTitle).font(.headline).foregroundStyle(t.text)
            Text(message).font(.subheadline).foregroundStyle(t.secondary).multilineTextAlignment(.center)
            if model.isConfigured {
                Button(ToolsStoreText.retry) { model.reload() }
                    .font(.subheadline.weight(.bold))
                    .buttonStyle(.mirsaPress)
                    .foregroundStyle(t.accent[0])
            }
        }
        .frame(maxWidth: .infinity)
        .padding(22)
        .sourcesGlass(t, radius: 22)
        .accessibilityIdentifier("tools-store-unavailable")
    }

    private func emptyCard(_ t: SourcesTheme, _ text: String) -> some View {
        Text(text).font(.subheadline).foregroundStyle(t.secondary)
            .frame(maxWidth: .infinity).padding(22)
            .sourcesGlass(t, radius: 22)
            .accessibilityIdentifier("tools-store-empty")
    }
}

// MARK: - Pieces

/// Read-only star display (supports halves).
struct ToolsStoreStars: View {
    let value: Double
    var size: CGFloat = 11
    var body: some View {
        HStack(spacing: 1) {
            ForEach(1...5, id: \.self) { i in
                let v = value - Double(i - 1)
                Image(systemName: v >= 0.75 ? "star.fill" : (v >= 0.25 ? "star.leadinghalf.filled" : "star"))
                    .font(.system(size: size, weight: .semibold))
                    .foregroundStyle(Color(sourcesRGB: 0xFBBF24))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(format: "%.1f / 5", value))
    }
}

private struct ToolsStorePreview: View {
    let item: ToolsStoreItem
    let theme: SourcesTheme
    let size: CGFloat
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                .fill(LinearGradient(colors: theme.accent.map { $0.opacity(0.85) }, startPoint: .topLeading, endPoint: .bottomTrailing))
            Image(systemName: item.kind?.icon ?? "shippingbox.fill")
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(.white)
            if let url = item.preview {
                AsyncImage(url: url) { phase in
                    if let image = phase.image { image.resizable().scaledToFill() } else { Color.clear }
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
        .accessibilityHidden(true)
    }
}

private struct ToolsStoreCard: View {
    let item: ToolsStoreItem
    let theme: SourcesTheme
    let open: () -> Void
    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 6) {
                ToolsStorePreview(item: item, theme: theme, size: 64)
                Text(item.title).font(.system(size: 14, weight: .bold)).foregroundStyle(theme.text)
                    .fixedSize(horizontal: false, vertical: true)
                if let target = item.targetTitle {
                    Text(ToolsStoreText.forApp + " " + target).font(.system(size: 11)).foregroundStyle(theme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 4) {
                    ToolsStoreStars(value: item.ratingAvg, size: 9)
                    if item.ratingCount > 0 {
                        Text(item.ratingCount.formatted()).font(.system(size: 10)).foregroundStyle(theme.secondary)
                    }
                }
                Label(item.downloads.formatted(), systemImage: "arrow.down.circle")
                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(theme.secondary)
            }
            .frame(width: 132, alignment: .leading)
            .padding(12)
            .sourcesGlass(theme, radius: 20)
        }
        .buttonStyle(.mirsaPress)
        .accessibilityIdentifier("tools-store-card-" + item.id)
    }
}

/// One item with its actions. Every item has Download and Save; wallpapers add Apply, tweaks add Inject.
private struct ToolsStoreItemRow: View {
    let item: ToolsStoreItem
    @ObservedObject var actions: ToolsStoreActions
    let theme: SourcesTheme
    let open: () -> Void
    @ObservedObject private var saved = ToolsStoreSaved.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: open) {
                HStack(spacing: 12) {
                    ToolsStorePreview(item: item, theme: theme, size: 54)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.title).font(.system(size: 15.5, weight: .bold)).foregroundStyle(theme.text)
                            .fixedSize(horizontal: false, vertical: true)
                        let meta = [item.targetTitle.map { ToolsStoreText.forApp + " " + $0 },
                                    item.version.flatMap { $0.isEmpty ? nil : "v" + $0 },
                                    item.authorName.flatMap { $0.isEmpty ? nil : ToolsStoreText.by + " " + $0 }]
                            .compactMap { $0 }.joined(separator: " · ")
                        if !meta.isEmpty {
                            Text(meta).font(.system(size: 12)).foregroundStyle(theme.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        HStack(spacing: 6) {
                            ToolsStoreStars(value: item.ratingAvg)
                            Text(item.ratingCount.formatted()).font(.system(size: 11)).foregroundStyle(theme.secondary)
                            Label(item.downloads.formatted(), systemImage: "arrow.down.circle")
                                .font(.system(size: 11, weight: .semibold)).foregroundStyle(theme.secondary)
                                .labelStyle(.titleAndIcon)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            ToolsStoreActionBar(item: item, actions: actions, theme: theme)
        }
        .padding(12)
        .sourcesGlass(theme, radius: 20)
        .accessibilityIdentifier("tools-store-item-" + item.id)
    }
}

private struct ToolsStoreActionBar: View {
    let item: ToolsStoreItem
    @ObservedObject var actions: ToolsStoreActions
    let theme: SourcesTheme
    @ObservedObject private var saved = ToolsStoreSaved.shared

    var body: some View {
        let busy = actions.isBusy(item)
        let locked = actions.busyID != nil
        HStack(spacing: 8) {
            if busy {
                ProgressView().tint(theme.text).frame(maxWidth: .infinity, minHeight: 36)
            } else {
                switch item.kind {
                case .wallpapers?:
                    primary(ToolsStoreText.apply, icon: "paintbrush.pointed.fill") { actions.apply(item) }
                    secondary(ToolsStoreText.download, icon: "arrow.down.to.line") { actions.download(item) }
                case .tweaks?, .appTweaks?:
                    primary(ToolsStoreText.inject, icon: "syringe.fill") { actions.inject(item) }
                    secondary(ToolsStoreText.download, icon: "arrow.down.to.line") { actions.download(item) }
                default:
                    primary(ToolsStoreText.download, icon: "arrow.down.to.line") { actions.download(item) }
                }
            }
            Button { saved.toggle(item) } label: {
                Image(systemName: saved.isSaved(item.id) ? "bookmark.fill" : "bookmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(saved.isSaved(item.id) ? theme.accent[0] : theme.text)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(theme.card).overlay(Circle().stroke(theme.stroke)))
            }
            .buttonStyle(.mirsaPress)
            .accessibilityLabel(saved.isSaved(item.id) ? ToolsStoreText.unsave : ToolsStoreText.save)
            .accessibilityIdentifier("tools-store-save-" + item.id)
        }
        .disabled(locked && !busy)
    }

    private func primary(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, minHeight: 36)
                .background(Capsule().fill(theme.accentGradient))
                .shadow(color: theme.accent[0].opacity(0.35), radius: 8, y: 4)
        }
        .buttonStyle(.mirsaPress)
    }

    private func secondary(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(theme.text)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, minHeight: 36)
                .background(Capsule().fill(theme.card).overlay(Capsule().stroke(theme.stroke)))
        }
        .buttonStyle(.mirsaPress)
    }
}

// MARK: - Item sheet (details + rating)

private struct ToolsStoreItemSheet: View {
    @State var item: ToolsStoreItem
    @ObservedObject var actions: ToolsStoreActions
    @ObservedObject var model: ToolsStoreModel
    @State private var rating: Int?
    @State private var rateError: String?
    @State private var ratingBusy = false
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SourcesTheme.key) private var themeRaw = SourcesTheme.aurora.rawValue
    private var theme: SourcesTheme { SourcesTheme(rawValue: themeRaw) ?? .aurora }

    var body: some View {
        let t = theme
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 14) {
                    ToolsStorePreview(item: item, theme: t, size: 84)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.title).font(.system(size: 22, weight: .bold)).foregroundStyle(t.text)
                            .fixedSize(horizontal: false, vertical: true)
                        if let c = item.kind { Label(c.title, systemImage: c.icon).font(.system(size: 12)).foregroundStyle(t.secondary) }
                        if let target = item.targetTitle {
                            Text(ToolsStoreText.forApp + " " + target).font(.system(size: 12)).foregroundStyle(t.secondary)
                        }
                        if let author = item.authorName, !author.isEmpty {
                            Text(ToolsStoreText.by + " " + author).font(.system(size: 12)).foregroundStyle(t.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").font(.system(size: 14, weight: .bold)).foregroundStyle(t.text)
                            .frame(width: 34, height: 34).background(Circle().fill(t.card))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(ToolsStoreText.close)
                }

                HStack(spacing: 0) {
                    infoCell(String(format: "%.1f", item.ratingAvg), item.ratingCount.formatted() + " " + ToolsStoreText.ratings, t)
                    Rectangle().fill(t.stroke).frame(width: 1, height: 34)
                    infoCell(item.downloads.formatted(), ToolsStoreText.downloads, t)
                    if let v = item.version, !v.isEmpty {
                        Rectangle().fill(t.stroke).frame(width: 1, height: 34)
                        infoCell(v, SourcesText.version, t)
                    }
                    if let s = item.fileSize, s > 0 {
                        Rectangle().fill(t.stroke).frame(width: 1, height: 34)
                        infoCell(ByteCountFormatter.string(fromByteCount: s, countStyle: .file), SourcesText.size, t)
                    }
                }
                .padding(.vertical, 8)
                .overlay(alignment: .top) { Rectangle().fill(t.stroke).frame(height: 1) }
                .overlay(alignment: .bottom) { Rectangle().fill(t.stroke).frame(height: 1) }

                ToolsStoreActionBar(item: item, actions: actions, theme: t)

                if item.kind == .fonts {
                    Text(ToolsStoreText.fontHint).font(.footnote).foregroundStyle(t.secondary).fixedSize(horizontal: false, vertical: true)
                } else if item.kind == .sounds {
                    Text(ToolsStoreText.soundHint).font(.footnote).foregroundStyle(t.secondary).fixedSize(horizontal: false, vertical: true)
                }

                if let url = item.preview {
                    AsyncImage(url: url) { phase in
                        if let image = phase.image { image.resizable().scaledToFit() }
                        else { RoundedRectangle(cornerRadius: 18).fill(t.card).frame(height: 160).overlay(ProgressView()) }
                    }
                    .frame(maxWidth: .infinity, maxHeight: 360)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }

                if let d = item.description?.trimmingCharacters(in: .whitespacesAndNewlines), !d.isEmpty {
                    Text(SourcesText.about).font(.system(size: 18, weight: .bold)).foregroundStyle(t.text)
                    Text(d).font(.system(size: 14)).foregroundStyle(t.text.opacity(0.88)).fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(ToolsStoreText.yourRating).font(.system(size: 18, weight: .bold)).foregroundStyle(t.text)
                    HStack(spacing: 10) {
                        ForEach(1...5, id: \.self) { star in
                            Button { rate(star) } label: {
                                Image(systemName: (rating ?? 0) >= star ? "star.fill" : "star")
                                    .font(.system(size: 28, weight: .semibold))
                                    .foregroundStyle(Color(sourcesRGB: 0xFBBF24))
                            }
                            .buttonStyle(.mirsaPress)
                            .disabled(ratingBusy || item.status.map { $0 != "approved" } ?? false)
                            .accessibilityLabel("\(star)")
                            .accessibilityIdentifier("tools-store-rate-\(star)")
                        }
                        if ratingBusy { ProgressView().tint(t.text) }
                    }
                    Text(rateError ?? ToolsStoreText.rateThis).font(.footnote)
                        .foregroundStyle(rateError == nil ? t.secondary : Color.orange)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .sourcesGlass(t, radius: 18)
            }
            .padding(.horizontal, 18).padding(.top, 24).padding(.bottom, 30)
        }
        .background(LinearGradient(colors: t.sheetBase, startPoint: .top, endPoint: .bottom).ignoresSafeArea())
        .tint(t.accent[0])
        .environment(\.colorScheme, t.colorScheme)
        .modifier(ToolsStorePresenters(host: "sheet", actions: actions, respring: actions.respring))
        .presentationDetents([.large, .medium])
        .presentationDragIndicator(.visible)
        .onAppear {
            rating = item.myRating
            actions.activeHost = "sheet"
        }
        .onDisappear { actions.activeHost = "main" }
    }

    private func infoCell(_ value: String, _ label: String, _ t: SourcesTheme) -> some View {
        VStack(spacing: 3) {
            Text(value).font(.system(size: 15, weight: .bold)).foregroundStyle(t.text).lineLimit(1).minimumScaleFactor(0.6)
            Text(label).font(.system(size: 10)).foregroundStyle(t.secondary).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }

    private func rate(_ stars: Int) {
        guard !ratingBusy else { return }
        ratingBusy = true
        rateError = nil
        let previous = rating
        rating = stars
        Task { @MainActor in
            defer { ratingBusy = false }
            do {
                let result = try await ToolsStoreClient.rate(item.id, stars: stars)
                var updated = item
                updated.ratingAvg = result.ratingAvg
                updated.ratingCount = result.ratingCount
                updated.myRating = result.myRating ?? stars
                item = updated
                model.update(updated)
            } catch {
                rating = previous
                rateError = error.localizedDescription
            }
        }
    }
}

// MARK: - Upload

private struct ToolsStoreUploadSheet: View {
    @State private var category: ToolsStoreCategory
    @State private var title = ""
    @State private var details = ""
    @State private var version = ""
    @State private var author = ""
    @State private var target: ToolsStoreTargetApp = .youtube
    @State private var customBundle = ""
    @State private var file: URL?
    @State private var picking = false
    @State private var confirmed = false
    @State private var uploading = false
    @State private var progress: Double = 0
    @State private var result: String?
    @State private var failure: String?
    @State private var mine: [ToolsStoreItem] = []
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SourcesTheme.key) private var themeRaw = SourcesTheme.aurora.rawValue
    private var theme: SourcesTheme { SourcesTheme(rawValue: themeRaw) ?? .aurora }

    init(initialCategory: ToolsStoreCategory) {
        _category = State(initialValue: initialCategory)
    }

    private var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var targetValue: String? {
        guard category == .appTweaks else { return nil }
        if target == .other {
            let b = customBundle.trimmingCharacters(in: .whitespacesAndNewlines)
            return b.isEmpty ? nil : b
        }
        return target.rawValue
    }
    private var canSubmit: Bool {
        ToolsStoreConfig.isConfigured && !uploading && confirmed && file != nil && trimmedTitle.count >= 2
            && (category != .appTweaks || targetValue != nil)
    }

    var body: some View {
        let t = theme
        NavigationStack {
            Form {
                Section {
                    Label {
                        Text(ToolsStoreText.reviewBanner).font(.footnote).fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "checkmark.shield.fill").foregroundStyle(t.accentGradient)
                    }
                    .accessibilityIdentifier("tools-store-upload-review-notice")
                    if !ToolsStoreConfig.isConfigured {
                        Text(ToolsStoreText.notConfigured).font(.footnote).foregroundStyle(.orange)
                    }
                }
                Section {
                    Picker(ToolsStoreText.category, selection: $category) {
                        ForEach(ToolsStoreCategory.allCases) { c in Label(c.title, systemImage: c.icon).tag(c) }
                    }
                    TextField(ToolsStoreText.itemTitle, text: $title)
                    TextField(ToolsStoreText.itemDescription, text: $details, axis: .vertical).lineLimit(3...8)
                    TextField(ToolsStoreText.itemVersion, text: $version)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    TextField(ToolsStoreText.authorName, text: $author)
                    if category == .appTweaks {
                        Picker(ToolsStoreText.targetApp, selection: $target) {
                            ForEach(ToolsStoreTargetApp.allCases) { a in Text(a.title).tag(a) }
                        }
                        if target == .other {
                            TextField(ToolsStoreText.bundleID, text: $customBundle)
                                .textInputAutocapitalization(.never).autocorrectionDisabled()
                        }
                    }
                }
                Section {
                    Button { picking = true } label: {
                        Label(file?.lastPathComponent ?? ToolsStoreText.chooseFile, systemImage: "doc.badge.plus")
                    }
                    Text(ToolsStoreText.allowedTypes + ": " + category.allowedExtensions.sorted().map { "." + $0 }.joined(separator: ", "))
                        .font(.caption).foregroundStyle(.secondary)
                    Toggle(ToolsStoreText.confirmRights, isOn: $confirmed).font(.footnote)
                }
                Section {
                    Button {
                        submit()
                    } label: {
                        HStack {
                            Spacer()
                            if uploading {
                                ProgressView(value: progress).frame(width: 120)
                                Text(ToolsStoreText.uploading)
                            } else {
                                Label(ToolsStoreText.submit, systemImage: "paperplane.fill").font(.headline)
                            }
                            Spacer()
                        }
                    }
                    .disabled(!canSubmit)
                    .accessibilityIdentifier("tools-store-upload-submit")
                    if let result { Text(result).font(.footnote).foregroundStyle(t.success) }
                    if let failure { Text(failure).font(.footnote).foregroundStyle(.orange) }
                }
                if !mine.isEmpty {
                    Section(ToolsStoreText.myUploads) {
                        ForEach(mine) { item in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.title).font(.subheadline.weight(.semibold))
                                    if let note = item.reviewNote, !note.isEmpty {
                                        Text(note).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                Text(statusTitle(item.status)).font(.caption.weight(.bold))
                                    .foregroundStyle(statusColor(item.status))
                            }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(LinearGradient(colors: t.sheetBase, startPoint: .top, endPoint: .bottom).ignoresSafeArea())
            .navigationTitle(ToolsStoreText.uploadTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(ToolsStoreText.close) { dismiss() }.disabled(uploading)
                }
            }
            .fileImporter(isPresented: $picking, allowedContentTypes: [.item], allowsMultipleSelection: false) { picked in
                failure = nil
                switch picked {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    if category.allowedExtensions.contains(url.pathExtension.lowercased()) { file = url }
                    else { file = nil; failure = ToolsStoreError.badFile.localizedDescription }
                case .failure(let error):
                    failure = error.localizedDescription
                }
            }
            .onChange(of: category) { _, c in
                if let f = file, !c.allowedExtensions.contains(f.pathExtension.lowercased()) { file = nil }
            }
            .task { await loadMine() }
        }
        .tint(t.accent[0])
        .environment(\.colorScheme, t.colorScheme)
        .interactiveDismissDisabled(uploading)
    }

    private func statusTitle(_ s: String?) -> String {
        switch s {
        case "approved": return ToolsStoreText.statusApproved
        case "held": return ToolsStoreText.statusHeld
        case "rejected": return ToolsStoreText.statusRejected
        case "uploading": return ToolsStoreText.statusUploading
        default: return ToolsStoreText.statusPending
        }
    }

    private func statusColor(_ s: String?) -> Color {
        switch s {
        case "approved": return .green
        case "held", "rejected": return .red
        default: return .orange
        }
    }

    private func loadMine() async {
        guard ToolsStoreConfig.isConfigured else { return }
        mine = (try? await ToolsStoreClient.myUploads()) ?? []
    }

    /// Copies the picked file into a private temporary folder first, so the upload never depends on a
    /// security-scoped URL staying open.
    private func submit() {
        guard canSubmit, let picked = file else { return }
        uploading = true; progress = 0; result = nil; failure = nil
        let draftCategory = category, draftTitle = trimmedTitle, draftDetails = details, draftVersion = version
        let draftAuthor = author, draftTarget = targetValue
        Task { @MainActor in
            defer { uploading = false }
            var folder: URL?
            do {
                let dir = try MirsaManagedTmp.begin("tools-upload")
                folder = dir
                let local = dir.appendingPathComponent(ToolsStoreClient.safeFileName(picked.lastPathComponent, fallbackExtension: picked.pathExtension.lowercased()))
                let scoped = picked.startAccessingSecurityScopedResource()
                defer { if scoped { picked.stopAccessingSecurityScopedResource() } }
                try FileManager.default.copyItem(at: picked, to: local)
                let draft = ToolsStoreClient.UploadDraft(category: draftCategory, title: draftTitle, description: draftDetails,
                                                         version: draftVersion, targetApp: draftTarget, authorName: draftAuthor, file: local)
                try await ToolsStoreClient.upload(draft) { value in
                    Task { @MainActor in progress = value }
                }
                result = ToolsStoreText.submitted
                title = ""; details = ""; version = ""; file = nil; confirmed = false
                await loadMine()
            } catch {
                failure = error.localizedDescription
            }
            if let folder { MirsaManagedTmp.end(folder) }
        }
    }
}
