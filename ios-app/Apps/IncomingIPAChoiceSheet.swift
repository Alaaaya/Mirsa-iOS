import SwiftUI

/// Every external IPA opens the original choice screen, not the details screen.
/// importIPA owns a private work directory before any action can be selected.
struct IncomingIPAChoiceSheet: View {
    let url: URL
    @ObservedObject var store: AppsStore
    let vm: AppViewModel
    let onFinish: () -> Void
    @State private var prepared = false
    @State private var completing = false
    @State private var failure: String?

    var body: some View {
        Group {
            if prepared, let pending = store.pending {
                InstallChoiceSheet(pending: pending, store: store, onPersonal: {
                    Task { @MainActor in
                        do {
                            // Use current pending after edits, not the original snapshot.
                            guard let current = store.pending else { return }
                            try await PersonalAppsLibrary.shared.add(current.originalIPA, signed: false)
                            completing = true
                            store.cancelPending()
                            vm.selectedTab = .personalHub
                            onFinish()
                        } catch { store.error = error.localizedDescription }
                    }
                }) { location in
                    Task { @MainActor in
                        completing = true
                        await store.commitPending(to: location, vm: vm)
                        if let error = store.error { vm.errorMessage = error }
                        onFinish()
                    }
                }
            } else {
                ZStack {
                    AuroraBackground()
                    VStack(spacing: 18) {
                        if let failure {
                            Text(failure).foregroundStyle(.orange)
                            Button(L.t("choice.cancel"), action: onFinish)
                        } else { ProgressView(L.t("busy.importing")).tint(.white) }
                    }.padding(24)
                }
            }
        }
        .environment(\.layoutDirection, .leftToRight)
        .preferredColorScheme(.dark)
        .interactiveDismissDisabled(store.busy != nil)
        .onChange(of: store.pending?.id) { _, id in
            // Cancel and successful certificate install also close this owner sheet.
            if prepared && !completing && id == nil { onFinish() }
        }
        .task {
            guard !prepared else { return }
            guard store.busy == nil, store.pending == nil, !store.explicitIncomingInstall else {
                failure = tr("Finish the current import first.", "خلّص الاستيراد الحالي أولاً.")
                return
            }
            store.explicitIncomingInstall = true
            store.error = nil
            await store.importIPA(from: url)
            if store.pending != nil { prepared = true }
            else { failure = store.error }
        }
    }
}
