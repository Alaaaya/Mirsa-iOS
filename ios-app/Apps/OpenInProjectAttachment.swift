import SwiftUI
import UIKit
import UniformTypeIdentifiers
import CryptoKit

enum OpenInAttachmentText {
    static var title: String { tr("Attach to project", "إرفاق إلى المشروع", ckb: "لکاندن بە پڕۆژە", kmr: "Bi projeyê ve girê bide") }
    static var cancel: String { tr("Cancel", "إلغاء", ckb: "هەڵوەشاندنەوە", kmr: "Betal") }
    static var importTitle: String { tr("Import", "استيراد", ckb: "هاوردەکردن", kmr: "Bîne") }
    static var help: String { tr("Choose projects. Additions are saved only; review them before signing or installing.", "اختار المشاريع. الإضافات بتنحفظ بس، راجعها قبل التوقيع أو التثبيت.", ckb: "پڕۆژەکان هەڵبژێرە. زیادکراوەکان تەنیا پاشەکەوت دەکرێن؛ پێش واژۆکردن یان دامەزراندن بیانپشکنە.", kmr: "Projeyan hilbijêre. Pêvek tenê tên parastin; berî îmzekirin an sazkirinê wan kontrol bike.") }
    static var empty: String { tr("No projects yet. Import an IPA into your certificate library first.", "لسا ما عندك مشاريع. ضيف IPA لمكتبة الشهادة بالأول.", ckb: "هێشتا پڕۆژە نییە. سەرەتا IPA بۆ کتێبخانەی بڕوانامە زیاد بکە.", kmr: "Hê projeyek tune. Pêşî IPA li pirtûkxaneya sertîfîkayê zêde bike.") }
    static var failed: String { tr("Could not attach. Existing project additions were preserved. Review the file and try again.", "ما قدرت أرفق الإضافة. إضافات المشروع القديمة ضلّت متل ما هي. راجع الملف وجرّب من جديد.", ckb: "نەتوانرا بلکێندرێت. زیادکراوە کۆنەکان پارێزراون. فایلەکە بپشکنە و دووبارە بکەرەوە.", kmr: "Nehat girêdan. Pêvekên berê hatin parastin. Dosyayê kontrol bike û dîsa biceribîne.") }
    static var collision: String { tr("A different addition with the same name is already selected. Review it in project details first.", "في إضافة مختلفة بنفس الاسم بالمشروع. راجعها بتفاصيل المشروع بالأول.", ckb: "زیادکراوێکی جیاواز بە هەمان ناو لە پڕۆژە هەیە. سەرەتا لە وردەکاری پڕۆژە بیپشکنە.", kmr: "Pêvekeke cuda bi heman navî heye. Pêşî di hûrguliyên projeyê de kontrol bike.") }
    static func count(_ count: Int) -> String { "\(count) " + tr("additions", "إضافات", ckb: "زیادکراو", kmr: "pêvek") }
}

/// Foreign file formats are read-only inputs, never code loaded into Mirsa.
enum OpenInTweak {
    static let extensions: Set<String> = ["dylib", "deb", "zip"]
    static func accepts(_ url: URL) -> Bool { url.isFileURL && extensions.contains(url.pathExtension.lowercased()) }
    static func snapshot(_ source: URL, maxBytes: Int = 128 * 1024 * 1024) throws -> URL {
        guard accepts(source) else { throw CocoaError(.fileReadUnsupportedScheme) }
        let access = source.startAccessingSecurityScopedResource()
        defer { if access { source.stopAccessingSecurityScopedResource() } }
        guard try source.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else { throw CocoaError(.fileReadNoPermission) }
        let session = try MirsaManagedTmp.begin("external-attach")
        do {
            let name = source.lastPathComponent
            guard !name.isEmpty, name != ".", name != "..", !name.contains("\\"), !name.contains("\0") else { throw CocoaError(.fileReadInvalidFileName) }
            let target = session.appendingPathComponent(name)
            var coordinatorError: NSError?
            var copyError: Error?
            NSFileCoordinator().coordinate(readingItemAt: source, options: [], error: &coordinatorError) { readable in
                do {
                    let v = try readable.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
                    guard v.isRegularFile == true, v.isSymbolicLink != true, (v.fileSize ?? 0) > 0, (v.fileSize ?? Int.max) <= maxBytes else {
                        throw CocoaError(.fileReadNoPermission)
                    }
                    try IPATweakLibrary.copyValidated(readable, to: target)
                } catch { copyError = error }
            }
            if let error = coordinatorError ?? (copyError as NSError?) { throw error }
            return target
        } catch { MirsaManagedTmp.end(session); throw error }
    }
    static func remove(_ url: URL) { MirsaManagedTmp.end(url.deletingLastPathComponent()) }
}

/// All draft writes occur on the main actor, with open editors flushed before each transaction.
@MainActor
enum ProjectAttachmentStore {
    struct Signature: Equatable, Sendable { let identity: String; let hash: String }
    static func draft(_ app: PersonalLibraryApp, library: PersonalAppsLibrary = .shared) throws -> PersonalProjectDraft {
        let file = library.draftURL(app)
        if FileManager.default.fileExists(atPath: file.path) {
            return try JSONDecoder().decode(PersonalProjectDraft.self, from: Data(contentsOf: file))
        }
        return PersonalProjectDraft(name: app.name, bundleID: app.bundleID, version: app.version,
                                    outputFilename: app.name.replacingOccurrences(of: "/", with: "-") + "-signed")
    }
    static func components(_ draft: PersonalProjectDraft, items: [IPATweak]) -> [(IPATweak, String)] {
        let excluded = Set(draft.excludedRoots ?? [])
        var seen = Set<String>()
        return draft.tweakIDs.flatMap { id -> [(IPATweak, String)] in
            guard let item = items.first(where: { $0.id == id }) else { return [] }
            return item.roots.filter {
                let cid = IPATweakLibrary.componentID(item, $0)
                return !excluded.contains(cid) && seen.insert(cid).inserted
            }.map { (item, $0) }
        }
    }
    /// Hash complete resource-bearing framework trees, not just their executable.
    nonisolated static func signature(_ url: URL) throws -> Signature {
        let fm = FileManager.default
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey]
        let root = try url.resourceValues(forKeys: keys)
        guard root.isSymbolicLink != true else { throw CocoaError(.fileReadNoPermission) }
        var files = [url]
        if root.isDirectory == true {
            guard let walk = fm.enumerator(at: url, includingPropertiesForKeys: Array(keys)) else { throw CocoaError(.fileReadCorruptFile) }
            while let file = walk.nextObject() as? URL {
                guard files.count < 10_000, file.pathComponents.count - url.pathComponents.count <= 64 else { throw CocoaError(.fileReadTooLarge) }
                guard try file.resourceValues(forKeys: keys).isSymbolicLink != true else { throw CocoaError(.fileReadNoPermission) }
                files.append(file)
            }
        }
        var hash = SHA256(), total = 0
        for file in files.sorted(by: { $0.path < $1.path }) {
            try Task.checkCancellation()
            let v = try file.resourceValues(forKeys: keys)
            guard v.isSymbolicLink != true, v.isRegularFile == true || v.isDirectory == true else { throw CocoaError(.fileReadNoPermission) }
            if root.isDirectory == true {
                let relative = file == url ? "." : String(file.path.dropFirst(url.path.count + 1))
                hash.update(data: Data(relative.utf8)); hash.update(data: Data([0]))
            }
            if v.isRegularFile == true {
                let input = try FileHandle(forReadingFrom: file)
                defer { try? input.close() }
                var size = 0
                var fileHash = SHA256()
                while true {
                    try Task.checkCancellation()
                    let data = try input.read(upToCount: 65536) ?? Data()
                    if data.isEmpty { break }
                    size += data.count; total += data.count
                    guard size <= 128 * 1024 * 1024, total <= 256 * 1024 * 1024 else { throw CocoaError(.fileReadTooLarge) }
                    fileHash.update(data: data)
                }
                guard size == v.fileSize else { throw CocoaError(.fileReadCorruptFile) }
                hash.update(data: Data(fileHash.finalize()))
            }
        }
        return Signature(identity: url.lastPathComponent.precomposedStringWithCanonicalMapping.folding(options: [.caseInsensitive], locale: Locale(identifier: "en_US_POSIX")),
                         hash: hash.finalize().map { String(format: "%02x", $0) }.joined())
    }
    nonisolated static func merge(_ draft: PersonalProjectDraft, additions: [IPATweak], items: [IPATweak], root: URL = IPATweakLibrary.root) throws -> PersonalProjectDraft {
        var result = draft
        var known: [Signature] = try componentsForMerge(draft, items: items).map {
            try signature(root.appendingPathComponent($0.0.id.uuidString).appendingPathComponent($0.1))
        }
        for item in additions {
            // The same stored item is already selected. Do not exclude its own roots.
            if result.tweakIDs.contains(item.id) { continue }
            var accepted = false
            for relative in item.roots {
                let candidate = try signature(root.appendingPathComponent(item.id.uuidString).appendingPathComponent(relative))
                if known.contains(candidate) { // Exact duplicate must not be reintroduced by a package reference.
                    var excluded = result.excludedRoots ?? []
                    let cid = item.id.uuidString + ":" + relative
                    if !excluded.contains(cid) { excluded.append(cid) }
                    result.excludedRoots = excluded
                    continue
                }
                guard !known.contains(where: { $0.identity == candidate.identity }) else { throw SideloadError.message(OpenInAttachmentText.collision) }
                known.append(candidate); accepted = true
            }
            if accepted && !result.tweakIDs.contains(item.id) { result.tweakIDs.append(item.id) }
        }
        return result
    }
    // Pure helper also callable from the background hashing task.
    nonisolated private static func componentsForMerge(_ draft: PersonalProjectDraft, items: [IPATweak]) -> [(IPATweak, String)] {
        let excluded = Set(draft.excludedRoots ?? [])
        return draft.tweakIDs.flatMap { id in
            (items.first { $0.id == id }).map { item in
                item.roots.filter { !excluded.contains(item.id.uuidString + ":" + $0) }.map { (item, $0) }
            } ?? []
        }
    }
    static func attach(_ additions: [IPATweak], to app: PersonalLibraryApp) async throws {
        let library = PersonalAppsLibrary.shared
        guard library.loadError == nil, library.apps.contains(where: { $0.id == app.id }),
              !(PersonalSigningOperation.shared.running && PersonalSigningOperation.shared.state?.projectID == app.id) else {
            throw CocoaError(.fileWriteNoPermission)
        }
        try PersonalProjectDraftWriter.flushAll()
        let before = try draft(app)
        let items = IPATweakLibrary.shared.items
        let merged = try await Task.detached(priority: .userInitiated) { try merge(before, additions: additions, items: items) }.value
        try Task.checkCancellation()
        // Revalidate after asynchronous hashing. Never overwrite concurrent editor changes.
        try PersonalProjectDraftWriter.flushAll()
        guard try draft(app) == before, library.apps.contains(where: { $0.id == app.id }),
              !(PersonalSigningOperation.shared.running && PersonalSigningOperation.shared.state?.projectID == app.id) else {
            throw CocoaError(.fileWriteNoPermission)
        }
        try JSONEncoder().encode(merged).write(to: library.draftURL(app), options: [.atomic, .completeFileProtection])
        NotificationCenter.default.post(name: .mirsaProjectAttached, object: app.id)
    }
}

extension Notification.Name { static let mirsaProjectAttached = Notification.Name("mirsa.project.attached") }

/// Scene-level queue. Provider access is acquired BEFORE the first async boundary.
/// UIKit presents above an existing modal without dismissing its edits or resetting navigation.
@MainActor
final class OpenInProjectCoordinator: NSObject, ObservableObject, UIAdaptivePresentationControllerDelegate {
    static let shared = OpenInProjectCoordinator()
    struct Input: Identifiable { let id = UUID(); let file: URL?; let name: String; let error: String?; let source: URL }
    private var queue: [Input] = []
    private var sources = Set<URL>()
    private var pendingBytes = 0
    private weak var anchor: UIViewController?
    private weak var presented: UIViewController?
    private var active: Input?
    func register(_ controller: UIViewController) { anchor = controller; presentNext() }
    func receive(_ urls: [URL]) {
        for url in urls where OpenInTweak.accepts(url) {
            let source = url.standardizedFileURL
            guard sources.count < 16, sources.insert(source).inserted else { continue }
            let scope = url.startAccessingSecurityScopedResource()
            // File-provider metadata is read while access is held. Unknown sizes
            // reserve the full per-file limit; copying cannot exceed its reservation.
            let hint = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 128 * 1024 * 1024
            let reservation = max(1, min(hint, 128 * 1024 * 1024))
            guard pendingBytes + reservation <= 256 * 1024 * 1024 else {
                if scope { url.stopAccessingSecurityScopedResource() }
                queue.append(Input(file: nil, name: url.lastPathComponent, error: IPATweakImportText.error("limits"), source: source))
                presentNext()
                continue
            }
            pendingBytes += reservation
            Task {
                defer { if scope { url.stopAccessingSecurityScopedResource() } }
                do {
                    let file = try await Task.detached(priority: .userInitiated) { try OpenInTweak.snapshot(url, maxBytes: reservation) }.value
                    let size = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                    pendingBytes += size - reservation
                    queue.append(Input(file: file, name: url.lastPathComponent, error: nil, source: source))
                } catch {
                    pendingBytes -= reservation
                    queue.append(Input(file: nil, name: url.lastPathComponent, error: OpenInAttachmentText.failed, source: source))
                }
                presentNext()
            }
        }
    }
    func presentNext() {
        guard active == nil, !queue.isEmpty, let anchor, anchor.viewIfLoaded?.window != nil,
              anchor.view.window?.windowScene?.activationState == .foregroundActive else { return }
        var top = anchor.view.window?.rootViewController ?? anchor
        while let next = top.presentedViewController { top = next }
        if top.isBeingDismissed || top.isBeingPresented {
            top.transitionCoordinator?.animate(alongsideTransition: nil) { [weak self] _ in self?.presentNext() }
            return
        }
        let input = queue.removeFirst(); active = input
        let host = UIHostingController(rootView: OpenInProjectAttachmentSheet(input: input) { [weak self] in self?.finish() })
        host.modalPresentationStyle = .pageSheet
        host.sheetPresentationController?.detents = [.medium(), .large()]
        host.sheetPresentationController?.prefersGrabberVisible = true
        host.presentationController?.delegate = self
        presented = host
        top.present(host, animated: true)
    }
    func finish() {
        guard let controller = presented else { clean(); return }
        controller.dismiss(animated: true) { [weak self] in self?.clean() }
    }
    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) { clean() }
    private func clean() {
        if let input = active {
            if let file = input.file {
                pendingBytes -= (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                OpenInTweak.remove(file)
            }
            sources.remove(input.source)
        }
        presented = nil; active = nil; presentNext()
    }
}

struct OpenInProjectPresenter: UIViewControllerRepresentable {
    final class Anchor: UIViewController {
        override func viewDidAppear(_ animated: Bool) { super.viewDidAppear(animated); OpenInProjectCoordinator.shared.register(self) }
    }
    func makeUIViewController(context: Context) -> Anchor { Anchor() }
    func updateUIViewController(_ controller: Anchor, context: Context) { OpenInProjectCoordinator.shared.register(controller) }
}

struct OpenInProjectAttachmentSheet: View {
    let input: OpenInProjectCoordinator.Input
    let finish: () -> Void
    @StateObject private var library = PersonalAppsLibrary.shared
    @StateObject private var tweaks = IPATweakLibrary.shared
    @State private var selected = Set<UUID>()
    @State private var drafts: [UUID: PersonalProjectDraft] = [:]
    @State private var busy = false
    @State private var message: String?
    @State private var operation: Task<Void, Never>?
    @State private var completed = Set<UUID>()
    @State private var imported: IPATweak?
    @State private var ownsImporter = false
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(OpenInAttachmentText.title).font(.headline)
                        Text(input.name).font(.subheadline).textSelection(.enabled)
                        Text(OpenInAttachmentText.help).font(.caption).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(16).appsGlass(cornerRadius: 18)
                    if let message = message ?? input.error { Text(message).foregroundStyle(.orange).accessibilityIdentifier("mirsa.attach.error") }
                    if let error = library.loadError { Text(error).foregroundStyle(.orange) }
                    if library.apps.isEmpty { Text(OpenInAttachmentText.empty) }
                    ForEach(library.apps) { app in
                        let draft = drafts[app.id]
                        Button {
                            if selected.contains(app.id) { selected.remove(app.id) } else { selected.insert(app.id) }
                        } label: {
                            HStack(alignment: .top, spacing: 12) {
                                Group {
                                    if let icon = library.icon(for: app) { Image(uiImage: icon).resizable().scaledToFill() }
                                    else { Image(systemName: "app.dashed").resizable().scaledToFit().padding(10) }
                                }.frame(width: 48, height: 48).clipShape(RoundedRectangle(cornerRadius: 12))
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(draft?.name ?? app.name).font(.headline)
                                    Text(draft?.bundleID ?? app.bundleID).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                                    Text("v" + (draft?.version ?? app.version)).font(.caption)
                                    Text(OpenInAttachmentText.count(draft.map { ProjectAttachmentStore.components($0, items: tweaks.items).count } ?? 0)).font(.caption)
                                }.frame(maxWidth: .infinity, alignment: .leading)
                                Image(systemName: completed.contains(app.id) ? "checkmark.seal.fill" : selected.contains(app.id) ? "checkmark.circle.fill" : "circle").font(.title3)
                            }.padding(14).frame(maxWidth: .infinity, alignment: .leading).appsGlass(cornerRadius: 18)
                        }.buttonStyle(.plain)
                        .disabled(busy || completed.contains(app.id) || (PersonalSigningOperation.shared.running && PersonalSigningOperation.shared.state?.projectID == app.id))
                        .accessibilityIdentifier("mirsa.attach.project." + app.id.uuidString)
                        .accessibilityAddTraits(selected.contains(app.id) ? .isSelected : [])
                    }
                    if busy { ProgressView().accessibilityIdentifier("mirsa.attach.progress") }
                }.padding(16)
            }
            .background(MirsaPalette.sheet)
            .navigationTitle(OpenInAttachmentText.title).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(OpenInAttachmentText.cancel) {
                        operation?.cancel()
                        if ownsImporter { tweaks.cancelImport() }
                        if !busy { discardUnattached(); finish() }
                    }
                        .accessibilityIdentifier("mirsa.attach.cancel")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(OpenInAttachmentText.importTitle) { start() }
                        .disabled(busy || tweaks.importing || library.loadError != nil || selected.subtracting(completed).isEmpty || input.file == nil || drafts.count != library.apps.count)
                        .accessibilityIdentifier("mirsa.attach.import")
                }
            }
        }
        .preferredColorScheme(.dark).environment(\.layoutDirection, .leftToRight)
        .interactiveDismissDisabled(busy)
        .sheet(item: Binding(get: { ownsImporter ? tweaks.pendingImport : nil }, set: { if ownsImporter { tweaks.pendingImport = $0 } }), onDismiss: { if ownsImporter { tweaks.finishImportSelection(nil) } }) { choice in
            IPATweakImportSelectionView(choice: choice) { tweaks.finishImportSelection($0) }
        }
        .task { refresh() }
        .onReceive(NotificationCenter.default.publisher(for: .mirsaProjectAttached)) { _ in refresh() }
        .onDisappear { if !busy { discardUnattached() } }
    }
    private func discardUnattached() {
        if completed.isEmpty, let item = imported { try? tweaks.delete(item); imported = nil }
    }
    private func refresh() {
        do {
            try PersonalProjectDraftWriter.flushAll()
            drafts = try Dictionary(uniqueKeysWithValues: library.apps.map { ($0.id, try ProjectAttachmentStore.draft($0)) })
        } catch { message = OpenInAttachmentText.failed }
    }
    private func start() {
        guard let file = input.file, !busy, !tweaks.importing else { return }
        busy = true; message = nil
        let targets = library.apps.filter { selected.contains($0.id) && !completed.contains($0.id) }
        operation = Task {
            defer { busy = false; operation = nil; ownsImporter = false }
            do {
                let item: IPATweak
                if let previous = imported { item = previous }
                else {
                    ownsImporter = true
                    item = try await tweaks.addFile(file, allowSelection: true)
                    ownsImporter = false
                    imported = item
                }
                var failures: [String] = []
                for app in targets {
                    try Task.checkCancellation()
                    do { try await ProjectAttachmentStore.attach([item], to: app); completed.insert(app.id) }
                    catch is CancellationError { throw CancellationError() }
                    catch { failures.append(app.name + "\n" + error.localizedDescription) }
                }
                refresh()
                if failures.isEmpty { finish() } else { message = failures.joined(separator: "\n\n") }
            } catch is CancellationError {
                discardUnattached()
                finish()
            } catch { message = error.localizedDescription }
        }
    }
}
