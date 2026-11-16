import SwiftUI

/// Diagnostic build: journal rows keep strict deletion; unclassified rows are inspect-only.
/// Nothing here runs on appear except a read-only listing.
struct MirsaWallpaperManagementSection<Extra: View>: View {
    let externalBusy: Bool
    let log: (String) -> Void
    /// Called on main only after a current-session owned delete succeeded.
    let onDeleted: () -> Void
    /// Everything secondary from the page (import, video, maker, options, respring, log) lives in the same closed tools group.
    @ViewBuilder let extraTools: () -> Extra
    @State private var toolsOpen = false

    @State private var items: [MirsaCustomWallpapers.Item] = []
    @State private var busy = false
    @State private var thumbnailGeneration = UUID()
    @State private var pendingDelete: MirsaCustomWallpapers.Item?
    @State private var confirmCleanup = false
    @State private var message: String?
    @State private var failed = false
    @State private var journal: [MirsaWallpaperJournal.Record] = []
    @State private var pendingReconcile: MirsaWallpaperJournal.Record?
    @State private var presentRecord: MirsaWallpaperJournal.Record?
    @State private var pendingJournalDelete: MirsaWallpaperJournal.Record?

    private func t(_ k: MirsaWallpaperActionStrings.Key) -> String { MirsaWallpaperActionStrings.text(k) }
    private var disabled: Bool { busy || externalBusy }

    private func cardTitle(_ rec: MirsaCustomWallpapers.Item) -> String {
        rec.title.isEmpty ? MirsaWallpaperActionStrings.fallbackName(max(rec.fallbackIndex, 1)) : rec.title
    }

    private func thumb(_ rec: MirsaCustomWallpapers.Item) -> some View {
        Group {
            if let data = rec.thumbnail, let img = UIImage(data: data) {
                Image(uiImage: img).resizable().scaledToFill()
                    .frame(width: 44, height: 60).clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                RoundedRectangle(cornerRadius: 8).fill(Color(UIColor.tertiarySystemFill))
                    .frame(width: 44, height: 60)
                    .overlay { Image(systemName: "photo.on.rectangle").foregroundColor(.secondary) }
            }
        }
    }

    private func thumbnailTask(_ rec: MirsaCustomWallpapers.Item) -> some View {
        Color.clear.frame(width: 0, height: 0)
            .task(id: String(describing: thumbnailGeneration) + String(disabled)) {
                guard !disabled, rec.thumbnail == nil else { return }
                let generation = thumbnailGeneration
                let data = await MirsaCustomWallpapers.thumbnail(rec)
                guard !Task.isCancelled, generation == thumbnailGeneration,
                      let index = items.firstIndex(where: { $0.id == rec.id && $0.relative == rec.relative }) else { return }
                items[index].thumbnail = data
            }
    }

    var body: some View {
        Group {
            // Installed wallpapers: compact cards (thumbnail, name, current confirmed delete).
            Section {
                if !items.contains(where: { $0.canDelete }) {
                    Text(TendiesPageText.text(.yoursEmpty)).font(.subheadline).foregroundColor(.secondary)
                }
                ForEach(items.filter { $0.canDelete }) { rec in
                    HStack(spacing: 12) {
                        thumb(rec)
                        Text(cardTitle(rec)).font(.subheadline.bold()).lineLimit(2)
                        Spacer()
                        Button(role: .destructive) { pendingDelete = rec } label: {
                            Text(t(.deleteItem)).font(.caption.bold())
                        }
                        .buttonStyle(.bordered).tint(.red)
                        .disabled(disabled)
                    }
                    .background(thumbnailTask(rec))
                }
            } header: {
                Text(TendiesPageText.text(.yours))
            }

            // One closed tools group: nothing is removed, everything secondary lives here.
            Section {
                // Keep the header identifier on its own button. On iOS 26 a
                // DisclosureGroup identifier propagates into the expanded rows,
                // hiding their explicit control identifiers from accessibility.
                Button { withAnimation { toolsOpen.toggle() } } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(TendiesPageText.text(.tools)).font(.headline)
                            Text(TendiesPageText.text(.toolsHint)).font(.caption).foregroundColor(.secondary)
                        }
                        Spacer()
                        Image(systemName: toolsOpen ? "chevron.down" : "chevron.forward")
                            .font(.caption.bold()).foregroundColor(.secondary)
                    }.contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("wallpaper-tools")
                if toolsOpen {
                    extraTools()
                    ForEach(items.filter { !$0.canDelete }) { rec in
                        HStack(spacing: 10) {
                            thumb(rec)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(cardTitle(rec)).font(.subheadline.bold()).lineLimit(1)
                                Text(rec.id).font(.caption2.monospaced()).foregroundColor(.secondary).lineLimit(1)
                                Label(t(.unknownWarning), systemImage: "exclamationmark.triangle")
                                    .font(.caption2).foregroundColor(.orange)
                                    .fixedSize(horizontal: false, vertical: true)
                                Button { inspect(rec) } label: { Text(t(.inspect)).font(.caption.bold()) }
                                    .buttonStyle(.bordered).disabled(disabled)
                            }
                            Spacer()
                        }
                        .background(thumbnailTask(rec))
                    }
                    ForEach(items.filter { $0.canDelete }) { rec in
                        // Deletable rows keep their separate inspect action here too.
                        HStack {
                            Text(cardTitle(rec)).font(.caption).lineLimit(1)
                            Spacer()
                            Button { inspect(rec) } label: { Text(t(.inspect)).font(.caption.bold()) }
                                .buttonStyle(.bordered).disabled(disabled)
                        }
                    }
                    journalRows
                    Button { reload() } label: { Label(t(.refresh), systemImage: "arrow.clockwise") }
                        .disabled(disabled)
                    Button { confirmCleanup = true } label: { Label(t(.cleanup), systemImage: "sparkles") }
                        .disabled(disabled)
                    if busy { HStack { ProgressView(); Text(t(.busy)).font(.caption).foregroundColor(.secondary) } }
                    else if externalBusy { Text(t(.busy)).font(.caption).foregroundColor(.secondary) }
                    if let message {
                        Text(message).font(.caption).foregroundColor(failed ? .red : .secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(t(.ownedFooter))
                        Text(t(.importRemoveHint))
                    }.font(.caption2).foregroundColor(.secondary)
                }
            }
        }
        .onAppear { reload(); reloadJournal() }
        .onChange(of: externalBusy) { _, nowBusy in if !nowBusy { reload() } }
        .alert(t(.reconcileTitle), isPresented: Binding(get: { pendingReconcile != nil }, set: { if !$0 { pendingReconcile = nil } })) {
            Button(t(.reconcileConfirm)) { if let r = pendingReconcile { reconcile(r) }; pendingReconcile = nil }
            Button(t(.cancel), role: .cancel) { pendingReconcile = nil }
        } message: { Text(t(.reconcileBody)) }
        .alert(t(.reconcilePresentTitle), isPresented: Binding(get: { presentRecord != nil }, set: { if !$0 { presentRecord = nil } })) {
            Button(t(.deleteConfirm), role: .destructive) { pendingJournalDelete = presentRecord; presentRecord = nil }
            Button(t(.keepIt), role: .cancel) { presentRecord = nil }
        } message: { Text(t(.reconcilePresentBody)) }
        .alert(t(.deleteTitle), isPresented: Binding(get: { pendingJournalDelete != nil }, set: { if !$0 { pendingJournalDelete = nil } })) {
            Button(t(.deleteConfirm), role: .destructive) { if let r = pendingJournalDelete { deleteJournalItem(r) }; pendingJournalDelete = nil }
            Button(t(.cancel), role: .cancel) { pendingJournalDelete = nil }
        } message: { Text(t(.deleteBody)) }
        .alert(t(.deleteTitle), isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })) {
            Button(t(.deleteConfirm), role: .destructive) {
                if let rec = pendingDelete { delete(rec) }
                pendingDelete = nil
            }
            Button(t(.cancel), role: .cancel) { pendingDelete = nil }
        } message: { Text(pendingDelete.map { "“" + ($0.title.isEmpty ? $0.id : $0.title) + "”\n\n" } .map { $0 + t(.deleteBody) } ?? t(.deleteBody)) }
        .alert(t(.cleanupTitle), isPresented: $confirmCleanup) {
            Button(t(.cleanupConfirm)) { cleanup() }
            Button(t(.cancel), role: .cancel) {}
        } message: { Text(t(.cleanupBody)) }
    }

    @ViewBuilder private var journalRows: some View {
        Text(t(.journalTitle)).font(.footnote.bold()).padding(.top, 6)
        if journal.isEmpty {
            Text(t(.journalEmpty)).font(.caption).foregroundColor(.secondary)
        }
        ForEach(journal) { rec in
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(rec.title.isEmpty ? rec.id : rec.title).font(.subheadline.bold()).lineLimit(1)
                    Spacer()
                    Text(rec.copied ? t(.journalCopied) : t(.journalPending)).font(.caption2).foregroundColor(.secondary)
                }
                Text(rec.id).font(.caption2.monospaced()).foregroundColor(.secondary).lineLimit(1)
                Button { pendingReconcile = rec } label: { Text(t(.reconcile)).font(.caption.bold()) }
                    .buttonStyle(.bordered).disabled(disabled)
            }
        }
        Text(t(.journalFooter)).font(.caption2).foregroundColor(.secondary)
    }

    /// Runs blocking work off the main actor. busy stays set until the operation actually finishes,
    /// so a second operation can never start while a destructive one is still running and a late
    /// success is never discarded.
    private func run(_ work: @escaping @Sendable (LogBox) throws -> Void, done: @escaping (Error?) -> Void) {
        busy = true; message = nil
        Task.detached {
            let lines = LogBox()
            var err: Error?
            do { try work(lines) } catch { err = error }
            let out = lines.all
            await MainActor.run {
                out.forEach(log)
                busy = false
                done(err)
            }
        }
    }

    private func reloadJournal() {
        Task.detached {
            let recs = (try? MirsaWallpaperJournal.records()) ?? []
            await MainActor.run { journal = recs }
        }
    }

    private func reconcile(_ rec: MirsaWallpaperJournal.Record) {
        guard !disabled else { return }
        let box = StateBox()
        run({ lines in
            box.state = try MirsaWallpaperJournal.inspect(rec, log: { lines.add($0) })
            if box.state == .absent { try MirsaWallpaperJournal.archive(rec, log: { lines.add($0) }) }
        }, done: { err in
            reloadJournal()
            if let err { report(err, "") }
            else if box.state == .absent { failed = false; message = t(.reconcileClearedDone); reload() }
            else { failed = false; presentRecord = rec }
        })
    }

    private func deleteJournalItem(_ rec: MirsaWallpaperJournal.Record) {
        guard !disabled else { return }
        log("DELETE CONFIRMED by user for journal UUID " + rec.id)
        run({ lines in
            lines.add("DELETE IDENTITY CHECK exact journal UUID " + rec.id)
            try MirsaWallpaperJournal.delete(rec, log: { lines.add($0) })
        }, done: { err in
            reloadJournal(); reload()
            if let err { log("DELETE RESULT error " + err.localizedDescription); report(err, "") }
            else { log("DELETE RESULT success; offering respring"); failed = false; message = t(.deleteDone); onDeleted() }
        })
    }

    private func reload() {
        guard !busy, !externalBusy else { return }
        thumbnailGeneration = UUID()
        let box = ItemsBox()
        run({ lines in box.items = try MirsaCustomWallpapers.list(log: { lines.add($0) }) }, done: { err in
            reloadJournal()
            if let err { report(err, "") } else { items = box.items; failed = false }
        })
    }

    private func inspect(_ rec: MirsaCustomWallpapers.Item) {
        guard !disabled else { return }
        run({ lines in try MirsaWallpaperDiagnostics.inspect(rec, log: { lines.add($0) }) }, done: { err in
            if let err { report(err, "") }
            else { failed = false; message = t(.diagnosticDone) }
        })
    }

    private func report(_ error: Error, _ prefix: String) {
        failed = true
        message = t(.failedPrefix) + MirsaWallpaperActionStrings.localizedError(error.localizedDescription)
        log("MANAGEMENT ERROR " + error.localizedDescription)
    }

    private func delete(_ rec: MirsaCustomWallpapers.Item) {
        guard !disabled else { return }
        log("DELETE CONFIRMED by user for UUID " + rec.id)
        run({ lines in
            lines.add("DELETE IDENTITY CHECK exact journal UUID " + rec.id)
            try MirsaCustomWallpapers.delete(rec, log: { lines.add($0) })
        }, done: { err in
            reload()
            if let err { log("DELETE RESULT error " + err.localizedDescription); report(err, "") }
            else { log("DELETE RESULT success; offering respring"); failed = false; message = t(.deleteDone); onDeleted() }
        })
    }

    private func cleanup() {
        guard !disabled else { return }
        run({ lines in try MirsaWallpaperJournal.cleanup(log: { lines.add($0) }) }, done: { err in
            reloadJournal(); reload()
            if let err { report(err, "") }
            else { failed = false; message = t(.cleanupDone) }
        })
    }
}

private final class ItemsBox: @unchecked Sendable { var items: [MirsaCustomWallpapers.Item] = [] }
private final class StateBox: @unchecked Sendable { var state = MirsaWallpaperJournal.JournalState.present }
private final class LogBox: @unchecked Sendable {
    private let lock = NSLock()
    private var lines: [String] = []
    func add(_ s: String) { lock.lock(); lines.append(s); lock.unlock() }
    var all: [String] { lock.lock(); defer { lock.unlock() }; return lines }
}
