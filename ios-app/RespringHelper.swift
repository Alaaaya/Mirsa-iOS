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
    private static var crasherWebView: WKWebView?

    /// Triggers an immediate SpringBoard respring using Lumid-Off's compositor overload
    public static func instantRespring() {
        DispatchQueue.main.async {
            // 1. Try private framework FrontBoardServices / SpringBoardServices first
            if respringPrivateFramework() {
                return
            }

            // 2. Local compositor crash via in-app WKWebView
            // Overloads the RenderServer (backboardd/SpringBoard) with 5000 backdrop-filter blur layers
            let config = WKWebViewConfiguration()
            config.preferences.javaScriptCanOpenWindowsAutomatically = true
            let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 100, height: 100), configuration: config)
            crasherWebView = webView

            if let window = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .flatMap({ $0.windows })
                .first(where: { $0.isKeyWindow }) {
                window.addSubview(webView)
            }

            let crasherHTML = """
            <!DOCTYPE html>
            <html>
            <head><meta charset="utf-8"></head>
            <body style="background:#000;">
            <script>
                function crash() {
                    for (let i = 0; i < 5000; i++) {
                        const d = document.createElement('div');
                        d.style.cssText = 'position:fixed;width:100vw;height:100vh;backdrop-filter:blur(999px);z-index:' + (9999 + i) + ';';
                        document.body.appendChild(d);
                    }
                    setInterval(() => {
                        window.history.pushState(null, '', window.location.href);
                    }, 1);
                }
                window.addEventListener('DOMContentLoaded', crash);
                crash();
            </script>
            </body>
            </html>
            """
            webView.loadHTMLString(crasherHTML, baseURL: URL(string: "https://lumid-off.github.io"))

            // 3. Also open Lumid-Off hosted crasher in Safari as instant backup
            if let onlineURL = URL(string: "https://lumid-off.github.io/crash-springboard/") {
                UIApplication.shared.open(onlineURL, options: [:], completionHandler: nil)
            }
        }
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
