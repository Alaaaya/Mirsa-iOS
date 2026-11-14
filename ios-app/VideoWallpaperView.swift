import SwiftUI
import UniformTypeIdentifiers

/// Original 2.4 video wallpaper screen, restored as its own tab (Tendies maker lives in TendiesView).
struct VideoWallpaperView: View {
    @EnvironmentObject var vm: AppViewModel
    @State private var showFilePicker = false
    @State private var showVideoPicker = false
    @State private var preparingVideo = false
    @State private var videoProgress: Double = 0

    private typealias V = VideoWallpaperSection
    private func videoPicked(_ result: Result<URL, Error>?) {
        showVideoPicker = false
        guard let result = result else { return }
        switch result {
        case .failure(let error): vm.errorMessage = error.localizedDescription
        case .success(let source):
            preparingVideo = true
            videoProgress = 0
            let aspect = UIScreen.main.bounds.width / UIScreen.main.bounds.height
            Task {
                defer {
                    preparingVideo = false
                    try? FileManager.default.removeItem(at: source)
                }
                do {
                    let archive = try await Task.detached(priority: .userInitiated) {
                        try await VideoWallpaper.makeArchive(from: source, screenAspect: aspect) { value in
                            Task { @MainActor in videoProgress = value }
                        }
                    }.value
                    defer { try? FileManager.default.removeItem(at: archive) }
                    await vm.importTendieFiles(urls: [archive])
                } catch { vm.errorMessage = error.localizedDescription }
            }
        }
    }
    @State private var selectedDetailItem: TendieItem? = nil
    @State private var isNeoSpringing = false

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
                            Text(vm.tendieItems.isEmpty ? "Choose .tendies from Files…" : "Import More Wallpapers…")
                            Spacer()
                        }
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)

                    Button {
                        showVideoPicker = true
                    } label: {
                        Label(V.text(.fromPhotos), systemImage: "video.badge.plus")
                    }
                    .disabled(preparingVideo || videoApplyRunning)
                    if preparingVideo {
                        ProgressView(value: videoProgress) {
                            Text(V.text(.preparing))
                        }
                    }
                    Text(V.text(.info))
                        .font(.caption).foregroundStyle(.secondary)
                    Text(V.text(.experimental))
                        .font(.caption).foregroundStyle(.orange)
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
                            Text(MirsaTr.lit("Tap 'Choose .tendies from Files' or copy wallpapers into On My iPhone › Mirsa."))
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
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
                                .frame(height: 48)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.blue)
                            .disabled(selectedCount == 0)
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
                            .frame(height: 48)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                    }
                    .listRowInsets(EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14))
                } footer: {
                    Text(MirsaTr.lit("Flashing will automatically trigger NeoSpring to respring the device and apply your new wallpapers."))
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
            .safeAreaInset(edge: .bottom) {
                Color.clear.frame(height: 60)
            }
            .navigationTitle(MirsaTr.lit("Wallpapers"))
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
            .sheet(isPresented: $showVideoPicker) {
                WallpaperVideoPicker(completion: videoPicked)
                    .interactiveDismissDisabled()
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
        }
    }
}

// MARK: - Tendie Row View

