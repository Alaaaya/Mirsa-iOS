//
//  RespringHelper.swift
//  AirCard-iOS
//
//  SpringBoard respring utilities (without device reboot) using:
//  1. Pocket-Poster / Cowabunga XPC w00t crashers (restartBackboard, restartFrontboard)
//  2. Lumid-Off compositor crash technique (https://github.com/Lumid-Off/crash-springboard)
//  3. Embedded local server opening Lumid-Off crasher in MobileSafari
//  4. Display Zoom settings fallback
//

import UIKit
import WebKit
import Network

@_silgen_name("restartBackboard") func c_restartBackboard()
@_silgen_name("restartFrontboard") func c_restartFrontboard()
@_silgen_name("restartSpringboard") func c_restartSpringboard()
@_silgen_name("xpc_crasher") func c_xpc_crasher(_ name: UnsafePointer<CChar>)

/// Embedded local HTTP server for serving Lumid-Off SpringBoard Crasher to Safari
public final class LumidCrasherServer {
    public static let shared = LumidCrasherServer()
    private var listener: NWListener?
    public let port: UInt16 = 39999

    public func startIfNeeded() {
        guard listener == nil else { return }
        do {
            guard let nwPort = NWEndpoint.Port(rawValue: port) else { return }
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            listener = try NWListener(using: params, on: nwPort)
            listener?.newConnectionHandler = { connection in
                connection.start(queue: .global())
                connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { data, _, _, _ in
                    let html = RespringHelper.lumidCrasherHTML
                    let httpResponse = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=UTF-8\r\nContent-Length: \(html.utf8.count)\r\nConnection: close\r\n\r\n\(html)"
                    if let respData = httpResponse.data(using: .utf8) {
                        connection.send(content: respData, completion: .contentProcessed({ _ in
                            connection.cancel()
                        }))
                    }
                }
            }
            listener?.start(queue: .global())
            print("LumidCrasherServer started on port \(port)")
        } catch {
            print("Failed to start LumidCrasherServer: \(error)")
        }
    }
}

public final class RespringHelper: NSObject {
    private static var crasherWindow: UIWindow?
    private static var crasherWebView: WKWebView?

    /// The exact HTML from Lumid-Off/crash-springboard + Mond WebKit GPU exhaustion payload
    public static let lumidCrasherHTML = """
    <!DOCTYPE html>
    <html lang="ru">
    <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>SPRINGBOARD CRASHER</title>
        <style>
            body {
                background: #000;
                display: flex;
                align-items: center;
                justify-content: center;
                height: 100vh;
                margin: 0;
                color: #fff;
                font-family: sans-serif;
                text-transform: uppercase;
                overflow: hidden;
            }
        </style>
    </head>
    <body>
        <h1>springboard crasher by lumid</h1>
        <script>
            function crash() {
                var c = document.createElement('div');
                c.style.cssText = 'perspective:1px;perspective-origin:9999999% 9999999%;width:100vw;height:100vh;';
                document.body.appendChild(c);
                for (let i = 0; i < 5000; i++) {
                    const d = document.createElement('div');
                    d.style.cssText = `position:fixed;width:100vw;height:100vh;backdrop-filter:blur(999px);-webkit-backdrop-filter:blur(999px);transform:translate3d(${i}px,${i}px,${i}px) rotateY(90deg);z-index:${9999+i};`;
                    document.body.appendChild(d);
                }
                setInterval(() => {
                    try { window.history.pushState(null, "", window.location.href); } catch(e) {}
                    try { navigator.share({title:'R',text:'R'.repeat(100000)});} catch(e){}
                    try { crypto.getRandomValues(new Uint8Array(1024*1024*5));} catch(e){}
                }, 1);
            }
            window.addEventListener('DOMContentLoaded', crash);
            if (document.readyState !== 'loading') crash();
        </script>
    </body>
    </html>
    """

    /// Instant Respring: Pocket-Poster XPC crasher + in-app GPU compositor crash
    public static func instantRespring() {
        if !Thread.isMainThread {
            DispatchQueue.main.async { instantRespring() }
            return
        }

        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()

        // 1. Fire Pocket-Poster userspace XPC crashers (w00t technique)
        c_restartFrontboard()
        c_restartBackboard()
        c_restartSpringboard()

        // Also hit other common backboard / springboard Mach services
        "com.apple.backboard.TouchDeliveryPolicyServer".withCString { c_xpc_crasher($0) }
        "com.apple.frontboard.systemappservices".withCString { c_xpc_crasher($0) }
        "com.apple.springboard.services".withCString { c_xpc_crasher($0) }
        "com.apple.backboard.hid.services".withCString { c_xpc_crasher($0) }

        // 2. Slap full-screen WebKit GPU compositor crash window (.alert + 100)
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        let prefs = WKWebpagePreferences()
        prefs.allowsContentJavaScript = true
        config.defaultWebpagePreferences = prefs
        config.preferences.javaScriptCanOpenWindowsAutomatically = true

        let bounds = UIScreen.main.bounds
        let webView = WKWebView(frame: bounds, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.backgroundColor = .black
        crasherWebView = webView

        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let activeScene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first

        let window: UIWindow
        if let scene = activeScene {
            window = UIWindow(windowScene: scene)
            window.frame = scene.coordinateSpace.bounds
        } else {
            window = UIWindow(frame: bounds)
        }
        window.windowLevel = .alert + 100
        window.backgroundColor = .black
        window.isHidden = false

        let hostVC = UIViewController()
        hostVC.view.backgroundColor = .black
        hostVC.view.addSubview(webView)
        webView.frame = hostVC.view.bounds
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        window.rootViewController = hostVC
        window.makeKeyAndVisible()
        crasherWindow = window

        webView.loadHTMLString(lumidCrasherHTML, baseURL: URL(string: "about:blank"))
        window.layoutIfNeeded()
        webView.setNeedsLayout()
        webView.layoutIfNeeded()
        webView.loadHTMLString(lumidCrasherHTML, baseURL: nil)
    }

    /// Opens MobileSafari to the Lumid-Off crash page hosted on the local device
    public static func openSafariRespring() {
        LumidCrasherServer.shared.startIfNeeded()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            if let url = URL(string: "http://127.0.0.1:39999/") {
                UIApplication.shared.open(url, options: [:], completionHandler: nil)
            }
        }
    }

    /// Opens Display Zoom settings where tapping "Done" triggers iOS's native respring
    public static func openDisplayZoomSettings() {
        let candidates = [
            "App-prefs:DISPLAY&path=DISPLAY_ZOOM",
            "prefs:root=DISPLAY&path=DISPLAY_ZOOM",
            "App-prefs:root=DISPLAY",
            "prefs:root=DISPLAY",
            UIApplication.openSettingsURLString
        ]
        for c in candidates {
            if let url = URL(string: c) {
                UIApplication.shared.open(url, options: [:], completionHandler: nil)
                return
            }
        }
    }
}
