import SwiftUI

/// Lists positively identified custom wallpapers (Mirsa, Placard, Probe) with per-item delete; unknown/Apple items are hidden.
/// Nothing here runs on appear except a read-only listing.
struct MirsaWallpaperManagementSection: View {
    let externalBusy: Bool
    let log: (String) -> Void
    /// Called on main only after a current-session owned delete succeeded.
    let onDeleted: () -> Void

    @State private var items: [MirsaCustomWallpapers.Item] = []
    @State private var busy = false
    @State private var pendingDelete: MirsaCustomWallpapers.Item?
    @State private var confirmCleanup = false
    @State private var message: String?
    @State private var failed = false

    private func t(_ k: MirsaWallpaperActionStrings.Key) -> String { MirsaWallpaperActionStrings.text(k) }
    private var disabled: Bool { busy || externalBusy }

    var body: some View {
        Section {
            if items.isEmpty {
                Text(t(.ownedEmpty)).font(.subheadline).foregroundColor(.secondary)
            }
            ForEach(items) { rec in
                HStack(spacing: 10) {
                    if let data = rec.thumbnail, let img = UIImage(data: data) {
                        Image(uiImage: img).resizable().scaledToFill()
                            .frame(width: 32, height: 44).clipShape(RoundedRectangle(cornerRadius: 6))
                    } else {
                        Image(systemName: "photo.on.rectangle").foregroundColor(.secondary)
                            .frame(width: 32, height: 44)
                    }
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
        } message: { Text(pendingDelete.map { "“" + ($0.title.isEmpty ? $0.id : $0.title) + "”\n\n" } .map { $0 + t(.deleteBody) } ?? t(.deleteBody)) }
        .alert(t(.cleanupTitle), isPresented: $confirmCleanup) {
            Button(t(.cleanupConfirm)) { cleanup() }
            Button(t(.cancel), role: .cancel) {}
        } message: { Text(t(.cleanupBody)) }
    }

    private func reload() {
        guard !busy else { return }
        busy = true
        Task.detached {
            let lines = LogBox()
            var found: [MirsaCustomWallpapers.Item] = []
            var err: Error?
            do { found = try MirsaCustomWallpapers.list(log: { lines.add($0) }) } catch { err = error }
            let out = lines.all
            await MainActor.run {
                out.forEach(log)
                busy = false
                if let err { report(err, "") } else { items = found; failed = false }
            }
        }
    }

    private func report(_ error: Error, _ prefix: String) {
        failed = true
        message = t(.failedPrefix) + error.localizedDescription
        log("MANAGEMENT ERROR " + error.localizedDescription)
    }

    private func delete(_ rec: MirsaCustomWallpapers.Item) {
        guard !disabled else { return }
        busy = true; message = nil
        Task.detached {
            let lines = LogBox()
            var err: Error?
            do { try MirsaCustomWallpapers.delete(rec, log: { lines.add($0) }) } catch { err = error }
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
