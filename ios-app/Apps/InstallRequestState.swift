import SwiftUI

/// One request, identified by what the user actually asked for (a URL, an entry, "self"),
/// never by a bundle ID that a source feed could forge.
struct InstallRequest: Equatable, Identifiable {
    enum Phase: Equatable { case downloading, preparing, installing }
    let id = UUID()
    let key: String
    var phase: Phase = .downloading
    /// Real byte fraction only. nil means unknown length and the UI shows a spinner.
    var fraction: Double?
    var canCancel = false
    var cancellable: Bool { phase == .downloading && canCancel }
    static func == (a: InstallRequest, b: InstallRequest) -> Bool {
        a.id == b.id && a.phase == b.phase && a.fraction == b.fraction
    }
}

@MainActor
final class InstallTracker: ObservableObject {
    static let shared = InstallTracker()
    @Published private(set) var current: InstallRequest?
    private var cancelAction: (() -> Void)?

    static func urlKey(_ url: URL) -> String { "url:" + url.absoluteString }

    /// Returns a token, or nil when another request already owns the tracker (nested calls).
    func begin(key: String, phase: InstallRequest.Phase = .downloading, cancel: (() -> Void)? = nil) -> UUID? {
        guard current == nil else { return nil }
        var request = InstallRequest(key: key, phase: phase, fraction: nil)
        request.canCancel = phase == .downloading && cancel != nil
        current = request
        cancelAction = phase == .downloading ? cancel : nil
        return request.id
    }

    func set(_ token: UUID?, phase: InstallRequest.Phase, fraction: Double? = nil, cancel: (() -> Void)? = nil) {
        guard let token, current?.id == token else { return }
        current?.phase = phase
        current?.fraction = fraction.map { min(1, max(0, $0)) }
        if phase != .downloading { cancelAction = nil; current?.canCancel = false } else if let cancel { cancelAction = cancel; current?.canCancel = true }
    }

    func end(_ token: UUID?) {
        guard let token, current?.id == token else { return }
        current = nil; cancelAction = nil
    }

    func isActive(_ key: String) -> Bool { current?.key == key }
    func request(for key: String) -> InstallRequest? { current?.key == key ? current : nil }

    /// Cancels only while the transfer itself is cancellable. Prepare/sign/install are never cancelled here.
    @discardableResult
    func cancelIfSupported(_ key: String) -> Bool {
        guard let r = request(for: key), r.cancellable, let cancelAction else { return false }
        cancelAction(); return true
    }
}

/// Inline replacement for an install button's label, driven by one request key.
struct InstallKeyedLabel<Idle: View>: View {
    @ObservedObject private var tracker = InstallTracker.shared
    let key: String
    @ViewBuilder var idle: () -> Idle
    var body: some View {
        if let r = tracker.request(for: key) {
            SourceDownloadIndicator(fraction: r.fraction, phase: r.phase, cancellable: r.cancellable)
        } else { idle() }
    }
}
