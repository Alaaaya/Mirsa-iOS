//
//  TendiesView.swift
//  AirCard-iOS
//
//  Dedicated UI for importing, previewing, and flashing PosterBoard .tendies wallpapers.
//  Unified Form design matching Passcode Theme and Wallet Cards tabs.
//

import SwiftUI
import UniformTypeIdentifiers

struct TendiesView: View {
    @EnvironmentObject var vm: AppViewModel
    @State private var showFilePicker = false
    @State private var showCustomRequest = false
    @StateObject private var customRequest = WallpaperRequestDraft()
    @ObservedObject private var chatStore = ForgeChatStore.shared
    @ObservedObject private var chatLocal = ForgeChatLocal.shared
    private var requestUnread: Int { chatLocal.unreadCount(chatStore.threads) }
    @State private var selectedDetailItem: TendieItem? = nil
    // One presenter owns install and respring. Separate chained alerts can
    // dismiss each other when published copy/list state changes.
    private enum WallpaperPrompt: String, Identifiable {
        case install, respring
        var id: String { rawValue }
    }
    @State private var wallpaperPrompt: WallpaperPrompt?
    @StateObject private var respringPresentation = MirsaWallpaperRespringPresentation()
    /// Explicit confirmation gate shared by successful copy/delete and the standalone action.
    @State private var respringArmed = false
    @State private var installStartedThisSession = false
    private func ws(_ k: MirsaWallpaperActionStrings.Key) -> String { MirsaWallpaperActionStrings.text(k) }
    @State private var makerDescriptionFocused = false

    private var videoApplyRunning: Bool {
        if case .running = vm.tendiesFlashPhase { return true }
        return false
    }

    /// Specific localized cause for a failed install (journal exists / incomplete install), so the generic banner is not all the user sees.
    private var journalCause: String? {
        guard case .done(ok: false) = vm.tendiesFlashPhase else { return nil }
        for line in vm.tendiesFlashLog.reversed() {
            let mapped = MirsaWallpaperActionStrings.localizedError(line)
            if mapped != line { return mapped }
        }
        return nil
    }

    private var selectedCount: Int {
        vm.tendieItems.filter { $0.isSelected }.count
    }

    private var selectedAll: Bool {
        !vm.tendieItems.isEmpty && vm.tendieItems.allSatisfy { $0.isSelected }
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { scroll in
            MirsaForm {
                // Notice Banners
                if let err = vm.errorMessage {
                    Section {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.red)
                            Text(journalCause ?? err)
                                .font(.caption)
                                .foregroundColor(.red)
                            Spacer()
                            Button {
                                vm.errorMessage = nil
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }

                // Two primary actions side by side.
                Section {
                    HStack(spacing: 10) {
                        if case .running = vm.tendiesFlashPhase {
                            HStack(spacing: 8) {
                                ProgressView()
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(MirsaTr.lit("Flashing Wallpapers…")).font(.subheadline.bold())
                                    ProgressView(value: vm.tendiesFlashProgress)
                                }
                            }
                            .frame(maxWidth: .infinity)
                        } else {
                            Button { wallpaperPrompt = .install } label: {
                                Label(TendiesPageText.text(.install), systemImage: "sparkles")
                                    .font(.headline).lineLimit(2).minimumScaleFactor(0.8)
                                    .frame(maxWidth: .infinity, minHeight: 48)
                            }
                            .buttonStyle(.borderedProminent).tint(.blue)
                            .disabled(selectedCount == 0)
                            .accessibilityIdentifier("wallpaper-flash")
                        }
                        Button { showCustomRequest = true } label: {
                            Label(TendiesPageText.text(.request), systemImage: "sparkles.rectangle.stack")
                                .font(.headline).lineLimit(2).minimumScaleFactor(0.8)
                                .frame(maxWidth: .infinity, minHeight: 48)
                                .overlay(alignment: .topTrailing) {
                                    if requestUnread > 0 {
                                        Text(String(requestUnread)).font(.caption2.bold()).foregroundColor(.white)
                                            .padding(.horizontal, 6).padding(.vertical, 2)
                                            .background(Capsule().fill(Color.red))
                                            .offset(x: 6, y: -6)
                                            .accessibilityIdentifier("wallpaper-request-badge")
                                    }
                                }
                        }
                        .buttonStyle(.borderedProminent).tint(.indigo)
                        .disabled(videoApplyRunning)
                        .accessibilityIdentifier("wallpaper-request")
                    }
                    .listRowInsets(EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14))
                } footer: {
                    if !vm.tendiesSkippedTitles.isEmpty {
                        Text(TendiesPageText.skipped(vm.tendiesSkippedTitles))
                            .accessibilityIdentifier("wallpaper-skipped-note")
                    } else if case .done(ok: true) = vm.tendiesFlashPhase, !vm.tendiesInstalledNew {
                        Text(TendiesPageText.text(.nothingNew))
                    }
                }

                // Imported files waiting to be installed (selection for the install button).
                if !vm.tendieItems.isEmpty {
                    Section {
                        HStack {
                            Text(MirsaTr.p("wallpapersImported", vm.tendieItems.count))
                                .font(.caption.bold())
                                .foregroundColor(.secondary)
                            Spacer()
                            Button(WallpaperMakerStrings.text(selectedAll ? .deselectAll : .selectAll)) {
                                let target = !selectedAll
                                for i in 0..<vm.tendieItems.count {
                                    vm.tendieItems[i].isSelected = target
                                }
                            }
                            .font(.caption)
                        }
                        ForEach($vm.tendieItems) { $item in
                            TendieRowView(item: $item) {
                                selectedDetailItem = item
                            } onDelete: {
                                vm.deleteTendie(item: item)
                            }
                        }
                    } header: {
                        Text(TendiesPageText.text(.ready))
                    }
                }

                MirsaWallpaperManagementSection(
                    externalBusy: videoApplyRunning,
                    log: { vm.tendiesFlashLog.append($0) },
                    onDeleted: { offerRespring() },
                    extraTools: {
                        Button { showFilePicker = true } label: {
                            Label(WallpaperMakerStrings.text(vm.tendieItems.isEmpty ? .chooseTendies : .importMore), systemImage: "doc.badge.plus")
                        }
                        Text(WallpaperMakerStrings.text(.importHint)).font(.caption).foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(vm.posterBoardContainer.isEmpty
                             ? MirsaTr.lit("PosterBoard container will be auto-detected automatically on flash.")
                             : MirsaTr.lit("Target: PosterBoard container detected ✅"))
                            .font(.caption).foregroundColor(.secondary)
                        OriginalVideoWallpaperBlock(applyRunning: videoApplyRunning)
                        WallpaperMakerSection(applyRunning: videoApplyRunning) { archive in
                            await vm.importTendieFiles(urls: [archive])
                        }
                        Toggle(isOn: $vm.resetPBProtections) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(MirsaTr.lit("Force PosterBoard Cache Refresh")).font(.subheadline.weight(.medium))
                                Text(MirsaTr.lit("Resets file protections so iOS re-indexes wallpapers immediately"))
                                    .font(.caption2).foregroundColor(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        Button { offerRespring() } label: {
                            Label(ws(.respringConfirm), systemImage: "arrow.clockwise")
                        }
                        .disabled(videoApplyRunning || respringPresentation.isPresented)
                        .accessibilityIdentifier("wallpaper-respring")
                        Text(WallpaperMakerStrings.text(.respringHelp)).font(.caption).foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("wallpaper-flash-help")
                        if !vm.tendiesFlashLog.isEmpty {
                            CompactLogView(
                                title: "Flash Log (\(vm.tendiesFlashLog.count) lines)",
                                lines: vm.tendiesFlashLog,
                                onClear: { vm.tendiesFlashLog.removeAll() }
                            )
                            .accessibilityIdentifier("wallpaper-flash-log")
                        }
                    }
                )
            }
            // Bound the actual Form viewport, not just its scrollable content.
            // Classic/native tab bars and expanded Flash Log must not overlap actions.
            // A focused multiline input also needs clearance above the keyboard toolbar.
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Color.clear.frame(height: makerDescriptionFocused ? 56 : MirsaTabBarMetrics.clearance)
                    // Decorative clearance must not intercept taps on Form rows
                    // that SwiftUI scrolls into its transparent hosting region.
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .scrollDismissesKeyboard(.interactively)
            .onPreferenceChange(WallpaperMakerFocusKey.self) { makerDescriptionFocused = $0 }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidShowNotification)) { _ in
                guard makerDescriptionFocused else { return }
                // The keyboard toolbar is an extra obstruction. Center the complete
                // input in the reduced viewport instead of aligning to the keyboard edge.
                withAnimation { scroll.scrollTo("wallpaper-description-row", anchor: .center) }
            }
            .toolbarBackground(.visible, for: .navigationBar)
            .navigationTitle(TendiesSection.name)
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showFilePicker) {
                TendiesDocumentPickerView { urls in
                    Task {
                        await vm.importTendieFiles(urls: urls)
                    }
                }
            }
            .sheet(isPresented: $showCustomRequest) {
                WallpaperRequestView(draft: customRequest)
            }
            .sheet(item: $selectedDetailItem) { item in
                TendieDetailSheet(item: item)
            }
            .alert(item: $wallpaperPrompt) { prompt in
                switch prompt {
                case .install:
                    return Alert(title: Text(ws(.installTitle)), message: Text(ws(.installBody)),
                                 primaryButton: .default(Text(ws(.installConfirm))) {
                                     vm.errorMessage = nil
                                     installStartedThisSession = true
                                     Task { await vm.flashSelectedTendies() }
                                 },
                                 secondaryButton: .cancel(Text(ws(.cancel))))
                case .respring:
                    return Alert(title: Text(ws(.respringTitle)), message: Text(ws(.respringBody)),
                                 primaryButton: .destructive(Text(ws(.respringConfirm))) {
                                     vm.tendiesFlashLog.append("REFRESH TAP restart confirmation")
                                     let ok = respringArmed
                                     respringArmed = false
                                     if ok {
                                         wallpaperPrompt = nil
                                         respringPresentation.start { vm.tendiesFlashLog.append($0) }
                                     }
                                 },
                                 secondaryButton: .cancel(Text(ws(.respringLater))) {
                                     vm.tendiesFlashLog.append("REFRESH declined by user; no restart requested.")
                                     respringArmed = false
                                 })
                }
            }
            .onChange(of: vm.tendiesFlashPhase) { _, phase in
                // Only a copy that finished successfully in this session offers a respring.
                if installStartedThisSession, vm.tendiesInstalledNew, case .done(ok: true) = phase {
                    installStartedThisSession = false
                    offerRespring()
                } else if case .done = phase { installStartedThisSession = false }
            }
            .onAppear {
                vm.showSuccessAlert = false
                vm.successAlertMessage = ""
                vm.scanDocumentsForTendies()
                #if DEBUG
                if MirsaUITestHarness.active && ProcessInfo.processInfo.arguments.contains("-MirsaWallpaperFlashLogFixture") {
                    // Layout-only data. Never select, save, apply or respring a fixture.
                    vm.tendieItems = [TendieItem(name: "Layout fixture", fileName: "layout-fixture.tendies",
                                               relativePath: "layout-fixture.tendies", posterType: .suggestedPhotos,
                                               isSelected: false)]
                    vm.tendiesFlashLog = (1...24).map { "Layout fixture log line \($0), no device action performed." }
                }
                #endif
            }
            .task {
                if vm.posterBoardContainer.isEmpty {
                    await vm.autoDetectPosterBoardContainer(silent: true)
                }
            }
            } // ScrollViewReader
        }
        // Same presentation and lifetime as the proven PB Probe v26 path.
        // The confirmed action immediately sets one retained model flag. No
        // delayed Task or lazy Form overlay can cancel/drop the WebKit mount.
        .fullScreenCover(isPresented: $respringPresentation.isPresented, onDismiss: {
            let line = "REFRESH AFTER cover dismissed · system respring and picker visibility require device confirmation"
            MirsaWallpaperEvidence.record(line)
            vm.tendiesFlashLog.append(line)
        }) {
            ZStack(alignment: .topTrailing) {
                MirsaWallpaperRespringView(event: { line in
                    MirsaWallpaperEvidence.record(line)
                    vm.tendiesFlashLog.append(line)
                }).ignoresSafeArea()
                Button(ws(.cancel)) { respringPresentation.isPresented = false }
                    .padding().background(.black.opacity(0.8)).foregroundStyle(.white)
            }.interactiveDismissDisabled()
        }
    }

    private func offerRespring() {
        guard !videoApplyRunning, !respringPresentation.isPresented else { return }
        respringArmed = true
        vm.tendiesFlashLog.append("REFRESH PROMPT offered; awaiting explicit restart or not-now choice.")
        wallpaperPrompt = .respring
    }
}

// MARK: - Tendie Row View

struct TendieRowView: View {
    @Binding var item: TendieItem
    let onInspect: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Toggle("", isOn: $item.isSelected)
                .labelsHidden()

            if let imgData = item.previewImageData, let uiImg = UIImage(data: imgData) {
                Image(uiImage: uiImg)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 44, height: 60)
                    .cornerRadius(6)
                    .clipped()
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(UIColor.tertiarySystemFill))
                    .frame(width: 44, height: 60)
                    .overlay {
                        Image(systemName: item.posterType.systemIcon)
                            .foregroundColor(.secondary)
                    }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(item.name)
                    .font(.subheadline.bold())
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text(item.posterType.displayName)
                        .font(.caption2.bold())
                        .foregroundColor(item.posterType.badgeColor)

                    Text("•")
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    Text(MirsaTr.p("items", item.descriptorCount))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            Button {
                onInspect()
            } label: {
                Image(systemName: "info.circle")
                    .foregroundColor(.blue)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)

            Button(role: .destructive) {
                onDelete()
            } label: {
                Image(systemName: "trash")
                    .foregroundColor(.red)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Tendie Detail Sheet

struct TendieDetailSheet: View {
    let item: TendieItem
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if let imgData = item.previewImageData, let uiImg = UIImage(data: imgData) {
                        Image(uiImage: uiImg)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: .infinity, maxHeight: 300)
                            .cornerRadius(12)
                            .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
                            .listRowBackground(Color.clear)
                    }
                }

                Section(MirsaTr.lit("Information")) {
                    detailRow(title: "Name", value: item.name)
                    detailRow(title: "File Name", value: item.fileName)
                    detailRow(title: "Type", value: item.posterType.displayName)
                    detailRow(title: "Descriptors", value: "\(item.descriptorCount)")
                    detailRow(title: "Target Extension", value: item.posterType.extensionBundleId)
                    detailRow(title: "Format", value: item.isContainer ? "App Container" : "Descriptor Archive")
                    if item.unsafeContainer {
                        detailRow(title: "Warning", value: "Contains SQLite database")
                    }
                }
            }
            .navigationTitle(item.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(MirsaTr.lit("Done")) {
                        dismiss()
                    }
                }
            }
        }
    }

    private func detailRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline.bold())
                .foregroundColor(.primary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}

// MARK: - Tendies Document Picker

struct TendiesDocumentPickerView: UIViewControllerRepresentable {
    let onPick: ([URL]) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        var contentTypes: [UTType] = []
        if let customType = UTType("com.aircard.tendies") {
            contentTypes.append(customType)
        }
        if let extType = UTType(filenameExtension: "tendies") {
            contentTypes.append(extType)
        }
        contentTypes.append(contentsOf: [.archive, .zip, .data, .item])

        // asCopy: true ensures iOS safely copies documents into app sandbox tmp directory
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: contentTypes, asCopy: true)
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = true
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: TendiesDocumentPickerView

        init(_ parent: TendiesDocumentPickerView) {
            self.parent = parent
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard !urls.isEmpty else { return }
            parent.onPick(urls)
            parent.dismiss()
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            parent.dismiss()
        }
    }
}
