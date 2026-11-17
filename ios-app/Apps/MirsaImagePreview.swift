import SwiftUI
import UIKit
import Photos

/// Fullscreen preview for an already-decoded chat image: pinch/pan zoom, close, save to Photos (add-only).
struct MirsaImagePreview: View {
    let image: UIImage
    @Environment(\.dismiss) private var dismiss
    @State private var message: String?

    private func t(_ en: String, _ ar: String, _ de: String, _ kmr: String, _ ckb: String) -> String {
        if UserDefaults.standard.string(forKey: AppLanguageStore.key) == "de" { return de }
        switch AppLanguageStore.shared.current {
        case .german: return de
        case .english: return en
        case .arabic: return ar
        case .kurmanji: return kmr
        case .sorani: return ckb
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()
            MirsaZoomableImage(image: image).ignoresSafeArea()
                .accessibilityIdentifier("chat-image-zoom")
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 30)).symbolRenderingMode(.palette).foregroundStyle(.white, .black.opacity(0.55))
                }
                .accessibilityLabel(t("Close", "إغلاق", "Schließen", "Bigire", "داخستن"))
                .accessibilityIdentifier("chat-image-close")
                Spacer()
                Button { save() } label: {
                    Image(systemName: "square.and.arrow.down.circle.fill").font(.system(size: 30)).symbolRenderingMode(.palette).foregroundStyle(.white, .black.opacity(0.55))
                }
                .accessibilityLabel(t("Save to Photos", "حفظ بالصور", "In Fotos sichern", "Di Wêneyan de tomar bike", "هەڵگرتن لە وێنەکان"))
                .accessibilityIdentifier("chat-image-save")
            }
            .padding(.horizontal, 16).padding(.top, 8)
            if let message {
                Text(message).font(.footnote.weight(.medium)).foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 8).background(Capsule().fill(.black.opacity(0.7)))
                    .frame(maxHeight: .infinity, alignment: .bottom).padding(.bottom, 40)
                    .accessibilityIdentifier("chat-image-status")
            }
        }
        .environment(\.layoutDirection, .leftToRight)
        .preferredColorScheme(.dark)
    }

    private func save() {
        let img = image
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            DispatchQueue.main.async {
                guard status == .authorized || status == .limited else {
                    message = t("Photos access is off. Allow it in Settings to save.", "الوصول للصور مطفي. فعّله من الإعدادات للحفظ.",
                                "Der Zugriff auf Fotos ist aus. Erlaube ihn in den Einstellungen.", "Gihîştina Wêneyan girtî ye. Di Mîhengan de çalak bike.",
                                "دەستگەیشتن بە وێنەکان کوژاوەتەوە. لە ڕێکخستنەکان چالاکی بکە.")
                    return
                }
                PHPhotoLibrary.shared().performChanges({ PHAssetChangeRequest.creationRequestForAsset(from: img) }) { ok, _ in
                    DispatchQueue.main.async {
                        message = ok ? t("Saved to Photos", "انحفظت بالصور", "In Fotos gesichert", "Di Wêneyan de hate tomarkirin", "لە وێنەکان هەڵگیرا")
                                     : t("Couldn’t save the image.", "ما قدرت احفظ الصورة.", "Das Bild konnte nicht gesichert werden.", "Wêne nehat tomarkirin.", "نەتوانرا وێنەکە هەڵبگیرێت.")
                    }
                }
            }
        }
    }
}

/// UIScrollView-backed pinch/pan with double-tap zoom.
struct MirsaZoomableImage: UIViewRepresentable {
    let image: UIImage
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> UIScrollView {
        let sv = UIScrollView()
        sv.delegate = context.coordinator
        sv.minimumZoomScale = 1; sv.maximumZoomScale = 5
        sv.showsHorizontalScrollIndicator = false; sv.showsVerticalScrollIndicator = false
        sv.contentInsetAdjustmentBehavior = .never
        sv.backgroundColor = .clear
        let iv = UIImageView(image: image)
        iv.contentMode = .scaleAspectFit
        iv.isUserInteractionEnabled = true
        iv.translatesAutoresizingMaskIntoConstraints = false
        sv.addSubview(iv)
        NSLayoutConstraint.activate([
            iv.leadingAnchor.constraint(equalTo: sv.frameLayoutGuide.leadingAnchor),
            iv.trailingAnchor.constraint(equalTo: sv.frameLayoutGuide.trailingAnchor),
            iv.topAnchor.constraint(equalTo: sv.frameLayoutGuide.topAnchor),
            iv.bottomAnchor.constraint(equalTo: sv.frameLayoutGuide.bottomAnchor),
        ])
        context.coordinator.imageView = iv
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.doubleTap(_:)))
        tap.numberOfTapsRequired = 2
        sv.addGestureRecognizer(tap)
        return sv
    }
    func updateUIView(_ sv: UIScrollView, context: Context) { context.coordinator.imageView?.image = image }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        weak var imageView: UIImageView?
        func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }
        @objc func doubleTap(_ g: UITapGestureRecognizer) {
            guard let sv = g.view as? UIScrollView else { return }
            sv.setZoomScale(sv.zoomScale > 1.01 ? 1 : 2.5, animated: true)
        }
    }
}

/// Tappable thumbnail wrapper: opens the fullscreen preview.
struct MirsaTappableImage: View {
    let image: UIImage
    var maxWidth: CGFloat? = nil
    var maxHeight: CGFloat = 200
    var cornerRadius: CGFloat = 8
    @State private var open = false
    var body: some View {
        Image(uiImage: image).resizable().scaledToFit()
            .frame(maxWidth: maxWidth, maxHeight: maxHeight)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .contentShape(Rectangle())
            .onTapGesture { open = true }
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("chat-image-thumb")
            .fullScreenCover(isPresented: $open) { MirsaImagePreview(image: image) }
    }
}
