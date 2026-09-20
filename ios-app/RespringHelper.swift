//
//  RespringHelper.swift
//  AirCard-iOS
//
//  SpringBoard respring utilities (without device reboot) using
//  Lumid-Off compositor crash technique (https://github.com/Lumid-Off/crash-springboard).
//

import UIKit
import WebKit

public final class RespringHelper: NSObject {
    private static var crasherWindow: UIWindow?
    private static var crasherWebView: WKWebView?

    /// Triggers an immediate SpringBoard respring (without device reboot) using
    /// full-screen WebKit GPU compositor overload (Lumid-Off & Mond techniques).
    public static func instantRespring() {
        if !Thread.isMainThread {
            DispatchQueue.main.async { instantRespring() }
            return
        }

        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()

        // 1. Try private framework FrontBoardServices / SpringBoardServices first
        if respringPrivateFramework() {
            return
        }

        // 2. Overload the RenderServer (backboardd/SpringBoard compositor)
        // Must be on a high-level full-screen UIWindow (.alert + 100) so iOS doesn't optimize it away.
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

        // Combined Lumid-Off + Mond GPU crash payload
        let crasherHTML = """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <style>
                body, html { margin: 0; padding: 0; background: #000; overflow: hidden; width: 100vw; height: 100vh; }
            </style>
        </head>
        <body>
        <script>
            (function() {
                var c = document.createElement('div');
                c.style.cssText = 'perspective:1px;perspective-origin:9999999% 9999999%;width:100vw;height:100vh;';
                document.body.appendChild(c);

                // Create backdrop-filter blur layers with 3D transformations to exhaust GPU compositor
                for (var i = 0; i < 2500; i++) {
                    var d = document.createElement('div');
                    d.style.cssText = 'position:fixed;width:100vw;height:100vh;backdrop-filter:blur(500px);-webkit-backdrop-filter:blur(500px);transform:translate3d(' + (i * 10) + 'px,' + (i * 10) + 'px,' + i + 'px) rotateY(90deg);z-index:' + (9999 + i) + ';';
                    c.appendChild(d);
                }

                // Rapid allocation & history push to trigger RenderServer/SpringBoard timeout
                setInterval(function() {
                    try { window.history.pushState(null, '', window.location.href); } catch(e) {}
                    try { crypto.getRandomValues(new Uint8Array(1024 * 1024 * 5)); } catch(e) {}
                }, 0);
            })();
        </script>
        </body>
        </html>
        """

        webView.loadHTMLString(crasherHTML, baseURL: URL(string: "about:blank"))
        window.layoutIfNeeded()
        webView.setNeedsLayout()
        webView.layoutIfNeeded()
        webView.loadHTMLString(crasherHTML, baseURL: nil)
    }

    /// Attempts an in-memory SpringBoard respring using private FrontBoardServices / SpringBoardServices
    @discardableResult
    private static func respringPrivateFramework() -> Bool {
        guard let fbs = dlopen("/System/Library/PrivateFrameworks/FrontBoardServices.framework/FrontBoardServices", RTLD_NOW) else {
            return false
        }
        defer { dlclose(fbs) }

        _ = dlopen("/System/Library/PrivateFrameworks/SpringBoardServices.framework/SpringBoardServices", RTLD_NOW)

        guard let fbsClass = NSClassFromString("FBSSystemService") as? NSObject.Type,
              let sbsActionClass = NSClassFromString("SBSRelaunchAction") as? NSObject.Type else {
            return false
        }

        let selAction = NSSelectorFromString("actionWithReason:options:targetURL:")
        let selShared = NSSelectorFromString("sharedService")
        let selSend = NSSelectorFromString("sendActions:withResult:")

        guard sbsActionClass.responds(to: selAction),
              fbsClass.responds(to: selShared),
              let shared = fbsClass.perform(selShared)?.takeUnretainedValue() as? NSObject,
              shared.responds(to: selSend) else {
            return false
        }

        guard let method = class_getClassMethod(sbsActionClass, selAction) else {
            return false
        }
        let imp = method_getImplementation(method)
        typealias ActionFunc = @convention(c) (AnyClass, Selector, NSString, UInt64, NSURL?) -> AnyObject
        let actionFn = unsafeBitCast(imp, to: ActionFunc.self)
        let action = actionFn(sbsActionClass, selAction, "RestartRenderServer" as NSString, 1, nil)

        let set = NSSet(object: action)
        _ = shared.perform(selSend, with: set, with: nil)
        return true
    }

    /// Opens Display Zoom settings where tapping "Done" immediately triggers iOS's built-in SpringBoard respring
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
