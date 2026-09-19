//
//  RespringHelper.swift
//  AirCard-iOS
//
//  Safe SpringBoard respring utilities (without device reboot).
//

import UIKit

public enum RespringHelper {
    /// Attempts an in-memory SpringBoard respring using private FrontBoardServices / SpringBoardServices
    @discardableResult
    public static func respring() -> Bool {
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
        if let url = URL(string: "App-Prefs:DISPLAY&path=DISPLAY_ZOOM"), UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        } else if let url = URL(string: "prefs:root=DISPLAY&path=DISPLAY_ZOOM"), UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        } else if let url = URL(string: "App-Prefs:root=DISPLAY") {
            UIApplication.shared.open(url)
        }
    }
}
