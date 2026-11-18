import SwiftUI
import UIKit

struct NoProfileShortcutGuide: View {
    let app: ManagedApp
    @State private var sharing = false
    private var launchURL: URL {
        HomeShortcut.launchURL(for: app.id)
    }
    private var guide: String {
        MirsaTr.f("shortcut", app.name, app.id, launchURL.absoluteString)
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: MirsaSpacing.l) {
                    Text(app.name).font(MirsaFont.sheetTitle)
                    Text(guide).textSelection(.enabled)
                        .font(MirsaFont.secondary)
                        .foregroundStyle(MirsaPalette.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(MirsaSpacing.card)
                        .mirsaCard(radius: MirsaRadius.l)
                    Button(tr("Share guide and icon", "شارك التعليمات والأيقونة")) { sharing = true }
                        .buttonStyle(.mirsaPrimary)
                        .controlSize(.large)
                    ShareLink(item: launchURL) { Label(tr("Share launch link", "شارك رابط الفتح"), systemImage: "link") }
                        .buttonStyle(.mirsaSecondary)
                }
                .padding(MirsaSpacing.page)
            }
            .mirsaScreen()
            .navigationTitle(tr("No-profile shortcut", "اختصار بدون بروفايل"))
            .sheet(isPresented: $sharing) {
                ShortcutAssetsSheet(text: guide, icon: UIImage(contentsOfFile: AppsStore.iconURL(app.id).path))
            }
        }
        .preferredColorScheme(.dark)
    }
}

private struct ShortcutAssetsSheet: UIViewControllerRepresentable {
    let text: String
    let icon: UIImage?
    func makeUIViewController(context: Context) -> UIActivityViewController {
        var items: [Any] = [text]
        if let icon { items.append(icon) }
        return UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
