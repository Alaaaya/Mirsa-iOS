import SwiftUI

/// Lists wallpapers Mirsa itself installed (exact journal records) with per-item delete and cleanup.
/// Nothing here runs on appear except a read-only journal listing.
struct MirsaWallpaperManagementSection: View {
    let externalBusy: Bool
    let log: (String) -> Void
    /// Called on main only after a current-session owned delete succeeded.
    let onDeleted: () -> Void

    @State private var records: [MirsaWallpaperJournal.Record] = []
    @State private var busy = false
    @State private var pendingDelete: MirsaWallpaperJournal.Record?
    @State private var confirmCleanup = false
    @State private var message: String?
    @State private var failed = false

    private func t(_ k: MirsaWallpaperActionStrings.Key) -> String { MirsaWallpaperActionStrings.text(k) }
    private var disabled: Bool { busy || externalBusy }

    var body: some View {
        Section {
            if records.isEmpty {
                Text(t(.ownedEmpty)).font(.subheadline).foregroundColor(.secondary)
            }
            ForEach(records.filter { $0.copied }) { rec in
                HStack(spacing: 10) {
                    Image(systemName: "photo.on.rectangle").foregroundColor(.secondary)
                    Text(rec.title.isEmpty ? rec.id : rec.title).font(.subheadline.bold()).lineLimit(1)
                    Spacer()
                    Button(role: .destructive) { pendingDelete = rec } label: {
                        Text(t(.deleteItem)).font(.caption.bold())
                    }
                    .buttonStyle(.bordered).tint(.red)
                    .disabled(disabled)
                }
            }
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
        } header: {
            Text(t(.ownedTitle))
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text(t(.ownedFooter))
                Text(t(.importRemoveHint))
            }
        }
        .onAppear { reload() }
        .alert(t(.deleteTitle), isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })) {
            Button(t(.deleteConfirm), role: .destructive) {
                if let rec = pendingDelete { delete(rec) }
                pendingDelete = nil
            }
            Button(t(.cancel), role: .cancel) { pendingDelete = nil }
        } message: { Text(t(.deleteBody)) }
        .alert(t(.cleanupTitle), isPresented: $confirmCleanup) {
            Button(t(.cleanupConfirm)) { cleanup() }
            Button(t(.cancel), role: .cancel) {}
        } message: { Text(t(.cleanupBody)) }
    }

    private func reload() {
        do { records = try MirsaWallpaperJournal.records() }
        catch { report(error, "") }
    }

    private func report(_ error: Error, _ prefix: String) {
        failed = true
        message = t(.failedPrefix) + error.localizedDescription
        log("MANAGEMENT ERROR " + error.localizedDescription)
    }

    private func delete(_ rec: MirsaWallpaperJournal.Record) {
        guard !disabled else { return }
        busy = true; message = nil
        Task.detached {
            let lines = LogBox()
            var err: Error?
            do { try MirsaWallpaperJournal.delete(rec, log: { lines.add($0) }) } catch { err = error }
            let out = lines.all
            await MainActor.run {
                out.forEach(log)
                busy = false
                reload()
                if let err { report(err, "") }
                else { failed = false; message = t(.deleteDone); onDeleted() }
            }
        }
    }

    private func cleanup() {
        guard !disabled else { return }
        busy = true; message = nil
        Task.detached {
            let lines = LogBox()
            var err: Error?
            do { try MirsaWallpaperJournal.cleanup(log: { lines.add($0) }) } catch { err = error }
            let out = lines.all
            await MainActor.run {
                out.forEach(log)
                busy = false
                reload()
                if let err { report(err, "") }
                else { failed = false; message = t(.cleanupDone) }
            }
        }
    }
}

private final class LogBox: @unchecked Sendable {
    private let lock = NSLock()
    private var lines: [String] = []
    func add(_ s: String) { lock.lock(); lines.append(s); lock.unlock() }
    var all: [String] { lock.lock(); defer { lock.unlock() }; return lines }
}
