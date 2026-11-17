import SwiftUI

/// Existing one-time admin activation is checked by the server. No local boolean,
/// email, device ID or cached ForgePreciseStore.enabled is authorization.
@MainActor final class MirsaDiagnosticAccess: ObservableObject {
    @Published private(set) var allowed = false
    private var generation = UUID()
    private var binding: String?
    private let identity: () -> String?
    private let verify: () async -> Bool

    init(identity: (() -> String?)? = nil,
         verify: (() async -> Bool)? = nil) {
        self.identity = identity ?? Self.savedIdentity; self.verify = verify ?? Self.verifyAdmin
    }

    private static func credentials() -> ForgeFixCredentials? {
        guard let session = KeychainSessionStore().load(), session.expiresAt > Date(),
              let user = try? ForgeClient.fixUserID(session.accessToken) else { return nil }
        return try? ForgeClient.existingFixCredentials(bearer: session.accessToken, user: user)
    }
    static func savedIdentity() -> String? {
        guard let c = credentials() else { return nil }
        // Private transient binding only. Never published, logged or persisted.
        return c.accessToken + "|" + c.deviceID + "|" + c.deviceToken
    }
    static func verifyAdmin() async -> Bool {
        guard let c = credentials() else { return false }
        // Server verifies JWT plus opaque token hash plus exact user/device admin grant.
        return await ForgePreciseClient.capability(c)
    }
    func revoke() { generation = UUID(); binding = nil; allowed = false }
    func invalidateIfIdentityChanged() {
        if allowed && (identity() == nil || identity() != binding) { revoke() }
    }
    @discardableResult func refresh() async -> Bool {
        revoke() // loading and errors always render nothing
        let attempt = generation
        guard let current = identity() else { return false }
        let granted = await verify()
        guard attempt == generation, !Task.isCancelled,
              granted, identity() == current else { return false }
        binding = current; allowed = true
        return true
    }
    /// Clipboard, share, clear and inspection recheck the server at the actual action.
    /// The closure is deliberately synchronous: there is no post-check suspension gap.
    func perform(_ action: () -> Void) async {
        guard await refresh(), allowed else { return }
        action()
    }
}

/// Renders *nothing*, including no title/placeholder or action, until server approval.
/// Foreground mount/re-entry refresh; background/unmount/account changes revoke.
@MainActor struct MirsaOwnerDiagnostics<Content: View>: View {
    @ObservedObject private var access: MirsaDiagnosticAccess
    @Environment(\.scenePhase) private var scenePhase
    @State private var expanded = false
    @ViewBuilder var content: () -> Content
    init(access: MirsaDiagnosticAccess, @ViewBuilder content: @escaping () -> Content) {
        self.access = access
        self.content = content
    }

    private var title: String {
        switch AppLanguageStore.snapshot {
        case .arabic: return "التشخيص"
        case .german: return "Diagnose"
        case .sorani: return "پشکنین"
        case .kurmanji: return "Teşxîs"
        case .english: return "Diagnostics"
        }
    }
    var body: some View {
        Group {
            if access.allowed && scenePhase == .active {
                Section {
                    Button { expanded.toggle() } label: {
                        HStack {
                            Label(title, systemImage: "stethoscope")
                            Spacer()
                            Image(systemName: expanded ? "chevron.down" : "chevron.forward")
                        }.font(.subheadline)
                    }.buttonStyle(.plain).accessibilityIdentifier("owner-diagnostics")
                    if expanded { content().environmentObject(access) }
                }
            }
        }
        .onChange(of: access.allowed) { _, allowed in if !allowed { expanded = false } }
        .onChange(of: scenePhase) { _, phase in if phase != .active { expanded = false } }
    }
}

/// Attach to an always-present parent, NOT the empty, unauthorized Form section.
/// A hidden section cannot own the lifecycle that makes itself visible.
@MainActor struct MirsaDiagnosticAccessLifecycle: ViewModifier {
    @ObservedObject var access: MirsaDiagnosticAccess
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content
        .task(id: scenePhase) {
            access.revoke()
            guard scenePhase == .active else { return }
            _ = await access.refresh()
            // Keep observing even after an initial denial or a transient failure.
            var ticks = 0
            while !Task.isCancelled {
                do { try await Task.sleep(nanoseconds: 5_000_000_000) } catch { break }
                access.invalidateIfIdentityChanged(); ticks += 1
                if ticks == 12 { ticks = 0; _ = await access.refresh() }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .mirsaDiagnosticIdentityChanged).receive(on: RunLoop.main)) { _ in
            access.revoke()
            if scenePhase == .active { Task { await access.refresh() } }
        }
        .onDisappear { access.revoke() }
    }
}

extension Notification.Name {
    static let mirsaDiagnosticIdentityChanged = Notification.Name("mirsa.diagnostics.identity.changed")
}
