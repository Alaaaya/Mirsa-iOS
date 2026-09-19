//
//  TendiesView.swift
//  AirCard-iOS
//
//  Dedicated UI for importing, previewing, and flashing PosterBoard .tendies wallpapers.
//

import SwiftUI
import UniformTypeIdentifiers

struct TendiesView: View {
    @EnvironmentObject var vm: AppViewModel
    @State private var showFilePicker = false
    @State private var selectedDetailItem: TendieItem? = nil
    @State private var showManualContainerEditor = false
    @State private var manualContainerInput = ""

    private let columns = [
        GridItem(.adaptive(minimum: 155, maximum: 200), spacing: 16)
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Header / Status Banner
                    containerConfigSection

                    // Wallpapers Gallery
                    gallerySection
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .background(Color(UIColor.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("Wallpapers")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showFilePicker = true
                    } label: {
                        Label("Import", systemImage: "plus.circle.fill")
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
            .alert("Edit PosterBoard Container", isPresented: $showManualContainerEditor) {
                TextField("/var/mobile/Containers/Data/Application/UUID", text: $manualContainerInput)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                Button("Save") {
                    vm.posterBoardContainer = manualContainerInput.trimmingCharacters(in: .whitespacesAndNewlines)
                    UserDefaults.standard.set(vm.posterBoardContainer, forKey: "aircard.posterboard_container")
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Specify the absolute path of the PosterBoard container data directory.")
            }
        }
    }

    // MARK: - Container Config Section

    private var containerConfigSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "folder.badge.gearshape")
                    .foregroundColor(.blue)
                    .font(.headline)
                Text("PosterBoard Container")
                    .font(.headline)
                Spacer()
                if vm.isDetectingContainer {
                    ProgressView()
                        .scaleEffect(0.8)
                } else {
                    Button("Auto-Detect") {
                        Task {
                            await vm.autoDetectPosterBoardContainer()
                        }
                    }
                    .font(.caption.bold())
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }

            if vm.posterBoardContainer.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                        .font(.caption)
                    Text("Container not detected. Connect LocalDevVPN and tap Auto-Detect.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else {
                HStack {
                    Text(vm.posterBoardContainer)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button {
                        manualContainerInput = vm.posterBoardContainer
                        showManualContainerEditor = true
                    } label: {
                        Image(systemName: "pencil")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color(UIColor.tertiarySystemFill))
                .cornerRadius(8)
            }

            Divider()

            Toggle(isOn: $vm.resetPBProtections) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Force PosterBoard Refresh")
                        .font(.subheadline.weight(.medium))
                    Text("Resets file protections so iOS re-indexes posters immediately")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .tint(.blue)
        }
        .padding(14)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(14)
    }

    // MARK: - Gallery Section

    private var gallerySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Imported Tendies")
                        .font(.title3.bold())
                    Text("\(vm.tendieItems.count) wallpapers available")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()

                if !vm.tendieItems.isEmpty {
                    Button(selectedAll ? "Deselect All" : "Select All") {
                        let target = !selectedAll
                        for i in 0..<vm.tendieItems.count {
                            vm.tendieItems[i].isSelected = target
                        }
                    }
                    .font(.caption.weight(.medium))
                }
            }

            if vm.tendieItems.isEmpty {
                emptyStateCard
            } else {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach($vm.tendieItems) { $item in
                        TendieCardView(item: $item) {
                            selectedDetailItem = item
                        } onDelete: {
                            vm.deleteTendie(item: item)
                        }
                    }
                }

                // Flashing Action Bar & Inline Controls
                VStack(spacing: 12) {
                    if case .running = vm.tendiesFlashPhase {
                        HStack(spacing: 8) {
                            ProgressView()
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Flashing Wallpapers to PosterBoard…")
                                    .font(.subheadline.bold())
                                ProgressView(value: vm.tendiesFlashProgress)
                            }
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity)
                        .background(Color(UIColor.secondarySystemGroupedBackground))
                        .cornerRadius(12)
                    } else {
                        Button {
                            Task {
                                await vm.flashSelectedTendies()
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "sparkles")
                                Text("Flash \(selectedCount) Wallpaper\(selectedCount == 1 ? "" : "s") to iPhone")
                                    .fontWeight(.semibold)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .foregroundColor(.white)
                            .background(
                                selectedCount > 0
                                    ? LinearGradient(colors: [.blue, .purple], startPoint: .leading, endPoint: .trailing)
                                    : LinearGradient(colors: [.gray], startPoint: .leading, endPoint: .trailing)
                            )
                            .cornerRadius(12)
                        }
                        .disabled(selectedCount == 0)
                    }

                    // Respring Button
                    Button {
                        Task {
                            await vm.respringDevice()
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.clockwise")
                            Text("Respring Device")
                                .fontWeight(.medium)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(.bordered)
                    .tint(.purple)

                    Text("Flashes custom lock screen wallpapers directly into PosterBoard and resprings SpringBoard.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)

                    if !vm.tendiesFlashLog.isEmpty {
                        CompactLogView(
                            title: "Wallpapers Flash Log (\(vm.tendiesFlashLog.count) lines)",
                            lines: vm.tendiesFlashLog,
                            onClear: { vm.tendiesFlashLog.removeAll() }
                        )
                        .padding(.top, 4)
                    }
                }
                .padding(.top, 10)
            }
        }
    }

    private var selectedCount: Int {
        vm.tendieItems.filter { $0.isSelected }.count
    }

    private var selectedAll: Bool {
        !vm.tendieItems.isEmpty && vm.tendieItems.allSatisfy { $0.isSelected }
    }

    private var emptyStateCard: some View {
        VStack(spacing: 16) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 48))
                .foregroundColor(.blue.opacity(0.8))
                .padding(.top, 10)

            VStack(spacing: 6) {
                Text("No Tendies Imported")
                    .font(.headline)
                Text("Import .tendies files from your device to preview artwork and install custom PosterBoard wallpapers.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
            }

            Button {
                showFilePicker = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "square.and.arrow.down.fill")
                    Text("Import .tendies File")
                        .fontWeight(.semibold)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(10)
            }
            .padding(.bottom, 10)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(16)
    }
}

// MARK: - Tendie Card View

struct TendieCardView: View {
    @Binding var item: TendieItem
    let onInspect: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Poster Mockup Image
            ZStack(alignment: .topTrailing) {
                ZStack(alignment: .topLeading) {
                    if let img = item.uiPreview {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFill()
                            .frame(height: 190)
                            .clipped()
                    } else {
                        Rectangle()
                            .fill(LinearGradient(
                                colors: [Color.blue.opacity(0.3), Color.purple.opacity(0.4)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ))
                            .frame(height: 190)
                            .overlay(
                                Image(systemName: item.posterType.systemIcon)
                                    .font(.system(size: 38))
                                    .foregroundColor(.white.opacity(0.8))
                            )
                    }

                    // Delete button
                    Button {
                        onDelete()
                    } label: {
                        Image(systemName: "trash.circle.fill")
                            .font(.title3)
                            .foregroundColor(.white)
                            .shadow(radius: 3)
                    }
                    .padding(8)
                }

                // Selection checkmark
                Button {
                    item.isSelected.toggle()
                } label: {
                    Image(systemName: item.isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundColor(item.isSelected ? .green : .white)
                        .background(Circle().fill(Color.black.opacity(0.4)))
                        .shadow(radius: 2)
                }
                .padding(8)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                onInspect()
            }

            // Information details
            VStack(alignment: .leading, spacing: 6) {
                Text(item.name)
                    .font(.caption.bold())
                    .lineLimit(1)
                    .foregroundColor(.primary)

                HStack(spacing: 4) {
                    Label(item.posterType.rawValue, systemImage: item.posterType.systemIcon)
                        .font(.system(size: 9, weight: .bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(item.posterType.badgeColor.opacity(0.18))
                        .foregroundColor(item.posterType.badgeColor)
                        .clipShape(Capsule())

                    Spacer()

                    if item.descriptorCount > 1 {
                        Text("\(item.descriptorCount) items")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(10)
            .background(Color(UIColor.secondarySystemGroupedBackground))
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(item.isSelected ? Color.blue : Color(UIColor.separator).opacity(0.4), lineWidth: item.isSelected ? 2 : 1)
        )
        .shadow(color: Color.black.opacity(0.06), radius: 6, x: 0, y: 3)
    }
}

// MARK: - Detail Sheet

struct TendieDetailSheet: View {
    @Environment(\.dismiss) var dismiss
    let item: TendieItem

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if let img = item.uiPreview {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 380)
                            .cornerRadius(16)
                            .shadow(radius: 8)
                            .padding(.top, 10)
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        Text(item.name)
                            .font(.title2.bold())

                        HStack(spacing: 8) {
                            Label(item.posterType.rawValue, systemImage: item.posterType.systemIcon)
                                .font(.caption.bold())
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(item.posterType.badgeColor.opacity(0.2))
                                .foregroundColor(item.posterType.badgeColor)
                                .clipShape(Capsule())

                            if item.isContainer {
                                Text("Container Mode")
                                    .font(.caption.bold())
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(Color.indigo.opacity(0.2))
                                    .foregroundColor(.indigo)
                                    .clipShape(Capsule())
                            }

                            if item.unsafeContainer {
                                Label("Needs PRB Reset", systemImage: "exclamationmark.triangle.fill")
                                    .font(.caption.bold())
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(Color.orange.opacity(0.2))
                                    .foregroundColor(.orange)
                                    .clipShape(Capsule())
                            }
                        }

                        Divider()

                        VStack(alignment: .leading, spacing: 8) {
                            detailRow(title: "Filename", value: item.fileName)
                            detailRow(title: "Target Extension", value: item.posterType.extensionBundleId)
                            detailRow(title: "Descriptors Count", value: "\(item.descriptorCount)")
                            detailRow(title: "Imported", value: item.dateImported.formatted(date: .abbreviated, time: .shortened))
                        }
                    }
                    .padding(18)
                    .background(Color(UIColor.secondarySystemGroupedBackground))
                    .cornerRadius(16)
                }
                .padding(16)
            }
            .background(Color(UIColor.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("Wallpaper Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
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
        var contentTypes: [UTType] = [
            .zip,
            .data,
            .item,
            .archive
        ]
        if let customType = UTType("com.aircard.tendies") {
            contentTypes.insert(customType, at: 0)
        }
        if let extType = UTType(filenameExtension: "tendies") {
            contentTypes.insert(extType, at: 0)
        }

        // Open in place so security-scoped URL remains valid during synchronous copy
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: contentTypes, asCopy: false)
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
            var copiedURLs: [URL] = []
            let storageDir = TendiesEngine.tendiesStorageDirectory

            for url in urls {
                let shouldStop = url.startAccessingSecurityScopedResource()
                defer {
                    if shouldStop {
                        url.stopAccessingSecurityScopedResource()
                    }
                }

                let target = storageDir.appendingPathComponent(url.lastPathComponent)
                if FileManager.default.fileExists(atPath: target.path) {
                    try? FileManager.default.removeItem(at: target)
                }

                do {
                    try FileManager.default.copyItem(at: url, to: target)
                    copiedURLs.append(target)
                } catch {
                    if let data = try? Data(contentsOf: url) {
                        try? data.write(to: target, options: .atomic)
                        copiedURLs.append(target)
                    }
                }
            }

            parent.onPick(copiedURLs)
            parent.dismiss()
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            parent.dismiss()
        }
    }
}

