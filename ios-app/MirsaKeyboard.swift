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

        /// SwiftUI can retarget touches to its hosting view even though UIKit's
        /// current hit-test resolves to a native editor. Exclude either path;
        /// never force first responder from the window dismiss recognizer.
        static func isTextTouch(deliveredView: UIView?, hitView: UIView?) -> Bool {
            isTextInteraction(deliveredView) || isTextInteraction(hitView)
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
            // Separate short records avoid NSLog's line-size clipping and contain no text.
            NSLog("WALLPAPER-FOCUS %@ state=%ld fields=%@", event, outsideTap.state.rawValue,
                  fields.joined(separator: "; "))
            if let touch {
                let point = touch.location(in: window)
                let hit = window.hitTest(point, with: nil)
                NSLog("WALLPAPER-FOCUS classification sameWindow=%d phase=%ld deliveredText=%d hitText=%d x=%.1f y=%.1f",
                      touch.window === window, touch.phase.rawValue,
                      Self.isTextInteraction(touch.view), Self.isTextInteraction(hit), point.x, point.y)
                NSLog("WALLPAPER-FOCUS delivered %@", chain(touch.view))
                NSLog("WALLPAPER-FOCUS hit %@", chain(hit))
                for recognizer in touch.gestureRecognizers ?? [] {
                    NSLog("WALLPAPER-FOCUS recognizer %@ state=%ld view=%@",
                          String(describing: type(of: recognizer)), recognizer.state.rawValue,
                          String(describing: recognizer.view.map { type(of: $0) }))
                }
            }
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
            let hitView: UIView?
            if let window = attachedWindow {
                hitView = window.hitTest(touch.location(in: window), with: nil)
            } else {
                hitView = nil
            }
            return !Self.isTextTouch(deliveredView: touch.view, hitView: hitView)
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-MirsaWallpaperFixture") {
                NSLog("WALLPAPER-FOCUS simultaneous %@ state=%ld other=%@ state=%ld",
                      String(describing: type(of: gestureRecognizer)), gestureRecognizer.state.rawValue,
                      String(describing: type(of: otherGestureRecognizer)), otherGestureRecognizer.state.rawValue)
            }
            #endif
            return true
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
