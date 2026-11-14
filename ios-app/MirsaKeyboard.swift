import SwiftUI
import UIKit

/// One non-cancelling recognizer per app window, including presented forms.
/// Never captures field contents or changes focus while editing/selecting text.
struct MirsaKeyboardDismissal: UIViewRepresentable {
    func makeUIView(context: Context) -> KeyboardWindowAnchor { KeyboardWindowAnchor() }
    func updateUIView(_ uiView: KeyboardWindowAnchor, context: Context) {}

    final class KeyboardWindowAnchor: UIView, UIGestureRecognizerDelegate {
        private weak var attachedWindow: UIWindow?
        private lazy var outsideTap: UITapGestureRecognizer = {
            let tap = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
            tap.cancelsTouchesInView = false
            tap.delaysTouchesBegan = false
            tap.delaysTouchesEnded = false
            tap.delegate = self
            return tap
        }()

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard attachedWindow !== window else { return }
            attachedWindow?.removeGestureRecognizer(outsideTap)
            attachedWindow = window
            window?.addGestureRecognizer(outsideTap)
            isUserInteractionEnabled = false
            accessibilityElementsHidden = true
        }

        @objc private func dismissKeyboard() {
            #if DEBUG
            wallpaperFocusTrace("outsideTap-before-endEditing")
            #endif
            attachedWindow?.endEditing(false)
            #if DEBUG
            wallpaperFocusTrace("outsideTap-after-endEditing")
            #endif
        }

        static func isTextInteraction(_ view: UIView?) -> Bool {
            var current = view
            while let item = current {
                // Includes UITextField (also SecureField), UITextView, and their
                // selection/caret subviews. Tapping another field must focus it.
                if item is UITextField || item is UITextView { return true }
                if item is UIControl && item.canBecomeFirstResponder { return true }
                current = item.superview
            }
            return false
        }

        #if DEBUG
        private func wallpaperFocusTrace(_ event: String, touch: UITouch? = nil) {
            guard ProcessInfo.processInfo.arguments.contains("-MirsaWallpaperFixture"),
                  let window = attachedWindow else { return }
            func chain(_ view: UIView?) -> String {
                var result: [String] = []
                var current = view
                while let item = current {
                    result.append("\(type(of: item)){first=\(item.isFirstResponder),enabled=\(item.isUserInteractionEnabled)}")
                    current = item.superview
                }
                return result.joined(separator: " / ")
            }
            var fields: [String] = []
            func visit(_ view: UIView) {
                if view is UITextField || view is UITextView || view.isFirstResponder {
                    fields.append("\(type(of: view)){frame=\(view.convert(view.bounds, to: window)),first=\(view.isFirstResponder),canFocus=\(view.canBecomeFirstResponder),hidden=\(view.isHidden),alpha=\(view.alpha)}")
                }
                view.subviews.forEach { visit($0) }
            }
            visit(window)
            var hit = ""
            if let touch = touch {
                let point = touch.location(in: window)
                hit = " point=\(point) touch=\(chain(touch.view)) hit=\(chain(window.hitTest(point, with: nil))) textInteraction=\(Self.isTextInteraction(touch.view))"
            }
            NSLog("WALLPAPER-FOCUS \(event)\(hit) fields=\(fields.joined(separator: "; "))")
        }
        #endif

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            #if DEBUG
            wallpaperFocusTrace("touch", touch: touch)
            // Observe only. Do not request focus, change gesture decisions, or log text.
            if ProcessInfo.processInfo.arguments.contains("-MirsaWallpaperFixture") {
              for delay in [0.0, 0.1, 0.5] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    self?.wallpaperFocusTrace("after-touch-\(delay)")
                }
              }
            }
            #endif
            return !Self.isTextInteraction(touch.view)
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            true
        }
    }
}

/// Uses keyboard events rather than ignoring keyboard safe areas, so SwiftUI
/// continues scrolling the focused input above the software keyboard.
final class MirsaKeyboardVisibility: ObservableObject {
    @Published private(set) var isVisible = false
    private var tokens: [NSObjectProtocol] = []

    init(center: NotificationCenter = .default) {
        self.center = center
        tokens = [
            center.addObserver(forName: UIResponder.keyboardWillShowNotification, object: nil, queue: .main) { [weak self] _ in
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("-MirsaWallpaperFixture") {
                    NSLog("WALLPAPER-FOCUS keyboardWillShow")
                }
                #endif
                self?.isVisible = true
            },
            center.addObserver(forName: UIResponder.keyboardDidHideNotification, object: nil, queue: .main) { [weak self] _ in
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("-MirsaWallpaperFixture") {
                    NSLog("WALLPAPER-FOCUS keyboardDidHide")
                }
                #endif
                self?.isVisible = false
            }
        ]
    }
    private let center: NotificationCenter
    deinit { tokens.forEach { center.removeObserver($0) } }
}

extension View {
    /// Inherited by descendant ScrollViews, Lists and Forms, including sheets.
    func mirsaKeyboardDismissal() -> some View {
        scrollDismissesKeyboard(.interactively)
            .background(MirsaKeyboardDismissal().frame(width: 0, height: 0))
    }
}
