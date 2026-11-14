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
    @State private var selectedDetailItem: TendieItem? = nil
    @State private var isNeoSpringing = false
    @State private var makerDescriptionFocused = false

    private var videoApplyRunning: Bool {
        if case .running = vm.tendiesFlashPhase { return true }
        return false
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
                            Text(err)
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

                // Section 1: Import Wallpapers
                Section {
                    Button {
                        showFilePicker = true
                    } label: {
                        HStack(spacing: 8) {
                            Spacer()
                            Image(systemName: "doc.badge.plus")
                            Text(WallpaperMakerStrings.text(vm.tendieItems.isEmpty ? .chooseTendies : .importMore))
                            Spacer()
                        }
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 48)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)

                    WallpaperMakerSection(applyRunning: videoApplyRunning) { archive in
                        await vm.importTendieFiles(urls: [archive])
                    }
                } footer: {
                    if vm.posterBoardContainer.isEmpty {
                        Text(MirsaTr.lit("PosterBoard container will be auto-detected automatically on flash."))
                    } else {
                        Text(MirsaTr.lit("Target: PosterBoard container detected ✅"))
                    }
                }

                // Section 2: PosterBoard Options
                Section {
                    Toggle(isOn: $vm.resetPBProtections) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(MirsaTr.lit("Force PosterBoard Cache Refresh"))
                                .font(.subheadline.weight(.medium))
                            Text(MirsaTr.lit("Resets file protections so iOS re-indexes wallpapers immediately"))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                // Section 3: Wallpapers Gallery
                if !vm.tendieItems.isEmpty {
                    Section {
                        HStack {
                            Text(MirsaTr.p("wallpapersImported", vm.tendieItems.count))
                                .font(.caption.bold())
                                .foregroundColor(.secondary)
                            Spacer()
                            Button(selectedAll ? "Deselect All" : "Select All") {
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
                        Text(MirsaTr.lit("Wallpapers Gallery"))
                    }
                } else {
                    Section {
                        VStack(spacing: 10) {
                            Image(systemName: "photo.stack")
                                .font(.system(size: 32))
                                .foregroundColor(.secondary)
                            Text(MirsaTr.lit("No .tendies wallpapers loaded yet"))
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Text(WallpaperMakerStrings.text(.importHint))
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                    }
                }

                // Section 4: Flash Action & Respring
                Section {
                    VStack(spacing: 12) {
                        if case .running = vm.tendiesFlashPhase {
                            HStack(spacing: 10) {
                                ProgressView()
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(MirsaTr.lit("Flashing Wallpapers…")).font(.subheadline.bold())
                                    ProgressView(value: vm.tendiesFlashProgress)
                                }
                            }
                            .padding(.vertical, 4)
                        } else {
                            Button {
                                Task {
                                    await vm.flashSelectedTendies()
                                }
                            } label: {
                                HStack(spacing: 8) {
                                    Spacer()
                                    Image(systemName: "sparkles")
                                    Text(MirsaTr.p("flashWallpapers", selectedCount))
                                    Spacer()
                                }
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .frame(minHeight: 48)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.blue)
                            .disabled(selectedCount == 0)
                            .accessibilityIdentifier("wallpaper-flash")
                        }

                        Button(role: .destructive) {
                            vm.isNeoSpringing = true
                            isNeoSpringing = true
                            RespringHelper.triggerNeoSpring()
                        } label: {
                            HStack(spacing: 8) {
                                Spacer()
                                Image(systemName: "bolt.fill")
                                Text(MirsaTr.lit("Respring (NeoSpring)"))
                                Spacer()
                            }
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 48)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                        .accessibilityIdentifier("wallpaper-respring")
                    }
                    .listRowInsets(EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14))
                } footer: {
                    Text(MirsaTr.lit("Flashing will automatically trigger NeoSpring to respring the device and apply your new wallpapers."))
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("wallpaper-flash-help")
                }

                // Section 5: Flash Log (CompactLogView)
                if !vm.tendiesFlashLog.isEmpty {
                    Section {
                        CompactLogView(
                            title: "Flash Log (\(vm.tendiesFlashLog.count) lines)",
                            lines: vm.tendiesFlashLog,
                            onClear: { vm.tendiesFlashLog.removeAll() }
                        )
                    }
                }
            }
            // Keep the final controls inside the scrollable area above Mirsa's dock.
            // Unlike a fixed-height spacer, this also follows the shared dock metrics.
            .contentMargins(.bottom, MirsaTabBarMetrics.clearance, for: .scrollContent)
            .scrollDismissesKeyboard(.interactively)
            .onPreferenceChange(WallpaperMakerFocusKey.self) { makerDescriptionFocused = $0 }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidShowNotification)) { _ in
                guard makerDescriptionFocused else { return }
                // TextField scrolls only the caret into view. Center the whole multiline
                // row after the keyboard and its accessory toolbar finish changing size.
                withAnimation { scroll.scrollTo("wallpaper-description-row", anchor: .center) }
            }
            .toolbarBackground(.visible, for: .navigationBar)
            .navigationTitle(TendiesSection.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showFilePicker = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.headline)
                    }
                }
            }
            .sheet(isPresented: $showFilePicker) {
                TendiesDocumentPickerView { urls in
                    Task {
                        await vm.importTendieFiles(urls: urls)
                    }
                }
            }
            .sheet(item: $selectedDetailItem) { item in
                TendieDetailSheet(item: item)
            }
            .onAppear {
                vm.isNeoSpringing = false
                isNeoSpringing = false
                vm.showSuccessAlert = false
                vm.successAlertMessage = ""
                vm.scanDocumentsForTendies()
            }
            .task {
                if vm.posterBoardContainer.isEmpty {
                    await vm.autoDetectPosterBoardContainer(silent: true)
                }
            }
            .overlay {
                if isNeoSpringing || vm.isNeoSpringing {
                    ZStack {
                        Color.black.ignoresSafeArea()
                        NeoSpringView()
                            .brightness(-1.0)
                            .ignoresSafeArea()
                    }
                }
            }
            } // ScrollViewReader
        }
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
                    Text(item.posterType.rawValue)
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
                    detailRow(title: "Type", value: item.posterType.rawValue)
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
