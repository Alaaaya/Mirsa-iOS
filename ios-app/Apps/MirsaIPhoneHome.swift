import SwiftUI
import PhotosUI

// Mirsa 2.1: optional "iPhone" home screen style, modelled 1:1 on the iOS Home Screen.
// 4-column grid with labels, page swipe, «Search» pill above a glass dock of 4, iOS-style
// long-press menu, jiggle edit mode with Done / + (install IPA, install from link, choose wallpaper).
// Original implementation; no Apple artwork or third-party code. Left-to-right like the rest of Mirsa.

enum MirsaIPhoneText {
    static var search: String { tr("Search", "بحث", ckb: "گەڕان", kmr: "Lêgerîn") }
    static var settings: String { tr("Settings", "الإعدادات", ckb: "ڕێکخستنەکان", kmr: "Mîheng") }
    static var downloads: String { tr("Downloads", "التنزيلات", ckb: "داگرتنەکان", kmr: "Daxistin") }
    static var editHome: String { tr("Edit Home Screen", "تعديل الشاشة الرئيسية", ckb: "دەستکاریی شاشەی سەرەکی", kmr: "Ekrana sereke biguherîne") }
    static var installIPA: String { tr("Install IPA file", "ثبّت ملفّ IPA", ckb: "فایلی IPA دابمەزرێنە", kmr: "Pelê IPA saz bike") }
    static var installLink: String { tr("Install from link", "ثبّت من رابط", ckb: "لە بەستەرەوە دابمەزرێنە", kmr: "Ji girêdanê saz bike") }
    static var chooseWallpaper: String { tr("Choose Wallpaper", "اختار خلفية", ckb: "وێنەی پاشبنەما هەڵبژێرە", kmr: "Wêneyê paşxanê hilbijêre") }
    static var resetWallpaper: String { tr("Default Wallpaper", "الخلفية الافتراضية", ckb: "پاشبنەمای بنەڕەت", kmr: "Paşxana standard") }
    static var addToDock: String { tr("Add to Dock", "ضيف عالدوك", ckb: "زیادکردن بۆ دۆک", kmr: "Li dockê zêde bike") }
    static var removeFromDock: String { tr("Remove from Dock", "شيل من الدوك", ckb: "لابردن لە دۆک", kmr: "Ji dockê rake") }
    static var done: String { tr("Done", "تم", ckb: "تەواو", kmr: "Temam") }
    static var noResults: String { tr("No Results", "ما في نتائج", ckb: "هیچ ئەنجامێک نییە", kmr: "Encam tune") }
    static var empty: String { tr("Tap + to install your first app", "اكبس + لتثبّت أول تطبيق", ckb: "+ دابگرە بۆ دامەزراندنی یەکەم ئەپ", kmr: "Ji bo sepana yekem + bitikîne") }
}

/// The two built-in tiles that behave like apps on this screen.
private enum MirsaIPhoneSystem {
    static let settings = "mirsa.system.settings"
    static let downloads = "mirsa.system.downloads"
    static let all = [settings, downloads]
}

struct MirsaIPhoneHome<Menu: View>: View {
    let apps: [ManagedApp]
    let allAppIDs: [String]
    let onLaunch: (ManagedApp) -> Void
    let onSettings: () -> Void
    let onImport: () -> Void
    let onImportLink: () -> Void
    let onDownloads: () -> Void
    @ViewBuilder let menu: (ManagedApp) -> Menu

    @AppStorage("mirsa.iphone.order") private var orderRaw = "[]"
    @AppStorage("mirsa.iphone.dock") private var dockRaw = ""
    @AppStorage("mirsa.iphone.wallpaperStamp") private var wallpaperStamp: Double = 0
    @ObservedObject private var sources = SourcesStore.shared
    @State private var page = 0
    @State private var editing = false
    @State private var jiggle = false
    @State private var searching = false
    @State private var query = ""
    @State private var showDots = false
    @State private var dotsTask: Task<Void, Never>?
    @State private var photo: PhotosPickerItem?
    @State private var pickingPhoto = false
    @State private var wallpaper: UIImage?
    @FocusState private var searchFocused: Bool

    // MARK: layout state
    private static func decode(_ raw: String) -> [String] { (try? JSONDecoder().decode([String].self, from: Data(raw.utf8))) ?? [] }
    private static func encode(_ ids: [String]) -> String { (try? JSONEncoder().encode(ids)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]" }
    private var known: Set<String> { Set(apps.map(\.id) + MirsaIPhoneSystem.all) }
    /// First launch: Settings in the dock, like the stock iPhone dock holds a system app.
    private var dockIDs: [String] {
        let ids = dockRaw.isEmpty ? [MirsaIPhoneSystem.settings] : Self.decode(dockRaw)
        return Array(ids.filter { known.contains($0) }.prefix(4))
    }
    private var gridIDs: [String] {
        let dock = Set(dockIDs)
        var order = Self.decode(orderRaw).filter { known.contains($0) && !dock.contains($0) }
        let rest = (apps.map(\.id) + MirsaIPhoneSystem.all).filter { !dock.contains($0) && !order.contains($0) }
        order.append(contentsOf: rest)
        return order
    }
    private func setDock(_ ids: [String]) { withAnimation(.easeInOut(duration: 0.2)) { dockRaw = Self.encode(ids) } }
    private func setOrder(_ ids: [String]) { withAnimation(.easeInOut(duration: 0.2)) { orderRaw = Self.encode(ids) } }
    private func app(_ id: String) -> ManagedApp? { apps.first { $0.id == id } }
    private var updateIDs: Set<String> { Set(sources.availableUpdates().map(\.0.bundleID)) }

    private func label(_ id: String) -> String {
        switch id {
        case MirsaIPhoneSystem.settings: return MirsaIPhoneText.settings
        case MirsaIPhoneSystem.downloads: return MirsaIPhoneText.downloads
        default: return app(id)?.name ?? ""
        }
    }
    private func open(_ id: String) {
        guard !editing else { return }
        switch id {
        case MirsaIPhoneSystem.settings: onSettings()
        case MirsaIPhoneSystem.downloads: onDownloads()
        default: if let a = app(id) { onLaunch(a) }
        }
    }
    private func startEditing() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        withAnimation(.easeOut(duration: 0.2)) { editing = true }
        jiggle = false
        DispatchQueue.main.async { jiggle = true }
    }
    /// Drop `dragged` onto `target`: reorder within the grid or the dock, or move between them.
    private func move(_ dragged: String, before target: String) {
        guard dragged != target else { return }
        var dock = dockIDs, grid = gridIDs
        let toDock = dock.contains(target)
        dock.removeAll { $0 == dragged }; grid.removeAll { $0 == dragged }
        if toDock {
            guard dock.count < 4 else { return }
            dock.insert(dragged, at: dock.firstIndex(of: target) ?? dock.count)
        } else {
            grid.insert(dragged, at: grid.firstIndex(of: target) ?? grid.count)
        }
        setDock(dock); setOrder(grid)
    }
    private func appendToDock(_ id: String) {
        var dock = dockIDs.filter { $0 != id }
        guard dock.count < 4 else { return }
        dock.append(id); setDock(dock); setOrder(gridIDs.filter { $0 != id })
    }
    private func removeFromDock(_ id: String) {
        setDock(dockIDs.filter { $0 != id })
        var grid = gridIDs.filter { $0 != id }; grid.append(id); setOrder(grid)
    }

    // MARK: wallpaper
    private static var wallpaperURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("mirsa-home-wallpaper.jpg")
    }
    private func loadWallpaper() {
        wallpaper = wallpaperStamp > 0 ? UIImage(contentsOfFile: Self.wallpaperURL.path) : nil
    }
    private func saveWallpaper(_ item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else { return }
        let maxSide: CGFloat = 2400
        let scale = min(1, maxSide / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let resized = UIGraphicsImageRenderer(size: size).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        guard let jpeg = resized.jpegData(compressionQuality: 0.88) else { return }
        try? FileManager.default.createDirectory(at: Self.wallpaperURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? jpeg.write(to: Self.wallpaperURL, options: .atomic)
        await MainActor.run { wallpaperStamp = Date().timeIntervalSince1970; loadWallpaper() }
    }

    // MARK: body
    var body: some View {
        GeometryReader { geo in
            let iconSide: CGFloat = min(64, (geo.size.width - 2 * 26 - 3 * 24) / 4)
            let rowHeight = iconSide + 34
            let gridHeight = max(rowHeight, geo.size.height - 44 - 12 - 48 - 108)
            let rows = max(1, Int(gridHeight / (rowHeight + 12)))
            let capacity = rows * 4
            let ids = gridIDs
            let pages = max(1, (ids.count + capacity - 1) / capacity)
            VStack(spacing: 0) {
                topBar.frame(height: 44)
                TabView(selection: $page) {
                    ForEach(0..<pages, id: \.self) { p in
                        VStack(spacing: 0) {
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 12) {
                                ForEach(Array(ids.dropFirst(p * capacity).prefix(capacity)), id: \.self) { id in
                                    tile(id, side: iconSide, showLabel: true)
                                }
                            }
                            .padding(.horizontal, 26)
                            // Room for the red badge on the first row: TabView pages clip their content.
                            .padding(.top, 12)
                            if apps.isEmpty && p == 0 {
                                Text(MirsaIPhoneText.empty).font(.footnote.weight(.medium)).foregroundStyle(.white.opacity(0.85))
                                    .shadow(color: .black.opacity(0.4), radius: 3).padding(.top, 28)
                            }
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                        .onLongPressGesture(minimumDuration: 0.6) { if !editing { startEditing() } }
                        .tag(p)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .onChange(of: page) { _, _ in flashDots() }
                .onChange(of: pages) { _, n in page = min(page, n - 1) }
                pageIndicator(pages: pages).frame(height: 48)
                dock(side: iconSide).padding(.horizontal, 10).padding(.bottom, 6)
            }
        }
        .background { background.ignoresSafeArea() }
        .overlay { if searching { searchOverlay.transition(.opacity) } }
        .photosPicker(isPresented: $pickingPhoto, selection: $photo, matching: .images)
        .onChange(of: photo) { _, item in if let item { Task { await saveWallpaper(item) } } }
        .onAppear(perform: loadWallpaper)
        .onDisappear { dotsTask?.cancel() }
        .foregroundStyle(.white)
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityIdentifier("mirsa-iphone-home")
    }

    @ViewBuilder private var background: some View {
        if let wallpaper {
            GeometryReader { g in Image(uiImage: wallpaper).resizable().scaledToFill().frame(width: g.size.width, height: g.size.height).clipped() }
        } else {
            AuroraBackground()
        }
    }

    /// Edit mode only, as on iPhone: Done on one side, + on the other.
    @ViewBuilder private var topBar: some View {
        HStack {
            if editing {
                Button { withAnimation(.easeOut(duration: 0.2)) { editing = false } } label: {
                    Image(systemName: "checkmark").font(.system(size: 17, weight: .bold)).frame(width: 64, height: 30)
                        .background(.ultraThinMaterial, in: Capsule())
                }
                .accessibilityLabel(MirsaIPhoneText.done)
                .accessibilityIdentifier("iphone-home-done")
                Spacer()
                SwiftUI.Menu {
                    Button(action: onImport) { Label(MirsaIPhoneText.installIPA, systemImage: "doc.badge.plus") }
                    Button(action: onImportLink) { Label(MirsaIPhoneText.installLink, systemImage: "link.badge.plus") }
                    Divider()
                    Button { pickingPhoto = true } label: { Label(MirsaIPhoneText.chooseWallpaper, systemImage: "camera.macro") }
                    if wallpaperStamp > 0 {
                        Button { try? FileManager.default.removeItem(at: Self.wallpaperURL); wallpaperStamp = 0; loadWallpaper() } label: {
                            Label(MirsaIPhoneText.resetWallpaper, systemImage: "arrow.uturn.backward")
                        }
                    }
                } label: {
                    Image(systemName: "plus").font(.system(size: 17, weight: .bold)).frame(width: 64, height: 30)
                        .background(.ultraThinMaterial, in: Capsule())
                }
                .accessibilityLabel(L.t("empty.import"))
                .accessibilityIdentifier("iphone-home-add")
            } else {
                Spacer()
            }
        }
        .padding(.horizontal, 26)
        .transition(.opacity)
    }

    /// iOS shows the «Search» pill, and page dots while you swipe between pages.
    @ViewBuilder private func pageIndicator(pages: Int) -> some View {
        if pages > 1 && (showDots || editing) {
            HStack(spacing: 9) {
                ForEach(0..<pages, id: \.self) { i in
                    Circle().fill(.white.opacity(i == page ? 1 : 0.4)).frame(width: 7, height: 7)
                        .onTapGesture { withAnimation { page = i } }
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(.ultraThinMaterial.opacity(0.6), in: Capsule())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(MirsaTr.f("page", page + 1))
        } else {
            Button { query = ""; withAnimation(.easeOut(duration: 0.2)) { searching = true }; DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { searchFocused = true } } label: {
                HStack(spacing: 5) {
                    Image(systemName: "magnifyingglass").font(.system(size: 13, weight: .semibold))
                    Text(MirsaIPhoneText.search).font(.system(size: 15, weight: .medium))
                }
                .padding(.horizontal, 14).padding(.vertical, 7)
                .background(.ultraThinMaterial.opacity(0.8), in: Capsule())
                .overlay(Capsule().stroke(.white.opacity(0.18), lineWidth: 0.5))
            }
            .buttonStyle(.plain)
            .disabled(editing)
            .accessibilityIdentifier("iphone-home-search")
        }
    }
    private func flashDots() {
        dotsTask?.cancel()
        withAnimation(.easeOut(duration: 0.15)) { showDots = true }
        dotsTask = Task {
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            if !Task.isCancelled { await MainActor.run { withAnimation(.easeOut(duration: 0.3)) { showDots = false } } }
        }
    }

    private func dock(side: CGFloat) -> some View {
        HStack(spacing: 0) {
            ForEach(dockIDs, id: \.self) { id in tile(id, side: side, showLabel: false).frame(maxWidth: .infinity) }
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, minHeight: side + 32)
        .background(RoundedRectangle(cornerRadius: 38, style: .continuous).fill(.ultraThinMaterial.opacity(0.85)))
        .overlay(RoundedRectangle(cornerRadius: 38, style: .continuous).stroke(.white.opacity(0.16), lineWidth: 0.6))
        .dropDestination(for: String.self) { items, _ in
            guard editing, let id = items.first, known.contains(id), !dockIDs.contains(id) else { return false }
            appendToDock(id); return true
        }
        .accessibilityIdentifier("iphone-home-dock")
    }

    // MARK: tiles
    @ViewBuilder private func iconImage(_ id: String, side: CGFloat) -> some View {
        switch id {
        case MirsaIPhoneSystem.settings:
            LinearGradient(colors: [Color(white: 0.62), Color(white: 0.38)], startPoint: .top, endPoint: .bottom)
                .overlay(Image(systemName: "gearshape.fill").font(.system(size: side * 0.62)).foregroundStyle(Color(white: 0.2)))
        case MirsaIPhoneSystem.downloads:
            LinearGradient(colors: [Color(red: 0.25, green: 0.62, blue: 1), Color(red: 0.05, green: 0.38, blue: 0.95)], startPoint: .top, endPoint: .bottom)
                .overlay(Image(systemName: "arrow.down.circle.fill").font(.system(size: side * 0.55)).foregroundStyle(.white))
        default:
            if let a = app(id), let icon = MirsaIconCache.image(id: a.id, path: AppsStore.iconURL(a.id).path) {
                Image(uiImage: icon).resizable().scaledToFill()
            } else {
                Color.indigo.overlay(Text(String(label(id).prefix(1))).font(.system(size: side * 0.4, weight: .semibold)))
            }
        }
    }

    private func iconView(_ id: String, side: CGFloat) -> some View {
        iconImage(id, side: side)
            .frame(width: side, height: side)
            .clipShape(RoundedRectangle(cornerRadius: side * 0.225, style: .continuous))
            .overlay { if app(id) != nil { MirsaHomeOperationBadge(appID: id, cornerRadius: side * 0.225) } }
            .overlay(alignment: .topTrailing) {
                if !editing, updateIDs.contains(id) {
                    Text("1").font(.system(size: 15, weight: .regular)).monospacedDigit()
                        .padding(.horizontal, 7).frame(minWidth: 24, minHeight: 24)
                        .background(Color(red: 1, green: 0.23, blue: 0.19), in: Capsule())
                        .offset(x: 8, y: -8)
                }
            }
    }

    private func tile(_ id: String, side: CGFloat, showLabel: Bool) -> some View {
        let isDock = dockIDs.contains(id)
        return VStack(spacing: 5) {
            iconView(id, side: side)
                .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
            if showLabel {
                Text(label(id)).font(.system(size: 12, weight: .regular)).lineLimit(1).truncationMode(.tail)
                    .shadow(color: .black.opacity(0.55), radius: 2, y: 1)
                    .frame(width: side + 18)
            }
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .rotationEffect(.degrees(editing ? (jiggle ? 1.8 : -1.8) : 0))
        .animation(editing ? .easeInOut(duration: 0.13).repeatForever(autoreverses: true) : .default, value: jiggle)
        .onTapGesture { open(id) }
        .modifier(MirsaIPhoneTileMenu(editing: editing) {
            Button(action: startEditing) { Label(MirsaIPhoneText.editHome, systemImage: "apps.iphone") }
            if isDock {
                Button { removeFromDock(id) } label: { Label(MirsaIPhoneText.removeFromDock, systemImage: "rectangle.bottomhalf.inset.filled") }
            } else {
                Button { appendToDock(id) } label: { Label(MirsaIPhoneText.addToDock, systemImage: "dock.rectangle") }
                    .disabled(dockIDs.count >= 4)
            }
            if let a = app(id) { Divider(); menu(a) }
        } preview: {
            iconView(id, side: 96).padding(14)
        })
        .modifier(MirsaIPhoneDrag(enabled: editing, id: id))
        .dropDestination(for: String.self) { items, _ in
            guard editing, let dragged = items.first, known.contains(dragged) else { return false }
            move(dragged, before: id); return true
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label(id))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(.default) { open(id) }
        .accessibilityIdentifier("iphone-tile-\(id)")
    }

    // MARK: search
    private var searchOverlay: some View {
        let q = query.trimmingCharacters(in: .whitespaces)
        let all = apps.map(\.id) + MirsaIPhoneSystem.all
        let hits = q.isEmpty ? all : all.filter { label($0).localizedCaseInsensitiveContains(q) }
        return VStack(spacing: 18) {
            HStack(spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.white.opacity(0.7))
                    TextField(MirsaIPhoneText.search, text: $query).focused($searchFocused).submitLabel(.search)
                        .accessibilityIdentifier("iphone-home-search-field")
                    if !query.isEmpty { Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.white.opacity(0.6)) } }
                }
                .padding(.horizontal, 12).frame(height: 40)
                .background(.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                Button { searchFocused = false; withAnimation(.easeOut(duration: 0.2)) { searching = false } } label: {
                    Image(systemName: "xmark").font(.system(size: 15, weight: .semibold)).frame(width: 40, height: 40)
                        .background(.white.opacity(0.14), in: Circle())
                }.accessibilityLabel(ForgeChatText.cancel)
            }
            .padding(.horizontal, 18).padding(.top, 14)
            if hits.isEmpty {
                Text(MirsaIPhoneText.noResults).font(.title3.weight(.semibold)).foregroundStyle(.white.opacity(0.7)).padding(.top, 40)
            } else {
                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 16) {
                        ForEach(hits, id: \.self) { id in
                            Button { searchFocused = false; searching = false; open(id) } label: {
                                VStack(spacing: 5) {
                                    iconView(id, side: 58)
                                    Text(label(id)).font(.system(size: 12)).lineLimit(1).frame(width: 76)
                                }
                            }.buttonStyle(.plain)
                        }
                    }.padding(.horizontal, 22)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial.opacity(0.97))
        .environment(\.colorScheme, .dark)
    }
}

/// iOS long-press: the app's quick-action menu outside edit mode; nothing while icons jiggle (drag instead).
private struct MirsaIPhoneTileMenu<Items: View, Preview: View>: ViewModifier {
    let editing: Bool
    @ViewBuilder let items: () -> Items
    @ViewBuilder let preview: () -> Preview
    func body(content: Content) -> some View {
        if editing { content } else { content.contextMenu(menuItems: items, preview: preview) }
    }
}

private struct MirsaIPhoneDrag: ViewModifier {
    let enabled: Bool
    let id: String
    func body(content: Content) -> some View {
        if enabled { content.draggable(id) } else { content }
    }
}
