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
            .fileImporter(
                isPresented: $showFilePicker,
                allowedContentTypes: [
                    UTType(filenameExtension: "tendies") ?? .data,
                    .zip,
                    .data,
                    .item
                ],
                allowsMultipleSelection: true
            ) { result in
                switch result {
                case .success(let urls):
                    Task {
                        await vm.importTendieFiles(urls: urls)
                    }
                case .failure(let error):
                    vm.errorMessage = "File picker error: \(error.localizedDescription)"
                }
            }
            .sheet(item: $selectedDetailItem) { item in
                TendieDetailSheet(item: item)
            }
            .sheet(isPresented: Binding(
                get: { vm.tendiesFlashPhase == .running || (isDonePhase(vm.tendiesFlashPhase)) },
                set: { if !$0 { vm.tendiesFlashPhase = .idle } }
            )) {
                TendiesFlashProgressSheet()
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

    private func isDonePhase(_ phase: AppViewModel.FlashPhase) -> Bool {
        if case .done = phase { return true }
        return false
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

                // Flashing Action Bar
                VStack(spacing: 8) {
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

                    Text("Flashes custom lock screen wallpapers directly into PosterBoard.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
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

// MARK: - Flashing Progress Sheet

struct TendiesFlashProgressSheet: View {
    @EnvironmentObject var vm: AppViewModel
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                // Status Graphic
                VStack(spacing: 8) {
                    if case .running = vm.tendiesFlashPhase {
                        ProgressView()
                            .scaleEffect(1.4)
                            .padding(.bottom, 6)
                        Text("Injecting Wallpapers into PosterBoard…")
                            .font(.headline)
                        ProgressView(value: vm.tendiesFlashProgress)
                            .padding(.horizontal, 30)
                    } else if case .done(let ok) = vm.tendiesFlashPhase {
                        Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .font(.system(size: 52))
                            .foregroundColor(ok ? .green : .red)
                        Text(ok ? "Wallpapers Applied Successfully! 🎉" : "Flashing Failed")
                            .font(.title3.bold())
                    }
                }
                .padding(.top, 20)

                // Log viewer
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(Array(vm.tendiesFlashLog.enumerated()), id: \.offset) { idx, line in
                                Text(line)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundColor(colorForLine(line))
                                    .id(idx)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                    }
                    .background(Color(UIColor.black))
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color(UIColor.separator), lineWidth: 1)
                    )
                    .onChange(of: vm.tendiesFlashLog.count) {
                        if let last = vm.tendiesFlashLog.indices.last {
                            proxy.scrollTo(last)
                        }
                    }
                }

                if case .done = vm.tendiesFlashPhase {
                    Button("Done") {
                        vm.tendiesFlashPhase = .idle
                        dismiss()
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
            }
            .padding(20)
            .navigationTitle("PosterBoard Injection")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func colorForLine(_ line: String) -> Color {
        if line.contains("❌") || line.contains("error") || line.contains("Error") {
            return .red
        } else if line.contains("✅") || line.contains("🎉") {
            return .green
        } else if line.contains("⚠️") {
            return .orange
        } else if line.contains("🚀") || line.contains("✨") || line.contains("📦") {
            return .cyan
        }
        return .white.opacity(0.85)
    }
}
