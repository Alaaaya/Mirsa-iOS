import SwiftUI

/// Original 2.4 video wallpaper feature, shown at the TOP of the same wallpaper tab.
/// The Tendies maker sits below it (see TendiesView).
struct OriginalVideoWallpaperBlock: View {
    @EnvironmentObject var vm: AppViewModel
    let applyRunning: Bool
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

    var body: some View {
        Section {
            Button {
                showVideoPicker = true
            } label: {
                Label(V.text(.fromPhotos), systemImage: "video.badge.plus")
            }
            .disabled(preparingVideo || applyRunning)
            .accessibilityIdentifier("video-wallpaper-from-photos")
            .sheet(isPresented: $showVideoPicker) {
                WallpaperVideoPicker(completion: videoPicked)
            }
            if preparingVideo {
                ProgressView(value: videoProgress) {
                    Text(V.text(.preparing))
                }
            }
            Text(V.text(.info))
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(V.text(.experimental))
                .font(.caption).foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        } header: {
            Text(V.text(.tab))
        }
    }
}
