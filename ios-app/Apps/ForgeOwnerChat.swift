import SwiftUI
import WebKit

/// Owner-only chat with Kat. The URL is fetched on tap, lives only in memory, is never logged or stored.
/// No access token, device token or native bridge is ever given to the page.
enum ForgeOwnerChatText {
    static var title: String { tr("Create anything", "إنشاء كل شي", ckb: "هەموو شتێک دروست بکە", kmr: "Her tiştî çêke") }
    static var subtitle: String { tr("Talk to Kat and Kat makes what you want.", "احكي مع كات وهي بتعمل اللي بدك ياه.", ckb: "لەگەڵ کات قسە بکە و ئەو دروستی دەکات ئەوەی دەتەوێت.", kmr: "Bi Katê re baxive û ew tiştê tu dixwazî çêdike.") }
    static var failed: String { tr("Chat is not available right now.", "الشات مو متاح هلق.", ckb: "گفتوگۆ ئێستا بەردەست نییە.", kmr: "Sohbet niha peyda nîne.") }
}

enum ForgeOwnerChatPolicy {
    /// Trusted: https and the returned host or a subdomain of its last two labels (auth flow of the same service).
    static func trusted(_ url: URL, root: URL) -> Bool {
        guard url.scheme == "https", let host = url.host?.lowercased(), let base = root.host?.lowercased() else { return false }
        if host == base { return true }
        let labels = base.split(separator: ".")
        guard labels.count >= 2 else { return false }
        let parent = labels.suffix(2).joined(separator: ".")
        return host == parent || host.hasSuffix("." + parent)
    }
    static func parse(_ data: Data) -> URL? {
        guard let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let s = o["url"] as? String,
              let u = URL(string: s), u.scheme == "https", u.host != nil else { return nil }
        return u
    }
}

struct ForgeOwnerChatWebView: UIViewRepresentable {
    let url: URL
    func makeCoordinator() -> Coordinator { Coordinator(root: url) }
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = [.audio, .video]
        let web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = context.coordinator
        web.uiDelegate = context.coordinator
        web.allowsBackForwardNavigationGestures = true
        web.load(URLRequest(url: url))
        return web
    }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) { uiView.stopLoading() }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        let root: URL
        init(root: URL) { self.root = root }
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if let u = action.request.url, u.absoluteString == "about:blank" || ForgeOwnerChatPolicy.trusted(u, root: root) { decisionHandler(.allow) }
            else { decisionHandler(.cancel) } // no external schemes, no foreign origins
        }
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if let u = action.request.url, ForgeOwnerChatPolicy.trusted(u, root: root) { webView.load(action.request) }
            return nil
        }
        /// Microphone only for the trusted origin; the system permission prompt still applies. Camera is denied.
        func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin, initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType, decisionHandler: @escaping (WKPermissionDecision) -> Void) {
            let probe = URL(string: "https://" + origin.host)
            decisionHandler(type == .microphone && origin.protocol == "https" && probe.map { ForgeOwnerChatPolicy.trusted($0, root: root) } == true ? .prompt : .deny)
        }
    }
}

struct ForgeOwnerChatEntry: View {
    @ObservedObject private var precise = ForgePreciseStore.shared
    @State private var chatURL: URL?
    @State private var loading = false
    @State private var error: String?
    var body: some View {
        Group {
            if precise.enabled {
                VStack(alignment: .leading, spacing: 6) {
                    Button { open() } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Label(ForgeOwnerChatText.title, systemImage: "bubble.left.and.text.bubble.right")
                            Text(ForgeOwnerChatText.subtitle).font(.caption).foregroundStyle(.white.opacity(0.6))
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }.buttonStyle(.mirsaPress).disabled(loading)
                    if let error { Text(error).font(.footnote).foregroundStyle(.red) }
                }
                .foregroundStyle(.white).padding(14).appsGlass(cornerRadius: MirsaRadius.l)
                .environment(\.layoutDirection, .leftToRight)
            }
        }
        .task { await precise.refreshCapability() }
        .fullScreenCover(isPresented: Binding(get: { chatURL != nil }, set: { if !$0 { chatURL = nil } })) {
            if let url = chatURL {
                NavigationStack {
                    ForgeOwnerChatWebView(url: url).ignoresSafeArea(edges: .bottom)
                        .toolbar { ToolbarItem(placement: .cancellationAction) { Button(tr("Close", "إغلاق", ckb: "داخستن", kmr: "Bigire")) { chatURL = nil } } }
                }.environment(\.layoutDirection, .leftToRight)
            }
        }
    }
    private func open() {
        loading = true; error = nil
        Task {
            defer { loading = false }
            do {
                let c = try await ForgeClient.fixToken()
                let r = try await ForgePreciseClient.request(["action": "owner-chat-url"], credentials: c)
                guard r.status == 200, let url = ForgeOwnerChatPolicy.parse(r.data) else { throw ForgeClient.Failure.message(ForgeOwnerChatText.failed) }
                chatURL = url
            } catch { self.error = ForgeOwnerChatText.failed }
        }
    }
}
