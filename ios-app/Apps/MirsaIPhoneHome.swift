import SwiftUI
import PhotosUI

// Mirsa 2.1: optional "iPhone" home screen style, modelled 1:1 on the iOS Home Screen.
// 4-column grid with labels, page swipe, «Search» pill above a glass dock of 4, iOS-style
// long-press menu, jiggle edit mode with Done / + (install IPA, install from link, choose wallpaper),
// the «−» delete badge, and folders (frosted 3x3 tile, blurred overlay, rename while jiggling).
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
    static var delete: String { tr("Delete", "حذف", ckb: "سڕینەوە", kmr: "Jê bibe") }
    static var cancel: String { tr("Cancel", "إلغاء", ckb: "هەڵوەشاندنەوە", kmr: "Betal bike") }
    static func deleteTitle(_ name: String) -> String {
        tr("Delete “%@”?", "حذف “%@”؟", ckb: "“%@” بسڕدرێتەوە؟", kmr: "“%@” jê bibe?").replacingOccurrences(of: "%@", with: name)
    }
    static var deleteMessage: String {
        tr("Deleting this app will also delete its data.", "حذف هالتطبيق بيحذف بياناته كمان.",
           ckb: "سڕینەوەی ئەم ئەپە داتاکانیشی دەسڕێتەوە.", kmr: "Jêbirina vê sepanê daneyên wê jî jê dibe.")
    }
    static var folder: String { tr("Folder", "مجلد", ckb: "بوخچە", kmr: "Peldank") }
    static var rename: String { tr("Rename", "تغيير الاسم", ckb: "ناو بگۆڕە", kmr: "Nav biguherîne") }
    static var empty: String { tr("Tap + to install your first app", "اكبس + لتثبّت أول تطبيق", ckb: "+ دابگرە بۆ دامەزراندنی یەکەم ئەپ", kmr: "Ji bo sepana yekem + bitikîne") }
}

/// The two built-in tiles that behave like apps on this screen.
private enum MirsaIPhoneSystem {
    static let settings = "mirsa.system.settings"
    static let downloads = "mirsa.system.downloads"
    static let all = [settings, downloads]
}

/// A Home Screen folder. Its token in the grid order is `"folder:" + id`.
private struct MirsaIPhoneFolder: Codable, Hashable, Identifiable {
    static let prefix = "folder:"
    var id: String
    var name: String
    var appIDs: [String]
    var token: String { Self.prefix + id }
}

struct MirsaIPhoneHome<Menu: View>: View {
    let apps: [ManagedApp]
    let allAppIDs: [String]
    let onLaunch: (ManagedApp) -> Void
    let onSettings: () -> Void
    let onImport: () -> Void
    let onImportLink: () -> Void
    let onDownloads: () -> Void
    /// Called after the user confirms the «−» badge alert; wired to the app's existing delete path.
    let onDelete: (ManagedApp) -> Void
    @ViewBuilder let menu: (ManagedApp) -> Menu

    @AppStorage("mirsa.iphone.order") private var orderRaw = "[]"
    @AppStorage("mirsa.iphone.dock") private var dockRaw = ""
    @AppStorage("mirsa.iphone.folders") private var foldersRaw = "[]"
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
    @State private var pendingDelete: ManagedApp?
    @State private var openFolderID: String?
    @State private var folderPage = 0
    /// While an app is dragged out of an open folder the overlay fades away (kept alive so the drag
    /// session's source view survives) and stops hit-testing, so the grid and dock underneath take the drop.
    @State private var folderDragOut = false
    @State private var dragOutTask: Task<Void, Never>?

    // MARK: layout state
    private static func decode(_ raw: String) -> [String] { (try? JSONDecoder().decode([String].self, from: Data(raw.utf8))) ?? [] }
    private static func encode(_ ids: [String]) -> String { (try? JSONEncoder().encode(ids)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]" }
    private var known: Set<String> { Set(apps.map(\.id) + MirsaIPhoneSystem.all) }
    /// Every app that exists, hidden ones included (mirrors `allAppIDs`), plus the two built-in tiles.
    private var existing: Set<String> { Set(allAppIDs + MirsaIPhoneSystem.all) }
    private func isFolder(_ id: String) -> Bool { id.hasPrefix(MirsaIPhoneFolder.prefix) }
    /// Folders as read: unknown or deleted app ids are dropped, an app sits in one folder at most.
    /// Hidden apps stay in their folder (never lost) but are not shown.
    private var folders: [MirsaIPhoneFolder] {
        let stored = (try? JSONDecoder().decode([MirsaIPhoneFolder].self, from: Data(foldersRaw.utf8))) ?? []
        let ex = existing
        var seen = Set<String>()
        return stored.compactMap { (f: MirsaIPhoneFolder) -> MirsaIPhoneFolder? in
            var f = f
            f.appIDs = f.appIDs.filter { ex.contains($0) && seen.insert($0).inserted }
            return f.appIDs.isEmpty ? nil : f
        }
    }
    private func folder(_ token: String) -> MirsaIPhoneFolder? { isFolder(token) ? folders.first { $0.token == token } : nil }
    private func visibleMembers(_ f: MirsaIPhoneFolder) -> [String] { let k = known; return f.appIDs.filter { k.contains($0) } }
    private func folderName(_ f: MirsaIPhoneFolder?) -> String {
        let n = f?.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return n.isEmpty ? MirsaIPhoneText.folder : n
    }
    /// First launch: Settings in the dock, like the stock iPhone dock holds a system app. Folders never go in the dock.
    private var dockIDs: [String] {
        let nested = Set(folders.flatMap(\.appIDs))
        let ids = dockRaw.isEmpty ? [MirsaIPhoneSystem.settings] : Self.decode(dockRaw)
        return Array(ids.filter { known.contains($0) && !nested.contains($0) }.prefix(4))
    }
    /// Grid order: app ids and `folder:` tokens. A folder whose apps are all hidden is not shown.
    private var gridIDs: [String] {
        let dock = Set(dockIDs), fs = folders
        let nested = Set(fs.flatMap(\.appIDs))
        let shown = Set(fs.filter { !visibleMembers($0).isEmpty }.map(\.token))
        var seen = Set<String>()
        var order = Self.decode(orderRaw).filter { id in
            let ok = isFolder(id) ? shown.contains(id) : (known.contains(id) && !dock.contains(id) && !nested.contains(id))
            return ok && seen.insert(id).inserted
        }
        order.append(contentsOf: (apps.map(\.id) + MirsaIPhoneSystem.all).filter { !dock.contains($0) && !nested.contains($0) && !seen.contains($0) })
        order.append(contentsOf: fs.map(\.token).filter { shown.contains($0) && !seen.contains($0) })
        return order
    }
    private func setDock(_ ids: [String]) { withAnimation(.easeInOut(duration: 0.2)) { dockRaw = Self.encode(ids) } }
    private func setOrder(_ ids: [String]) { withAnimation(.easeInOut(duration: 0.2)) { orderRaw = Self.encode(ids) } }
    private func app(_ id: String) -> ManagedApp? { apps.first { $0.id == id } }
    private var updateIDs: Set<String> { Set(sources.availableUpdates().map(\.0.bundleID)) }

    /// Writes grid, dock and folders together. A folder left with one app dissolves into that app
    /// (in the folder's place); an empty folder is removed.
    private func commit(grid: [String], dock: [String], folders fs: [MirsaIPhoneFolder]) {
        var grid = grid, kept: [MirsaIPhoneFolder] = []
        let ex = existing
        for f in fs {
            var f = f
            f.appIDs = f.appIDs.filter { ex.contains($0) }
            let at = grid.firstIndex(of: f.token)
            if f.appIDs.count >= 2 {
                kept.append(f)
            } else if let only = f.appIDs.first {
                if let at { grid[at] = only } else { grid.append(only) }
            } else if let at {
                grid.remove(at: at)
            }
        }
        let nested = Set(kept.flatMap(\.appIDs))
        var seen = Set<String>()
        grid = grid.filter { !nested.contains($0) && seen.insert($0).inserted }
        let dock = dock.filter { !nested.contains($0) && !isFolder($0) }
        let data = (try? JSONEncoder().encode(kept)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        withAnimation(.easeInOut(duration: 0.2)) {
            foldersRaw = data
            orderRaw = Self.encode(grid)
            dockRaw = Self.encode(dock)
            if let open = openFolderID, !kept.contains(where: { $0.token == open }) { openFolderID = nil; folderDragOut = false }
        }
    }
    private func foldersWithout(_ id: String) -> [MirsaIPhoneFolder] {
        folders.map { (f: MirsaIPhoneFolder) -> MirsaIPhoneFolder in var f = f; f.appIDs.removeAll { $0 == id }; return f }
    }

    private func label(_ id: String) -> String {
        switch id {
        case MirsaIPhoneSystem.settings: return MirsaIPhoneText.settings
        case MirsaIPhoneSystem.downloads: return MirsaIPhoneText.downloads
        default: return isFolder(id) ? folderName(folder(id)) : (app(id)?.name ?? "")
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

    // MARK: moving, folders, delete
    //
    // How a drop is read while icons jiggle (one drop target per tile, decided by where the finger lifts):
    //  - finger over the middle of another app's icon (the inner ~60% square)  -> make a folder of the two;
    //  - finger over the middle of a folder's icon                             -> add the app to that folder;
    //  - finger on the icon's outer ring or its label                         -> reorder: insert before that tile;
    //  - finger on empty space on a page                                       -> move to the end of that page.
    // The dock only reorders and never takes a folder; folders never nest.
    // Out of an open folder: drag past the panel's edge; after a short hover the folder fades away and the
    // drop lands on the grid or dock underneath. Dropping on the blurred backdrop right away puts the app
    // next to the folder on the grid.
    private func isCentreDrop(_ p: CGPoint, cell: CGFloat, side: CGFloat) -> Bool {
        let left = (cell - side) / 2, inset = side * 0.2
        return p.x > left + inset && p.x < left + side - inset && p.y > inset && p.y < side - inset
    }
    private func canDrag(_ id: String) -> Bool { known.contains(id) || folder(id) != nil }

    /// Drop `dragged` onto `target`: reorder within the grid or the dock, or move between them.
    private func move(_ dragged: String, before target: String) {
        guard dragged != target else { return }
        var dock = dockIDs, grid = gridIDs
        let toDock = dock.contains(target)
        if toDock && isFolder(dragged) { return }
        dock.removeAll { $0 == dragged }; grid.removeAll { $0 == dragged }
        if toDock {
            guard dock.count < 4 else { return }
            dock.insert(dragged, at: dock.firstIndex(of: target) ?? dock.count)
        } else {
            grid.insert(dragged, at: grid.firstIndex(of: target) ?? grid.count)
        }
        commit(grid: grid, dock: dock, folders: foldersWithout(dragged))
    }
    /// Drop on empty page space: the end of page `pageEnd / capacity`.
    private func move(_ dragged: String, toIndex pageEnd: Int) {
        var grid = gridIDs
        var at = pageEnd
        if let old = grid.firstIndex(of: dragged) { if old < pageEnd { at -= 1 }; grid.remove(at: old) }
        grid.insert(dragged, at: max(0, min(at, grid.count)))
        commit(grid: grid, dock: dockIDs.filter { $0 != dragged }, folders: foldersWithout(dragged))
    }
    /// Drop an app on the middle of `target`: a new folder with both, or into an existing folder.
    private func combine(_ dragged: String, onto target: String) {
        guard dragged != target, !isFolder(dragged) else { move(dragged, before: target); return }
        var grid = gridIDs.filter { $0 != dragged }
        var fs = foldersWithout(dragged)
        if isFolder(target), let i = fs.firstIndex(where: { $0.token == target }) {
            fs[i].appIDs.append(dragged)
        } else if let i = grid.firstIndex(of: target) {
            let f = MirsaIPhoneFolder(id: UUID().uuidString, name: "", appIDs: [target, dragged])
            fs.append(f); grid[i] = f.token
        } else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        commit(grid: grid, dock: dockIDs.filter { $0 != dragged }, folders: fs)
    }
    /// Reorder inside an open folder (`target == nil`: to its end).
    private func moveInFolder(_ dragged: String, before target: String?, folder token: String) {
        guard dragged != target else { return }
        var fs = foldersWithout(dragged)
        guard let fi = fs.firstIndex(where: { $0.token == token }) else { return }
        if let target, let ti = fs[fi].appIDs.firstIndex(of: target) { fs[fi].appIDs.insert(dragged, at: ti) }
        else { fs[fi].appIDs.append(dragged) }
        commit(grid: gridIDs.filter { $0 != dragged }, dock: dockIDs.filter { $0 != dragged }, folders: fs)
    }
    /// Dropped on the folder's backdrop: out of the folder, onto the grid right after it.
    private func moveOut(_ dragged: String, from token: String) {
        guard folder(token)?.appIDs.contains(dragged) == true else { return }
        var grid = gridIDs.filter { $0 != dragged }
        grid.insert(dragged, at: grid.firstIndex(of: token).map { $0 + 1 } ?? grid.count)
        commit(grid: grid, dock: dockIDs, folders: foldersWithout(dragged))
        closeFolder()
    }
    private func appendToDock(_ id: String) {
        guard !isFolder(id) else { return }
        var dock = dockIDs.filter { $0 != id }
        guard dock.count < 4 else { return }
        dock.append(id)
        commit(grid: gridIDs.filter { $0 != id }, dock: dock, folders: foldersWithout(id))
    }
    private func removeFromDock(_ id: String) {
        setDock(dockIDs.filter { $0 != id })
        var grid = gridIDs.filter { $0 != id }; grid.append(id); setOrder(grid)
    }
    private func confirmDelete(_ a: ManagedApp) {
        commit(grid: gridIDs.filter { $0 != a.id }, dock: dockIDs.filter { $0 != a.id }, folders: foldersWithout(a.id))
        onDelete(a)
    }
    private func renameFolder(_ token: String, to name: String) {
        var fs = folders
        guard let i = fs.firstIndex(where: { $0.token == token }) else { return }
        fs[i].name = String(name.prefix(40))
        foldersRaw = (try? JSONEncoder().encode(fs)).flatMap { String(data: $0, encoding: .utf8) } ?? foldersRaw
    }
    private func openFolder(_ token: String) {
        guard folder(token) != nil else { return }
        dragOutTask?.cancel()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) { folderPage = 0; folderDragOut = false; openFolderID = token }
    }
    private func closeFolder() {
        dragOutTask?.cancel()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) { openFolderID = nil; folderDragOut = false }
    }
    private func dragOutHover(_ over: Bool) {
        dragOutTask?.cancel()
        guard over, editing else { return }
        dragOutTask = Task {
            try? await Task.sleep(nanoseconds: 450_000_000)
            if !Task.isCancelled { await MainActor.run { withAnimation(.easeOut(duration: 0.2)) { folderDragOut = true } } }
        }
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
    // Split into small pieces so the Swift type checker stays fast.
    var body: some View {
        GeometryReader { geo in homeContent(size: geo.size) }
            .background { background.ignoresSafeArea() }
            .overlay { if searching { searchOverlay.transition(.opacity) } }
            .photosPicker(isPresented: $pickingPhoto, selection: $photo, matching: .images)
            .onChange(of: photo) { _, item in if let item { Task { await saveWallpaper(item) } } }
            .onAppear(perform: loadWallpaper)
            .onDisappear { dotsTask?.cancel(); dragOutTask?.cancel() }
            .modifier(deleteAlert)
            .foregroundStyle(.white)
            .environment(\.layoutDirection, .leftToRight)
            .accessibilityIdentifier("mirsa-iphone-home")
    }

    private var deleteAlert: MirsaIPhoneDeleteAlert {
        MirsaIPhoneDeleteAlert(pending: $pendingDelete, onConfirm: confirmDelete)
    }

    private func homeContent(size: CGSize) -> some View {
        let iconSide: CGFloat = min(64, (size.width - 2 * 26 - 3 * 24) / 4)
        let rowHeight = iconSide + 34
        let gridHeight = max(rowHeight, size.height - 44 - 12 - 48 - 108)
        let rows = max(1, Int(gridHeight / (rowHeight + 12)))
        let capacity = rows * 4
        let ids = gridIDs
        let pages = max(1, (ids.count + capacity - 1) / capacity)
        let cell = (size.width - 2 * 26 - 3 * 12) / 4
        return ZStack {
            VStack(spacing: 0) {
                topBar.frame(height: 44)
                homePages(ids: ids, pages: pages, capacity: capacity, side: iconSide, cell: cell)
                pageIndicator(pages: pages).frame(height: 48)
                dock(side: iconSide).padding(.horizontal, 10).padding(.bottom, 6)
            }
            if openFolderID != nil { folderOverlay(side: iconSide).transition(.opacity.combined(with: .scale(scale: 0.92))) }
        }
    }

    private func homePages(ids: [String], pages: Int, capacity: Int, side: CGFloat, cell: CGFloat) -> some View {
        TabView(selection: $page) {
            ForEach(0..<pages, id: \.self) { p in
                homePage(Array(ids.dropFirst(p * capacity).prefix(capacity)), index: p, capacity: capacity, side: side, cell: cell)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .onChange(of: page) { _, _ in flashDots() }
        .onChange(of: pages) { _, n in page = min(page, n - 1) }
    }

    private func homePage(_ pageIDs: [String], index p: Int, capacity: Int, side: CGFloat, cell: CGFloat) -> some View {
        VStack(spacing: 0) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 12) {
                ForEach(pageIDs, id: \.self) { id in
                    tile(id, side: side, showLabel: true, cell: cell)
                }
            }
            .padding(.horizontal, 26)
            // Room for the red badge and the «−» badge on the first row: TabView pages clip their content.
            .padding(.top, 12)
            if apps.isEmpty && p == 0 {
                Text(MirsaIPhoneText.empty).font(.footnote.weight(.medium)).foregroundStyle(.white.opacity(0.85))
                    .shadow(color: .black.opacity(0.4), radius: 3).padding(.top, 28)
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .onLongPressGesture(minimumDuration: 0.6) { if !editing { startEditing() } }
        // Empty space on a page: move there (end of this page).
        .dropDestination(for: String.self) { items, _ in
            guard editing, let dragged = items.first, canDrag(dragged) else { return false }
            move(dragged, toIndex: (p + 1) * capacity)
            if folderDragOut { closeFolder() }
            return true
        }
        .tag(p)
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
            appendToDock(id)
            if folderDragOut { closeFolder() }
            return true
        }
        .accessibilityIdentifier("iphone-home-dock")
    }

    // MARK: tiles
    @ViewBuilder private func iconImage(_ id: String, side: CGFloat) -> some View {
        switch id {
        case MirsaIPhoneSystem.settings:
            // Mirsa's Aurora accent instead of the stock gray, white gear.
            MirsaPalette.accentGradient
                .overlay(Image(systemName: "gearshape.fill").font(.system(size: side * 0.62)).foregroundStyle(.white))
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

    /// iOS «−» badge, top-left, in edit mode only; real apps only (not Settings / Downloads, not folders).
    @ViewBuilder private func deleteBadge(_ id: String) -> some View {
        if editing, let a = app(id) {
            Button { pendingDelete = a } label: {
                Image(systemName: "minus").font(.system(size: 12, weight: .heavy)).foregroundStyle(Color.black.opacity(0.78))
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(Color(white: 0.86)))
                    .overlay(Circle().stroke(.black.opacity(0.08), lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.25), radius: 1.5, y: 0.5)
            }
            .buttonStyle(.plain)
            .offset(x: -8, y: -8)
            .transition(.scale.combined(with: .opacity))
            .accessibilityIdentifier("iphone-delete-\(id)")
        }
    }

    /// Frosted rounded square, same size as an app icon, with a 3x3 mini-grid of the first 9 apps.
    private func folderIcon(_ token: String, side: CGFloat) -> some View {
        let members = folder(token).map { visibleMembers($0) } ?? []
        let pad = side * 0.12, gap = side * 0.06
        let mini = (side - 2 * pad - 2 * gap) / 3
        return RoundedRectangle(cornerRadius: side * 0.225, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(RoundedRectangle(cornerRadius: side * 0.225, style: .continuous).stroke(.white.opacity(0.14), lineWidth: 0.5))
            .frame(width: side, height: side)
            .overlay(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: gap) {
                    ForEach(0..<3, id: \.self) { r in
                        HStack(spacing: gap) {
                            ForEach(0..<3, id: \.self) { c in miniIcon(members, r * 3 + c, side: mini) }
                        }
                    }
                }
                .padding(pad)
            }
    }
    @ViewBuilder private func miniIcon(_ members: [String], _ i: Int, side: CGFloat) -> some View {
        if i < members.count {
            iconImage(members[i], side: side)
                .frame(width: side, height: side)
                .clipShape(RoundedRectangle(cornerRadius: side * 0.225, style: .continuous))
        } else {
            Color.clear.frame(width: side, height: side)
        }
    }
    @ViewBuilder private func icon(_ id: String, side: CGFloat) -> some View {
        if isFolder(id) { folderIcon(id, side: side) } else { iconView(id, side: side) }
    }

    /// Icon (with «−» while jiggling) and label; shared by the grid, the dock and the folder panel.
    private func tileFace(_ id: String, side: CGFloat, showLabel: Bool) -> some View {
        VStack(spacing: 5) {
            icon(id, side: side)
                .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
                .overlay(alignment: .topLeading) { deleteBadge(id) }
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
    }

    @ViewBuilder private func appMenuItems(_ id: String) -> some View {
        Button(action: startEditing) { Label(MirsaIPhoneText.editHome, systemImage: "apps.iphone") }
        if isFolder(id) {
            Button { startEditing(); openFolder(id) } label: { Label(MirsaIPhoneText.rename, systemImage: "pencil") }
        } else if dockIDs.contains(id) {
            Button { removeFromDock(id) } label: { Label(MirsaIPhoneText.removeFromDock, systemImage: "rectangle.bottomhalf.inset.filled") }
        } else {
            Button { appendToDock(id) } label: { Label(MirsaIPhoneText.addToDock, systemImage: "dock.rectangle") }
                .disabled(dockIDs.count >= 4)
        }
        if let a = app(id) { Divider(); menu(a) }
    }

    /// Grid (`cell` = column width) or dock (`cell == nil`) tile.
    private func tile(_ id: String, side: CGFloat, showLabel: Bool, cell: CGFloat? = nil) -> some View {
        let isDock = dockIDs.contains(id)
        return tileFace(id, side: side, showLabel: showLabel)
            .onTapGesture { if isFolder(id) { openFolder(id) } else { open(id) } }
            .modifier(MirsaIPhoneTileMenu(editing: editing) {
                appMenuItems(id)
            } preview: {
                icon(id, side: 96).padding(14)
            })
            .modifier(MirsaIPhoneDrag(enabled: editing, id: id))
            .dropDestination(for: String.self) { items, location in
                guard editing, let dragged = items.first, canDrag(dragged) else { return false }
                if let cell, !isDock, isCentreDrop(location, cell: cell, side: side) { combine(dragged, onto: id) }
                else { move(dragged, before: id) }
                if folderDragOut { closeFolder() }
                return true
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label(id))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(.default) { if isFolder(id) { openFolder(id) } else { open(id) } }
            .accessibilityAction(named: Text(MirsaIPhoneText.delete)) { if editing, let a = app(id) { pendingDelete = a } }
            .accessibilityIdentifier("iphone-tile-\(id)")
    }

    // MARK: folder overlay
    /// iOS-style open folder: blurred, darkened backdrop (tap to close), big name, frosted panel of 3 columns,
    /// paged by 9. While jiggling the name is a text field and apps can be reordered or dragged out.
    @ViewBuilder private func folderOverlay(side: CGFloat) -> some View {
        if let token = openFolderID, let f = folder(token) {
            let members = visibleMembers(f)
            let pages = max(1, (members.count + 8) / 9)
            GeometryReader { g in
                folderLayer(token: token, folder: f, members: members, pages: pages, side: side, size: g.size)
            }
            .environment(\.colorScheme, .dark)
            .opacity(folderDragOut ? 0 : 1)
            .allowsHitTesting(!folderDragOut)
            .onChange(of: pages) { _, n in folderPage = min(folderPage, n - 1) }
        }
    }

    private func folderLayer(token: String, folder f: MirsaIPhoneFolder, members: [String], pages: Int, side: CGFloat, size: CGSize) -> some View {
        let panel = min(size.width - 56, 340)
        let fside = min(side, (panel - 28) / 3 - 22)
        return ZStack {
            folderBackdrop(token: token)
            VStack(alignment: .leading, spacing: 20) {
                folderTitle(token: token, folder: f)
                folderPanel(token: token, folder: f, members: members, pages: pages, panel: panel, side: fside)
            }
            .frame(width: panel)
            .padding(.bottom, 40)
        }
        .frame(width: size.width, height: size.height)
    }

    /// Blurred, darkened backdrop: tap to close; hover a dragged app here to fade the folder and drop on the grid.
    private func folderBackdrop(token: String) -> some View {
        Rectangle().fill(.ultraThinMaterial)
            .overlay(Color.black.opacity(0.25))
            .ignoresSafeArea()
            .contentShape(Rectangle())
            .onTapGesture { closeFolder() }
            .dropDestination(for: String.self) { items, _ in
                guard editing, let dragged = items.first else { return false }
                moveOut(dragged, from: token)
                return true
            } isTargeted: { over in dragOutHover(over) }
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(MirsaIPhoneText.done)
    }

    @ViewBuilder private func folderTitle(token: String, folder f: MirsaIPhoneFolder) -> some View {
        if editing {
            let name = Binding<String>(get: { folder(token)?.name ?? "" }, set: { renameFolder(token, to: $0) })
            HStack(spacing: 6) {
                TextField(MirsaIPhoneText.folder, text: name)
                    .font(.system(size: 28, weight: .bold))
                    .submitLabel(.done)
                    .accessibilityIdentifier("iphone-folder-name-field")
                if !f.name.isEmpty {
                    Button { renameFolder(token, to: "") } label: {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 18)).foregroundStyle(.white.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(MirsaIPhoneText.cancel)
                }
            }
            .padding(.horizontal, 14).frame(height: 48)
            .background(.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        } else {
            Text(folderName(f)).font(.system(size: 32, weight: .bold)).lineLimit(1)
                .shadow(color: .black.opacity(0.3), radius: 3)
                .padding(.horizontal, 6)
                .accessibilityAddTraits(.isHeader)
        }
    }

    private func folderPanel(token: String, folder f: MirsaIPhoneFolder, members: [String], pages: Int, panel: CGFloat, side: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: 38, style: .continuous)
        return TabView(selection: $folderPage) {
            ForEach(0..<pages, id: \.self) { p in
                folderGridPage(Array(members.dropFirst(p * 9).prefix(9)), index: p, token: token, side: side)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: pages > 1 ? .always : .never))
        .frame(width: panel, height: panel)
        .background(shape.fill(.ultraThinMaterial))
        .clipShape(shape)
        .contentShape(shape)
        // Empty space in the panel: to the end of this folder.
        .dropDestination(for: String.self) { items, _ in
            guard editing, let dragged = items.first, f.appIDs.contains(dragged) else { return false }
            moveInFolder(dragged, before: nil, folder: token)
            return true
        }
        .accessibilityIdentifier("iphone-folder-panel")
    }

    private func folderGridPage(_ pageIDs: [String], index p: Int, token: String, side: CGFloat) -> some View {
        VStack(spacing: 0) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 3), spacing: 16) {
                ForEach(pageIDs, id: \.self) { id in folderTile(id, folder: token, side: side) }
            }
            // Room for the «−» badge on the first row: TabView pages clip their content.
            .padding(.top, 16)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .tag(p)
    }

    /// App inside an open folder: launches normally, same long-press menu, jiggles and drags while editing.
    private func folderTile(_ id: String, folder token: String, side: CGFloat) -> some View {
        tileFace(id, side: side, showLabel: true)
            .onTapGesture { open(id) }
            .modifier(MirsaIPhoneTileMenu(editing: editing) {
                appMenuItems(id)
            } preview: {
                icon(id, side: 96).padding(14)
            })
            .modifier(MirsaIPhoneDrag(enabled: editing, id: id))
            .dropDestination(for: String.self) { items, _ in
                guard editing, let dragged = items.first, folder(token)?.appIDs.contains(dragged) == true else { return false }
                moveInFolder(dragged, before: id, folder: token); return true
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label(id))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(.default) { open(id) }
            .accessibilityAction(named: Text(MirsaIPhoneText.delete)) { if editing, let a = app(id) { pendingDelete = a } }
            .accessibilityIdentifier("iphone-folder-tile-\(id)")
    }

    // MARK: search
    private var searchOverlay: some View {
        let q = query.trimmingCharacters(in: .whitespaces)
        // Every visible app, including the ones inside folders.
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

/// iOS «Delete “App”?» confirmation for the «−» badge.
private struct MirsaIPhoneDeleteAlert: ViewModifier {
    @Binding var pending: ManagedApp?
    let onConfirm: (ManagedApp) -> Void
    func body(content: Content) -> some View {
        content.alert(MirsaIPhoneText.deleteTitle(pending?.name ?? ""),
                      isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }),
                      presenting: pending) { a in
            Button(MirsaIPhoneText.delete, role: .destructive) { onConfirm(a) }
            Button(MirsaIPhoneText.cancel, role: .cancel) {}
        } message: { _ in
            Text(MirsaIPhoneText.deleteMessage)
        }
    }
}

private struct MirsaIPhoneDrag: ViewModifier {
    let enabled: Bool
    let id: String
    func body(content: Content) -> some View {
        if enabled { content.draggable(id) } else { content }
    }
}
